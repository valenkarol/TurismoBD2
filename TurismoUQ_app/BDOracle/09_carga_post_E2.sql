-- =====================================================================
--  1. Completa RESERVA_HABITACION.valor_estadia de las 25.000 reservas
--     cargadas en la entrega 1, usando fn_valor_estadia.
--  2. Archiva en el histórico
--  3. Ejecuta la liquidación mensual 2024–2026.
--  4. Refresca la vista materializada y recoge estadísticas.
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET TIMING ON

-- 1. Valor de estadía de las reservas existentes ----------------------
--    (el disparador de solapes no se dispara: solo vigila id_reserva e
--     id_habitacion, no valor_estadia)
UPDATE RESERVA_HABITACION rh
SET rh.valor_estadia = (
        SELECT PKG_TURISMOUQ.fn_cotizar_estadia(rh.id_habitacion,
                                                r.fecha_checkin,
                                                r.fecha_checkout)
        FROM RESERVA r
        WHERE r.id_reserva = rh.id_reserva)
WHERE rh.valor_estadia IS NULL;

COMMIT;

-- Debe dar 0 (todas las estadías tienen tarifa gracias al script 06)
SELECT COUNT(*) AS estadias_sin_valor
FROM RESERVA_HABITACION
WHERE valor_estadia IS NULL;

-- 2. Histórico: reservas cerradas antes del 2025-01-01 ---------------
DECLARE
    v_filas NUMBER;
BEGIN
    PKG_TURISMOUQ.sp_archivar_reservas(
        p_fecha_corte => DATE '2025-01-01',
        p_filas       => v_filas,
        p_purgar      => 'N');   -- 'N': se copian pero NO se borran
    DBMS_OUTPUT.PUT_LINE('Reservas archivadas en TS_HISTORICO_RESERVAS: ' || v_filas);
END;
/

SELECT estado, COUNT(*) AS reservas, SUM(total_pagado) AS total_pagado
FROM HISTORICO_RESERVA
GROUP BY estado;

SELECT segment_name, segment_type, tablespace_name, ROUND(bytes / 1024 / 1024, 2) AS mb
FROM user_segments
WHERE tablespace_name = 'TS_HISTORICO_RESERVAS';

-- 3. Liquidación mensual (cursor explícito con parámetros) -----------
BEGIN
    PKG_TURISMOUQ.sp_liquidar_anio(2024);
    PKG_TURISMOUQ.sp_liquidar_anio(2025);
    PKG_TURISMOUQ.sp_liquidar_anio(2026);
END;
/

SELECT anio, COUNT(*) AS filas, SUM(total_bruto) AS bruto, SUM(valor_neto) AS neto
FROM LIQUIDACION_MENSUAL
GROUP BY anio
ORDER BY anio;

-- 4. Vista materializada y estadísticas -------------------------------
BEGIN
    DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
END;
/

BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS(ownname => USER);
END;
/

SET TIMING OFF