-- =====================================================================
-- ENTREGA 3 · CONCURRENCIA  ·  MONITOREO DEL BLOQUEO
-- Conectarse como: SYSTEM (en XEPDB1). TURISMOUQ no tiene permiso sobre
-- las vistas V$, por eso se consulta desde la sesión del administrador.
--
-- Cuándo ejecutarlo: en el paso B3 del experimento, mientras la sesión B
-- está esperando a que la sesión A confirme. Sirve para el pantallazo de
-- "muestren el bloqueo".
-- =====================================================================

-- 1. Sesiones de TURISMOUQ.
--    La sesión B aparece con:
--      BLOCKING_SESSION = SID de la sesión A   (quién la tiene bloqueada)
--      EVENT            = enq: TX - row lock contention
--    Nota: si la interfaz Flask está encendida, sus conexiones también
--    aparecen como TURISMOUQ (STATUS INACTIVE, sin BLOCKING_SESSION).
SELECT sid, serial#, username, status, event, blocking_session, seconds_in_wait
FROM v$session
WHERE username = 'TURISMOUQ'
ORDER BY sid;

-- 2. Solo las sesiones que están esperando a otra.
SELECT sid AS sesion_esperando, blocking_session AS sesion_que_bloquea,
       event, seconds_in_wait
FROM v$session
WHERE blocking_session IS NOT NULL;

-- 3. Objetos sobre los que hay bloqueos en este momento.
--    Aparece HABITACION (la fila tomada con SELECT ... FOR UPDATE) y las
--    tablas donde la sesión A insertó (RESERVA, RESERVA_HABITACION).
SELECT s.sid, s.username, o.object_name AS tabla,
       DECODE(l.locked_mode,
              2, 'ROW SHARE',
              3, 'ROW EXCLUSIVE',
              6, 'EXCLUSIVE',
              TO_CHAR(l.locked_mode)) AS modo_bloqueo
FROM v$locked_object l
JOIN dba_objects o ON o.object_id = l.object_id
JOIN v$session s   ON s.sid = l.session_id
WHERE s.username = 'TURISMOUQ'
ORDER BY s.sid, o.object_name;