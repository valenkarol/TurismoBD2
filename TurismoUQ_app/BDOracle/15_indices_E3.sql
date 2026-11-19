SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET LINESIZE 220
SET PAGESIZE 200

-- ---------------------------------------------------------------------
-- 0. Limpieza, para poder repetir el experimento desde cero.
--    En una base limpia no encuentra nada y no hace nada.
-- ---------------------------------------------------------------------
BEGIN
    FOR i IN (SELECT index_name
              FROM user_indexes
              WHERE index_name IN ('IX_PAGO_METODO_ESTADO_FECHA',
                                   'IX_CLIENTE_APELLIDOS_UPPER',
                                   'IX_RS_SERVICIO_VENTA',
                                   'IX_RESERVA_ESTADO')) LOOP
        EXECUTE IMMEDIATE 'DROP INDEX ' || i.index_name;
    END LOOP;

    FOR t IN (SELECT table_name
              FROM user_tables
              WHERE table_name IN ('E3_MEDICION', 'E3_CONSULTA')) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' PURGE';
    END LOOP;
END;
/

-- 1. Las consultas del experimento

CREATE TABLE E3_CONSULTA (
    codigo        VARCHAR2(5)     NOT NULL,
    descripcion   VARCHAR2(200)   NOT NULL,
    repeticiones  NUMBER          NOT NULL,
    sql_texto     VARCHAR2(2000)  NOT NULL,
    CONSTRAINT pk_e3_consulta PRIMARY KEY (codigo)
);

CREATE TABLE E3_MEDICION (
    codigo           VARCHAR2(5)    NOT NULL,
    momento          VARCHAR2(10)   NOT NULL,
    costo            NUMBER,
    filas_estimadas  NUMBER,
    acceso           VARCHAR2(400),
    tiempo_ms        NUMBER,
    fecha            DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_e3_medicion PRIMARY KEY (codigo, momento),
    CONSTRAINT ck_e3_medicion_momento CHECK (momento IN ('ANTES', 'DESPUES'))
);

-- C1 · Cierre de caja: Filtra por dos igualdades y un rango de fechas.
INSERT INTO E3_CONSULTA (codigo, descripcion, repeticiones, sql_texto)
VALUES ('C1', 'Cierre de caja: pagos PSE aprobados del 20 al 23 de marzo de 2026', 300,
q'[SELECT id_pago, id_reserva, fecha_pago, valor
FROM PAGO
WHERE metodo_pago = 'PSE'
  AND estado = 'APROBADO'
  AND fecha_pago >= DATE '2026-03-20'
  AND fecha_pago <  DATE '2026-03-24']');

-- C2 · Recepción busca un cliente por apellido sin importar si lo
--      escribe en mayúsculas o minúsculas.
INSERT INTO E3_CONSULTA (codigo, descripcion, repeticiones, sql_texto)
VALUES ('C2', 'Buscar cliente por apellido sin importar mayusculas', 300,
q'[SELECT id_cliente, tipo_documento, numero_documento, nombres, apellidos, telefono, correo
FROM CLIENTE
WHERE UPPER(apellidos) = 'APELLIDO1500']');

-- C3 · Gerencia: cuántas veces se vendió un servicio y cuánto dejó.
--      RESERVA_SERVICIO es la tabla más grande (40.000 filas).
INSERT INTO E3_CONSULTA (codigo, descripcion, repeticiones, sql_texto)
VALUES ('C3', 'Ventas de un servicio: lineas, unidades e ingreso', 300,
q'[SELECT COUNT(*) AS lineas,
       SUM(cantidad) AS unidades,
       SUM(cantidad * precio_unitario) AS ingreso
FROM RESERVA_SERVICIO
WHERE id_servicio = 7]');

-- C4 · Listado de reservas confirmadas (caso donde el índice NO ayuda).
INSERT INTO E3_CONSULTA (codigo, descripcion, repeticiones, sql_texto)
VALUES ('C4', 'Reservas CONFIRMADAS (el indice no ayuda)', 20,
q'[SELECT id_reserva, id_cliente, fecha_checkin, fecha_checkout
FROM RESERVA
WHERE estado = 'CONFIRMADA']');

-- C5 · La misma C4, pero con un hint que OBLIGA a Oracle a usar el índice
--      por estado. Antes de crear el índice el hint no tiene efecto.
INSERT INTO E3_CONSULTA (codigo, descripcion, repeticiones, sql_texto)
VALUES ('C5', 'La misma C4 obligando a usar el indice por estado', 20,
q'[SELECT /*+ INDEX(r IX_RESERVA_ESTADO) */ r.id_reserva, r.id_cliente, r.fecha_checkin, r.fecha_checkout
FROM RESERVA r
WHERE r.estado = 'CONFIRMADA']');

COMMIT;

-- ---------------------------------------------------------------------
-- 2. Procedimiento que mide todas las consultas 
CREATE OR REPLACE PROCEDURE pr_e3_medir (p_momento IN VARCHAR2) IS
    v_id      VARCHAR2(30);
    v_costo   NUMBER;
    v_filas   NUMBER;
    v_acceso  VARCHAR2(400);
    v_bloque  VARCHAR2(2200);
    v_inicio  NUMBER;
    v_ms      NUMBER;
BEGIN
    FOR c IN (SELECT codigo, repeticiones, sql_texto
              FROM E3_CONSULTA
              ORDER BY codigo) LOOP
        v_id := c.codigo || '_' || p_momento;

        -- a) Plan de ejecución
        DELETE FROM plan_table WHERE statement_id = v_id;
        EXECUTE IMMEDIATE
            'EXPLAIN PLAN SET STATEMENT_ID = ''' || v_id || ''' FOR ' || c.sql_texto;

        -- b) Costo total (línea 0 del plan) y cómo llega a los datos
        SELECT cost, cardinality
        INTO v_costo, v_filas
        FROM plan_table
        WHERE statement_id = v_id
          AND id = 0;

        SELECT SUBSTR(LISTAGG(TRIM(operation || ' ' || options) || ' (' || object_name || ')', ' + ')
                      WITHIN GROUP (ORDER BY id), 1, 400)
        INTO v_acceso
        FROM plan_table
        WHERE statement_id = v_id
          AND object_name IS NOT NULL;

        -- c) Tiempo: la consulta se recorre completa dentro de un FOR
        v_bloque := 'BEGIN FOR f IN (' || c.sql_texto || ') LOOP NULL; END LOOP; END;';
        EXECUTE IMMEDIATE v_bloque;              -- una vez para "calentar"

        v_inicio := DBMS_UTILITY.GET_TIME;       -- centésimas de segundo
        FOR i IN 1 .. c.repeticiones LOOP
            EXECUTE IMMEDIATE v_bloque;
        END LOOP;
        v_ms := (DBMS_UTILITY.GET_TIME - v_inicio) * 10;

        -- d) Guardar
        DELETE FROM E3_MEDICION WHERE codigo = c.codigo AND momento = p_momento;
        INSERT INTO E3_MEDICION (codigo, momento, costo, filas_estimadas, acceso, tiempo_ms)
        VALUES (c.codigo, p_momento, v_costo, v_filas, v_acceso, v_ms);

        DBMS_OUTPUT.PUT_LINE(RPAD(v_id, 12) || 'costo ' || LPAD(v_costo, 5) ||
                             ' | ' || LPAD(v_ms, 6) || ' ms en ' || c.repeticiones ||
                             ' ejecuciones | ' || v_acceso);
    END LOOP;

    COMMIT;
END pr_e3_medir;
/

SHOW ERRORS PROCEDURE pr_e3_medir

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'PAGO');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'CLIENTE');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA_SERVICIO');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA');
END;
/

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ANTES de crear los índices ===');
    pr_e3_medir('ANTES');
END;
/

-- Planes ANTES: en todos se espera TABLE ACCESS FULL (recorre toda la tabla)
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'C1_ANTES', 'TYPICAL'));
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'C2_ANTES', 'TYPICAL'));
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'C3_ANTES', 'TYPICAL'));
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'C4_ANTES', 'TYPICAL'));

-- ---------------------------------------------------------------------
-- 4. Los índices
-- ---------------------------------------------------------------------

-- C1 · COMPUESTO (3 columnas).
CREATE INDEX IX_PAGO_METODO_ESTADO_FECHA
    ON PAGO (metodo_pago, estado, fecha_pago);

-- C2 · BASADO EN FUNCIÓN.
CREATE INDEX IX_CLIENTE_APELLIDOS_UPPER
    ON CLIENTE (UPPER(apellidos));

-- C3 · COMPUESTO que "cubre" la consulta.
CREATE INDEX IX_RS_SERVICIO_VENTA
    ON RESERVA_SERVICIO (id_servicio, cantidad, precio_unitario);

-- C4 · Índice simple sobre una columna con solo 4 valores distintos.
--      Se crea para demostrar que NO ayuda (explicación en el punto 7).
CREATE INDEX IX_RESERVA_ESTADO
    ON RESERVA (estado);

-- Los cuatro deben aparecer VALID. El de CLIENTE es FUNCTION-BASED NORMAL.
SELECT index_name, table_name, index_type, status
FROM user_indexes
WHERE index_name IN ('IX_PAGO_METODO_ESTADO_FECHA', 'IX_CLIENTE_APELLIDOS_UPPER',
                     'IX_RS_SERVICIO_VENTA', 'IX_RESERVA_ESTADO')
ORDER BY table_name;

-- Columnas de cada índice, en orden
SELECT index_name, column_position, column_name
FROM user_ind_columns
WHERE index_name IN ('IX_PAGO_METODO_ESTADO_FECHA', 'IX_CLIENTE_APELLIDOS_UPPER',
                     'IX_RS_SERVICIO_VENTA', 'IX_RESERVA_ESTADO')
ORDER BY index_name, column_position;

-- Expresión del índice basado en función
SELECT index_name, column_expression
FROM user_ind_expressions
WHERE index_name = 'IX_CLIENTE_APELLIDOS_UPPER';

-- ---------------------------------------------------------------------
-- 5. DESPUÉS · estadísticas, medición y planes
-- ---------------------------------------------------------------------
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'PAGO');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'CLIENTE');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA_SERVICIO');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA');
END;
/

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== DESPUÉS de crear los índices ===');
    pr_e3_medir('DESPUES');
END;
/

-- Planes DESPUÉS
--   C1: INDEX RANGE SCAN del índice compuesto + TABLE ACCESS BY INDEX ROWID
--   C2: INDEX RANGE SCAN del índice basado en función + TABLE ACCESS BY INDEX ROWID
--   C3: INDEX RANGE SCAN y nada más (no aparece la tabla)
--   C4: sigue en TABLE ACCESS FULL aunque el índice existe
--   C5: usa el índice a la fuerza y el costo sube
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'C1_DESPUES', 'TYPICAL'));
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'C2_DESPUES', 'TYPICAL'));
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'C3_DESPUES', 'TYPICAL'));
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'C4_DESPUES', 'TYPICAL'));
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'C5_DESPUES', 'TYPICAL'));

SELECT c.codigo,
       c.descripcion,
       a.costo      AS costo_antes,
       d.costo      AS costo_despues,
       a.tiempo_ms  AS ms_antes,
       d.tiempo_ms  AS ms_despues,
       c.repeticiones
FROM E3_CONSULTA c
JOIN E3_MEDICION a ON a.codigo = c.codigo AND a.momento = 'ANTES'
JOIN E3_MEDICION d ON d.codigo = c.codigo AND d.momento = 'DESPUES'
ORDER BY c.codigo;

SELECT c.codigo,
       a.acceso AS acceso_antes,
       d.acceso AS acceso_despues
FROM E3_CONSULTA c
JOIN E3_MEDICION a ON a.codigo = c.codigo AND a.momento = 'ANTES'
JOIN E3_MEDICION d ON d.codigo = c.codigo AND d.momento = 'DESPUES'
ORDER BY c.codigo;

-- ---------------------------------------------------------------------
-- 7. El caso donde el índice NO ayuda (C4) y por qué
-- ---------------------------------------------------------------------
-- La columna estado solo tiene 4 valores y cada uno aparece en cerca del
-- 25 % de las reservas:
SELECT estado,
       COUNT(*) AS reservas,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS porcentaje
FROM RESERVA
GROUP BY estado
ORDER BY estado;


DROP INDEX IX_RESERVA_ESTADO;

-- Índices de la entrega 3 que SÍ quedan en el esquema (3 filas)
SELECT index_name, table_name, index_type
FROM user_indexes
WHERE index_name IN ('IX_PAGO_METODO_ESTADO_FECHA', 'IX_CLIENTE_APELLIDOS_UPPER',
                     'IX_RS_SERVICIO_VENTA', 'IX_RESERVA_ESTADO')
ORDER BY table_name;