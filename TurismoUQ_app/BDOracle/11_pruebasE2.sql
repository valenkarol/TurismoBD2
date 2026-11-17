-- =====================================================================
-- Demostración de cada requisito. Cada bloque imprime "OK" o "FALLO".
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

-- ---------------------------------------------------------------------
-- P1. fn_valor_estadia: dentro de una temporada, cruzando dos temporadas
--     y cruzando el cambio de año. Se compara con el cálculo a mano.
-- ---------------------------------------------------------------------
DECLARE
    v_hab      NUMBER;
    v_obtenido NUMBER;
    v_esperado NUMBER;

    FUNCTION tarifa (p_hab NUMBER, p_temporada VARCHAR2) RETURN NUMBER IS
        v NUMBER;
    BEGIN
        SELECT ta.valor_noche INTO v
        FROM TARIFA ta JOIN TEMPORADA te ON te.id_temporada = ta.id_temporada
        WHERE ta.id_habitacion = p_hab AND te.nombre = p_temporada;
        RETURN v;
    END;

    PROCEDURE comparar (p_caso VARCHAR2, p_obtenido NUMBER, p_esperado NUMBER) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(
            CASE WHEN p_obtenido = p_esperado THEN 'OK     ' ELSE 'FALLO  ' END ||
            p_caso || ' -> obtenido ' || p_obtenido || ', esperado ' || p_esperado);
    END;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== P1 fn_valor_estadia ===');
    SELECT MIN(id_habitacion) INTO v_hab FROM HABITACION;

    -- 3 noches, todas en TEMPORADA MEDIA 2027
    v_obtenido := PKG_TURISMOUQ.fn_valor_estadia(v_hab, DATE '2027-05-10', DATE '2027-05-13');
    v_esperado := 3 * tarifa(v_hab, 'TEMPORADA MEDIA 2027');
    comparar('Una temporada (05-10 a 05-13)', v_obtenido, v_esperado);

    -- 3 noches BAJA 2027 (29, 30, 31 mar) + 2 noches MEDIA 2027 (1, 2 abr)
    v_obtenido := PKG_TURISMOUQ.fn_valor_estadia(v_hab, DATE '2027-03-29', DATE '2027-04-03');
    v_esperado := 3 * tarifa(v_hab, 'TEMPORADA BAJA 2027')
                + 2 * tarifa(v_hab, 'TEMPORADA MEDIA 2027');
    comparar('Dos temporadas (03-29 a 04-03)', v_obtenido, v_esperado);

    -- 2 noches ALTA DICIEMBRE 2026 + 1 noche BAJA 2027
    v_obtenido := PKG_TURISMOUQ.fn_valor_estadia(v_hab, DATE '2026-12-30', DATE '2027-01-02');
    v_esperado := 2 * tarifa(v_hab, 'TEMPORADA ALTA DICIEMBRE 2026')
                + 1 * tarifa(v_hab, 'TEMPORADA BAJA 2027');
    comparar('Cambio de año (2026-12-30 a 2027-01-02)', v_obtenido, v_esperado);

    -- 4 temporadas en una estadía larga: 06-25 a 10-05 de 2027
    v_obtenido := PKG_TURISMOUQ.fn_valor_estadia(v_hab, DATE '2027-06-25', DATE '2027-10-05');
    v_esperado := 6  * tarifa(v_hab, 'TEMPORADA MEDIA 2027')
                + 92 * tarifa(v_hab, 'TEMPORADA ALTA 2027')
                + 4  * tarifa(v_hab, 'TEMPORADA BAJA OCT-NOV 2027');
    comparar('Estadía larga (06-25 a 10-05)', v_obtenido, v_esperado);
END;
/

-- Desglose por temporada (lo que vería la interfaz al cotizar)
DECLARE
    v_hab    NUMBER;
    c        SYS_REFCURSOR;
    v_temp   VARCHAR2(100);
    v_desde  DATE;
    v_hasta  DATE;
    v_noches NUMBER;
    v_valor  NUMBER;
    v_sub    NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== P1b Desglose 2027-03-29 a 2027-04-03 ===');
    SELECT MIN(id_habitacion) INTO v_hab FROM HABITACION;
    PKG_TURISMOUQ.sp_detalle_estadia(v_hab, DATE '2027-03-29', DATE '2027-04-03', c);
    LOOP
        FETCH c INTO v_temp, v_desde, v_hasta, v_noches, v_valor, v_sub;
        EXIT WHEN c%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE(RPAD(v_temp, 25) || TO_CHAR(v_desde, 'YYYY-MM-DD') || ' a ' ||
                             TO_CHAR(v_hasta, 'YYYY-MM-DD') || '  ' || v_noches ||
                             ' noches x ' || v_valor || ' = ' || v_sub);
    END LOOP;
    CLOSE c;
END;
/

-- ---------------------------------------------------------------------
-- P2. fn_valor_estadia: errores
-- ---------------------------------------------------------------------
DECLARE
    v NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== P2 errores de fn_valor_estadia ===');
    BEGIN
        v := PKG_TURISMOUQ.fn_valor_estadia(1, DATE '2027-05-10', DATE '2027-05-10');
        DBMS_OUTPUT.PUT_LINE('FALLO  se esperaba -20001');
    EXCEPTION WHEN PKG_TURISMOUQ.e_fechas_invalidas THEN
        DBMS_OUTPUT.PUT_LINE('OK     ' || SQLERRM);
    END;

    BEGIN
        -- 2028 no tiene temporadas: la noche del 2028-01-01 no tiene tarifa
        v := PKG_TURISMOUQ.fn_valor_estadia(1, DATE '2027-12-30', DATE '2028-01-03');
        DBMS_OUTPUT.PUT_LINE('FALLO  se esperaba -20006');
    EXCEPTION WHEN PKG_TURISMOUQ.e_sin_tarifa THEN
        DBMS_OUTPUT.PUT_LINE('OK     ' || SQLERRM);
    END;

    BEGIN
        v := PKG_TURISMOUQ.fn_valor_estadia(-1, DATE '2027-05-10', DATE '2027-05-12');
        DBMS_OUTPUT.PUT_LINE('FALLO  se esperaba -20005');
    EXCEPTION WHEN PKG_TURISMOUQ.e_habitacion_inexistente THEN
        DBMS_OUTPUT.PUT_LINE('OK     ' || SQLERRM);
    END;
END;
/

-- ---------------------------------------------------------------------
-- P3. Flujo completo: reserva que cruza temporadas + segunda habitación
--     + servicio + pago del anticipo -> queda CONFIRMADA
-- ---------------------------------------------------------------------
DECLARE
    v_cli    NUMBER;
    v_hab    NUMBER;
    v_hab2   NUMBER;
    v_res    NUMBER;
    v_valor  NUMBER;
    v_valor2 NUMBER;
    v_pago   NUMBER;
    v_total  NUMBER;
    v_estado VARCHAR2(20);
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== P3 flujo completo de reserva ===');
    SELECT MIN(id_cliente) INTO v_cli FROM CLIENTE;
    SELECT MIN(id_habitacion) INTO v_hab FROM HABITACION
    WHERE capacidad >= 2 AND estado = 'DISPONIBLE';

    SELECT MIN(h2.id_habitacion) INTO v_hab2
    FROM HABITACION h1
    JOIN HABITACION h2 ON h2.id_alojamiento = h1.id_alojamiento
                      AND h2.id_habitacion <> h1.id_habitacion
    WHERE h1.id_habitacion = v_hab
      AND h2.estado = 'DISPONIBLE';

    PKG_TURISMOUQ.sp_crear_reserva(
        p_id_cliente    => v_cli,
        p_id_habitacion => v_hab,
        p_fecha_in      => DATE '2027-06-28',   -- MEDIA 2027
        p_fecha_out     => DATE '2027-07-02',   -- ALTA 2027
        p_huespedes     => 2,
        p_id_reserva    => v_res,
        p_valor_estadia => v_valor,
        p_commit        => 'N');
    DBMS_OUTPUT.PUT_LINE('OK     reserva ' || v_res || ' creada, valor habitación 1: ' || v_valor);

    IF v_hab2 IS NOT NULL THEN
        PKG_TURISMOUQ.sp_agregar_habitacion(v_res, v_hab2, 1, v_valor2, 'N');
        DBMS_OUTPUT.PUT_LINE('OK     habitación ' || v_hab2 || ' agregada, valor: ' || v_valor2);
    END IF;

    PKG_TURISMOUQ.sp_agregar_servicio(v_res, 1, 2, 'N');
    v_total := PKG_TURISMOUQ.fn_total_reserva(v_res);
    DBMS_OUTPUT.PUT_LINE('       total reserva (hospedaje + servicios): ' || v_total);

    PKG_TURISMOUQ.sp_registrar_pago(v_res, CEIL(v_total * 0.30), 'PSE', v_pago, 'N');
    SELECT estado INTO v_estado FROM RESERVA WHERE id_reserva = v_res;
    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_estado = 'CONFIRMADA' THEN 'OK     ' ELSE 'FALLO  ' END ||
                         'tras pagar el 30 % la reserva quedó ' || v_estado);

    ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P4. sp_crear_reserva: las tres excepciones exigidas (+ fecha pasada)
-- ---------------------------------------------------------------------
DECLARE
    v_cli   NUMBER;
    v_hab   NUMBER;
    v_cap   NUMBER;
    v_res   NUMBER;
    v_res2  NUMBER;
    v_valor NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== P4 excepciones de sp_crear_reserva ===');
    SELECT MIN(id_cliente) INTO v_cli FROM CLIENTE;
    SELECT MIN(id_habitacion) INTO v_hab FROM HABITACION
    WHERE capacidad >= 2 AND estado = 'DISPONIBLE';
    SELECT capacidad INTO v_cap FROM HABITACION WHERE id_habitacion = v_hab;

    -- a) Habitación no disponible: se reserva 05-10 a 05-15 y se intenta 05-12 a 05-14
    PKG_TURISMOUQ.sp_crear_reserva(v_cli, v_hab, DATE '2027-05-10', DATE '2027-05-15', 2,
                                   v_res, v_valor, p_commit => 'N');
    BEGIN
        PKG_TURISMOUQ.sp_crear_reserva(v_cli, v_hab, DATE '2027-05-12', DATE '2027-05-14', 1,
                                       v_res2, v_valor, p_commit => 'N');
        DBMS_OUTPUT.PUT_LINE('FALLO  se esperaba -20002');
    EXCEPTION WHEN PKG_TURISMOUQ.e_no_disponible THEN
        DBMS_OUTPUT.PUT_LINE('OK     ' || SQLERRM);
    END;

    -- b) Checkout anterior o igual al checkin
    BEGIN
        PKG_TURISMOUQ.sp_crear_reserva(v_cli, v_hab, DATE '2027-08-10', DATE '2027-08-08', 1,
                                       v_res2, v_valor, p_commit => 'N');
        DBMS_OUTPUT.PUT_LINE('FALLO  se esperaba -20001');
    EXCEPTION WHEN PKG_TURISMOUQ.e_fechas_invalidas THEN
        DBMS_OUTPUT.PUT_LINE('OK     ' || SQLERRM);
    END;

    BEGIN
        PKG_TURISMOUQ.sp_crear_reserva(v_cli, v_hab, DATE '2027-08-10', DATE '2027-08-10', 1,
                                       v_res2, v_valor, p_commit => 'N');
        DBMS_OUTPUT.PUT_LINE('FALLO  se esperaba -20001');
    EXCEPTION WHEN PKG_TURISMOUQ.e_fechas_invalidas THEN
        DBMS_OUTPUT.PUT_LINE('OK     ' || SQLERRM);
    END;

    -- c) Capacidad excedida
    BEGIN
        PKG_TURISMOUQ.sp_crear_reserva(v_cli, v_hab, DATE '2027-08-10', DATE '2027-08-12', v_cap + 1,
                                       v_res2, v_valor, p_commit => 'N');
        DBMS_OUTPUT.PUT_LINE('FALLO  se esperaba -20003');
    EXCEPTION WHEN PKG_TURISMOUQ.e_capacidad_excedida THEN
        DBMS_OUTPUT.PUT_LINE('OK     ' || SQLERRM);
    END;

    -- d) Checkin en el pasado
    BEGIN
        PKG_TURISMOUQ.sp_crear_reserva(v_cli, v_hab, TRUNC(SYSDATE) - 5, TRUNC(SYSDATE) - 2, 1,
                                       v_res2, v_valor, p_commit => 'N');
        DBMS_OUTPUT.PUT_LINE('FALLO  se esperaba -20008');
    EXCEPTION WHEN PKG_TURISMOUQ.e_fecha_pasada THEN
        DBMS_OUTPUT.PUT_LINE('OK     ' || SQLERRM);
    END;

    -- e) Habitación de otro alojamiento en la misma reserva
    DECLARE
        v_otra NUMBER;
    BEGIN
        SELECT MIN(h.id_habitacion) INTO v_otra
        FROM HABITACION h
        WHERE h.estado = 'DISPONIBLE'
          AND h.id_alojamiento <> (SELECT id_alojamiento FROM HABITACION WHERE id_habitacion = v_hab);
        PKG_TURISMOUQ.sp_agregar_habitacion(v_res, v_otra, 1, v_valor, 'N');
        DBMS_OUTPUT.PUT_LINE('FALLO  se esperaba -20009');
    EXCEPTION WHEN PKG_TURISMOUQ.e_alojamiento_distinto THEN
        DBMS_OUTPUT.PUT_LINE('OK     ' || SQLERRM);
    END;

    ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P5. Disparador de fila: solape aunque se salte el procedimiento
-- ---------------------------------------------------------------------
DECLARE
    v_cli   NUMBER;
    v_hab   NUMBER;
    v_r1    NUMBER;
    v_r2    NUMBER;
    v_valor NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== P5 disparadores de solapamiento ===');
    SELECT MIN(id_cliente) INTO v_cli FROM CLIENTE;
    SELECT MIN(id_habitacion) INTO v_hab FROM HABITACION WHERE estado = 'DISPONIBLE';

    PKG_TURISMOUQ.sp_crear_reserva(v_cli, v_hab, DATE '2027-05-10', DATE '2027-05-15', 1,
                                   v_r1, v_valor, p_commit => 'N');

    -- a) INSERT directo (sin el procedimiento) que se cruza con la anterior
    BEGIN
        INSERT INTO RESERVA (fecha_checkin, fecha_checkout, estado, id_cliente)
        VALUES (DATE '2027-05-12', DATE '2027-05-14', 'PENDIENTE', v_cli)
        RETURNING id_reserva INTO v_r2;

        INSERT INTO RESERVA_HABITACION (id_reserva, id_habitacion, cantidad_huespedes)
        VALUES (v_r2, v_hab, 1);

        DBMS_OUTPUT.PUT_LINE('FALLO  el disparador debió impedir el solape');
    EXCEPTION WHEN PKG_TURISMOUQ.e_solapamiento THEN
        DBMS_OUTPUT.PUT_LINE('OK     ' || SQLERRM);
    END;

    -- b) Estadías contiguas NO se solapan (checkout de una = checkin de otra)
    BEGIN
        PKG_TURISMOUQ.sp_crear_reserva(v_cli, v_hab, DATE '2027-05-15', DATE '2027-05-17', 1,
                                       v_r2, v_valor, p_commit => 'N');
        DBMS_OUTPUT.PUT_LINE('OK     reserva contigua aceptada (' || v_r2 || ')');
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('FALLO  ' || SQLERRM);
    END;

    -- c) Mover las fechas de una reserva encima de otra (UPDATE en RESERVA)
    BEGIN
        UPDATE RESERVA SET fecha_checkout = DATE '2027-05-16' WHERE id_reserva = v_r1;
        DBMS_OUTPUT.PUT_LINE('FALLO  el disparador debió impedir el cambio de fechas');
    EXCEPTION WHEN PKG_TURISMOUQ.e_solapamiento THEN
        DBMS_OUTPUT.PUT_LINE('OK     ' || SQLERRM);
    END;

    -- d) Una reserva CANCELADA libera la habitación...
    PKG_TURISMOUQ.sp_cancelar_reserva(v_r1, 'N');
    BEGIN
        PKG_TURISMOUQ.sp_crear_reserva(v_cli, v_hab, DATE '2027-05-11', DATE '2027-05-13', 1,
                                       v_r2, v_valor, p_commit => 'N');
        DBMS_OUTPUT.PUT_LINE('OK     tras cancelar, la habitación se volvió a reservar (' || v_r2 || ')');
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('FALLO  ' || SQLERRM);
    END;

    -- e) ...y ya no se puede reactivar la cancelada porque ahora se cruza
    BEGIN
        UPDATE RESERVA SET estado = 'PENDIENTE' WHERE id_reserva = v_r1;
        DBMS_OUTPUT.PUT_LINE('FALLO  el disparador debió impedir la reactivación');
    EXCEPTION WHEN PKG_TURISMOUQ.e_solapamiento THEN
        DBMS_OUTPUT.PUT_LINE('OK     ' || SQLERRM);
    END;

    ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P6. Disparador de sentencia: auditoría de TARIFA
--     Se simula que el cambio lo hace el usuario "gerente1" de la interfaz
--     (CLIENT_IDENTIFIER). Se sube 1.000 y se vuelve a bajar: la tarifa
--     queda igual, pero quedan 2 sentencias auditadas.
-- ---------------------------------------------------------------------
DECLARE
    v_hab NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== P6 auditoría de TARIFA ===');
    SELECT MIN(id_habitacion) INTO v_hab FROM HABITACION;

    DBMS_SESSION.SET_IDENTIFIER('gerente1');

    UPDATE TARIFA SET valor_noche = valor_noche + 1000
    WHERE id_habitacion = v_hab
      AND id_temporada IN (SELECT id_temporada FROM TEMPORADA WHERE fecha_inicio >= DATE '2027-01-01');
    DBMS_OUTPUT.PUT_LINE('UPDATE +1000 sobre ' || SQL%ROWCOUNT || ' tarifas');

    UPDATE TARIFA SET valor_noche = valor_noche - 1000
    WHERE id_habitacion = v_hab
      AND id_temporada IN (SELECT id_temporada FROM TEMPORADA WHERE fecha_inicio >= DATE '2027-01-01');
    DBMS_OUTPUT.PUT_LINE('UPDATE -1000 sobre ' || SQL%ROWCOUNT || ' tarifas');

    COMMIT;
    DBMS_SESSION.CLEAR_IDENTIFIER;
END;
/

-- Una fila por sentencia (quién / cuándo / cuántas filas)
SELECT id_auditoria, operacion, filas_afectadas, usuario_bd, usuario_app,
       usuario_so, equipo, fecha_cambio
FROM AUDITORIA_TARIFA
ORDER BY id_auditoria DESC
FETCH FIRST 2 ROWS ONLY;

-- Detalle: valor anterior y nuevo de cada tarifa
SELECT id_auditoria, habitacion, temporada, valor_anterior, valor_nuevo, diferencia
FROM VW_AUDITORIA_TARIFA
WHERE id_auditoria >= (SELECT MAX(id_auditoria) - 1 FROM AUDITORIA_TARIFA)
ORDER BY id_auditoria, id_tarifa;

-- ---------------------------------------------------------------------
-- P7. Temporadas que se cruzan (disparador de sentencia extra)
-- ---------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== P7 temporada solapada ===');
    INSERT INTO TEMPORADA (nombre, fecha_inicio, fecha_fin, tipo)
    VALUES ('PRUEBA SOLAPE', DATE '2027-02-01', DATE '2027-02-15', 'ALTA');
    DBMS_OUTPUT.PUT_LINE('FALLO  se esperaba -20013');
    ROLLBACK;
EXCEPTION WHEN PKG_TURISMOUQ.e_temporada_solapada THEN
    DBMS_OUTPUT.PUT_LINE('OK     ' || SQLERRM);
    ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P8. Cursor explícito con parámetros: liquidación de julio 2025
-- ---------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== P8 liquidación mensual ===');
    PKG_TURISMOUQ.sp_liquidar_mes(p_anio => 2025, p_mes => 7, p_porcentaje_comision => 10);
END;
/

SELECT municipio, alojamiento, num_reservas, noches_vendidas,
       ingreso_hospedaje, ingreso_servicios, total_bruto, valor_comision, valor_neto
FROM VW_LIQUIDACION_MENSUAL
WHERE anio = 2025 AND mes = 7
ORDER BY valor_neto DESC
FETCH FIRST 10 ROWS ONLY;

-- Control cruzado: las noches liquidadas en julio deben coincidir con las
-- noches de reservas CONFIRMADA/FINALIZADA que caen en julio.
SELECT (SELECT SUM(noches_vendidas) FROM LIQUIDACION_MENSUAL WHERE anio = 2025 AND mes = 7) AS noches_liquidadas,
       (SELECT SUM(LEAST(r.fecha_checkout, DATE '2025-08-01') - GREATEST(r.fecha_checkin, DATE '2025-07-01'))
        FROM RESERVA r
        JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
        WHERE r.estado IN ('CONFIRMADA', 'FINALIZADA')
          AND r.fecha_checkin  < DATE '2025-08-01'
          AND r.fecha_checkout > DATE '2025-07-01') AS noches_calculadas
FROM dual;

-- ---------------------------------------------------------------------
-- P9. Buscador de disponibilidad (API para la interfaz)
-- ---------------------------------------------------------------------
DECLARE
    c        SYS_REFCURSOR;
    v_id     NUMBER;
    v_num    VARCHAR2(20);
    v_tipo   VARCHAR2(50);
    v_cap    NUMBER;
    v_ida    NUMBER;
    v_aloj   VARCHAR2(150);
    v_mun    VARCHAR2(100);
    v_tal    VARCHAR2(50);
    v_noches NUMBER;
    v_valor  NUMBER;
    v_salento NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== P9 habitaciones libres en Salento, 2027-06-01 a 06-05, 2 huéspedes ===');
    SELECT id_municipio INTO v_salento FROM MUNICIPIO WHERE nombre = 'Salento';
    PKG_TURISMOUQ.sp_buscar_disponibles(
        p_fecha_in     => DATE '2027-06-01',
        p_fecha_out    => DATE '2027-06-05',
        p_huespedes    => 2,
        p_cursor       => c,
        p_id_municipio => v_salento);
    FOR i IN 1 .. 5 LOOP
        FETCH c INTO v_id, v_num, v_tipo, v_cap, v_ida, v_aloj, v_mun, v_tal, v_noches, v_valor;
        EXIT WHEN c%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE(v_aloj || ' · ' || v_num || ' (' || v_tipo || ', ' || v_cap ||
                             ' pers.) -> ' || v_valor);
    END LOOP;
    CLOSE c;
END;
/

-- ---------------------------------------------------------------------
-- P10. Cursor para actualización (FOR UPDATE + WHERE CURRENT OF):
--      cierre de reservas pendientes sin anticipo. Se ejecuta sin
--      confirmar y se deshace al final, para no alterar los datos.
-- ---------------------------------------------------------------------
DECLARE
    v_canceladas NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== P10 cancelar pendientes vencidas (FOR UPDATE) ===');
    PKG_TURISMOUQ.sp_cancelar_pendientes_vencidas(
        p_horas      => 24,
        p_canceladas => v_canceladas,
        p_commit     => 'N');
    DBMS_OUTPUT.PUT_LINE('OK     se cancelarían ' || v_canceladas || ' reservas (se deshace con ROLLBACK)');
    ROLLBACK;
END;
/

-- ---------------------------------------------------------------------
-- P11. Formas de invocación vistas en clase
-- ---------------------------------------------------------------------
-- a) Función dentro de una consulta SQL (SELECT)
SELECT h.numero,
       PKG_TURISMOUQ.fn_valor_estadia(h.id_habitacion, DATE '2027-03-29', DATE '2027-04-03') AS valor_5_noches
FROM HABITACION h
WHERE h.id_habitacion <= 5
ORDER BY h.id_habitacion;

-- b) Función en una asignación dentro de un bloque PL/SQL
DECLARE
    v_valor NUMBER;
BEGIN
    v_valor := PKG_TURISMOUQ.fn_valor_estadia(1, DATE '2027-06-28', DATE '2027-07-02');
    DBMS_OUTPUT.PUT_LINE('Valor estadía habitación 1: ' || v_valor);
END;
/

-- c) Procedimiento con EXEC (notación posicional) y con CALL (notación nominal)
EXEC PKG_TURISMOUQ.sp_liquidar_mes(2025, 8);

CALL PKG_TURISMOUQ.sp_liquidar_mes(p_anio => 2025, p_mes => 9, p_porcentaje_comision => 10);

-- d) Procedimiento con parámetro OUT usando variables de enlace
VARIABLE v_canceladas NUMBER
EXEC PKG_TURISMOUQ.sp_cancelar_pendientes_vencidas(24, :v_canceladas, 'N');
PRINT v_canceladas
ROLLBACK;