SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

-- ---------------------------------------------------------------------
-- A0. Preparación (una sola vez, solo en la sesión A)

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

-- ---------------------------------------------------------------------
-- A1. La sesión A reserva la habitación y NO confirma todavía.
--     Resultado: "Sesión A: reserva ... creada".

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
-- A3. 
SELECT r.id_reserva, r.id_cliente, rh.id_habitacion,
       r.fecha_checkin, r.fecha_checkout, r.estado
FROM RESERVA r
JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
WHERE rh.id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION WHERE estado = 'DISPONIBLE')
  AND r.fecha_checkin = DATE '2027-08-10'
  AND r.estado <> 'CANCELADA';


-- ---------------------------------------------------------------------
-- A4. La sesión A reserva (ahora con bloqueo) y NO confirma todavía.

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


-- ---------------------------------------------------------------------
-- A5. La sesión A confirma. En ese instante B se desbloquea
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
-- A9. Limpieza final
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