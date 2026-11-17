SHOW USER;
SELECT
    mview_name,
    refresh_mode,
    refresh_method
FROM USER_MVIEWS
WHERE mview_name = 'MV_OCUPACION_MENSUAL';

--datos de la vista
SELECT *
FROM MV_OCUPACION_MENSUAL
ORDER BY municipio, anio, mes;

--- Politica de refresco justificada

REFRESH COMPLETE
ON DEMAND

BEGIN
    DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL');
END;
/