INSERT INTO MUNICIPIO (nombre, departamento)
VALUES ('Armenia', 'Quindío');

INSERT INTO MUNICIPIO (nombre, departamento)
VALUES ('Calarcá', 'Quindío');

INSERT INTO MUNICIPIO (nombre, departamento)
VALUES ('Circasia', 'Quindío');

INSERT INTO MUNICIPIO (nombre, departamento)
VALUES ('Filandia', 'Quindío');

INSERT INTO MUNICIPIO (nombre, departamento)
VALUES ('Salento', 'Quindío');

INSERT INTO MUNICIPIO (nombre, departamento)
VALUES ('Montenegro', 'Quindío');

INSERT INTO MUNICIPIO (nombre, departamento)
VALUES ('Quimbaya', 'Quindío');

INSERT INTO MUNICIPIO (nombre, departamento)
VALUES ('La Tebaida', 'Quindío');

INSERT INTO MUNICIPIO (nombre, departamento)
VALUES ('Pijao', 'Quindío');

INSERT INTO MUNICIPIO (nombre, departamento)
VALUES ('Buenavista', 'Quindío');

INSERT INTO MUNICIPIO (nombre, departamento)
VALUES ('Córdoba', 'Quindío');

INSERT INTO MUNICIPIO (nombre, departamento)
VALUES ('Génova', 'Quindío');

COMMIT;


INSERT INTO TIPO_ALOJAMIENTO (nombre, descripcion)
VALUES (
    'FINCA CAFETERA',
    'Alojamiento rural relacionado con la cultura cafetera'
);

INSERT INTO TIPO_ALOJAMIENTO (nombre, descripcion)
VALUES (
    'HOTEL',
    'Alojamiento tradicional con habitaciones y servicios'
);

INSERT INTO TIPO_ALOJAMIENTO (nombre, descripcion)
VALUES (
    'GLAMPING',
    'Alojamiento turístico tipo glamping'
);

INSERT INTO TIPO_ALOJAMIENTO (nombre, descripcion)
VALUES (
    'HOSTAL',
    'Alojamiento turístico tipo hostal'
);

COMMIT;


INSERT INTO TEMPORADA (
    nombre,
    fecha_inicio,
    fecha_fin
)
VALUES (
    'TEMPORADA BAJA 2024',
    DATE '2024-01-01',
    DATE '2024-04-01'
);

INSERT INTO TEMPORADA (
    nombre,
    fecha_inicio,
    fecha_fin
)
VALUES (
    'TEMPORADA MEDIA 2024',
    DATE '2024-04-01',
    DATE '2024-07-01'
);

INSERT INTO TEMPORADA (
    nombre,
    fecha_inicio,
    fecha_fin
)
VALUES (
    'TEMPORADA ALTA 2024',
    DATE '2024-07-01',
    DATE '2024-10-01'
);

INSERT INTO TEMPORADA (
    nombre,
    fecha_inicio,
    fecha_fin
)
VALUES (
    'TEMPORADA BAJA 2025',
    DATE '2025-01-01',
    DATE '2025-04-01'
);

INSERT INTO TEMPORADA (
    nombre,
    fecha_inicio,
    fecha_fin
)
VALUES (
    'TEMPORADA MEDIA 2025',
    DATE '2025-04-01',
    DATE '2025-07-01'
);

INSERT INTO TEMPORADA (
    nombre,
    fecha_inicio,
    fecha_fin
)
VALUES (
    'TEMPORADA ALTA 2025',
    DATE '2025-07-01',
    DATE '2025-10-01'
);

INSERT INTO TEMPORADA (
    nombre,
    fecha_inicio,
    fecha_fin
)
VALUES (
    'TEMPORADA BAJA 2026',
    DATE '2026-01-01',
    DATE '2026-04-01'
);

INSERT INTO TEMPORADA (
    nombre,
    fecha_inicio,
    fecha_fin
)
VALUES (
    'TEMPORADA MEDIA 2026',
    DATE '2026-04-01',
    DATE '2026-07-01'
);

INSERT INTO TEMPORADA (
    nombre,
    fecha_inicio,
    fecha_fin
)
VALUES (
    'TEMPORADA ALTA 2026',
    DATE '2026-07-01',
    DATE '2026-10-01'
);

COMMIT;


------- generando con PL/SQL y DBMS_RANDOM -------

-------- 60 alojamientos ------

DECLARE
    v_municipio NUMBER;
    v_tipo NUMBER;
BEGIN

    FOR i IN 1..60 LOOP

        -- Seleccionar un municipio aleatorio entre los 12 existentes
        v_municipio := TRUNC(DBMS_RANDOM.VALUE(1, 13));

        -- Seleccionar un tipo de alojamiento aleatorio entre los 4 existentes
        v_tipo := TRUNC(DBMS_RANDOM.VALUE(1, 5));

        INSERT INTO ALOJAMIENTO (
            nombre,
            direccion,
            telefono,
            correo,
            id_municipio,
            id_tipo_alojamiento
        )
        VALUES (
            'Alojamiento TurismoUQ ' || i,
            'Carrera ' || TRUNC(DBMS_RANDOM.VALUE(1, 30))
                || ' # ' || TRUNC(DBMS_RANDOM.VALUE(1, 100)),
            '3' || TRUNC(DBMS_RANDOM.VALUE(100000000, 999999999)),
            'alojamiento' || i || '@turismouq.com',
            v_municipio,
            v_tipo
        );

    END LOOP;

    COMMIT;
END;
/

------- 400 habitaciones ------- 

DECLARE
    v_alojamiento NUMBER;
    v_capacidad NUMBER;
    v_tipo VARCHAR2(50);
BEGIN

    FOR i IN 1..400 LOOP

        -- Distribuir las habitaciones entre los 60 alojamientos
        v_alojamiento := MOD(i - 1, 60) + 1;

        -- Capacidad aleatoria entre 1 y 6 huéspedes
        v_capacidad := TRUNC(DBMS_RANDOM.VALUE(1, 7));

        -- Tipo de habitación aleatorio
        v_tipo := CASE TRUNC(DBMS_RANDOM.VALUE(1, 5))
                    WHEN 1 THEN 'SENCILLA'
                    WHEN 2 THEN 'DOBLE'
                    WHEN 3 THEN 'FAMILIAR'
                    WHEN 4 THEN 'SUITE'
                  END;

        INSERT INTO HABITACION (
            numero,
            capacidad,
            tipo,
            estado,
            id_alojamiento
        )
        VALUES (
            'H' || LPAD(i, 3, '0'),
            v_capacidad,
            v_tipo,
            'DISPONIBLE',
            v_alojamiento
        );

    END LOOP;

    COMMIT;
END;
/

---------- 3.600 registros en tarifas 400x9 ---------

DECLARE
    v_valor NUMBER(12,2);
BEGIN

    FOR h IN (
        SELECT id_habitacion
        FROM HABITACION
        ORDER BY id_habitacion
    ) LOOP

        FOR t IN (
            SELECT id_temporada
            FROM TEMPORADA
            ORDER BY id_temporada
        ) LOOP

            -- Valor base aleatorio entre $100.000 y $350.000
            v_valor := TRUNC(
                DBMS_RANDOM.VALUE(100000, 350001),
                -3
            );

            INSERT INTO TARIFA (
                valor_noche,
                id_habitacion,
                id_temporada
            )
            VALUES (
                v_valor,
                h.id_habitacion,
                t.id_temporada
            );

        END LOOP;

    END LOOP;

    COMMIT;
END;
/

-------- 3000 clientes-----

DECLARE
    v_tipo_documento VARCHAR2(20);
BEGIN

    FOR i IN 1..3000 LOOP

        v_tipo_documento :=
            CASE TRUNC(DBMS_RANDOM.VALUE(1, 4))
                WHEN 1 THEN 'CC'
                WHEN 2 THEN 'CE'
                WHEN 3 THEN 'PASAPORTE'
            END;

        INSERT INTO CLIENTE (
            tipo_documento,
            numero_documento,
            nombres,
            apellidos,
            telefono,
            correo
        )
        VALUES (
            v_tipo_documento,
            TO_CHAR(10000000 + i),
            'Cliente' || i,
            'Apellido' || i,
            '3' || TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(100000000, 1000000000))),
            'cliente' || i || '@correo.com'
        );

    END LOOP;

    COMMIT;
END;
/

-------- 20 servicios ----------

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('DESAYUNO', 'Desayuno para huéspedes', 25000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('ALMUERZO', 'Almuerzo para huéspedes', 40000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('CENA', 'Cena para huéspedes', 45000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('TOUR_CAFETERO', 'Recorrido por finca cafetera', 80000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('TOUR_VALLE_COCORA', 'Excursión al Valle del Cocora', 120000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('TRANSPORTE', 'Servicio de transporte turístico', 60000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('SPA', 'Servicio de spa', 90000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('MASAJE', 'Servicio de masaje', 70000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('PISCINA', 'Acceso a piscina', 20000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('JACUZZI', 'Acceso a jacuzzi', 30000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('CABALGATA', 'Cabalgata turística', 100000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('BICICLETAS', 'Alquiler de bicicletas', 35000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('SENDERISMO', 'Actividad de senderismo', 50000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('PARQUEADERO', 'Servicio de parqueadero', 15000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('WIFI_PREMIUM', 'Servicio de internet premium', 10000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('LAVANDERIA', 'Servicio de lavandería', 30000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('MINIBAR', 'Consumo de minibar', 25000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('FOTOGRAFIA', 'Sesión fotográfica turística', 80000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('CENA_ROMANTICA', 'Cena especial para huéspedes', 150000);

INSERT INTO SERVICIO (nombre, descripcion, precio)
VALUES ('GUIA_TURISTICO', 'Guía turístico privado', 100000);

COMMIT;

--------- 25000 reservas --------

DECLARE
    v_fecha_checkin DATE;
    v_fecha_checkout DATE;
    v_estado VARCHAR2(20);
    v_cliente NUMBER;
BEGIN

    FOR i IN 1..25000 LOOP

        -- Cliente aleatorio entre los 3.000 existentes
        v_cliente := TRUNC(DBMS_RANDOM.VALUE(1, 3001));

        -- Fecha de entrada aleatoria entre 2024 y 2026
        v_fecha_checkin :=
            DATE '2024-01-01'
            + TRUNC(DBMS_RANDOM.VALUE(0, 1095));

        -- Estadía entre 1 y 7 noches
        v_fecha_checkout :=
            v_fecha_checkin
            + TRUNC(DBMS_RANDOM.VALUE(1, 8));

        -- Estado aleatorio
        v_estado :=
            CASE TRUNC(DBMS_RANDOM.VALUE(1, 5))
                WHEN 1 THEN 'PENDIENTE'
                WHEN 2 THEN 'CONFIRMADA'
                WHEN 3 THEN 'FINALIZADA'
                WHEN 4 THEN 'CANCELADA'
            END;

        INSERT INTO RESERVA (
            fecha_reserva,
            fecha_checkin,
            fecha_checkout,
            estado,
            id_cliente
        )
        VALUES (
            v_fecha_checkin - TRUNC(DBMS_RANDOM.VALUE(1, 60)),
            v_fecha_checkin,
            v_fecha_checkout,
            v_estado,
            v_cliente
        );

    END LOOP;

    COMMIT;
END;
/

---------- asignar habitaciones a las reservas -------

DECLARE
    v_habitacion NUMBER;
    v_huespedes NUMBER;
BEGIN

    FOR r IN (
        SELECT id_reserva
        FROM RESERVA
        ORDER BY id_reserva
    ) LOOP

        v_habitacion :=
            TRUNC(DBMS_RANDOM.VALUE(1, 401));

        v_huespedes :=
            TRUNC(DBMS_RANDOM.VALUE(1, 5));

        BEGIN

            INSERT INTO RESERVA_HABITACION (
                id_reserva,
                id_habitacion,
                cantidad_huespedes
            )
            VALUES (
                r.id_reserva,
                v_habitacion,
                v_huespedes
            );

        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                NULL;
        END;

    END LOOP;

    COMMIT;
END;
/

--------- pagos asociados a reservas -------------

DECLARE
    v_valor NUMBER(12,2);
    v_metodo VARCHAR2(30);
    v_estado VARCHAR2(20);
BEGIN

    FOR r IN (
        SELECT id_reserva
        FROM RESERVA
        WHERE estado <> 'CANCELADA'
        ORDER BY id_reserva
    ) LOOP

        v_valor :=
            TRUNC(DBMS_RANDOM.VALUE(150000, 2000001), -3);

        v_metodo :=
            CASE TRUNC(DBMS_RANDOM.VALUE(1, 5))
                WHEN 1 THEN 'EFECTIVO'
                WHEN 2 THEN 'TARJETA'
                WHEN 3 THEN 'TRANSFERENCIA'
                WHEN 4 THEN 'PSE'
            END;

        v_estado :=
            CASE TRUNC(DBMS_RANDOM.VALUE(1, 4))
                WHEN 1 THEN 'APROBADO'
                WHEN 2 THEN 'APROBADO'
                WHEN 3 THEN 'PENDIENTE'
            END;

        INSERT INTO PAGO (
            fecha_pago,
            valor,
            metodo_pago,
            estado,
            id_reserva
        )
        VALUES (
            SYSDATE - TRUNC(DBMS_RANDOM.VALUE(0, 1000)),
            v_valor,
            v_metodo,
            v_estado,
            r.id_reserva
        );

    END LOOP;

    COMMIT;
END;
/

------------ 40000 lineas de servicios --------------

DECLARE
    v_reserva NUMBER;
    v_servicio NUMBER;
    v_cantidad NUMBER;
    v_precio NUMBER(12,2);
    v_insertados NUMBER := 0;
BEGIN

    WHILE v_insertados < 40000 LOOP

        v_reserva :=
            TRUNC(DBMS_RANDOM.VALUE(1, 25001));

        v_servicio :=
            TRUNC(DBMS_RANDOM.VALUE(1, 21));

        v_cantidad :=
            TRUNC(DBMS_RANDOM.VALUE(1, 4));

        SELECT precio
        INTO v_precio
        FROM SERVICIO
        WHERE id_servicio = v_servicio;

        BEGIN

            INSERT INTO RESERVA_SERVICIO (
                id_reserva,
                id_servicio,
                cantidad,
                precio_unitario
            )
            VALUES (
                v_reserva,
                v_servicio,
                v_cantidad,
                v_precio
            );

            v_insertados := v_insertados + 1;

        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                NULL;
        END;

    END LOOP;

    COMMIT;
END;
/

----------- crear reseñas ---------

DECLARE
    v_calificacion NUMBER;
    v_alojamiento NUMBER;
BEGIN
    FOR r IN (
        SELECT id_reserva,
               id_cliente,
               fecha_reserva
        FROM RESERVA
        WHERE estado = 'FINALIZADA'
        AND ROWNUM <= 10000
    ) LOOP

        BEGIN
            SELECT h.id_alojamiento
            INTO v_alojamiento
            FROM RESERVA_HABITACION rh
            JOIN HABITACION h
                ON h.id_habitacion = rh.id_habitacion
            WHERE rh.id_reserva = r.id_reserva
            AND ROWNUM = 1;

            v_calificacion := TRUNC(DBMS_RANDOM.VALUE(1, 6));

            INSERT INTO RESENA (
                calificacion,
                comentario,
                fecha_resena,
                id_cliente,
                id_alojamiento,
                id_reserva
            )
            VALUES (
                v_calificacion,
                'Excelente experiencia en TurismoUQ',
                r.fecha_reserva,
                r.id_cliente,
                v_alojamiento,
                r.id_reserva
            );

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL;
            WHEN DUP_VAL_ON_INDEX THEN
                NULL;
        END;

    END LOOP;

    COMMIT;
END;
/


