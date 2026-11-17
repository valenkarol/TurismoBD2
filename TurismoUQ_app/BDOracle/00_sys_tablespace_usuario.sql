-- =====================================================================
--
-- Crea el tablespace del histórico de reservas y el usuario TURISMOUQ
-- y otorga los privilegios que necesitan las entregas
-- Reemplaza a SYSTEM_XEPDB1.sql y TURISMOUQ_XEPDB1.sql.
-- =====================================================================
SET SERVEROUTPUT ON
SET DEFINE OFF

SHOW USER;
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS contenedor FROM dual;

-- ---------------------------------------------------------------------
-- 1. Tablespace propio para el histórico de reservas
-- ---------------------------------------------------------------------

CREATE TABLESPACE TS_HISTORICO_RESERVAS
    DATAFILE 'ts_historico_reservas01.dbf'
    SIZE 50M
    AUTOEXTEND ON NEXT 25M MAXSIZE 2G
    EXTENT MANAGEMENT LOCAL AUTOALLOCATE
    SEGMENT SPACE MANAGEMENT AUTO;

-- ---------------------------------------------------------------------
-- 2. Usuario dueño del esquema
-- ---------------------------------------------------------------------
DECLARE
    v_existe NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_existe FROM dba_users WHERE username = 'TURISMOUQ';

    IF v_existe = 0 THEN
        EXECUTE IMMEDIATE
            'CREATE USER TURISMOUQ IDENTIFIED BY Turismo123 ' ||
            'DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP';
        DBMS_OUTPUT.PUT_LINE('Usuario TURISMOUQ creado.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('El usuario TURISMOUQ ya existía.');
    END IF;
END;
/

-- ---------------------------------------------------------------------
-- 3. Privilegios
--    RESOURCE ya incluye CREATE TABLE, SEQUENCE, PROCEDURE, TRIGGER, TYPE.
-- ---------------------------------------------------------------------
GRANT CONNECT, RESOURCE TO TURISMOUQ;
GRANT CREATE VIEW              TO TURISMOUQ;
GRANT CREATE MATERIALIZED VIEW TO TURISMOUQ;
GRANT CREATE SYNONYM           TO TURISMOUQ;

ALTER USER TURISMOUQ QUOTA UNLIMITED ON USERS;
ALTER USER TURISMOUQ QUOTA UNLIMITED ON TS_HISTORICO_RESERVAS;

-- ---------------------------------------------------------------------
-- 4. Verificación con las vistas del Diccionario de Datos vistas en clase
--    (DBA_TABLESPACES, DBA_DATA_FILES, DBA_SEGMENTS, DBA_FREE_SPACE)
-- ---------------------------------------------------------------------
SELECT tablespace_name, status, contents, extent_management,
       allocation_type, segment_space_management
FROM dba_tablespaces
ORDER BY tablespace_name;

SELECT tablespace_name, file_name,
       ROUND(bytes / 1024 / 1024) AS mb_actual,
       autoextensible,
       ROUND(maxbytes / 1024 / 1024) AS mb_maximo
FROM dba_data_files
WHERE tablespace_name = 'TS_HISTORICO_RESERVAS';

-- Espacio libre del tablespace (se reduce a medida que se archivan reservas)
SELECT tablespace_name, ROUND(SUM(bytes) / 1024 / 1024, 2) AS mb_libres
FROM dba_free_space
WHERE tablespace_name = 'TS_HISTORICO_RESERVAS'
GROUP BY tablespace_name;

-- Segmentos (tablas e índices) guardados en el tablespace.
-- Aparecen después de correr el script 09, cuando ya hay datos archivados.
SELECT owner, segment_name, segment_type, ROUND(bytes / 1024 / 1024, 2) AS mb
FROM dba_segments
WHERE tablespace_name = 'TS_HISTORICO_RESERVAS';

SELECT privilege
FROM dba_sys_privs
WHERE grantee = 'TURISMOUQ'
ORDER BY privilege;

SELECT tablespace_name, max_bytes
FROM dba_ts_quotas
WHERE username = 'TURISMOUQ';