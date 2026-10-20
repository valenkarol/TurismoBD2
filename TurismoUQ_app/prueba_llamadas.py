"""
prueba_llamadas.py  ·  ¿Qué forma de llamar al paquete se queda pegada?

Ejecutar con el entorno activo, dentro de TurismoUQ_app:
    python prueba_llamadas.py

Cada prueba usa su propia conexión y se corta a los 10 s.
No guarda nada en la base (todo lo que escribe se deshace con ROLLBACK).
"""
import platform
import time
from datetime import date, datetime, timedelta

import oracledb

import db

LLEGADA = date.today() + timedelta(days=60)
SALIDA = LLEGADA + timedelta(days=1)
LLEGADA_DT = datetime(LLEGADA.year, LLEGADA.month, LLEGADA.day)
SALIDA_DT = datetime(SALIDA.year, SALIDA.month, SALIDA.day)


def prueba(nombre, funcion):
    print(f"\n>> {nombre}", flush=True)
    inicio = time.time()
    try:
        with db.conexion() as con:
            con.call_timeout = 10_000
            with con.cursor() as cur:
                r = funcion(cur)
            con.rollback()
        print(f"   OK en {time.time() - inicio:.2f} s -> {r}")
    except oracledb.DatabaseError as e:
        texto = str(e).splitlines()[0]
        marca = "SE QUEDÓ PEGADA" if "DPY-4024" in texto else "respondió con error (no se pegó)"
        print(f"   {marca} en {time.time() - inicio:.2f} s -> {texto}")


def con_cursor(cur, sql, **binds):
    ref = cur.var(oracledb.DB_TYPE_CURSOR)
    cur.execute(sql, cursor_salida=ref, **binds)
    return f"{len(ref.getvalue().fetchall())} filas"


with db.conexion() as con:
    print("python-oracledb", oracledb.__version__, "| Python", platform.python_version(),
          "| Oracle", con.version, "| modo thin:", con.thin)

prueba("1. sp_buscar_disponibles con callproc SOLO posicional", lambda cur: (
    lambda ref: (cur.callproc("PKG_TURISMOUQ.sp_buscar_disponibles", [LLEGADA, SALIDA, 2, ref]),
                 f"{len(ref.getvalue().fetchall())} filas")[1])(cur.var(oracledb.DB_TYPE_CURSOR)))

prueba("2. sp_buscar_disponibles con bloque BEGIN...END y nombres", lambda cur: con_cursor(cur,
    "BEGIN PKG_TURISMOUQ.sp_buscar_disponibles(p_fecha_in => :llegada, p_fecha_out => :salida, "
    "p_huespedes => 2, p_cursor => :cursor_salida, p_id_municipio => 1); END;",
    llegada=LLEGADA, salida=SALIDA))

prueba("3. Igual que 2, pero fechas como datetime", lambda cur: con_cursor(cur,
    "BEGIN PKG_TURISMOUQ.sp_buscar_disponibles(p_fecha_in => :llegada, p_fecha_out => :salida, "
    "p_huespedes => 2, p_cursor => :cursor_salida, p_id_municipio => 1); END;",
    llegada=LLEGADA_DT, salida=SALIDA_DT))

prueba("4. Igual que 2, pero fechas escritas en el SQL (sin enviar fechas)", lambda cur: con_cursor(cur,
    "BEGIN PKG_TURISMOUQ.sp_buscar_disponibles(p_fecha_in => TRUNC(SYSDATE) + 60, "
    "p_fecha_out => TRUNC(SYSDATE) + 61, p_huespedes => 2, p_cursor => :cursor_salida, "
    "p_id_municipio => 1); END;"))

prueba("5. sp_detalle_estadia (también devuelve cursor)", lambda cur: con_cursor(cur,
    "BEGIN PKG_TURISMOUQ.sp_detalle_estadia(:hab, :llegada, :salida, :cursor_salida); END;",
    hab=1, llegada=LLEGADA, salida=SALIDA))


def crear_reserva(cur):
    id_res, valor = cur.var(oracledb.DB_TYPE_NUMBER), cur.var(oracledb.DB_TYPE_NUMBER)
    cur.callproc("PKG_TURISMOUQ.sp_crear_reserva",
                 [1, 1, LLEGADA, SALIDA, 1, id_res, valor, None, "N"])
    return f"reserva {id_res.getvalue()} por {valor.getvalue()} (se deshace)"


prueba("6. sp_crear_reserva con salidas numéricas, sin cursor (se deshace)", crear_reserva)

prueba("7. Cursor de un SELECT sencillo, sin el paquete", lambda cur: con_cursor(cur,
    "BEGIN OPEN :cursor_salida FOR SELECT nombre FROM MUNICIPIO; END;"))

print("\nCopia todo este resultado y envíaselo a Claude.")