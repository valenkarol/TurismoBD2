"""
diagnostico_busqueda.py  ·  ¿Por qué se queda pegada sp_buscar_disponibles?

Ejecutar con el entorno activo, dentro de TurismoUQ_app:
    python diagnostico_busqueda.py

Al inicio pide la clave de SYSTEM (la de tu Oracle). Con ella, mientras la
búsqueda está corriendo, mira desde otra sesión QUÉ está esperando Oracle.
La clave no se guarda en ningún lado.
"""
import getpass
import os
import threading
import time
from datetime import date, timedelta

import oracledb

import db

LLEGADA = date.today() + timedelta(days=1)
SALIDA = LLEGADA + timedelta(days=1)
DSN = os.getenv("DB_DSN", "localhost:1521/XEPDB1")

CONSULTA_DIRECTA = """
WITH libres AS (
    SELECT h.id_habitacion
    FROM HABITACION h
    JOIN ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
    WHERE h.estado = 'DISPONIBLE' AND h.capacidad >= 2 {filtro}
      AND NOT EXISTS (SELECT 1 FROM RESERVA_HABITACION rh
                      JOIN RESERVA r ON r.id_reserva = rh.id_reserva
                      WHERE rh.id_habitacion = h.id_habitacion
                        AND r.estado <> 'CANCELADA'
                        AND r.fecha_checkin < :salida AND r.fecha_checkout > :llegada)
),
tramos AS (
    SELECT ta.id_habitacion,
           LEAST(TRUNC(te.fecha_fin), :salida) - GREATEST(TRUNC(te.fecha_inicio), :llegada) AS n,
           ta.valor_noche
    FROM TARIFA ta JOIN TEMPORADA te ON te.id_temporada = ta.id_temporada
    WHERE te.fecha_inicio < :salida AND te.fecha_fin > :llegada
)
SELECT COUNT(*) FROM (
    SELECT l.id_habitacion FROM libres l JOIN tramos t ON t.id_habitacion = l.id_habitacion
    GROUP BY l.id_habitacion HAVING SUM(t.n) = 1
)"""


def medir(nombre, funcion, limite_ms=30_000):
    print(f"\n>> {nombre} ...", flush=True)
    inicio = time.time()
    try:
        with db.conexion() as con:
            con.call_timeout = limite_ms
            with con.cursor() as cur:
                r = funcion(cur)
        print(f"   OK en {time.time() - inicio:.2f} s  ->  {r}")
    except oracledb.DatabaseError as e:
        print(f"   FALLÓ en {time.time() - inicio:.2f} s  ->  {str(e).splitlines()[0]}")


clave_system = getpass.getpass("Clave de SYSTEM (Enter para omitir el paso C): ")

# A. ¿Qué versión del procedimiento tiene Oracle?
medir("A. Versión de sp_buscar_disponibles en Oracle", lambda cur: (
    "NUEVA (por conjuntos)" if cur.execute(
        "SELECT COUNT(*) FROM user_source WHERE name = 'PKG_TURISMOUQ' "
        "AND type = 'PACKAGE BODY' AND text LIKE '%por conjuntos%'").fetchone()[0]
    else "ANTIGUA (llama fn_cotizar_estadia por fila)"))

# B. La misma consulta del procedimiento, escrita directo en SQL
medir("B1. Consulta directa, municipio fijo", lambda cur: cur.execute(
    CONSULTA_DIRECTA.format(filtro="AND a.id_municipio = 1"),
    {"llegada": LLEGADA, "salida": SALIDA}).fetchone())
medir("B2. Consulta directa con el patrón (:m IS NULL OR ...)", lambda cur: cur.execute(
    CONSULTA_DIRECTA.format(filtro="AND (:m IS NULL OR a.id_municipio = :m) "
                                   "AND (:t IS NULL OR a.id_tipo_alojamiento = :t)"),
    {"llegada": LLEGADA, "salida": SALIDA, "m": 1, "t": None}).fetchone())

# C. El procedimiento, mientras SYSTEM mira qué espera la sesión
resultado = {}


def correr_procedimiento():
    inicio = time.time()
    try:
        with db.conexion() as con:
            con.call_timeout = 30_000
            con.action = "DIAGNOSTICO_BUSQUEDA"
            with con.cursor() as cur:
                ref = cur.var(oracledb.DB_TYPE_CURSOR)
                cur.callproc("PKG_TURISMOUQ.sp_buscar_disponibles",
                             [LLEGADA, SALIDA, 2, ref], {"p_id_municipio": 1})
                print(f"   (abrir el cursor tardó {time.time() - inicio:.2f} s)", flush=True)
                filas = ref.getvalue().fetchall()
        resultado["ok"] = f"OK en {time.time() - inicio:.2f} s -> {len(filas)} habitaciones"
    except oracledb.DatabaseError as e:
        resultado["ok"] = f"FALLÓ en {time.time() - inicio:.2f} s -> {str(e).splitlines()[0]}"


print("\n>> C. sp_buscar_disponibles", flush=True)
hilo = threading.Thread(target=correr_procedimiento)
hilo.start()

if clave_system:
    time.sleep(6)
    if hilo.is_alive():
        try:
            with oracledb.connect(user="SYSTEM", password=clave_system, dsn=DSN) as sc:
                cur = sc.cursor()
                cur.execute("""
                    SELECT s.sid, s.status, s.event, s.wait_class, s.seconds_in_wait,
                           s.blocking_session, s.sql_id, s.action,
                           (SELECT SUBSTR(q.sql_text, 1, 120) FROM v$sql q
                             WHERE q.sql_id = s.sql_id AND ROWNUM = 1) AS sql_text
                    FROM v$session s
                    WHERE s.username = 'TURISMOUQ'
                    ORDER BY s.last_call_et DESC""")
                print("   Sesiones de TURISMOUQ en este momento:")
                for f in cur.fetchall():
                    print("   -", dict(zip([d[0].lower() for d in cur.description], f)))
                cur.execute("""
                    SELECT b.sid, b.username, b.program, b.status, b.event
                    FROM v$session b
                    WHERE b.sid IN (SELECT blocking_session FROM v$session
                                    WHERE username = 'TURISMOUQ' AND blocking_session IS NOT NULL)""")
                bloqueadores = cur.fetchall()
                print("   Sesiones que bloquean:", bloqueadores or "ninguna")
        except oracledb.DatabaseError as e:
            print("   No se pudo entrar como SYSTEM:", str(e).splitlines()[0])

hilo.join()
print("  ", resultado.get("ok"))
print("\nCopia todo este resultado y envíaselo a Claude.")