"""
db.py  ·  Conexión a Oracle (esquema TURISMOUQ)

Todo lo que habla con la base de datos pasa por aquí.
Usa python-oracledb en modo "thin": NO necesita instalar Oracle Instant Client.
"""
import os
from contextlib import contextmanager

import oracledb
from dotenv import load_dotenv

load_dotenv()  # lee el archivo .env

_pool = None

# Límites para que la app nunca se quede "cargando" para siempre
TIEMPO_MAX_CONSULTA_MS = 60_000   # una consulta que pase de 60 s se corta con error
TIEMPO_ESPERA_POOL_MS = 10_000    # si no hay conexión libre en 10 s, error en vez de esperar


def iniciar_pool():
    """Crea un pool de conexiones al arrancar la app."""
    global _pool
    _pool = oracledb.create_pool(
        user=os.getenv("DB_USER", "TURISMOUQ"),
        password=os.getenv("DB_PASSWORD", "Turismo123"),
        dsn=os.getenv("DB_DSN", "localhost:1521/XEPDB1"),
        min=1,
        max=10,
        increment=1,
        getmode=oracledb.POOL_GETMODE_TIMEDWAIT,
        wait_timeout=TIEMPO_ESPERA_POOL_MS,
        ping_interval=30,
    )


@contextmanager
def conexion():
    """Presta una conexión del pool y la devuelve al terminar.
    Si no se hizo commit, Oracle descarta los cambios."""
    if _pool is None:
        iniciar_pool()
    con = _pool.acquire()
    con.call_timeout = TIEMPO_MAX_CONSULTA_MS
    try:
        yield con
    finally:
        try:
            _pool.release(con)
        except oracledb.Error:
            pass  # la conexión quedó dañada (p. ej. por timeout); el pool abre otra


def _filas_como_dict(cursor):
    """Hace que cada fila llegue como diccionario: fila['nombre']."""
    columnas = [c[0].lower() for c in cursor.description]
    cursor.rowfactory = lambda *valores: dict(zip(columnas, valores))


def leer_cursor(cursor):
    """Convierte un SYS_REFCURSOR (o un cursor normal) en lista de dicts."""
    _filas_como_dict(cursor)
    return cursor.fetchall()


def llamar_con_cursor(procedimiento, **parametros):
    """Llama un procedimiento que devuelve un SYS_REFCURSOR (parámetro p_cursor)
    y entrega sus filas como lista de dicts.

    Por qué no se usa cursor.callproc():
    python-oracledb 2.4.1 en modo thin se queda esperando (Oracle muestra
    'SQL*Net more data from client') cuando en la MISMA llamada se envía un
    número como parámetro y se recibe un cursor. Se comprobó con
    prueba_llamadas.py. Para evitarlo:
      * los números (ya convertidos con int(), por eso es seguro) y los NULL
        se escriben directamente en el bloque PL/SQL;
      * las fechas y los textos sí se envían como variables (:nombre);
      * los parámetros van por nombre (p_x => ...), así el orden no importa.
    """
    partes, binds = [], {}
    for nombre, valor in parametros.items():
        if valor is None:
            partes.append(f"{nombre} => NULL")
        elif isinstance(valor, bool) or not isinstance(valor, (int, float)):
            binds[nombre] = valor
            partes.append(f"{nombre} => :{nombre}")
        else:
            partes.append(f"{nombre} => {int(valor) if float(valor).is_integer() else float(valor)}")
    partes.append("p_cursor => :cursor_salida")
    sql = f"BEGIN {procedimiento}({', '.join(partes)}); END;"

    with conexion() as con:
        with con.cursor() as cur:
            ref = cur.var(oracledb.DB_TYPE_CURSOR)
            cur.execute(sql, cursor_salida=ref, **binds)
            return leer_cursor(ref.getvalue())


def consultar(sql, params=None):
    """SELECT que devuelve varias filas (lista de dicts)."""
    with conexion() as con:
        with con.cursor() as cur:
            cur.execute(sql, params or {})
            return leer_cursor(cur)


def consultar_uno(sql, params=None):
    """SELECT que devuelve una sola fila (dict) o None."""
    filas = consultar(sql, params)
    return filas[0] if filas else None


def mensaje_error(error):
    """Convierte un error de Oracle en un texto entendible.

    Los errores propios del paquete (ORA-20001 ... ORA-20013) ya traen un
    mensaje en español; se quita el prefijo 'ORA-200xx:' y las líneas
    'ORA-06512' (pila de llamadas)."""
    err = error.args[0]
    texto = getattr(err, "message", str(err))
    if "DPY-4024" in texto or "ORA-01013" in texto:
        return ("La consulta tardó más de 60 segundos y se canceló. "
                "Prueba con menos días o filtra por municipio.")
    if "DPY-4005" in texto:
        return ("Todas las conexiones a Oracle están ocupadas. Espera unos segundos "
                "y vuelve a intentar; si sigue igual, reinicia la app (Ctrl + C y python app.py).")
    if "DPY-6005" in texto or "DPY-6000" in texto:
        return ("No se pudo conectar a Oracle. Revisa que la base esté encendida "
                "y los datos del archivo .env.")
    primera_linea = texto.splitlines()[0] if texto else str(err)
    codigo = getattr(err, "code", 0)
    if 20000 <= codigo <= 20999 and ":" in primera_linea:
        return primera_linea.split(":", 1)[1].strip()
    return primera_linea

