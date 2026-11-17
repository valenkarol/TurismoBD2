-- Reservas de una habitación (NOT EXISTS de sp_buscar_disponibles,
-- fn_habitacion_disponible y pr_validar_solape)
CREATE INDEX ix_rh_habitacion ON RESERVA_HABITACION (id_habitacion, id_reserva);

-- Cruce de fechas de reservas
CREATE INDEX ix_reserva_fechas ON RESERVA (fecha_checkin, fecha_checkout, estado);

-- Reservas de un cliente (pantalla Clientes y listado de reservas)
CREATE INDEX ix_reserva_cliente ON RESERVA (id_cliente);

-- Pagos y servicios de una reserva (detalle, fn_total_reserva, sp_registrar_pago)
CREATE INDEX ix_pago_reserva ON PAGO (id_reserva);

-- Habitaciones por alojamiento
CREATE INDEX ix_habitacion_alojamiento ON HABITACION (id_alojamiento);

-- Estadísticas actualizadas para que el optimizador use los índices
BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS(ownname => 'TURISMOUQ');
END;
/

-- Verificación
SELECT index_name, table_name
FROM user_indexes
WHERE index_name LIKE 'IX\_%' ESCAPE '\'
ORDER BY table_name;

-- Prueba de tiempo de la búsqueda (debe tardar pocos segundos)
SET TIMING ON
SET SERVEROUTPUT ON
DECLARE
    c   SYS_REFCURSOR;
    n   NUMBER := 0;
    r_id NUMBER; r_num VARCHAR2(20); r_tipo VARCHAR2(50); r_cap NUMBER; r_aloj NUMBER;
    r_naloj VARCHAR2(150); r_mun VARCHAR2(100); r_taloj VARCHAR2(50); r_noches NUMBER; r_valor NUMBER;
BEGIN
    PKG_TURISMOUQ.sp_buscar_disponibles(TRUNC(SYSDATE) + 1, TRUNC(SYSDATE) + 3, 2, c);
    LOOP
        FETCH c INTO r_id, r_num, r_tipo, r_cap, r_aloj, r_naloj, r_mun, r_taloj, r_noches, r_valor;
        EXIT WHEN c%NOTFOUND;
        n := n + 1;
    END LOOP;
    CLOSE c;
    DBMS_OUTPUT.PUT_LINE('Habitaciones disponibles: ' || n);
END;
/