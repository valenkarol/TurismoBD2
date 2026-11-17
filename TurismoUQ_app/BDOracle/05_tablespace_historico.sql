-- Ejecutar como: TURISMOUQ   (requiere haber corrido 00 como SYSTEM)
--
-- Tabla de histórico de reservas ubicada en su propio tablespace
-- TS_HISTORICO_RESERVAS.
--
-- La tabla se llena con PKG_TURISMOUQ.sp_archivar_reservas (script 07),
-- que se ejecuta en el script 09 con corte 2025-01-01.
-- =====================================================================
SET DEFINE OFF
SET SQLBLANKLINES ON

CREATE TABLE HISTORICO_RESERVA (
    id_reserva          NUMBER          NOT NULL,
    fecha_reserva       DATE            NOT NULL,
    fecha_checkin       DATE            NOT NULL,
    fecha_checkout      DATE            NOT NULL,
    noches              NUMBER          NOT NULL,
    estado              VARCHAR2(20)    NOT NULL,
    id_cliente          NUMBER          NOT NULL,
    documento_cliente   VARCHAR2(60),
    nombre_cliente      VARCHAR2(210),
    id_alojamiento      NUMBER,
    alojamiento         VARCHAR2(150),
    municipio           VARCHAR2(100),
    habitaciones        VARCHAR2(400),
    total_huespedes     NUMBER,
    valor_estadia       NUMBER(14,2),
    total_servicios     NUMBER(14,2)    DEFAULT 0 NOT NULL,
    total_pagado        NUMBER(14,2)    DEFAULT 0 NOT NULL,
    calificacion        NUMBER(1),
    fecha_archivo       DATE            DEFAULT SYSDATE NOT NULL,
    usuario_archivo     VARCHAR2(128)   DEFAULT USER NOT NULL,
    CONSTRAINT pk_historico_reserva
        PRIMARY KEY (id_reserva)
        USING INDEX TABLESPACE TS_HISTORICO_RESERVAS,
    CONSTRAINT ck_hist_estado
        CHECK (estado IN ('FINALIZADA', 'CANCELADA')),
    CONSTRAINT ck_hist_fechas
        CHECK (fecha_checkout > fecha_checkin),
    CONSTRAINT ck_hist_calificacion
        CHECK (calificacion BETWEEN 1 AND 5)
)
TABLESPACE TS_HISTORICO_RESERVAS
PCTFREE 0;

CREATE INDEX ix_hist_checkin
    ON HISTORICO_RESERVA (fecha_checkin)
    TABLESPACE TS_HISTORICO_RESERVAS;

COMMENT ON TABLE HISTORICO_RESERVA IS
    'Foto desnormalizada de reservas cerradas (FINALIZADA/CANCELADA). Vive en TS_HISTORICO_RESERVAS.';


-- Después del script 09
-- (que archiva las reservas de 2024) sí aparecen la tabla y sus índices.
SELECT segment_name, segment_type, tablespace_name,
       ROUND(bytes / 1024 / 1024, 2) AS mb
FROM user_segments
WHERE tablespace_name = 'TS_HISTORICO_RESERVAS';

SELECT table_name, tablespace_name, pct_free
FROM user_tables
WHERE table_name = 'HISTORICO_RESERVA';