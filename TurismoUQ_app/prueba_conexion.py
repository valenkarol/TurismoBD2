"""
prueba_conexion.py  ·  Diagnóstico paso a paso (sin Flask)

Ejecutar en la terminal, con el entorno activo, dentro de TurismoUQ_app:
    python prueba_conexion.py

Cada paso muestra cuánto tardó. El primer paso que falle o tarde
mucho indica dónde está el problema.
"""
import time
from datetime import date, timedelta

import oracledb

import db

LLEGADA = date.today() + timedelta(days=1)
SALIDA = LLEGADA + timedelta(days=1)


def paso(nombre, funcion):
    print(f"\n>> {nombre} ...", flush=True)
    inicio = time.time()
    try:
        resultado = funcion()
        print(f"   OK en {time.time() - inicio:.2f} s  ->  {resultado}")
    except oracledb.DatabaseError as e:
        print(f"   FALLÓ en {time.time() - inicio:.2f} s  ->  {e}")
        raise SystemExit(1)


with db.conexion() as con:
    con.call_timeout = 30_000  # cada paso se corta a los 30 s
    cur = con.cursor()

    paso("1. Conexión a Oracle (SELECT 1)",
         lambda: cur.execute("SELECT USER, SYS_CONTEXT('USERENV','CON_NAME') FROM dual").fetchone())

    paso("2. Objetos inválidos del esquema",
         lambda: cur.execute("SELECT object_name || ' ' || object_type FROM user_objects "
                             "WHERE status <> 'VALID'").fetchall() or "ninguno")

    paso("3. Índices de 12_indices_interfaz.sql",
         lambda: [r[0] for r in cur.execute("SELECT index_name FROM user_indexes "
                                             "WHERE index_name LIKE 'IX\\_%' ESCAPE '\\'").fetchall()]
         or "NO EXISTEN")

    paso("4. Consulta SQL simple (habitaciones de Armenia)",
         lambda: cur.execute("SELECT COUNT(*) FROM HABITACION h JOIN ALOJAMIENTO a "
                             "ON a.id_alojamiento = h.id_alojamiento WHERE a.id_municipio = 1").fetchone())

    paso("5. Habitaciones libres SIN usar el paquete",
         lambda: cur.execute("""
             SELECT COUNT(*) FROM HABITACION h
             JOIN ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
             WHERE a.id_municipio = 1 AND h.estado = 'DISPONIBLE'
               AND NOT EXISTS (SELECT 1 FROM RESERVA_HABITACION rh
                               JOIN RESERVA r ON r.id_reserva = rh.id_reserva
                               WHERE rh.id_habitacion = h.id_habitacion
                                 AND r.estado <> 'CANCELADA'
                                 AND r.fecha_checkin < :salida AND r.fecha_checkout > :llegada)""",
             {"llegada": LLEGADA, "salida": SALIDA}).fetchone())

    paso("6. Una llamada al paquete (precio de la habitación 1)",
         lambda: cur.callfunc("PKG_TURISMOUQ.fn_cotizar_estadia", oracledb.DB_TYPE_NUMBER,
                              [1, LLEGADA, SALIDA]))

    def buscar():
        ref = cur.var(oracledb.DB_TYPE_CURSOR)
        cur.callproc("PKG_TURISMOUQ.sp_buscar_disponibles", [LLEGADA, SALIDA, 2, ref],
                     {"p_id_municipio": 1})
        return f"{len(ref.getvalue().fetchall())} habitaciones"

    paso("7. sp_buscar_disponibles (lo mismo que hace la pantalla)", buscar)

print("\nTodo respondió. Si la página sigue lenta, el problema está en la interfaz.")