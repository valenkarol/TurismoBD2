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


def iniciar_pool():
    """Crea un pool de conexiones al arrancar la app."""
    global _pool
    _pool = oracledb.create_pool(
        user=os.getenv("DB_USER", "TURISMOUQ"),
        password=os.getenv("DB_PASSWORD", "Turismo123"),
        dsn=os.getenv("DB_DSN", "localhost:1521/XEPDB1"),
        min=1,
        max=5,
        increment=1,
    )


@contextmanager
def conexion():
    """Presta una conexión del pool y la devuelve al terminar.
    Si no se hizo commit, Oracle descarta los cambios."""
    if _pool is None:
        iniciar_pool()
    con = _pool.acquire()
    try:
        yield con
    finally:
        _pool.release(con)


def _filas_como_dict(cursor):
    """Hace que cada fila llegue como diccionario: fila['nombre']."""
    columnas = [c[0].lower() for c in cursor.description]
    cursor.rowfactory = lambda *valores: dict(zip(columnas, valores))


def leer_cursor(cursor):
    """Convierte un SYS_REFCURSOR (o un cursor normal) en lista de dicts."""
    _filas_como_dict(cursor)
    return cursor.fetchall()


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
    primera_linea = texto.splitlines()[0] if texto else str(err)
    codigo = getattr(err, "code", 0)
    if 20000 <= codigo <= 20999 and ":" in primera_linea:
        return primera_linea.split(":", 1)[1].strip()
    return primera_linea
