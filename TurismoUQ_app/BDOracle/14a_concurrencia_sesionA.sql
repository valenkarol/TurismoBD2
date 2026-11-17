-- =====================================================================
-- ENTREGA 3 · CONCURRENCIA  ·  SESIÓN A
-- Conectarse como: TURISMOUQ
--
-- Qué pide el enunciado:
--   "Experimento documentado con dos sesiones intentando reservar la
--    misma habitación al tiempo. Muestren el bloqueo, apliquen
--    SELECT ... FOR UPDATE y comparen el comportamiento antes y después."
--
-- CÓMO SE EJECUTA (importante)
--   * Este archivo NO se corre de una sola vez: se ejecuta PASO A PASO,
--     alternando con 14b_concurrencia_sesion_B.sql.
--   * Se necesitan DOS sesiones reales de TURISMOUQ. En SQL Developer:
--       - Sesión A: abrir este archivo con la conexión TURISMOUQ.
--       - Sesión B: con la conexión TURISMOUQ seleccionada, presionar
--         Ctrl + Shift + N (hoja de trabajo NO compartida) y abrir allí
--         el archivo 14b. Esa hoja tiene su propia sesión.
--   * Para ejecutar un paso: seleccionar el bloque completo (desde
--     DECLARE/BEGIN/SELECT hasta el "/" o el ";") y presionar F5.
--   * El orden está marcado en cada paso:  A1 -> B1 -> A2 -> B2 -> ...
--   * (Opcional) Una tercera hoja como SYSTEM con 14c para VER el bloqueo.
--
-- Datos del experimento
--   Habitación: la de menor id en estado DISPONIBLE (la misma en A y B).
--   Sesión A reserva para el cliente de menor id; B para el siguiente.
--   PARTE 1 (antes)   -> 10 al 13 de agosto de 2027
--   PARTE 2 (después) -> 10 al 13 de septiembre de 2027
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

-- ---------------------------------------------------------------------
-- A0. Preparación (una sola vez, solo en la sesión A)
--     Cancela reservas de un experimento anterior y verifica que la
--     habitación esté libre en las dos fechas. Debe mostrar S y S.
-- ---------------------------------------------------------------------
BEGIN
    FOR x IN (SELECT r.id_reserva
              FROM RESERVA r
              JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
              WHERE rh.id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION
                                        WHERE estado = 'DISPONIBLE')
                AND r.fecha_checkin IN (DATE '2027-08-10', DATE '2027-09-10')
                AND r.estado IN ('PENDIENTE', 'CONFIRMADA')) LOOP
        PKG_TURISMOUQ.sp_cancelar_reserva(x.id_reserva, 'N');
    END LOOP;
    COMMIT;
END;
/

SELECT h.id_habitacion, h.numero,
       PKG_TURISMOUQ.fn_habitacion_disponible(h.id_habitacion, DATE '2027-08-10', DATE '2027-08-13') AS libre_agosto,
       PKG_TURISMOUQ.fn_habitacion_disponible(h.id_habitacion, DATE '2027-09-10', DATE '2027-09-13') AS libre_septiembre
FROM HABITACION h
WHERE h.id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION WHERE estado = 'DISPONIBLE');


-- =====================================================================
-- PARTE 1 · ANTES: sin SELECT ... FOR UPDATE   (p_bloquear => 'N')
-- =====================================================================

-- ---------------------------------------------------------------------
-- A1. La sesión A reserva la habitación y NO confirma todavía.
--     Resultado: "Sesión A: reserva ... creada".
-- ---------------------------------------------------------------------
DECLARE
    v_cli     NUMBER;
    v_hab     NUMBER;
    v_reserva NUMBER;
    v_valor   NUMBER;
BEGIN
    SELECT MIN(id_cliente)    INTO v_cli FROM CLIENTE;
    SELECT MIN(id_habitacion) INTO v_hab FROM HABITACION WHERE estado = 'DISPONIBLE';

    PKG_TURISMOUQ.sp_crear_reserva(
        p_id_cliente    => v_cli,
        p_id_habitacion => v_hab,
        p_fecha_in      => DATE '2027-08-10',
        p_fecha_out     => DATE '2027-08-13',
        p_huespedes     => 1,
        p_id_reserva    => v_reserva,
        p_valor_estadia => v_valor,
        p_commit        => 'N',      -- la transacción queda abierta
        p_bloquear      => 'N');     -- SIN bloqueo (como en la entrega 2)

    DBMS_OUTPUT.PUT_LINE('Sesión A: reserva ' || v_reserva || ' creada (sin COMMIT).');
END;
/

--  >>> Ir a la SESIÓN B y ejecutar B1.
--      B también logra reservar, y de inmediato: no hubo ningún bloqueo.

-- ---------------------------------------------------------------------
-- A2. La sesión A confirma.
-- ---------------------------------------------------------------------
COMMIT;

--  >>> Ir a la SESIÓN B y ejecutar B2 (COMMIT).

-- ---------------------------------------------------------------------
-- A3. Resultado del "antes": la MISMA habitación quedó vendida DOS veces
--     para las mismas noches (deben salir 2 filas).
--
--     ¿Por qué pasó? Oracle trabaja en READ COMMITTED: cada sesión solo
--     ve datos confirmados. Cuando B revisó la disponibilidad, la reserva
--     de A todavía no tenía COMMIT, así que para B la habitación estaba
--     libre. Ni el procedimiento ni el disparador de solapes (script 08)
--     podían ver la fila de la otra sesión. Es el problema de
--     concurrencia "dos clientes reservando el último cupo".
-- ---------------------------------------------------------------------
SELECT r.id_reserva, r.id_cliente, rh.id_habitacion,
       r.fecha_checkin, r.fecha_checkout, r.estado
FROM RESERVA r
JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
WHERE rh.id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION WHERE estado = 'DISPONIBLE')
  AND r.fecha_checkin = DATE '2027-08-10'
  AND r.estado <> 'CANCELADA';


-- =====================================================================
-- PARTE 2 · DESPUÉS: con SELECT ... FOR UPDATE   (p_bloquear => 'S')
--   sp_crear_reserva ejecuta primero (script 07, bloquear_habitacion):
--       SELECT id_habitacion FROM HABITACION
--       WHERE id_habitacion = :hab FOR UPDATE WAIT 20;
--   y solo después revisa la disponibilidad.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A4. La sesión A reserva (ahora con bloqueo) y NO confirma todavía.
--     La fila de la habitación queda bloqueada por la sesión A.
-- ---------------------------------------------------------------------
DECLARE
    v_cli     NUMBER;
    v_hab     NUMBER;
    v_reserva NUMBER;
    v_valor   NUMBER;
BEGIN
    SELECT MIN(id_cliente)    INTO v_cli FROM CLIENTE;
    SELECT MIN(id_habitacion) INTO v_hab FROM HABITACION WHERE estado = 'DISPONIBLE';

    PKG_TURISMOUQ.sp_crear_reserva(
        p_id_cliente    => v_cli,
        p_id_habitacion => v_hab,
        p_fecha_in      => DATE '2027-09-10',
        p_fecha_out     => DATE '2027-09-13',
        p_huespedes     => 1,
        p_id_reserva    => v_reserva,
        p_valor_estadia => v_valor,
        p_commit        => 'N',      -- la transacción queda abierta
        p_bloquear      => 'S');     -- CON bloqueo (valor por defecto)

    DBMS_OUTPUT.PUT_LINE('Sesión A: reserva ' || v_reserva || ' creada (sin COMMIT). Habitación bloqueada.');
END;
/

--  >>> Ir a la SESIÓN B y ejecutar B3.
--      B se queda "pensando": está esperando el bloqueo de A.
--      (Opcional: en la hoja de SYSTEM ejecutar 14c para ver el bloqueo
--       y tomar el pantallazo.)
--      Hay 20 segundos para volver aquí y ejecutar A5.

-- ---------------------------------------------------------------------
-- A5. La sesión A confirma. En ese instante B se desbloquea, revisa la
--     disponibilidad, YA ve la reserva de A y es rechazada (ORA-20002).
-- ---------------------------------------------------------------------
COMMIT;

-- ---------------------------------------------------------------------
-- A6. Resultado del "después": solo UNA reserva para esas noches.
-- ---------------------------------------------------------------------
SELECT r.id_reserva, r.id_cliente, rh.id_habitacion,
       r.fecha_checkin, r.fecha_checkout, r.estado
FROM RESERVA r
JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
WHERE rh.id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION WHERE estado = 'DISPONIBLE')
  AND r.fecha_checkin = DATE '2027-09-10'
  AND r.estado <> 'CANCELADA';


-- =====================================================================
-- PARTE 3 · Opciones de SELECT ... FOR UPDATE  (NOWAIT, WAIT, lectura)
-- =====================================================================

-- ---------------------------------------------------------------------
-- A7. La sesión A bloquea la fila de la habitación y la deja bloqueada.
-- ---------------------------------------------------------------------
SELECT id_habitacion, numero, estado
FROM HABITACION
WHERE id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION WHERE estado = 'DISPONIBLE')
FOR UPDATE;

--  >>> Ir a la SESIÓN B y ejecutar B4, B5 y B6.

-- ---------------------------------------------------------------------
-- A8. La sesión A libera el bloqueo.
-- ---------------------------------------------------------------------
ROLLBACK;


-- =====================================================================
-- A9. Limpieza final (después de tomar los pantallazos)
--     Cancela las reservas del experimento, incluida la doble venta de
--     la PARTE 1, para que la base quede consistente.
-- =====================================================================
BEGIN
    FOR x IN (SELECT r.id_reserva
              FROM RESERVA r
              JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
              WHERE rh.id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION
                                        WHERE estado = 'DISPONIBLE')
                AND r.fecha_checkin IN (DATE '2027-08-10', DATE '2027-09-10')
                AND r.estado IN ('PENDIENTE', 'CONFIRMADA')) LOOP
        PKG_TURISMOUQ.sp_cancelar_reserva(x.id_reserva, 'N');
        DBMS_OUTPUT.PUT_LINE('Reserva del experimento ' || x.id_reserva || ' cancelada.');
    END LOOP;
    COMMIT;
END;
/