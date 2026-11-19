
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF


-- ---------------------------------------------------------------------
-- B1. (después de A1)  La sesión B reserva la MISMA habitación para las
--     MISMAS noches. 
DECLARE
    v_cli     NUMBER;
    v_hab     NUMBER;
    v_reserva NUMBER;
    v_valor   NUMBER;
BEGIN
    SELECT MIN(id_cliente) + 1 INTO v_cli FROM CLIENTE;
    SELECT MIN(id_habitacion)  INTO v_hab FROM HABITACION WHERE estado = 'DISPONIBLE';

    PKG_TURISMOUQ.sp_crear_reserva(
        p_id_cliente    => v_cli,
        p_id_habitacion => v_hab,
        p_fecha_in      => DATE '2027-08-10',
        p_fecha_out     => DATE '2027-08-13',
        p_huespedes     => 1,
        p_id_reserva    => v_reserva,
        p_valor_estadia => v_valor,
        p_commit        => 'N',
        p_bloquear      => 'N');     -- SIN bloqueo

    DBMS_OUTPUT.PUT_LINE('Sesión B: reserva ' || v_reserva || ' creada (sin COMMIT). No hubo espera.');
END;
/

--  >>> Volver a la SESIÓN A y ejecutar A2 (COMMIT).

-- ---------------------------------------------------------------------
-- B2. (después de A2)  La sesión B también confirma.

COMMIT;



-- ---------------------------------------------------------------------
-- B3. (después de A4)  La sesión B intenta reservar la misma habitación.
--     Ahora NO termina de inmediato: se queda esperando porque la sesión
--     A tiene bloqueada la fila de la habitación.
DECLARE
    v_cli     NUMBER;
    v_hab     NUMBER;
    v_reserva NUMBER;
    v_valor   NUMBER;
BEGIN
    SELECT MIN(id_cliente) + 1 INTO v_cli FROM CLIENTE;
    SELECT MIN(id_habitacion)  INTO v_hab FROM HABITACION WHERE estado = 'DISPONIBLE';

    PKG_TURISMOUQ.sp_crear_reserva(
        p_id_cliente    => v_cli,
        p_id_habitacion => v_hab,
        p_fecha_in      => DATE '2027-09-10',
        p_fecha_out     => DATE '2027-09-13',
        p_huespedes     => 1,
        p_id_reserva    => v_reserva,
        p_valor_estadia => v_valor,
        p_commit        => 'N',
        p_bloquear      => 'S');     -- CON bloqueo

    DBMS_OUTPUT.PUT_LINE('Sesión B: reserva ' || v_reserva || ' creada. (No se esperaba este resultado.)');
EXCEPTION
    WHEN PKG_TURISMOUQ.e_no_disponible THEN
        DBMS_OUTPUT.PUT_LINE('Sesión B: RECHAZADA después de esperar a A -> ' || SQLERRM);
    WHEN PKG_TURISMOUQ.e_habitacion_ocupada THEN
        DBMS_OUTPUT.PUT_LINE('Sesión B: se cansó de esperar (20 s) -> ' || SQLERRM);
END;
/

-- La sesión B no dejó nada pendiente
ROLLBACK;

--  >>> Volver a la SESIÓN A y ejecutar A6: sale 1 sola reserva.


-- ---------------------------------------------------------------------
-- B4. NOWAIT: pide el bloqueo y, como está ocupado, NO espera.

SELECT id_habitacion, numero, estado
FROM HABITACION
WHERE id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION WHERE estado = 'DISPONIBLE')
FOR UPDATE NOWAIT;

-- ---------------------------------------------------------------------
-- B5. WAIT 5: espera máximo 5 segundos.

SELECT id_habitacion, numero, estado
FROM HABITACION
WHERE id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION WHERE estado = 'DISPONIBLE')
FOR UPDATE WAIT 5;

-- ---------------------------------------------------------------------
-- B6. Lectura normal (sin FOR UPDATE): responde de inmediato.

SELECT id_habitacion, numero, estado
FROM HABITACION
WHERE id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION WHERE estado = 'DISPONIBLE');

--  >>> Volver a la SESIÓN A y ejecutar A8 (ROLLBACK) y A9 (limpieza).

-- ---------------------------------------------------------------------
-- B7. Cierre de la sesión B: libera cualquier bloqueo que haya quedado.
-- ---------------------------------------------------------------------
ROLLBACK;