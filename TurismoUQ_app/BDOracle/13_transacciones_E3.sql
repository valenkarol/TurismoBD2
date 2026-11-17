-- =====================================================================
-- ENTREGA 3 · TRANSACCIONES
-- Ejecutar como: TURISMOUQ, después de los scripts 00 a 12.
--
-- Qué pide el enunciado:
--   "Procedimiento que registre reserva y pago de forma atómica, con
--    SAVEPOINT y demostración de un rollback parcial."
--
-- Qué contiene este script:
--   1. LOG_INTENTO_FALLIDO  -> bitácora de intentos que terminaron en error
--   2. PKG_TURISMOUQ_TX     -> paquete con:
--        pr_registrar_intento_fallido  (transacción AUTÓNOMA)
--        sp_reservar_con_pago          (reserva + pago, todo o nada)
--   3. Tres demostraciones:
--        CASO 1  todo sale bien            -> COMMIT
--        CASO 2  falla el servicio extra   -> ROLLBACK PARCIAL (SAVEPOINT)
--        CASO 3  falla el pago             -> ROLLBACK TOTAL
--   4. Limpieza de las reservas de prueba (para poder repetir el script).
--
-- Nota: si se ejecuta por segunda vez, el CREATE TABLE del punto 1 da
-- ORA-00955 (la tabla ya existe). Se puede ignorar: todo lo demás corre.
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

-- ---------------------------------------------------------------------
-- 1. Bitácora de intentos fallidos
--    No tiene llaves foráneas a propósito: un intento puede fallar
--    justamente porque el cliente o la habitación no existen, y aun así
--    queremos dejarlo registrado.
-- ---------------------------------------------------------------------
CREATE TABLE LOG_INTENTO_FALLIDO (
    id_intento      NUMBER GENERATED ALWAYS AS IDENTITY,
    fecha_intento   TIMESTAMP       DEFAULT SYSTIMESTAMP NOT NULL,
    usuario_bd      VARCHAR2(128)   DEFAULT USER NOT NULL,
    id_usuario_app  NUMBER,
    id_cliente      NUMBER,
    id_habitacion   NUMBER,
    fecha_checkin   DATE,
    fecha_checkout  DATE,
    valor_pago      NUMBER(14,2),
    metodo_pago     VARCHAR2(30),
    codigo_error    NUMBER          NOT NULL,
    mensaje_error   VARCHAR2(500)   NOT NULL,
    CONSTRAINT pk_log_intento_fallido PRIMARY KEY (id_intento)
);

COMMENT ON TABLE LOG_INTENTO_FALLIDO IS
    'Intentos de reserva con pago que terminaron en ROLLBACK. Se llena con una transacción autónoma.';

-- ---------------------------------------------------------------------
-- 2. Paquete de transacciones
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_TURISMOUQ_TX AS

    -- Guarda el intento fallido en la bitácora con su PROPIO commit.
    PROCEDURE pr_registrar_intento_fallido (
        p_id_usuario_app IN NUMBER,
        p_id_cliente     IN NUMBER,
        p_id_habitacion  IN NUMBER,
        p_fecha_in       IN DATE,
        p_fecha_out      IN DATE,
        p_valor_pago     IN NUMBER,
        p_metodo_pago    IN VARCHAR2,
        p_codigo_error   IN NUMBER,
        p_mensaje_error  IN VARCHAR2
    );

    -- Reserva + (servicio opcional) + pago en UNA sola transacción.
    --   * Si falla la reserva o el pago  -> no queda nada (rollback total).
    --   * Si falla solo el servicio extra -> se deshace solo ese paso
    --     (rollback parcial) y p_aviso explica qué pasó.
    PROCEDURE sp_reservar_con_pago (
        p_id_cliente    IN  CLIENTE.id_cliente%TYPE,
        p_id_habitacion IN  HABITACION.id_habitacion%TYPE,
        p_fecha_in      IN  DATE,
        p_fecha_out     IN  DATE,
        p_huespedes     IN  NUMBER,
        p_valor_pago    IN  NUMBER,
        p_metodo_pago   IN  VARCHAR2,
        p_id_reserva    OUT RESERVA.id_reserva%TYPE,
        p_id_pago       OUT PAGO.id_pago%TYPE,
        p_aviso         OUT VARCHAR2,
        p_id_servicio   IN  SERVICIO.id_servicio%TYPE DEFAULT NULL,
        p_cantidad      IN  NUMBER DEFAULT 1,
        p_id_usuario    IN  USUARIO_SISTEMA.id_usuario%TYPE DEFAULT NULL,
        p_commit        IN  VARCHAR2 DEFAULT 'S'
    );

END PKG_TURISMOUQ_TX;
/

CREATE OR REPLACE PACKAGE BODY PKG_TURISMOUQ_TX AS

    -- =================================================================
    -- TRANSACCIÓN AUTÓNOMA
    -- -----------------------------------------------------------------
    -- Problema: cuando la reserva falla se hace ROLLBACK. Si el registro
    -- del error se insertara en la misma transacción, el ROLLBACK también
    -- lo borraría y no quedaría rastro del intento.
    -- Solución: PRAGMA AUTONOMOUS_TRANSACTION. Este procedimiento abre
    -- una transacción independiente, inserta y hace su propio COMMIT sin
    -- tocar la transacción principal (la que llamó).
    -- =================================================================
    PROCEDURE pr_registrar_intento_fallido (
        p_id_usuario_app IN NUMBER,
        p_id_cliente     IN NUMBER,
        p_id_habitacion  IN NUMBER,
        p_fecha_in       IN DATE,
        p_fecha_out      IN DATE,
        p_valor_pago     IN NUMBER,
        p_metodo_pago    IN VARCHAR2,
        p_codigo_error   IN NUMBER,
        p_mensaje_error  IN VARCHAR2
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO LOG_INTENTO_FALLIDO (
            id_usuario_app, id_cliente, id_habitacion, fecha_checkin,
            fecha_checkout, valor_pago, metodo_pago, codigo_error, mensaje_error)
        VALUES (
            p_id_usuario_app, p_id_cliente, p_id_habitacion, p_fecha_in,
            p_fecha_out, p_valor_pago, SUBSTR(p_metodo_pago, 1, 30),
            p_codigo_error, SUBSTR(p_mensaje_error, 1, 500));

        COMMIT;   -- confirma SOLO la bitácora
    END pr_registrar_intento_fallido;

    -- =================================================================
    -- sp_reservar_con_pago
    -- -----------------------------------------------------------------
    -- Línea de tiempo de la transacción:
    --
    --   SAVEPOINT sv_inicio
    --      Paso 1: crear la reserva        (obligatorio)
    --   SAVEPOINT sv_reserva_creada
    --      Paso 2: agregar servicio extra  (opcional)
    --      Paso 3: registrar el pago       (obligatorio)
    --   COMMIT
    --
    --   Falla el paso 2 -> ROLLBACK TO sv_reserva_creada  (PARCIAL:
    --                      se pierde el servicio, la reserva sigue viva
    --                      y la transacción continúa con el pago).
    --   Falla el paso 1 o el 3 -> ROLLBACK TO sv_inicio   (TOTAL:
    --                      no queda ni reserva ni pago).
    --
    -- Los procedimientos de PKG_TURISMOUQ se llaman con p_commit => 'N'
    -- para que NO confirmen por su cuenta: el único COMMIT es el del
    -- final. Eso es lo que hace que reserva y pago sean atómicos.
    -- =================================================================
    PROCEDURE sp_reservar_con_pago (
        p_id_cliente    IN  CLIENTE.id_cliente%TYPE,
        p_id_habitacion IN  HABITACION.id_habitacion%TYPE,
        p_fecha_in      IN  DATE,
        p_fecha_out     IN  DATE,
        p_huespedes     IN  NUMBER,
        p_valor_pago    IN  NUMBER,
        p_metodo_pago   IN  VARCHAR2,
        p_id_reserva    OUT RESERVA.id_reserva%TYPE,
        p_id_pago       OUT PAGO.id_pago%TYPE,
        p_aviso         OUT VARCHAR2,
        p_id_servicio   IN  SERVICIO.id_servicio%TYPE DEFAULT NULL,
        p_cantidad      IN  NUMBER DEFAULT 1,
        p_id_usuario    IN  USUARIO_SISTEMA.id_usuario%TYPE DEFAULT NULL,
        p_commit        IN  VARCHAR2 DEFAULT 'S'
    ) IS
        v_valor_estadia NUMBER;
        v_codigo        NUMBER;
        v_mensaje       VARCHAR2(500);
    BEGIN
        SAVEPOINT sv_inicio;
        p_aviso := NULL;

        -- Paso 1: la reserva. Por dentro bloquea la habitación con
        -- SELECT ... FOR UPDATE (ver script 07 y script 14).
        PKG_TURISMOUQ.sp_crear_reserva(
            p_id_cliente    => p_id_cliente,
            p_id_habitacion => p_id_habitacion,
            p_fecha_in      => p_fecha_in,
            p_fecha_out     => p_fecha_out,
            p_huespedes     => p_huespedes,
            p_id_reserva    => p_id_reserva,
            p_valor_estadia => v_valor_estadia,
            p_id_usuario    => p_id_usuario,
            p_commit        => 'N');

        SAVEPOINT sv_reserva_creada;

        -- Paso 2: servicio opcional. Si falla NO se pierde la reserva.
        IF p_id_servicio IS NOT NULL THEN
            BEGIN
                PKG_TURISMOUQ.sp_agregar_servicio(
                    p_id_reserva  => p_id_reserva,
                    p_id_servicio => p_id_servicio,
                    p_cantidad    => p_cantidad,
                    p_commit      => 'N');
            EXCEPTION
                WHEN OTHERS THEN
                    ROLLBACK TO sv_reserva_creada;   -- <<< ROLLBACK PARCIAL
                    p_aviso := SUBSTR('La reserva se creó SIN el servicio adicional. Motivo: '
                                      || SQLERRM, 1, 500);
                    DBMS_OUTPUT.PUT_LINE('ROLLBACK PARCIAL (hasta sv_reserva_creada): ' || SQLERRM);
            END;
        END IF;

        -- Paso 3: el pago. Si falla, la excepción salta al manejador de
        -- abajo y se deshace TODO.
        PKG_TURISMOUQ.sp_registrar_pago(
            p_id_reserva => p_id_reserva,
            p_valor      => p_valor_pago,
            p_metodo     => p_metodo_pago,
            p_id_pago    => p_id_pago,
            p_commit     => 'N');

        IF UPPER(NVL(p_commit, 'S')) = 'S' THEN
            COMMIT;   -- reserva + pago quedan confirmados juntos
        END IF;

        DBMS_OUTPUT.PUT_LINE('Reserva ' || p_id_reserva || ' y pago ' || p_id_pago ||
                             ' registrados en una sola transacción.');
    EXCEPTION
        WHEN OTHERS THEN
            -- SQLCODE y SQLERRM se guardan antes de hacer cualquier otra cosa
            v_codigo  := SQLCODE;
            v_mensaje := SUBSTR(SQLERRM, 1, 500);

            ROLLBACK TO sv_inicio;                   -- <<< ROLLBACK TOTAL

            -- La bitácora sobrevive al ROLLBACK porque es autónoma
            pr_registrar_intento_fallido(
                p_id_usuario, p_id_cliente, p_id_habitacion, p_fecha_in, p_fecha_out,
                p_valor_pago, p_metodo_pago, v_codigo, v_mensaje);

            p_id_reserva := NULL;
            p_id_pago    := NULL;
            DBMS_OUTPUT.PUT_LINE('ROLLBACK TOTAL (hasta sv_inicio): ' || v_mensaje);
            RAISE;   -- quien llama (SQL Developer o la interfaz) se entera del error
    END sp_reservar_con_pago;

END PKG_TURISMOUQ_TX;
/

SHOW ERRORS PACKAGE BODY PKG_TURISMOUQ_TX

-- Los dos deben aparecer VALID
SELECT object_name, object_type, status
FROM user_objects
WHERE object_name = 'PKG_TURISMOUQ_TX';

-- =====================================================================
-- 3. DEMOSTRACIONES
--    Todas usan la misma habitación (la de menor id que esté DISPONIBLE)
--    y el cliente de menor id, con fechas de 2027 para no chocar con las
--    25.000 reservas cargadas (que llegan hasta inicios de 2027).
--      CASO 1 -> 10 al 13 de febrero de 2027
--      CASO 2 -> 10 al 13 de marzo de 2027
--      CASO 3 -> 10 al 13 de abril de 2027
-- =====================================================================

-- Por si quedó algo de una ejecución anterior: se cancelan las reservas
-- de prueba de esas fechas para que la habitación esté libre.
BEGIN
    FOR x IN (SELECT r.id_reserva
              FROM RESERVA r
              JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
              WHERE rh.id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION
                                        WHERE estado = 'DISPONIBLE')
                AND r.fecha_checkin IN (DATE '2027-02-10', DATE '2027-03-10', DATE '2027-04-10')
                AND r.estado IN ('PENDIENTE', 'CONFIRMADA')) LOOP
        PKG_TURISMOUQ.sp_cancelar_reserva(x.id_reserva, 'N');
    END LOOP;
    COMMIT;
END;
/

-- ---------------------------------------------------------------------
-- CASO 1 · Todo correcto: reserva + servicio + pago -> COMMIT
--          Se paga el valor completo del hospedaje.
-- ---------------------------------------------------------------------
DECLARE
    v_cli     NUMBER;
    v_hab     NUMBER;
    v_serv    NUMBER;
    v_valor   NUMBER;
    v_reserva NUMBER;
    v_pago    NUMBER;
    v_aviso   VARCHAR2(500);
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== CASO 1: todo correcto ===');
    SELECT MIN(id_cliente)    INTO v_cli  FROM CLIENTE;
    SELECT MIN(id_habitacion) INTO v_hab  FROM HABITACION WHERE estado = 'DISPONIBLE';
    SELECT MIN(id_servicio)   INTO v_serv FROM SERVICIO;

    v_valor := PKG_TURISMOUQ.fn_valor_estadia(v_hab, DATE '2027-02-10', DATE '2027-02-13');

    PKG_TURISMOUQ_TX.sp_reservar_con_pago(
        p_id_cliente    => v_cli,
        p_id_habitacion => v_hab,
        p_fecha_in      => DATE '2027-02-10',
        p_fecha_out     => DATE '2027-02-13',
        p_huespedes     => 1,
        p_valor_pago    => v_valor,
        p_metodo_pago   => 'PSE',
        p_id_reserva    => v_reserva,
        p_id_pago       => v_pago,
        p_aviso         => v_aviso,
        p_id_servicio   => v_serv,
        p_cantidad      => 1);

    DBMS_OUTPUT.PUT_LINE('OK     reserva ' || v_reserva || ', pago ' || v_pago ||
                         ', aviso: ' || NVL(v_aviso, '(ninguno)'));
END;
/

-- Esperado: 1 fila · estado CONFIRMADA · habitaciones 1 · servicios 1 · pagos 1
SELECT r.id_reserva, r.estado,
       (SELECT COUNT(*) FROM RESERVA_HABITACION x WHERE x.id_reserva = r.id_reserva) AS habitaciones,
       (SELECT COUNT(*) FROM RESERVA_SERVICIO x   WHERE x.id_reserva = r.id_reserva) AS servicios,
       (SELECT COUNT(*) FROM PAGO x               WHERE x.id_reserva = r.id_reserva) AS pagos
FROM RESERVA r
JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
WHERE rh.id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION WHERE estado = 'DISPONIBLE')
  AND r.fecha_checkin = DATE '2027-02-10'
  AND r.estado <> 'CANCELADA';

-- ---------------------------------------------------------------------
-- CASO 2 · ROLLBACK PARCIAL
--          El servicio 9999 no existe. Se deshace SOLO ese paso
--          (ROLLBACK TO sv_reserva_creada); la reserva y el pago quedan.
--          Se paga el 30 % (anticipo), así que queda CONFIRMADA.
-- ---------------------------------------------------------------------
DECLARE
    v_cli     NUMBER;
    v_hab     NUMBER;
    v_valor   NUMBER;
    v_reserva NUMBER;
    v_pago    NUMBER;
    v_aviso   VARCHAR2(500);
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== CASO 2: rollback parcial ===');
    SELECT MIN(id_cliente)    INTO v_cli FROM CLIENTE;
    SELECT MIN(id_habitacion) INTO v_hab FROM HABITACION WHERE estado = 'DISPONIBLE';

    v_valor := PKG_TURISMOUQ.fn_valor_estadia(v_hab, DATE '2027-03-10', DATE '2027-03-13');

    PKG_TURISMOUQ_TX.sp_reservar_con_pago(
        p_id_cliente    => v_cli,
        p_id_habitacion => v_hab,
        p_fecha_in      => DATE '2027-03-10',
        p_fecha_out     => DATE '2027-03-13',
        p_huespedes     => 1,
        p_valor_pago    => CEIL(v_valor * 0.30),
        p_metodo_pago   => 'TARJETA',
        p_id_reserva    => v_reserva,
        p_id_pago       => v_pago,
        p_aviso         => v_aviso,
        p_id_servicio   => 9999,      -- servicio que NO existe
        p_cantidad      => 1);

    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_reserva IS NOT NULL AND v_pago IS NOT NULL AND v_aviso IS NOT NULL
                              THEN 'OK     ' ELSE 'FALLO  ' END ||
                         'reserva ' || v_reserva || ' y pago ' || v_pago || ' quedaron guardados');
    DBMS_OUTPUT.PUT_LINE('       aviso: ' || v_aviso);
END;
/

-- Esperado: 1 fila · estado CONFIRMADA · habitaciones 1 · servicios 0 · pagos 1
SELECT r.id_reserva, r.estado,
       (SELECT COUNT(*) FROM RESERVA_HABITACION x WHERE x.id_reserva = r.id_reserva) AS habitaciones,
       (SELECT COUNT(*) FROM RESERVA_SERVICIO x   WHERE x.id_reserva = r.id_reserva) AS servicios,
       (SELECT COUNT(*) FROM PAGO x               WHERE x.id_reserva = r.id_reserva) AS pagos
FROM RESERVA r
JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
WHERE rh.id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION WHERE estado = 'DISPONIBLE')
  AND r.fecha_checkin = DATE '2027-03-10'
  AND r.estado <> 'CANCELADA';

-- ---------------------------------------------------------------------
-- CASO 3 · ROLLBACK TOTAL
--          El método de pago 'BITCOIN' no es válido: el pago se rechaza
--          y la reserva que ya se había insertado se deshace también.
--          Lo único que queda es la fila de la bitácora (autónoma).
-- ---------------------------------------------------------------------
DECLARE
    v_cli     NUMBER;
    v_hab     NUMBER;
    v_valor   NUMBER;
    v_reserva NUMBER;
    v_pago    NUMBER;
    v_aviso   VARCHAR2(500);
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== CASO 3: rollback total ===');
    SELECT MIN(id_cliente)    INTO v_cli FROM CLIENTE;
    SELECT MIN(id_habitacion) INTO v_hab FROM HABITACION WHERE estado = 'DISPONIBLE';

    v_valor := PKG_TURISMOUQ.fn_valor_estadia(v_hab, DATE '2027-04-10', DATE '2027-04-13');

    PKG_TURISMOUQ_TX.sp_reservar_con_pago(
        p_id_cliente    => v_cli,
        p_id_habitacion => v_hab,
        p_fecha_in      => DATE '2027-04-10',
        p_fecha_out     => DATE '2027-04-13',
        p_huespedes     => 1,
        p_valor_pago    => v_valor,
        p_metodo_pago   => 'BITCOIN',  -- método que NO existe
        p_id_reserva    => v_reserva,
        p_id_pago       => v_pago,
        p_aviso         => v_aviso);

    DBMS_OUTPUT.PUT_LINE('FALLO  el pago debió rechazarse');
EXCEPTION
    WHEN PKG_TURISMOUQ.e_pago_invalido THEN
        DBMS_OUTPUT.PUT_LINE('OK     pago rechazado, no quedó reserva: ' || SQLERRM);
END;
/

-- Un ROLLBACK de la sesión tampoco borra la bitácora: ya tiene su COMMIT.
ROLLBACK;

-- Esperado: 0 (la reserva del 10 de abril NO existe)
SELECT COUNT(*) AS reservas_del_caso_3
FROM RESERVA r
JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
WHERE rh.id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION WHERE estado = 'DISPONIBLE')
  AND r.fecha_checkin = DATE '2027-04-10';

-- Esperado: la fila más reciente es el intento del CASO 3 (ORA-20012)
SELECT id_intento, fecha_intento, id_cliente, id_habitacion, fecha_checkin,
       valor_pago, metodo_pago, codigo_error, mensaje_error
FROM LOG_INTENTO_FALLIDO
ORDER BY id_intento DESC
FETCH FIRST 5 ROWS ONLY;

-- ---------------------------------------------------------------------
-- 4. Limpieza: se cancelan las reservas de los casos 1 y 2 para dejar la
--    habitación libre y poder repetir el script. Las filas no se borran,
--    quedan como CANCELADA (y la bitácora se conserva).
-- ---------------------------------------------------------------------
BEGIN
    FOR x IN (SELECT r.id_reserva
              FROM RESERVA r
              JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
              WHERE rh.id_habitacion = (SELECT MIN(id_habitacion) FROM HABITACION
                                        WHERE estado = 'DISPONIBLE')
                AND r.fecha_checkin IN (DATE '2027-02-10', DATE '2027-03-10', DATE '2027-04-10')
                AND r.estado IN ('PENDIENTE', 'CONFIRMADA')) LOOP
        PKG_TURISMOUQ.sp_cancelar_reserva(x.id_reserva, 'N');
        DBMS_OUTPUT.PUT_LINE('Reserva de prueba ' || x.id_reserva || ' cancelada.');
    END LOOP;
    COMMIT;
END;
/