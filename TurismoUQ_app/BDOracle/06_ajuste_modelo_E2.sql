-- =====================================================================
-- Ejecutar como: TURISMOUQ, después de 01, 02, 04 y 05.
-- =====================================================================
SET DEFINE OFF
SET SQLBLANKLINES ON
SET SERVEROUTPUT ON

-- ---------------------------------------------------------------------
-- 1. TEMPORADA: tipo + calendario completo
-- ---------------------------------------------------------------------
ALTER TABLE TEMPORADA ADD (tipo VARCHAR2(10));

UPDATE TEMPORADA
SET tipo = CASE
               WHEN nombre LIKE '%BAJA%'  THEN 'BAJA'
               WHEN nombre LIKE '%MEDIA%' THEN 'MEDIA'
               ELSE 'ALTA'
           END
WHERE tipo IS NULL;

-- Temporadas que faltaban. Rango semiabierto [fecha_inicio, fecha_fin):
-- la noche de fecha_fin ya pertenece a la siguiente temporada.
INSERT INTO TEMPORADA (nombre, fecha_inicio, fecha_fin, tipo) VALUES ('TEMPORADA BAJA OCT-NOV 2024',  DATE '2024-10-01', DATE '2024-12-01', 'BAJA');
INSERT INTO TEMPORADA (nombre, fecha_inicio, fecha_fin, tipo) VALUES ('TEMPORADA ALTA DICIEMBRE 2024', DATE '2024-12-01', DATE '2025-01-01', 'ALTA');
INSERT INTO TEMPORADA (nombre, fecha_inicio, fecha_fin, tipo) VALUES ('TEMPORADA BAJA OCT-NOV 2025',  DATE '2025-10-01', DATE '2025-12-01', 'BAJA');
INSERT INTO TEMPORADA (nombre, fecha_inicio, fecha_fin, tipo) VALUES ('TEMPORADA ALTA DICIEMBRE 2025', DATE '2025-12-01', DATE '2026-01-01', 'ALTA');
INSERT INTO TEMPORADA (nombre, fecha_inicio, fecha_fin, tipo) VALUES ('TEMPORADA BAJA OCT-NOV 2026',  DATE '2026-10-01', DATE '2026-12-01', 'BAJA');
INSERT INTO TEMPORADA (nombre, fecha_inicio, fecha_fin, tipo) VALUES ('TEMPORADA ALTA DICIEMBRE 2026', DATE '2026-12-01', DATE '2027-01-01', 'ALTA');
INSERT INTO TEMPORADA (nombre, fecha_inicio, fecha_fin, tipo) VALUES ('TEMPORADA BAJA 2027',          DATE '2027-01-01', DATE '2027-04-01', 'BAJA');
INSERT INTO TEMPORADA (nombre, fecha_inicio, fecha_fin, tipo) VALUES ('TEMPORADA MEDIA 2027',         DATE '2027-04-01', DATE '2027-07-01', 'MEDIA');
INSERT INTO TEMPORADA (nombre, fecha_inicio, fecha_fin, tipo) VALUES ('TEMPORADA ALTA 2027',          DATE '2027-07-01', DATE '2027-10-01', 'ALTA');
INSERT INTO TEMPORADA (nombre, fecha_inicio, fecha_fin, tipo) VALUES ('TEMPORADA BAJA OCT-NOV 2027',  DATE '2027-10-01', DATE '2027-12-01', 'BAJA');
INSERT INTO TEMPORADA (nombre, fecha_inicio, fecha_fin, tipo) VALUES ('TEMPORADA ALTA DICIEMBRE 2027', DATE '2027-12-01', DATE '2028-01-01', 'ALTA');

ALTER TABLE TEMPORADA MODIFY (tipo NOT NULL);
ALTER TABLE TEMPORADA ADD CONSTRAINT ck_temporada_tipo
    CHECK (tipo IN ('BAJA', 'MEDIA', 'ALTA'));

COMMIT;

-- ---------------------------------------------------------------------
-- 2. TARIFA de las temporadas nuevas
--    Para cada habitación: promedio de lo que ya cobra en temporadas del
--    mismo tipo (redondeado a miles). Para 2027 se suma un 5 % de ajuste.
--    Se hace ANTES de crear los disparadores de auditoría (script 08),
--    por eso esta carga inicial no queda auditada.
-- ---------------------------------------------------------------------
INSERT INTO TARIFA (valor_noche, id_habitacion, id_temporada)
SELECT ROUND(AVG(ta.valor_noche)
             * CASE WHEN tn.fecha_inicio >= DATE '2027-01-01' THEN 1.05 ELSE 1 END,
             -3),
       ta.id_habitacion,
       tn.id_temporada
FROM TEMPORADA tn
JOIN TEMPORADA tv
    ON tv.tipo = tn.tipo
   AND tv.id_temporada <> tn.id_temporada
JOIN TARIFA ta
    ON ta.id_temporada = tv.id_temporada
WHERE NOT EXISTS (SELECT 1 FROM TARIFA x WHERE x.id_temporada = tn.id_temporada)
GROUP BY ta.id_habitacion, tn.id_temporada, tn.fecha_inicio;

COMMIT;

-- Verificación: cada temporada debe tener 400 tarifas y no debe haber huecos
SELECT te.nombre, te.tipo, te.fecha_inicio, te.fecha_fin, COUNT(ta.id_tarifa) AS tarifas
FROM TEMPORADA te
LEFT JOIN TARIFA ta ON ta.id_temporada = te.id_temporada
GROUP BY te.nombre, te.tipo, te.fecha_inicio, te.fecha_fin
ORDER BY te.fecha_inicio;

-- Huecos entre temporadas consecutivas (debe devolver 0 filas)
SELECT nombre, fecha_fin, siguiente_inicio
FROM (
    SELECT nombre, fecha_fin,
           LEAD(fecha_inicio) OVER (ORDER BY fecha_inicio) AS siguiente_inicio
    FROM TEMPORADA
)
WHERE siguiente_inicio IS NOT NULL
  AND siguiente_inicio <> fecha_fin;

-- ---------------------------------------------------------------------
-- 3. Valor de la estadía congelado por habitación reservada
--    Se guarda al reservar (sp_crear_reserva). Si mañana cambian las
--    tarifas, las reservas ya hechas conservan su precio.
--    Las 25.000 reservas existentes se completan en el script 09.
-- ---------------------------------------------------------------------
ALTER TABLE RESERVA_HABITACION ADD (
    valor_estadia NUMBER(14,2),
    CONSTRAINT ck_rh_valor_estadia CHECK (valor_estadia >= 0)
);

-- ---------------------------------------------------------------------
-- 4. Usuarios del sistema (login de la interfaz / roles entrega 3)
-- ---------------------------------------------------------------------
ALTER TABLE USUARIO_SISTEMA ADD (
    clave_hash      VARCHAR2(128),
    id_alojamiento  NUMBER,
    fecha_creacion  DATE DEFAULT SYSDATE NOT NULL,
    ultimo_acceso   DATE,
    CONSTRAINT fk_usuario_alojamiento
        FOREIGN KEY (id_alojamiento) REFERENCES ALOJAMIENTO(id_alojamiento)
);

COMMENT ON COLUMN USUARIO_SISTEMA.clave_hash IS
    'Hash de la clave. La interfaz debe generarlo (bcrypt/argon2). Los usuarios semilla usan SHA-256 solo para pruebas.';
COMMENT ON COLUMN USUARIO_SISTEMA.id_alojamiento IS
    'Alojamiento que administra (solo para rol ADMINISTRADOR).';

ALTER TABLE RESERVA ADD (
    id_usuario_registro NUMBER,
    CONSTRAINT fk_reserva_usuario
        FOREIGN KEY (id_usuario_registro) REFERENCES USUARIO_SISTEMA(id_usuario)
);

-- Un usuario por rol (clave de prueba: Turismo2026*)
MERGE INTO USUARIO_SISTEMA u
USING (
    SELECT 'recepcion1' AS nombre_usuario, 'Recepción Demo' AS nombre_completo,
           'recepcion1@turismouq.com' AS correo, 'RECEPCION' AS rol, CAST(NULL AS NUMBER) AS id_alojamiento FROM dual
    UNION ALL
    SELECT 'admin_aloj1', 'Administrador Alojamiento 1', 'admin1@turismouq.com', 'ADMINISTRADOR', 1 FROM dual
    UNION ALL
    SELECT 'gerente1', 'Gerente Demo', 'gerente1@turismouq.com', 'GERENTE', NULL FROM dual
    UNION ALL
    SELECT 'auditor1', 'Auditor Demo', 'auditor1@turismouq.com', 'AUDITOR', NULL FROM dual
) s
ON (u.nombre_usuario = s.nombre_usuario)
WHEN NOT MATCHED THEN
    INSERT (nombre_usuario, nombre_completo, correo, rol, activo, clave_hash, id_alojamiento)
    VALUES (s.nombre_usuario, s.nombre_completo, s.correo, s.rol, 'S',
            RAWTOHEX(STANDARD_HASH('Turismo2026*', 'SHA256')), s.id_alojamiento);

COMMIT;

-- ---------------------------------------------------------------------
-- 5. Auditoría de TARIFA
--    AUDITORIA_TARIFA          -> 1 fila por SENTENCIA (quién y cuándo)
--    AUDITORIA_TARIFA_DETALLE  -> 1 fila por tarifa afectada (antes/después)
--    GTT_AUDITORIA_TARIFA      -> tabla temporal global donde el disparador
--                                 de fila deja los valores :OLD/:NEW para
--                                 que el disparador de SENTENCIA los guarde.
--                                 ON COMMIT DELETE ROWS: cada sesión ve solo
--                                 lo suyo y nada queda colgado.
-- ---------------------------------------------------------------------
CREATE TABLE AUDITORIA_TARIFA (
    id_auditoria     NUMBER GENERATED ALWAYS AS IDENTITY,
    operacion        VARCHAR2(10)   NOT NULL,
    filas_afectadas  NUMBER         NOT NULL,
    usuario_bd       VARCHAR2(128)  NOT NULL,
    usuario_app      VARCHAR2(128),
    usuario_so       VARCHAR2(128),
    equipo           VARCHAR2(128),
    direccion_ip     VARCHAR2(50),
    programa         VARCHAR2(128),
    fecha_cambio     TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_auditoria_tarifa PRIMARY KEY (id_auditoria),
    CONSTRAINT ck_aud_tarifa_operacion CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE'))
);

CREATE TABLE AUDITORIA_TARIFA_DETALLE (
    id_detalle       NUMBER GENERATED ALWAYS AS IDENTITY,
    id_auditoria     NUMBER         NOT NULL,
    operacion        VARCHAR2(10)   NOT NULL,
    id_tarifa        NUMBER         NOT NULL,
    id_habitacion    NUMBER,
    id_temporada     NUMBER,
    valor_anterior   NUMBER(12,2),
    valor_nuevo      NUMBER(12,2),
    CONSTRAINT pk_auditoria_tarifa_detalle PRIMARY KEY (id_detalle),
    CONSTRAINT fk_aud_detalle_encabezado
        FOREIGN KEY (id_auditoria) REFERENCES AUDITORIA_TARIFA(id_auditoria)
);

CREATE GLOBAL TEMPORARY TABLE GTT_AUDITORIA_TARIFA (
    operacion        VARCHAR2(10),
    id_tarifa        NUMBER,
    id_habitacion    NUMBER,
    id_temporada     NUMBER,
    valor_anterior   NUMBER(12,2),
    valor_nuevo      NUMBER(12,2)
) ON COMMIT DELETE ROWS;

-- ---------------------------------------------------------------------
-- 6. Liquidación mensual por alojamiento (proceso masivo con cursor)
-- ---------------------------------------------------------------------
CREATE TABLE LIQUIDACION_MENSUAL (
    id_liquidacion       NUMBER GENERATED BY DEFAULT AS IDENTITY,
    id_alojamiento       NUMBER         NOT NULL,
    anio                 NUMBER(4)      NOT NULL,
    mes                  NUMBER(2)      NOT NULL,
    num_reservas         NUMBER         DEFAULT 0 NOT NULL,
    noches_vendidas      NUMBER         DEFAULT 0 NOT NULL,
    ingreso_hospedaje    NUMBER(14,2)   DEFAULT 0 NOT NULL,
    ingreso_servicios    NUMBER(14,2)   DEFAULT 0 NOT NULL,
    total_bruto          NUMBER(14,2)   DEFAULT 0 NOT NULL,
    porcentaje_comision  NUMBER(5,2)    NOT NULL,
    valor_comision       NUMBER(14,2)   DEFAULT 0 NOT NULL,
    valor_neto           NUMBER(14,2)   DEFAULT 0 NOT NULL,
    estadias_sin_tarifa  NUMBER         DEFAULT 0 NOT NULL,
    fecha_generacion     DATE           DEFAULT SYSDATE NOT NULL,
    usuario_generacion   VARCHAR2(128)  DEFAULT USER NOT NULL,
    CONSTRAINT pk_liquidacion_mensual PRIMARY KEY (id_liquidacion),
    CONSTRAINT fk_liquidacion_alojamiento
        FOREIGN KEY (id_alojamiento) REFERENCES ALOJAMIENTO(id_alojamiento),
    CONSTRAINT uq_liquidacion_periodo UNIQUE (id_alojamiento, anio, mes),
    CONSTRAINT ck_liquidacion_mes CHECK (mes BETWEEN 1 AND 12),
    CONSTRAINT ck_liquidacion_comision CHECK (porcentaje_comision BETWEEN 0 AND 100)
);