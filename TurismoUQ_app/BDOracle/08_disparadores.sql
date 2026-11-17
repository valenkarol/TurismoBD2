-- =====================================================================
--  A. Auditoría de TARIFA  -> disparador a NIVEL DE SENTENCIA
--  B. Impedir reservas solapadas -> disparador a NIVEL DE FILA
--  C. trg_temporada_sin_solape (SENTENCIA) evita temporadas que se
--     crucen
-- =====================================================================
SET DEFINE OFF

-- ---------------------------------------------------------------------
-- A. Auditoría de TARIFA
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_tarifa_aud_fila
AFTER INSERT OR UPDATE OR DELETE ON TARIFA
FOR EACH ROW
DECLARE
    v_operacion VARCHAR2(10);
BEGIN
    IF INSERTING THEN
        v_operacion := 'INSERT';
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
    ELSE
        v_operacion := 'DELETE';
    END IF;

    INSERT INTO GTT_AUDITORIA_TARIFA (
        operacion, id_tarifa, id_habitacion, id_temporada, valor_anterior, valor_nuevo)
    VALUES (
        v_operacion,
        NVL(:NEW.id_tarifa,     :OLD.id_tarifa),
        NVL(:NEW.id_habitacion, :OLD.id_habitacion),
        NVL(:NEW.id_temporada,  :OLD.id_temporada),
        :OLD.valor_noche,
        :NEW.valor_noche);
END trg_tarifa_aud_fila;
/

CREATE OR REPLACE TRIGGER trg_tarifa_auditoria
AFTER INSERT OR UPDATE OR DELETE ON TARIFA
DECLARE
    v_operacion    VARCHAR2(10);
    v_filas        NUMBER;
    v_id_auditoria AUDITORIA_TARIFA.id_auditoria%TYPE;
BEGIN
    SELECT COUNT(*) INTO v_filas FROM GTT_AUDITORIA_TARIFA;

    IF v_filas > 0 THEN
        IF INSERTING THEN
            v_operacion := 'INSERT';
        ELSIF UPDATING THEN
            v_operacion := 'UPDATE';
        ELSE
            v_operacion := 'DELETE';
        END IF;

        -- Quién y cuándo (una vez por sentencia)
        INSERT INTO AUDITORIA_TARIFA (
            operacion, filas_afectadas, usuario_bd, usuario_app,
            usuario_so, equipo, direccion_ip, programa, fecha_cambio)
        VALUES (
            v_operacion,
            v_filas,
            SYS_CONTEXT('USERENV', 'SESSION_USER'),
            SYS_CONTEXT('USERENV', 'CLIENT_IDENTIFIER'),  -- usuario de la interfaz
            SYS_CONTEXT('USERENV', 'OS_USER'),
            SYS_CONTEXT('USERENV', 'HOST'),
            SYS_CONTEXT('USERENV', 'IP_ADDRESS'),
            SYS_CONTEXT('USERENV', 'MODULE'),
            SYSTIMESTAMP)
        RETURNING id_auditoria INTO v_id_auditoria;

        -- Valor anterior y nuevo de cada tarifa tocada
        INSERT INTO AUDITORIA_TARIFA_DETALLE (
            id_auditoria, operacion, id_tarifa, id_habitacion, id_temporada,
            valor_anterior, valor_nuevo)
        SELECT v_id_auditoria, operacion, id_tarifa, id_habitacion, id_temporada,
               valor_anterior, valor_nuevo
        FROM GTT_AUDITORIA_TARIFA;

        DELETE FROM GTT_AUDITORIA_TARIFA;
    END IF;
END trg_tarifa_auditoria;
/

-- ---------------------------------------------------------------------
-- B. Impedir reservas solapadas sobre la misma habitación
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_rh_impedir_solape
FOR INSERT OR UPDATE OF id_reserva, id_habitacion ON RESERVA_HABITACION
COMPOUND TRIGGER

    TYPE t_fila IS RECORD (
        id_reserva    RESERVA_HABITACION.id_reserva%TYPE,
        id_habitacion RESERVA_HABITACION.id_habitacion%TYPE
    );
    TYPE t_filas IS TABLE OF t_fila INDEX BY PLS_INTEGER;

    g_filas t_filas;

    BEFORE STATEMENT IS
    BEGIN
        g_filas.DELETE;
    END BEFORE STATEMENT;

    -- Nivel de fila: se ejecuta una vez por cada fila insertada/actualizada
    BEFORE EACH ROW IS
        v_i PLS_INTEGER;
    BEGIN
        v_i := g_filas.COUNT + 1;
        g_filas(v_i).id_reserva    := :NEW.id_reserva;
        g_filas(v_i).id_habitacion := :NEW.id_habitacion;
    END BEFORE EACH ROW;

    -- La tabla ya no está mutando: se valida cada fila capturada
    AFTER STATEMENT IS
        v_id_reserva    RESERVA_HABITACION.id_reserva%TYPE;
        v_id_habitacion RESERVA_HABITACION.id_habitacion%TYPE;
    BEGIN
        FOR i IN 1 .. g_filas.COUNT LOOP
            v_id_reserva    := g_filas(i).id_reserva;
            v_id_habitacion := g_filas(i).id_habitacion;
            PKG_TURISMOUQ.pr_validar_solape(v_id_reserva, v_id_habitacion);
        END LOOP;
        g_filas.DELETE;
    END AFTER STATEMENT;

END trg_rh_impedir_solape;
/

-- Si se cambian las fechas de una reserva (o se reactiva una CANCELADA)
-- también se puede generar un solape: se revalidan sus habitaciones.
-- Cambios de estado normales (PENDIENTE -> CONFIRMADA -> FINALIZADA, o
-- cancelar) no se revalidan.
CREATE OR REPLACE TRIGGER trg_reserva_impedir_solape
FOR UPDATE OF fecha_checkin, fecha_checkout, estado ON RESERVA
COMPOUND TRIGGER

    TYPE t_ids IS TABLE OF RESERVA.id_reserva%TYPE INDEX BY PLS_INTEGER;
    g_ids t_ids;

    BEFORE STATEMENT IS
    BEGIN
        g_ids.DELETE;
    END BEFORE STATEMENT;

    AFTER EACH ROW IS
    BEGIN
        IF :NEW.estado <> 'CANCELADA'
           AND (   :NEW.fecha_checkin  <> :OLD.fecha_checkin
                OR :NEW.fecha_checkout <> :OLD.fecha_checkout
                OR :OLD.estado = 'CANCELADA') THEN
            g_ids(g_ids.COUNT + 1) := :NEW.id_reserva;
        END IF;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_id_reserva RESERVA.id_reserva%TYPE;
    BEGIN
        FOR i IN 1 .. g_ids.COUNT LOOP
            v_id_reserva := g_ids(i);
            FOR rh IN (SELECT id_habitacion
                       FROM RESERVA_HABITACION
                       WHERE id_reserva = v_id_reserva) LOOP
                PKG_TURISMOUQ.pr_validar_solape(v_id_reserva, rh.id_habitacion);
            END LOOP;
        END LOOP;
        g_ids.DELETE;
    END AFTER STATEMENT;

END trg_reserva_impedir_solape;
/

-- ---------------------------------------------------------------------
-- C. Temporadas sin cruces (nivel de sentencia)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_temporada_sin_solape
AFTER INSERT OR UPDATE OF fecha_inicio, fecha_fin ON TEMPORADA
DECLARE
    v_cruces NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO v_cruces
    FROM TEMPORADA t1
    JOIN TEMPORADA t2
        ON t1.id_temporada < t2.id_temporada
       AND t1.fecha_inicio < t2.fecha_fin
       AND t2.fecha_inicio < t1.fecha_fin;

    IF v_cruces > 0 THEN
        RAISE_APPLICATION_ERROR(PKG_TURISMOUQ.c_err_temporada,
            'Hay temporadas con fechas que se cruzan. Cada noche debe pertenecer a una sola temporada.');
    END IF;
END trg_temporada_sin_solape;
/

-- Verificación
SELECT trigger_name, trigger_type, triggering_event, table_name, status
FROM user_triggers
ORDER BY table_name, trigger_name;