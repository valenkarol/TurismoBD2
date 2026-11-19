SET DEFINE OFF
SET SERVEROUTPUT ON

CREATE OR REPLACE PACKAGE PKG_TURISMOUQ AS

    -- -----------------------------------------------------------------
    -- Códigos de error propios (la interfaz puede mapearlos a mensajes)
    -- -----------------------------------------------------------------
    c_err_fechas            CONSTANT PLS_INTEGER := -20001; -- checkout <= checkin
    c_err_no_disponible     CONSTANT PLS_INTEGER := -20002; -- habitación ocupada / fuera de servicio
    c_err_capacidad         CONSTANT PLS_INTEGER := -20003; -- huéspedes > capacidad
    c_err_cliente           CONSTANT PLS_INTEGER := -20004; -- cliente no existe
    c_err_habitacion        CONSTANT PLS_INTEGER := -20005; -- habitación no existe
    c_err_sin_tarifa        CONSTANT PLS_INTEGER := -20006; -- alguna noche sin tarifa
    c_err_reserva           CONSTANT PLS_INTEGER := -20007; -- reserva no existe / estado no válido
    c_err_fecha_pasada      CONSTANT PLS_INTEGER := -20008; -- checkin anterior a hoy
    c_err_alojamiento       CONSTANT PLS_INTEGER := -20009; -- habitaciones de distinto alojamiento
    c_err_solape            CONSTANT PLS_INTEGER := -20010; -- disparador: reservas solapadas
    c_err_parametro         CONSTANT PLS_INTEGER := -20011; -- parámetro nulo o fuera de rango
    c_err_pago              CONSTANT PLS_INTEGER := -20012; -- pago inválido
    c_err_temporada         CONSTANT PLS_INTEGER := -20013; -- temporadas solapadas
    c_err_ocupada           CONSTANT PLS_INTEGER := -20014; -- E3: otra sesión tiene bloqueada la habitación

    e_fechas_invalidas      EXCEPTION; PRAGMA EXCEPTION_INIT(e_fechas_invalidas,      -20001);
    e_no_disponible         EXCEPTION; PRAGMA EXCEPTION_INIT(e_no_disponible,         -20002);
    e_capacidad_excedida    EXCEPTION; PRAGMA EXCEPTION_INIT(e_capacidad_excedida,    -20003);
    e_cliente_inexistente   EXCEPTION; PRAGMA EXCEPTION_INIT(e_cliente_inexistente,   -20004);
    e_habitacion_inexistente EXCEPTION; PRAGMA EXCEPTION_INIT(e_habitacion_inexistente, -20005);
    e_sin_tarifa            EXCEPTION; PRAGMA EXCEPTION_INIT(e_sin_tarifa,            -20006);
    e_reserva_invalida      EXCEPTION; PRAGMA EXCEPTION_INIT(e_reserva_invalida,      -20007);
    e_fecha_pasada          EXCEPTION; PRAGMA EXCEPTION_INIT(e_fecha_pasada,          -20008);
    e_alojamiento_distinto  EXCEPTION; PRAGMA EXCEPTION_INIT(e_alojamiento_distinto,  -20009);
    e_solapamiento          EXCEPTION; PRAGMA EXCEPTION_INIT(e_solapamiento,          -20010);
    e_parametro_invalido    EXCEPTION; PRAGMA EXCEPTION_INIT(e_parametro_invalido,    -20011);
    e_pago_invalido         EXCEPTION; PRAGMA EXCEPTION_INIT(e_pago_invalido,         -20012);
    e_temporada_solapada    EXCEPTION; PRAGMA EXCEPTION_INIT(e_temporada_solapada,    -20013);
    e_habitacion_ocupada    EXCEPTION; PRAGMA EXCEPTION_INIT(e_habitacion_ocupada,    -20014);

    -- Reglas de negocio parametrizables
    c_porcentaje_anticipo   CONSTANT NUMBER := 30;  -- % pagado para pasar a CONFIRMADA

    -- -----------------------------------------------------------------
    -- Valor de estadías
    -- -----------------------------------------------------------------
    FUNCTION fn_valor_estadia (
        p_id_habitacion IN HABITACION.id_habitacion%TYPE,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER;

    -- Igual que fn_valor_estadia pero devuelve NULL en vez de error.
    -- Útil en SELECT masivos (catálogo, búsqueda de disponibilidad).
    FUNCTION fn_cotizar_estadia (
        p_id_habitacion IN HABITACION.id_habitacion%TYPE,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER;

    -- Desglose por temporada (temporada, desde, hasta, noches, valor_noche, subtotal)
    PROCEDURE sp_detalle_estadia (
        p_id_habitacion IN  HABITACION.id_habitacion%TYPE,
        p_fecha_in      IN  DATE,
        p_fecha_out     IN  DATE,
        p_cursor        OUT SYS_REFCURSOR
    );

    -- 'S' si la habitación está en servicio y libre en [p_fecha_in, p_fecha_out)
    FUNCTION fn_habitacion_disponible (
        p_id_habitacion   IN HABITACION.id_habitacion%TYPE,
        p_fecha_in        IN DATE,
        p_fecha_out       IN DATE,
        p_excluir_reserva IN RESERVA.id_reserva%TYPE DEFAULT NULL
    ) RETURN VARCHAR2;

    -- Hospedaje + servicios de una reserva
    FUNCTION fn_total_reserva (
        p_id_reserva IN RESERVA.id_reserva%TYPE
    ) RETURN NUMBER;

    -- -----------------------------------------------------------------
    -- Clientes
    -- Busca el cliente por documento. Si existe devuelve su id (y
    -- actualiza teléfono/correo si llegan); si no existe lo crea, para lo
    -- cual nombres y apellidos son obligatorios.
    -- -----------------------------------------------------------------
    PROCEDURE sp_registrar_cliente (
        p_tipo_documento   IN  CLIENTE.tipo_documento%TYPE,
        p_numero_documento IN  CLIENTE.numero_documento%TYPE,
        p_nombres          IN  CLIENTE.nombres%TYPE,
        p_apellidos        IN  CLIENTE.apellidos%TYPE,
        p_telefono         IN  CLIENTE.telefono%TYPE,
        p_correo           IN  CLIENTE.correo%TYPE,
        p_id_cliente       OUT CLIENTE.id_cliente%TYPE,
        p_commit           IN  VARCHAR2 DEFAULT 'S'
    );

    -- -----------------------------------------------------------------
    -- Reservas
    -- -----------------------------------------------------------------
    PROCEDURE sp_crear_reserva (
        p_id_cliente    IN  CLIENTE.id_cliente%TYPE,
        p_id_habitacion IN  HABITACION.id_habitacion%TYPE,
        p_fecha_in      IN  DATE,
        p_fecha_out     IN  DATE,
        p_huespedes     IN  NUMBER,
        p_id_reserva    OUT RESERVA.id_reserva%TYPE,
        p_valor_estadia OUT NUMBER,
        p_id_usuario    IN  USUARIO_SISTEMA.id_usuario%TYPE DEFAULT NULL,
        p_commit        IN  VARCHAR2 DEFAULT 'S',
        -- E3 · Concurrencia: 'S' bloquea la habitación con SELECT ... FOR UPDATE
        -- antes de revisar la disponibilidad. 'N' deja el comportamiento de la
        -- entrega 2 (sin bloqueo) y solo se usa en el experimento del script 14.
        p_bloquear      IN  VARCHAR2 DEFAULT 'S'
    );

    -- Una reserva puede tomar varias habitaciones (del mismo alojamiento)
    PROCEDURE sp_agregar_habitacion (
        p_id_reserva    IN  RESERVA.id_reserva%TYPE,
        p_id_habitacion IN  HABITACION.id_habitacion%TYPE,
        p_huespedes     IN  NUMBER,
        p_valor_estadia OUT NUMBER,
        p_commit        IN  VARCHAR2 DEFAULT 'S'
    );

    PROCEDURE sp_agregar_servicio (
        p_id_reserva  IN RESERVA.id_reserva%TYPE,
        p_id_servicio IN SERVICIO.id_servicio%TYPE,
        p_cantidad    IN NUMBER,
        p_commit      IN VARCHAR2 DEFAULT 'S'
    );

    PROCEDURE sp_registrar_pago (
        p_id_reserva IN  RESERVA.id_reserva%TYPE,
        p_valor      IN  NUMBER,
        p_metodo     IN  VARCHAR2,
        p_id_pago    OUT PAGO.id_pago%TYPE,
        p_commit     IN  VARCHAR2 DEFAULT 'S'
    );

    PROCEDURE sp_cancelar_reserva (
        p_id_reserva IN RESERVA.id_reserva%TYPE,
        p_commit     IN VARCHAR2 DEFAULT 'S'
    );

    -- Habitaciones libres para un rango (para el buscador de la interfaz)
    PROCEDURE sp_buscar_disponibles (
        p_fecha_in            IN  DATE,
        p_fecha_out           IN  DATE,
        p_huespedes           IN  NUMBER,
        p_cursor              OUT SYS_REFCURSOR,
        p_id_municipio        IN  MUNICIPIO.id_municipio%TYPE DEFAULT NULL,
        p_id_tipo_alojamiento IN  TIPO_ALOJAMIENTO.id_tipo_alojamiento%TYPE DEFAULT NULL
    );

    -- -----------------------------------------------------------------
    -- Procesos masivos
    -- -----------------------------------------------------------------
    PROCEDURE sp_liquidar_mes (
        p_anio                IN NUMBER,
        p_mes                 IN NUMBER,
        p_porcentaje_comision IN NUMBER   DEFAULT 10,
        p_id_municipio        IN NUMBER   DEFAULT NULL,
        p_commit              IN VARCHAR2 DEFAULT 'S'
    );

    PROCEDURE sp_liquidar_anio (
        p_anio                IN NUMBER,
        p_porcentaje_comision IN NUMBER DEFAULT 10
    );

    -- Cierre de reservas no pagadas: cursor FOR UPDATE + WHERE CURRENT OF.
    -- Cancela las reservas PENDIENTE, con checkin futuro, sin pagos
    -- aprobados y creadas hace más de p_horas horas.
    PROCEDURE sp_cancelar_pendientes_vencidas (
        p_horas      IN  NUMBER DEFAULT 24,
        p_canceladas OUT NUMBER,
        p_commit     IN  VARCHAR2 DEFAULT 'S'
    );

    -- Copia al histórico (TS_HISTORICO_RESERVAS) las reservas cerradas con
    -- checkout anterior a p_fecha_corte. Con p_purgar = 'S' además las
    -- borra de las tablas operativas.
    PROCEDURE sp_archivar_reservas (
        p_fecha_corte IN  DATE,
        p_filas       OUT NUMBER,
        p_purgar      IN  VARCHAR2 DEFAULT 'N',
        p_commit      IN  VARCHAR2 DEFAULT 'S'
    );

    -- -----------------------------------------------------------------
    -- Soporte de disparadores
    -- -----------------------------------------------------------------
    PROCEDURE pr_validar_solape (
        p_id_reserva    IN RESERVA.id_reserva%TYPE,
        p_id_habitacion IN HABITACION.id_habitacion%TYPE
    );

END PKG_TURISMOUQ;
/

CREATE OR REPLACE PACKAGE BODY PKG_TURISMOUQ AS

    -- =================================================================
    -- Utilidades privadas
    -- =================================================================
    FUNCTION fmt (p_fecha IN DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(p_fecha, 'YYYY-MM-DD');
    END fmt;

    FUNCTION debe_confirmar (p_commit IN VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        RETURN UPPER(NVL(p_commit, 'S')) = 'S';
    END debe_confirmar;

    PROCEDURE validar_rango (p_fecha_in IN DATE, p_fecha_out IN DATE) IS
    BEGIN
        IF p_fecha_in IS NULL OR p_fecha_out IS NULL THEN
            RAISE_APPLICATION_ERROR(c_err_parametro,
                'Las fechas de checkin y checkout son obligatorias.');
        END IF;

        IF TRUNC(p_fecha_out) <= TRUNC(p_fecha_in) THEN
            RAISE_APPLICATION_ERROR(c_err_fechas,
                'La fecha de checkout (' || fmt(p_fecha_out) ||
                ') debe ser posterior a la de checkin (' || fmt(p_fecha_in) || ').');
        END IF;
    END validar_rango;

    -- E3 · CONCURRENCIA  ·  bloqueo pesimista de la habitación
    PROCEDURE bloquear_habitacion (
        p_id_habitacion IN HABITACION.id_habitacion%TYPE
    ) IS
        v_id HABITACION.id_habitacion%TYPE;
        e_espera_agotada EXCEPTION;
        PRAGMA EXCEPTION_INIT(e_espera_agotada, -30006);
    BEGIN
        SELECT id_habitacion
        INTO v_id
        FROM HABITACION
        WHERE id_habitacion = p_id_habitacion
        FOR UPDATE WAIT 20;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            NULL;   -- no existe: el procedimiento que llama lanza el -20005
        WHEN e_espera_agotada THEN
            RAISE_APPLICATION_ERROR(c_err_ocupada,
                'Otro usuario está reservando la habitación ' || p_id_habitacion ||
                ' en este momento. Intente de nuevo en unos segundos.');
    END bloquear_habitacion;


    -- fn_valor_estadia

    FUNCTION fn_valor_estadia (
        p_id_habitacion IN HABITACION.id_habitacion%TYPE,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER IS
        v_in        DATE := TRUNC(p_fecha_in);
        v_out       DATE := TRUNC(p_fecha_out);
        v_cubierto  DATE;
        v_total     NUMBER(14,2) := 0;
        v_existe    PLS_INTEGER;

        -- Cursor explícito con parámetros: tramos de la estadía por temporada
        CURSOR c_tramos (cp_id_habitacion NUMBER, cp_in DATE, cp_out DATE) IS
            SELECT te.nombre AS temporada,
                   GREATEST(TRUNC(te.fecha_inicio), cp_in) AS desde,
                   LEAST(TRUNC(te.fecha_fin), cp_out)      AS hasta,
                   ta.valor_noche
            FROM TEMPORADA te
            JOIN TARIFA ta
                ON ta.id_temporada  = te.id_temporada
               AND ta.id_habitacion = cp_id_habitacion
            WHERE te.fecha_inicio < cp_out
              AND te.fecha_fin    > cp_in
            ORDER BY te.fecha_inicio;

        r_tramo c_tramos%ROWTYPE;
    BEGIN
        validar_rango(p_fecha_in, p_fecha_out);

        SELECT COUNT(*)
        INTO v_existe
        FROM HABITACION
        WHERE id_habitacion = p_id_habitacion;

        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(c_err_habitacion,
                'La habitación ' || p_id_habitacion || ' no existe.');
        END IF;

        v_cubierto := v_in;

        OPEN c_tramos(p_id_habitacion, v_in, v_out);
        LOOP
            FETCH c_tramos INTO r_tramo;
            EXIT WHEN c_tramos%NOTFOUND;

            IF r_tramo.desde > v_cubierto THEN
                RAISE_APPLICATION_ERROR(c_err_sin_tarifa,
                    'La habitación ' || p_id_habitacion ||
                    ' no tiene tarifa para la noche del ' || fmt(v_cubierto) || '.');
            ELSIF r_tramo.desde < v_cubierto THEN
                RAISE_APPLICATION_ERROR(c_err_temporada,
                    'Temporadas solapadas: ' || r_tramo.temporada ||
                    ' empieza antes de que termine la anterior (' || fmt(r_tramo.desde) || ').');
            END IF;

            v_total    := v_total + (r_tramo.hasta - r_tramo.desde) * r_tramo.valor_noche;
            v_cubierto := r_tramo.hasta;
        END LOOP;
        CLOSE c_tramos;

        IF v_cubierto < v_out THEN
            RAISE_APPLICATION_ERROR(c_err_sin_tarifa,
                'La habitación ' || p_id_habitacion ||
                ' no tiene tarifa para la noche del ' || fmt(v_cubierto) || '.');
        END IF;

        RETURN v_total;
    EXCEPTION
        WHEN OTHERS THEN
            IF c_tramos%ISOPEN THEN
                CLOSE c_tramos;
            END IF;
            RAISE;
    END fn_valor_estadia;

    -- =================================================================
    FUNCTION fn_cotizar_estadia (
        p_id_habitacion IN HABITACION.id_habitacion%TYPE,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER IS
    BEGIN
        RETURN fn_valor_estadia(p_id_habitacion, p_fecha_in, p_fecha_out);
    EXCEPTION
        WHEN e_sin_tarifa OR e_fechas_invalidas OR e_habitacion_inexistente
          OR e_parametro_invalido OR e_temporada_solapada THEN
            RETURN NULL;
    END fn_cotizar_estadia;

    -- =================================================================
    PROCEDURE sp_detalle_estadia (
        p_id_habitacion IN  HABITACION.id_habitacion%TYPE,
        p_fecha_in      IN  DATE,
        p_fecha_out     IN  DATE,
        p_cursor        OUT SYS_REFCURSOR
    ) IS
        v_in  DATE := TRUNC(p_fecha_in);
        v_out DATE := TRUNC(p_fecha_out);
    BEGIN
        validar_rango(p_fecha_in, p_fecha_out);

        OPEN p_cursor FOR
            SELECT te.nombre AS temporada,
                   GREATEST(TRUNC(te.fecha_inicio), v_in) AS desde,
                   LEAST(TRUNC(te.fecha_fin), v_out)      AS hasta,
                   LEAST(TRUNC(te.fecha_fin), v_out)
                     - GREATEST(TRUNC(te.fecha_inicio), v_in) AS noches,
                   ta.valor_noche,
                   (LEAST(TRUNC(te.fecha_fin), v_out)
                     - GREATEST(TRUNC(te.fecha_inicio), v_in)) * ta.valor_noche AS subtotal
            FROM TEMPORADA te
            JOIN TARIFA ta
                ON ta.id_temporada  = te.id_temporada
               AND ta.id_habitacion = p_id_habitacion
            WHERE te.fecha_inicio < v_out
              AND te.fecha_fin    > v_in
            ORDER BY te.fecha_inicio;
    END sp_detalle_estadia;

    -- =================================================================
    FUNCTION fn_habitacion_disponible (
        p_id_habitacion   IN HABITACION.id_habitacion%TYPE,
        p_fecha_in        IN DATE,
        p_fecha_out       IN DATE,
        p_excluir_reserva IN RESERVA.id_reserva%TYPE DEFAULT NULL
    ) RETURN VARCHAR2 IS
        v_estado HABITACION.estado%TYPE;
        v_cruces PLS_INTEGER;
    BEGIN
        validar_rango(p_fecha_in, p_fecha_out);

        BEGIN
            SELECT estado INTO v_estado
            FROM HABITACION
            WHERE id_habitacion = p_id_habitacion;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(c_err_habitacion,
                    'La habitación ' || p_id_habitacion || ' no existe.');
        END;

        IF v_estado <> 'DISPONIBLE' THEN
            RETURN 'N';
        END IF;

        -- Dos rangos [a1,b1) y [a2,b2) se cruzan si a1 < b2 AND a2 < b1
        SELECT COUNT(*)
        INTO v_cruces
        FROM RESERVA_HABITACION rh
        JOIN RESERVA r ON r.id_reserva = rh.id_reserva
        WHERE rh.id_habitacion = p_id_habitacion
          AND r.estado <> 'CANCELADA'
          AND r.fecha_checkin  < TRUNC(p_fecha_out)
          AND r.fecha_checkout > TRUNC(p_fecha_in)
          AND (p_excluir_reserva IS NULL OR r.id_reserva <> p_excluir_reserva)
          AND ROWNUM = 1;

        RETURN CASE WHEN v_cruces = 0 THEN 'S' ELSE 'N' END;
    END fn_habitacion_disponible;

    -- =================================================================
    FUNCTION fn_total_reserva (
        p_id_reserva IN RESERVA.id_reserva%TYPE
    ) RETURN NUMBER IS
        v_hospedaje NUMBER(14,2);
        v_servicios NUMBER(14,2);
    BEGIN
        -- COALESCE (y no NVL) para que la función solo se evalúe si falta el valor
        SELECT NVL(SUM(COALESCE(rh.valor_estadia,
                   PKG_TURISMOUQ.fn_cotizar_estadia(rh.id_habitacion,
                                                    r.fecha_checkin,
                                                    r.fecha_checkout))), 0)
        INTO v_hospedaje
        FROM RESERVA_HABITACION rh
        JOIN RESERVA r ON r.id_reserva = rh.id_reserva
        WHERE rh.id_reserva = p_id_reserva;

        SELECT NVL(SUM(cantidad * precio_unitario), 0)
        INTO v_servicios
        FROM RESERVA_SERVICIO
        WHERE id_reserva = p_id_reserva;

        RETURN v_hospedaje + v_servicios;
    END fn_total_reserva;

    -- =================================================================
    PROCEDURE sp_registrar_cliente (
        p_tipo_documento   IN  CLIENTE.tipo_documento%TYPE,
        p_numero_documento IN  CLIENTE.numero_documento%TYPE,
        p_nombres          IN  CLIENTE.nombres%TYPE,
        p_apellidos        IN  CLIENTE.apellidos%TYPE,
        p_telefono         IN  CLIENTE.telefono%TYPE,
        p_correo           IN  CLIENTE.correo%TYPE,
        p_id_cliente       OUT CLIENTE.id_cliente%TYPE,
        p_commit           IN  VARCHAR2 DEFAULT 'S'
    ) IS
        v_tipo   VARCHAR2(30)  := UPPER(TRIM(p_tipo_documento));
        v_numero VARCHAR2(60)  := TRIM(p_numero_documento);
    BEGIN
        SAVEPOINT sp_registrar_cliente_ini;

        IF v_tipo IS NULL OR v_tipo NOT IN ('CC', 'CE', 'PASAPORTE') THEN
            RAISE_APPLICATION_ERROR(c_err_parametro,
                'Tipo de documento no válido. Use CC, CE o PASAPORTE.');
        END IF;

        IF v_numero IS NULL THEN
            RAISE_APPLICATION_ERROR(c_err_parametro, 'El número de documento es obligatorio.');
        END IF;

        BEGIN
            SELECT id_cliente INTO p_id_cliente
            FROM CLIENTE
            WHERE tipo_documento = v_tipo
              AND numero_documento = v_numero;

            UPDATE CLIENTE
            SET telefono = NVL(TRIM(p_telefono), telefono),
                correo   = NVL(TRIM(p_correo), correo)
            WHERE id_cliente = p_id_cliente;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                IF TRIM(p_nombres) IS NULL OR TRIM(p_apellidos) IS NULL THEN
                    RAISE_APPLICATION_ERROR(c_err_cliente,
                        'El cliente ' || v_tipo || ' ' || v_numero ||
                        ' no existe. Ingrese nombres y apellidos para registrarlo.');
                END IF;

                INSERT INTO CLIENTE (tipo_documento, numero_documento, nombres,
                                     apellidos, telefono, correo)
                VALUES (v_tipo, v_numero, TRIM(p_nombres), TRIM(p_apellidos),
                        TRIM(p_telefono), TRIM(p_correo))
                RETURNING id_cliente INTO p_id_cliente;
        END;

        IF debe_confirmar(p_commit) THEN
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_registrar_cliente_ini;
            p_id_cliente := NULL;
            RAISE;
    END sp_registrar_cliente;

    -- sp_crear_reserva
    -- =================================================================
    PROCEDURE sp_crear_reserva (
        p_id_cliente    IN  CLIENTE.id_cliente%TYPE,
        p_id_habitacion IN  HABITACION.id_habitacion%TYPE,
        p_fecha_in      IN  DATE,
        p_fecha_out     IN  DATE,
        p_huespedes     IN  NUMBER,
        p_id_reserva    OUT RESERVA.id_reserva%TYPE,
        p_valor_estadia OUT NUMBER,
        p_id_usuario    IN  USUARIO_SISTEMA.id_usuario%TYPE DEFAULT NULL,
        p_commit        IN  VARCHAR2 DEFAULT 'S',
        p_bloquear      IN  VARCHAR2 DEFAULT 'S'
    ) IS
        v_in     DATE := TRUNC(p_fecha_in);
        v_out    DATE := TRUNC(p_fecha_out);
        v_hab    HABITACION%ROWTYPE;
        v_existe PLS_INTEGER;
    BEGIN
        SAVEPOINT sp_crear_reserva_ini;

        IF p_fecha_in IS NULL OR p_fecha_out IS NULL
           OR p_huespedes IS NULL OR p_huespedes <= 0 THEN
            RAISE_APPLICATION_ERROR(c_err_parametro,
                'Fechas y número de huéspedes (> 0) son obligatorios.');
        END IF;

        -- Checkout anterior o igual al checkin
        IF v_out <= v_in THEN
            RAISE_APPLICATION_ERROR(c_err_fechas,
                'El checkout (' || fmt(v_out) || ') debe ser posterior al checkin (' ||
                fmt(v_in) || ').');
        END IF;

        IF v_in < TRUNC(SYSDATE) THEN
            RAISE_APPLICATION_ERROR(c_err_fecha_pasada,
                'No se puede reservar con checkin en el pasado (' || fmt(v_in) || ').');
        END IF;

        SELECT COUNT(*) INTO v_existe
        FROM CLIENTE
        WHERE id_cliente = p_id_cliente;

        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(c_err_cliente,
                'El cliente ' || p_id_cliente || ' no existe.');
        END IF;

        -- E3 · Concurrencia: primero se bloquea la habitación y DESPUÉS se
        -- revisa si está libre (ver bloquear_habitacion).
        IF UPPER(NVL(p_bloquear, 'S')) = 'S' THEN
            bloquear_habitacion(p_id_habitacion);
        END IF;

        BEGIN
            SELECT * INTO v_hab
            FROM HABITACION
            WHERE id_habitacion = p_id_habitacion;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(c_err_habitacion,
                    'La habitación ' || p_id_habitacion || ' no existe.');
        END;

        -- Capacidad excedida
        IF p_huespedes > v_hab.capacidad THEN
            RAISE_APPLICATION_ERROR(c_err_capacidad,
                'La habitación ' || v_hab.numero || ' admite máximo ' || v_hab.capacidad ||
                ' huéspedes y se solicitaron ' || p_huespedes || '.');
        END IF;

        -- Habitación no disponible
        IF v_hab.estado <> 'DISPONIBLE' THEN
            RAISE_APPLICATION_ERROR(c_err_no_disponible,
                'La habitación ' || v_hab.numero || ' está en estado ' || v_hab.estado || '.');
        END IF;

        IF fn_habitacion_disponible(p_id_habitacion, v_in, v_out) = 'N' THEN
            RAISE_APPLICATION_ERROR(c_err_no_disponible,
                'La habitación ' || v_hab.numero || ' ya está reservada entre ' ||
                fmt(v_in) || ' y ' || fmt(v_out) || '.');
        END IF;

        -- Valor con tarifa por temporada (puede lanzar -20006)
        p_valor_estadia := fn_valor_estadia(p_id_habitacion, v_in, v_out);

        INSERT INTO RESERVA (fecha_reserva, fecha_checkin, fecha_checkout,
                             estado, id_cliente, id_usuario_registro)
        VALUES (SYSDATE, v_in, v_out, 'PENDIENTE', p_id_cliente, p_id_usuario)
        RETURNING id_reserva INTO p_id_reserva;

        INSERT INTO RESERVA_HABITACION (id_reserva, id_habitacion,
                                        cantidad_huespedes, valor_estadia)
        VALUES (p_id_reserva, p_id_habitacion, p_huespedes, p_valor_estadia);

        IF debe_confirmar(p_commit) THEN
            COMMIT;   -- confirmamos la reserva en la base de datos
        END IF;

        DBMS_OUTPUT.PUT_LINE('Reserva ' || p_id_reserva || ' creada: habitación ' ||
                             v_hab.numero || ', ' || (v_out - v_in) || ' noches, valor ' ||
                             p_valor_estadia || '.');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_crear_reserva_ini;   -- deshace solo lo de este procedimiento
            p_id_reserva    := NULL;
            p_valor_estadia := NULL;
            DBMS_OUTPUT.PUT_LINE('Error al crear la reserva: ' || SQLERRM);
            RAISE;   -- se propaga para que quien llama (o la interfaz) se entere
    END sp_crear_reserva;

    -- =================================================================
    PROCEDURE sp_agregar_habitacion (
        p_id_reserva    IN  RESERVA.id_reserva%TYPE,
        p_id_habitacion IN  HABITACION.id_habitacion%TYPE,
        p_huespedes     IN  NUMBER,
        p_valor_estadia OUT NUMBER,
        p_commit        IN  VARCHAR2 DEFAULT 'S'
    ) IS
        v_estado RESERVA.estado%TYPE;
        v_in     DATE;
        v_out    DATE;
        v_hab    HABITACION%ROWTYPE;
        v_aloj   NUMBER;
        v_existe PLS_INTEGER;
    BEGIN
        SAVEPOINT sp_agregar_hab_ini;

        BEGIN
            SELECT estado, fecha_checkin, fecha_checkout
            INTO v_estado, v_in, v_out
            FROM RESERVA
            WHERE id_reserva = p_id_reserva;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(c_err_reserva,
                    'La reserva ' || p_id_reserva || ' no existe.');
        END;

        IF v_estado NOT IN ('PENDIENTE', 'CONFIRMADA') THEN
            RAISE_APPLICATION_ERROR(c_err_reserva,
                'No se pueden agregar habitaciones a una reserva ' || v_estado || '.');
        END IF;

        IF p_huespedes IS NULL OR p_huespedes <= 0 THEN
            RAISE_APPLICATION_ERROR(c_err_parametro, 'El número de huéspedes debe ser > 0.');
        END IF;

        -- E3 · Concurrencia: misma protección al sumar otra habitación
        bloquear_habitacion(p_id_habitacion);

        BEGIN
            SELECT * INTO v_hab FROM HABITACION WHERE id_habitacion = p_id_habitacion;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(c_err_habitacion,
                    'La habitación ' || p_id_habitacion || ' no existe.');
        END;

        IF p_huespedes > v_hab.capacidad THEN
            RAISE_APPLICATION_ERROR(c_err_capacidad,
                'La habitación ' || v_hab.numero || ' admite máximo ' || v_hab.capacidad ||
                ' huéspedes y se solicitaron ' || p_huespedes || '.');
        END IF;

        SELECT COUNT(*) INTO v_existe
        FROM RESERVA_HABITACION
        WHERE id_reserva = p_id_reserva
          AND id_habitacion = p_id_habitacion;

        IF v_existe > 0 THEN
            RAISE_APPLICATION_ERROR(c_err_no_disponible,
                'La habitación ' || v_hab.numero || ' ya hace parte de la reserva.');
        END IF;

        -- Todas las habitaciones de una reserva son del mismo alojamiento
        SELECT MIN(h.id_alojamiento) INTO v_aloj
        FROM RESERVA_HABITACION rh
        JOIN HABITACION h ON h.id_habitacion = rh.id_habitacion
        WHERE rh.id_reserva = p_id_reserva;

        IF v_aloj IS NOT NULL AND v_aloj <> v_hab.id_alojamiento THEN
            RAISE_APPLICATION_ERROR(c_err_alojamiento,
                'La habitación ' || v_hab.numero ||
                ' pertenece a otro alojamiento distinto al de la reserva.');
        END IF;

        IF v_hab.estado <> 'DISPONIBLE'
           OR fn_habitacion_disponible(p_id_habitacion, v_in, v_out, p_id_reserva) = 'N' THEN
            RAISE_APPLICATION_ERROR(c_err_no_disponible,
                'La habitación ' || v_hab.numero || ' no está disponible entre ' ||
                fmt(v_in) || ' y ' || fmt(v_out) || '.');
        END IF;

        p_valor_estadia := fn_valor_estadia(p_id_habitacion, v_in, v_out);

        INSERT INTO RESERVA_HABITACION (id_reserva, id_habitacion,
                                        cantidad_huespedes, valor_estadia)
        VALUES (p_id_reserva, p_id_habitacion, p_huespedes, p_valor_estadia);

        IF debe_confirmar(p_commit) THEN
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_agregar_hab_ini;
            p_valor_estadia := NULL;
            RAISE;
    END sp_agregar_habitacion;

    -- =================================================================
    PROCEDURE sp_agregar_servicio (
        p_id_reserva  IN RESERVA.id_reserva%TYPE,
        p_id_servicio IN SERVICIO.id_servicio%TYPE,
        p_cantidad    IN NUMBER,
        p_commit      IN VARCHAR2 DEFAULT 'S'
    ) IS
        v_estado RESERVA.estado%TYPE;
        v_precio SERVICIO.precio%TYPE;
    BEGIN
        SAVEPOINT sp_agregar_srv_ini;

        BEGIN
            SELECT estado INTO v_estado FROM RESERVA WHERE id_reserva = p_id_reserva;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(c_err_reserva,
                    'La reserva ' || p_id_reserva || ' no existe.');
        END;

        IF v_estado NOT IN ('PENDIENTE', 'CONFIRMADA') THEN
            RAISE_APPLICATION_ERROR(c_err_reserva,
                'No se pueden agregar servicios a una reserva ' || v_estado || '.');
        END IF;

        IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
            RAISE_APPLICATION_ERROR(c_err_parametro, 'La cantidad debe ser > 0.');
        END IF;

        BEGIN
            SELECT precio INTO v_precio FROM SERVICIO WHERE id_servicio = p_id_servicio;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(c_err_parametro,
                    'El servicio ' || p_id_servicio || ' no existe.');
        END;

        -- Si el servicio ya estaba en la reserva se suma la cantidad
        -- (se conserva el precio con el que se pidió la primera vez).
        MERGE INTO RESERVA_SERVICIO rs
        USING (SELECT p_id_reserva AS id_reserva, p_id_servicio AS id_servicio FROM dual) s
        ON (rs.id_reserva = s.id_reserva AND rs.id_servicio = s.id_servicio)
        WHEN MATCHED THEN
            UPDATE SET rs.cantidad = rs.cantidad + p_cantidad
        WHEN NOT MATCHED THEN
            INSERT (id_reserva, id_servicio, cantidad, precio_unitario)
            VALUES (p_id_reserva, p_id_servicio, p_cantidad, v_precio);

        IF debe_confirmar(p_commit) THEN
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_agregar_srv_ini;
            RAISE;
    END sp_agregar_servicio;

    -- =================================================================
    -- Registra un pago APROBADO. Si con él se alcanza el anticipo
    -- (c_porcentaje_anticipo % del total) la reserva pasa a CONFIRMADA.
    -- =================================================================
    PROCEDURE sp_registrar_pago (
        p_id_reserva IN  RESERVA.id_reserva%TYPE,
        p_valor      IN  NUMBER,
        p_metodo     IN  VARCHAR2,
        p_id_pago    OUT PAGO.id_pago%TYPE,
        p_commit     IN  VARCHAR2 DEFAULT 'S'
    ) IS
        v_estado  RESERVA.estado%TYPE;
        v_total   NUMBER(14,2);
        v_pagado  NUMBER(14,2);
        v_metodo  VARCHAR2(200) := UPPER(TRIM(SUBSTR(p_metodo, 1, 200)));
    BEGIN
        SAVEPOINT sp_registrar_pago_ini;

        BEGIN
            SELECT estado INTO v_estado FROM RESERVA WHERE id_reserva = p_id_reserva;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(c_err_reserva,
                    'La reserva ' || p_id_reserva || ' no existe.');
        END;

        IF v_estado = 'CANCELADA' THEN
            RAISE_APPLICATION_ERROR(c_err_reserva,
                'No se pueden registrar pagos a una reserva CANCELADA.');
        END IF;

        IF p_valor IS NULL OR p_valor <= 0 THEN
            RAISE_APPLICATION_ERROR(c_err_pago, 'El valor del pago debe ser mayor que cero.');
        END IF;

        IF v_metodo IS NULL OR v_metodo NOT IN ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA', 'PSE') THEN
            RAISE_APPLICATION_ERROR(c_err_pago,
                'Método de pago no válido: ' || p_metodo ||
                '. Use EFECTIVO, TARJETA, TRANSFERENCIA o PSE.');
        END IF;

        v_total := fn_total_reserva(p_id_reserva);

        SELECT NVL(SUM(valor), 0) INTO v_pagado
        FROM PAGO
        WHERE id_reserva = p_id_reserva
          AND estado = 'APROBADO';

        IF v_total > 0 AND v_pagado + p_valor > v_total THEN
            RAISE_APPLICATION_ERROR(c_err_pago,
                'El pago excede el saldo. Total: ' || v_total ||
                ', pagado: ' || v_pagado || ', saldo: ' || (v_total - v_pagado) || '.');
        END IF;

        INSERT INTO PAGO (fecha_pago, valor, metodo_pago, estado, id_reserva)
        VALUES (SYSDATE, p_valor, v_metodo, 'APROBADO', p_id_reserva)
        RETURNING id_pago INTO p_id_pago;

        IF v_estado = 'PENDIENTE'
           AND v_pagado + p_valor >= v_total * c_porcentaje_anticipo / 100 THEN
            UPDATE RESERVA SET estado = 'CONFIRMADA' WHERE id_reserva = p_id_reserva;
        END IF;

        IF debe_confirmar(p_commit) THEN
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_registrar_pago_ini;
            p_id_pago := NULL;
            RAISE;
    END sp_registrar_pago;

    -- =================================================================
    PROCEDURE sp_cancelar_reserva (
        p_id_reserva IN RESERVA.id_reserva%TYPE,
        p_commit     IN VARCHAR2 DEFAULT 'S'
    ) IS
        v_estado RESERVA.estado%TYPE;
    BEGIN
        SAVEPOINT sp_cancelar_ini;

        BEGIN
            SELECT estado INTO v_estado FROM RESERVA WHERE id_reserva = p_id_reserva;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(c_err_reserva,
                    'La reserva ' || p_id_reserva || ' no existe.');
        END;

        IF v_estado IN ('CANCELADA', 'FINALIZADA') THEN
            RAISE_APPLICATION_ERROR(c_err_reserva,
                'La reserva ' || p_id_reserva || ' ya está ' || v_estado || '.');
        END IF;

        UPDATE RESERVA SET estado = 'CANCELADA' WHERE id_reserva = p_id_reserva;

        IF debe_confirmar(p_commit) THEN
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_cancelar_ini;
            RAISE;
    END sp_cancelar_reserva;

    -- =================================================================
    PROCEDURE sp_buscar_disponibles (
        p_fecha_in            IN  DATE,
        p_fecha_out           IN  DATE,
        p_huespedes           IN  NUMBER,
        p_cursor              OUT SYS_REFCURSOR,
        p_id_municipio        IN  MUNICIPIO.id_municipio%TYPE DEFAULT NULL,
        p_id_tipo_alojamiento IN  TIPO_ALOJAMIENTO.id_tipo_alojamiento%TYPE DEFAULT NULL
    ) IS
        v_in     DATE := TRUNC(p_fecha_in);
        v_out    DATE := TRUNC(p_fecha_out);
        v_noches NUMBER;
    BEGIN
        validar_rango(p_fecha_in, p_fecha_out);

        IF p_huespedes IS NULL OR p_huespedes <= 0 THEN
            RAISE_APPLICATION_ERROR(c_err_parametro, 'El número de huéspedes debe ser > 0.');
        END IF;

        v_noches := v_out - v_in;

        -- Versión por conjuntos (optimizada para la interfaz).
        -- Antes se llamaba fn_cotizar_estadia por cada habitación
        OPEN p_cursor FOR
            WITH libres AS (
                SELECT h.id_habitacion,
                       h.numero,
                       h.tipo       AS tipo_habitacion,
                       h.capacidad,
                       a.id_alojamiento,
                       a.nombre     AS alojamiento,
                       m.nombre     AS municipio,
                       t.nombre     AS tipo_alojamiento
                FROM HABITACION h
                JOIN ALOJAMIENTO a      ON a.id_alojamiento = h.id_alojamiento
                JOIN MUNICIPIO m        ON m.id_municipio = a.id_municipio
                JOIN TIPO_ALOJAMIENTO t ON t.id_tipo_alojamiento = a.id_tipo_alojamiento
                WHERE h.estado = 'DISPONIBLE'
                  AND h.capacidad >= p_huespedes
                  AND (p_id_municipio IS NULL OR a.id_municipio = p_id_municipio)
                  AND (p_id_tipo_alojamiento IS NULL OR a.id_tipo_alojamiento = p_id_tipo_alojamiento)
                  AND NOT EXISTS (
                        SELECT 1
                        FROM RESERVA_HABITACION rh
                        JOIN RESERVA r ON r.id_reserva = rh.id_reserva
                        WHERE rh.id_habitacion = h.id_habitacion
                          AND r.estado <> 'CANCELADA'
                          AND r.fecha_checkin  < v_out
                          AND r.fecha_checkout > v_in
                  )
            ),
            tramos AS (
                SELECT ta.id_habitacion,
                       LEAST(TRUNC(te.fecha_fin), v_out)
                         - GREATEST(TRUNC(te.fecha_inicio), v_in) AS noches_tramo,
                       ta.valor_noche
                FROM TARIFA ta
                JOIN TEMPORADA te ON te.id_temporada = ta.id_temporada
                WHERE te.fecha_inicio < v_out
                  AND te.fecha_fin    > v_in
            )
            SELECT l.id_habitacion,
                   l.numero,
                   l.tipo_habitacion,
                   l.capacidad,
                   l.id_alojamiento,
                   l.alojamiento,
                   l.municipio,
                   l.tipo_alojamiento,
                   v_noches                                AS noches,
                   SUM(tr.noches_tramo * tr.valor_noche)   AS valor_estadia
            FROM libres l
            JOIN tramos tr ON tr.id_habitacion = l.id_habitacion
            GROUP BY l.id_habitacion, l.numero, l.tipo_habitacion, l.capacidad,
                     l.id_alojamiento, l.alojamiento, l.municipio, l.tipo_alojamiento
            HAVING SUM(tr.noches_tramo) = v_noches
            ORDER BY valor_estadia, l.municipio, l.alojamiento, l.numero;
    END sp_buscar_disponibles;

    -- =================================================================
    -- sp_liquidar_mes  ·  PROCESO MASIVO CON CURSORES EXPLÍCITOS
    -- =================================================================
    PROCEDURE sp_liquidar_mes (
        p_anio                IN NUMBER,
        p_mes                 IN NUMBER,
        p_porcentaje_comision IN NUMBER   DEFAULT 10,
        p_id_municipio        IN NUMBER   DEFAULT NULL,
        p_commit              IN VARCHAR2 DEFAULT 'S'
    ) IS
        -- Cursor con parámetro y valor predeterminado (NULL = todos los municipios)
        CURSOR c_alojamientos (cp_id_municipio IN NUMBER := NULL) IS
            SELECT a.id_alojamiento, a.nombre
            FROM ALOJAMIENTO a
            WHERE cp_id_municipio IS NULL
               OR a.id_municipio = cp_id_municipio
            ORDER BY a.id_alojamiento;

        CURSOR c_estadias (cp_id_alojamiento IN NUMBER, cp_ini IN DATE, cp_fin IN DATE) IS
            SELECT r.id_reserva,
                   rh.id_habitacion,
                   GREATEST(r.fecha_checkin, cp_ini)  AS desde,
                   LEAST(r.fecha_checkout, cp_fin)    AS hasta
            FROM RESERVA r
            JOIN RESERVA_HABITACION rh ON rh.id_reserva = r.id_reserva
            JOIN HABITACION h          ON h.id_habitacion = rh.id_habitacion
            WHERE h.id_alojamiento = cp_id_alojamiento
              AND r.estado IN ('CONFIRMADA', 'FINALIZADA')
              AND r.fecha_checkin  < cp_fin
              AND r.fecha_checkout > cp_ini;

        CURSOR c_servicios (cp_id_alojamiento IN NUMBER, cp_ini IN DATE, cp_fin IN DATE) IS
            SELECT NVL(SUM(rs.cantidad * rs.precio_unitario), 0)
            FROM RESERVA_SERVICIO rs
            WHERE rs.id_reserva IN (
                SELECT rh.id_reserva
                FROM RESERVA_HABITACION rh
                JOIN HABITACION h ON h.id_habitacion = rh.id_habitacion
                JOIN RESERVA r    ON r.id_reserva = rh.id_reserva
                WHERE h.id_alojamiento = cp_id_alojamiento
                  AND r.estado IN ('CONFIRMADA', 'FINALIZADA')
                  AND r.fecha_checkout >  cp_ini
                  AND r.fecha_checkout <= cp_fin
            );

        TYPE t_marcas IS TABLE OF PLS_INTEGER INDEX BY PLS_INTEGER;

        v_reservas    t_marcas;
        v_aloj        c_alojamientos%ROWTYPE;
        r_estadia     c_estadias%ROWTYPE;
        v_ini         DATE;
        v_fin         DATE;
        v_valor       NUMBER(14,2);
        v_hospedaje   NUMBER(14,2);
        v_servicios   NUMBER(14,2);
        v_bruto       NUMBER(14,2);
        v_comision    NUMBER(14,2);
        v_neto        NUMBER(14,2);
        v_noches      NUMBER;
        v_num_res     NUMBER;
        v_sin_tarifa  NUMBER;
        v_procesados  PLS_INTEGER := 0;
    BEGIN
        IF p_anio IS NULL OR p_mes IS NULL OR p_mes NOT BETWEEN 1 AND 12 THEN
            RAISE_APPLICATION_ERROR(c_err_parametro, 'Año y mes (1-12) son obligatorios.');
        END IF;

        IF p_porcentaje_comision IS NULL OR p_porcentaje_comision NOT BETWEEN 0 AND 100 THEN
            RAISE_APPLICATION_ERROR(c_err_parametro, 'La comisión debe estar entre 0 y 100.');
        END IF;

        v_ini := TO_DATE(TO_CHAR(p_anio) || '-' || LPAD(TO_CHAR(p_mes), 2, '0') || '-01', 'YYYY-MM-DD');
        v_fin := ADD_MONTHS(v_ini, 1);

        OPEN c_alojamientos(p_id_municipio);
        LOOP
            FETCH c_alojamientos INTO v_aloj;
            EXIT WHEN c_alojamientos%NOTFOUND;

            v_reservas.DELETE;
            v_hospedaje  := 0;
            v_noches     := 0;
            v_sin_tarifa := 0;

            OPEN c_estadias(v_aloj.id_alojamiento, v_ini, v_fin);
            LOOP
                FETCH c_estadias INTO r_estadia;
                EXIT WHEN c_estadias%NOTFOUND;

                BEGIN
                    v_valor     := fn_valor_estadia(r_estadia.id_habitacion,
                                                    r_estadia.desde, r_estadia.hasta);
                    v_hospedaje := v_hospedaje + v_valor;
                    v_noches    := v_noches + (r_estadia.hasta - r_estadia.desde);
                    v_reservas(r_estadia.id_reserva) := 1;
                EXCEPTION
                    WHEN e_sin_tarifa THEN
                        v_sin_tarifa := v_sin_tarifa + 1;
                END;
            END LOOP;
            CLOSE c_estadias;

            OPEN c_servicios(v_aloj.id_alojamiento, v_ini, v_fin);
            FETCH c_servicios INTO v_servicios;
            CLOSE c_servicios;

            v_num_res  := v_reservas.COUNT;
            v_bruto    := v_hospedaje + v_servicios;
            v_comision := ROUND(v_bruto * p_porcentaje_comision / 100, 2);
            v_neto     := v_bruto - v_comision;

            MERGE INTO LIQUIDACION_MENSUAL l
            USING (SELECT v_aloj.id_alojamiento AS id_alojamiento FROM dual) s
            ON (l.id_alojamiento = s.id_alojamiento AND l.anio = p_anio AND l.mes = p_mes)
            WHEN MATCHED THEN UPDATE SET
                l.num_reservas        = v_num_res,
                l.noches_vendidas     = v_noches,
                l.ingreso_hospedaje   = v_hospedaje,
                l.ingreso_servicios   = v_servicios,
                l.total_bruto         = v_bruto,
                l.porcentaje_comision = p_porcentaje_comision,
                l.valor_comision      = v_comision,
                l.valor_neto          = v_neto,
                l.estadias_sin_tarifa = v_sin_tarifa,
                l.fecha_generacion    = SYSDATE,
                l.usuario_generacion  = USER
            WHEN NOT MATCHED THEN INSERT (
                id_alojamiento, anio, mes, num_reservas, noches_vendidas,
                ingreso_hospedaje, ingreso_servicios, total_bruto,
                porcentaje_comision, valor_comision, valor_neto, estadias_sin_tarifa)
            VALUES (
                s.id_alojamiento, p_anio, p_mes, v_num_res, v_noches,
                v_hospedaje, v_servicios, v_bruto,
                p_porcentaje_comision, v_comision, v_neto, v_sin_tarifa);

        END LOOP;
        v_procesados := c_alojamientos%ROWCOUNT;   -- filas leídas por el cursor
        CLOSE c_alojamientos;

        IF debe_confirmar(p_commit) THEN
            COMMIT;
        END IF;

        DBMS_OUTPUT.PUT_LINE('Liquidación ' || p_anio || '-' || LPAD(p_mes, 2, '0') ||
                             ': ' || v_procesados || ' alojamientos procesados.');
    EXCEPTION
        WHEN OTHERS THEN
            IF c_alojamientos%ISOPEN THEN CLOSE c_alojamientos; END IF;
            IF c_estadias%ISOPEN     THEN CLOSE c_estadias;     END IF;
            IF c_servicios%ISOPEN    THEN CLOSE c_servicios;    END IF;
            DBMS_OUTPUT.PUT_LINE('Error en la liquidación ' || p_anio || '-' || p_mes || ': ' || SQLERRM);
            RAISE;
    END sp_liquidar_mes;

    -- =================================================================
    PROCEDURE sp_liquidar_anio (
        p_anio                IN NUMBER,
        p_porcentaje_comision IN NUMBER DEFAULT 10
    ) IS
    BEGIN
        FOR m IN 1 .. 12 LOOP
            sp_liquidar_mes(p_anio, m, p_porcentaje_comision, NULL, 'N');
        END LOOP;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END sp_liquidar_anio;

    -- =================================================================
    -- sp_cancelar_pendientes_vencidas  ·  CURSOR PARA ACTUALIZACIÓN
    -- -----------------------------------------------------------------
    -- Al abrir el cursor, Oracle bloquea las filas de RESERVA que
    -- selecciona (FOR UPDATE OF estado) hasta el COMMIT o ROLLBACK, así
    -- nadie las paga ni las modifica mientras se cancelan.
    -- =================================================================
    PROCEDURE sp_cancelar_pendientes_vencidas (
        p_horas      IN  NUMBER DEFAULT 24,
        p_canceladas OUT NUMBER,
        p_commit     IN  VARCHAR2 DEFAULT 'S'
    ) IS
        CURSOR c_vencidas (cp_horas IN NUMBER := 24) IS
            SELECT r.id_reserva, r.fecha_reserva, r.fecha_checkin
            FROM RESERVA r
            WHERE r.estado = 'PENDIENTE'
              AND r.fecha_reserva  < SYSDATE - cp_horas / 24
              AND r.fecha_checkin >= TRUNC(SYSDATE)
              AND NOT EXISTS (SELECT 1 FROM PAGO p
                              WHERE p.id_reserva = r.id_reserva
                                AND p.estado = 'APROBADO')
            FOR UPDATE OF r.estado;

        r_vencida c_vencidas%ROWTYPE;
    BEGIN
        SAVEPOINT sp_cancelar_vencidas_ini;

        IF p_horas IS NULL OR p_horas <= 0 THEN
            RAISE_APPLICATION_ERROR(c_err_parametro, 'Las horas deben ser mayores que cero.');
        END IF;

        OPEN c_vencidas(p_horas);
        LOOP
            FETCH c_vencidas INTO r_vencida;
            EXIT WHEN c_vencidas%NOTFOUND;

            UPDATE RESERVA
            SET estado = 'CANCELADA'
            WHERE CURRENT OF c_vencidas;

            DBMS_OUTPUT.PUT_LINE('Reserva ' || r_vencida.id_reserva ||
                                 ' cancelada (creada el ' || fmt(r_vencida.fecha_reserva) ||
                                 ', sin anticipo).');
        END LOOP;
        p_canceladas := c_vencidas%ROWCOUNT;
        CLOSE c_vencidas;

        IF debe_confirmar(p_commit) THEN
            COMMIT;   -- libera los bloqueos del FOR UPDATE
        END IF;

        DBMS_OUTPUT.PUT_LINE('Total de reservas canceladas: ' || p_canceladas);
    EXCEPTION
        WHEN OTHERS THEN
            IF c_vencidas%ISOPEN THEN
                CLOSE c_vencidas;
            END IF;
            ROLLBACK TO sp_cancelar_vencidas_ini;
            p_canceladas := NULL;
            DBMS_OUTPUT.PUT_LINE('Error code: ' || SQLCODE);
            DBMS_OUTPUT.PUT_LINE('Error message: ' || SQLERRM);
            RAISE;
    END sp_cancelar_pendientes_vencidas;

    -- =================================================================
    -- sp_archivar_reservas  ·  histórico en TS_HISTORICO_RESERVAS
    -- =================================================================
    PROCEDURE sp_archivar_reservas (
        p_fecha_corte IN  DATE,
        p_filas       OUT NUMBER,
        p_purgar      IN  VARCHAR2 DEFAULT 'N',
        p_commit      IN  VARCHAR2 DEFAULT 'S'
    ) IS
        v_corte DATE := TRUNC(p_fecha_corte);
    BEGIN
        SAVEPOINT sp_archivar_ini;

        IF p_fecha_corte IS NULL THEN
            RAISE_APPLICATION_ERROR(c_err_parametro, 'La fecha de corte es obligatoria.');
        END IF;

        INSERT INTO HISTORICO_RESERVA (
            id_reserva, fecha_reserva, fecha_checkin, fecha_checkout, noches, estado,
            id_cliente, documento_cliente, nombre_cliente,
            id_alojamiento, alojamiento, municipio, habitaciones, total_huespedes,
            valor_estadia, total_servicios, total_pagado, calificacion)
        SELECT r.id_reserva, r.fecha_reserva, r.fecha_checkin, r.fecha_checkout,
               r.fecha_checkout - r.fecha_checkin, r.estado,
               c.id_cliente,
               c.tipo_documento || ' ' || c.numero_documento,
               c.nombres || ' ' || c.apellidos,
               hab.id_alojamiento, a.nombre, m.nombre,
               SUBSTR(hab.habitaciones, 1, 400), hab.huespedes,
               hab.valor_estadia, NVL(srv.total, 0), NVL(pag.total, 0), rs.calificacion
        FROM RESERVA r
        JOIN CLIENTE c ON c.id_cliente = r.id_cliente
        LEFT JOIN (
            SELECT rh.id_reserva,
                   MIN(h.id_alojamiento) AS id_alojamiento,
                   LISTAGG(h.numero, ',' ON OVERFLOW TRUNCATE)
                       WITHIN GROUP (ORDER BY h.numero) AS habitaciones,
                   SUM(rh.cantidad_huespedes) AS huespedes,
                   SUM(rh.valor_estadia)      AS valor_estadia
            FROM RESERVA_HABITACION rh
            JOIN HABITACION h ON h.id_habitacion = rh.id_habitacion
            GROUP BY rh.id_reserva
        ) hab ON hab.id_reserva = r.id_reserva
        LEFT JOIN ALOJAMIENTO a ON a.id_alojamiento = hab.id_alojamiento
        LEFT JOIN MUNICIPIO m   ON m.id_municipio = a.id_municipio
        LEFT JOIN (
            SELECT id_reserva, SUM(cantidad * precio_unitario) AS total
            FROM RESERVA_SERVICIO
            GROUP BY id_reserva
        ) srv ON srv.id_reserva = r.id_reserva
        LEFT JOIN (
            SELECT id_reserva, SUM(valor) AS total
            FROM PAGO
            WHERE estado = 'APROBADO'
            GROUP BY id_reserva
        ) pag ON pag.id_reserva = r.id_reserva
        LEFT JOIN RESENA rs ON rs.id_reserva = r.id_reserva
        WHERE r.estado IN ('FINALIZADA', 'CANCELADA')
          AND r.fecha_checkout < v_corte
          AND NOT EXISTS (
                SELECT 1 FROM HISTORICO_RESERVA hr WHERE hr.id_reserva = r.id_reserva);

        p_filas := SQL%ROWCOUNT;

        -- Purga opcional: solo lo que ya quedó copiado en el histórico
        IF UPPER(p_purgar) = 'S' THEN
            DELETE FROM RESENA WHERE id_reserva IN (
                SELECT hr.id_reserva FROM HISTORICO_RESERVA hr WHERE hr.fecha_checkout < v_corte);
            DELETE FROM RESERVA_SERVICIO WHERE id_reserva IN (
                SELECT hr.id_reserva FROM HISTORICO_RESERVA hr WHERE hr.fecha_checkout < v_corte);
            DELETE FROM PAGO WHERE id_reserva IN (
                SELECT hr.id_reserva FROM HISTORICO_RESERVA hr WHERE hr.fecha_checkout < v_corte);
            DELETE FROM RESERVA_HABITACION WHERE id_reserva IN (
                SELECT hr.id_reserva FROM HISTORICO_RESERVA hr WHERE hr.fecha_checkout < v_corte);
            DELETE FROM RESERVA WHERE id_reserva IN (
                SELECT hr.id_reserva FROM HISTORICO_RESERVA hr WHERE hr.fecha_checkout < v_corte);
        END IF;

        IF debe_confirmar(p_commit) THEN
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_archivar_ini;
            p_filas := NULL;
            RAISE;
    END sp_archivar_reservas;

    -- =================================================================
    -- pr_validar_solape  ·  la usan los disparadores (script 08)
    -- Lanza -20010 si la habitación ya está tomada por OTRA reserva no
    -- cancelada en un rango que se cruza con el de p_id_reserva.
    -- =================================================================
    PROCEDURE pr_validar_solape (
        p_id_reserva    IN RESERVA.id_reserva%TYPE,
        p_id_habitacion IN HABITACION.id_habitacion%TYPE
    ) IS
        v_in        DATE;
        v_out       DATE;
        v_estado    RESERVA.estado%TYPE;
        v_conflicto RESERVA.id_reserva%TYPE;
    BEGIN
        BEGIN
            SELECT fecha_checkin, fecha_checkout, estado
            INTO v_in, v_out, v_estado
            FROM RESERVA
            WHERE id_reserva = p_id_reserva;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN;  -- la FK se encarga de este caso
        END;

        IF v_estado = 'CANCELADA' THEN
            RETURN;
        END IF;

        SELECT MIN(r.id_reserva)
        INTO v_conflicto
        FROM RESERVA_HABITACION rh
        JOIN RESERVA r ON r.id_reserva = rh.id_reserva
        WHERE rh.id_habitacion = p_id_habitacion
          AND rh.id_reserva   <> p_id_reserva
          AND r.estado        <> 'CANCELADA'
          AND r.fecha_checkin  < v_out
          AND r.fecha_checkout > v_in;

        IF v_conflicto IS NOT NULL THEN
            RAISE_APPLICATION_ERROR(c_err_solape,
                'Solapamiento: la habitación ' || p_id_habitacion ||
                ' ya está ocupada por la reserva ' || v_conflicto ||
                ' en parte del rango ' || fmt(v_in) || ' a ' || fmt(v_out) || '.');
        END IF;
    END pr_validar_solape;

END PKG_TURISMOUQ;
/

-- Debe mostrar VALID para PACKAGE y PACKAGE BODY
SELECT object_name, object_type, status
FROM user_objects
WHERE object_name = 'PKG_TURISMOUQ';

SHOW ERRORS PACKAGE PKG_TURISMOUQ
SHOW ERRORS PACKAGE BODY PKG_TURISMOUQ