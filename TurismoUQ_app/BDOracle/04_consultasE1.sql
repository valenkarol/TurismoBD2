---C1- Ocupación por municipio y mes PIVOT -------- 
--- ¿Cuántas noches-habitación estuvieron ocupadas en cada municipio durante cada mes?
SELECT *
FROM (
    SELECT
        m.nombre AS municipio,
        EXTRACT(YEAR FROM r.fecha_checkin + (d.dia - 1)) AS anio,
        EXTRACT(MONTH FROM r.fecha_checkin + (d.dia - 1)) AS mes
    FROM RESERVA r
    JOIN RESERVA_HABITACION rh
        ON r.id_reserva = rh.id_reserva
    JOIN HABITACION h
        ON rh.id_habitacion = h.id_habitacion
    JOIN ALOJAMIENTO a
        ON h.id_alojamiento = a.id_alojamiento
    JOIN MUNICIPIO m
        ON a.id_municipio = m.id_municipio
    CROSS JOIN (
        SELECT LEVEL AS dia
        FROM dual
        CONNECT BY LEVEL <= 31
    ) d
    WHERE r.fecha_checkin + (d.dia - 1) < r.fecha_checkout
      AND r.fecha_checkin + (d.dia - 1) >= DATE '2024-01-01'
      AND r.fecha_checkin + (d.dia - 1) < DATE '2027-01-01'
)
PIVOT (
    COUNT(mes)
    FOR mes IN (
        1 AS ENERO,
        2 AS FEBRERO,
        3 AS MARZO,
        4 AS ABRIL,
        5 AS MAYO,
        6 AS JUNIO,
        7 AS JULIO,
        8 AS AGOSTO,
        9 AS SEPTIEMBRE,
        10 AS OCTUBRE,
        11 AS NOVIEMBRE,
        12 AS DICIEMBRE
    )
)
ORDER BY municipio, anio;

---C7-UNPIVOT para la PIVOT --- Ahora hacemos lo contrario: convertir las columnas de meses nuevamente en filas.

SELECT
    municipio,
    anio,
    mes,
    ocupacion
FROM (
    SELECT *
    FROM (
        SELECT
            m.nombre AS municipio,
            EXTRACT(YEAR FROM r.fecha_checkin) AS anio,
            EXTRACT(MONTH FROM r.fecha_checkin) AS mes
        FROM RESERVA r
        JOIN RESERVA_HABITACION rh
            ON r.id_reserva = rh.id_reserva
        JOIN HABITACION h
            ON rh.id_habitacion = h.id_habitacion
        JOIN ALOJAMIENTO a
            ON h.id_alojamiento = a.id_alojamiento
        JOIN MUNICIPIO m
            ON a.id_municipio = m.id_municipio
        WHERE r.fecha_checkin >= DATE '2024-01-01'
          AND r.fecha_checkin < DATE '2027-01-01'
    )
    PIVOT (
        COUNT(mes)
        FOR mes IN (
            1 AS ENERO,
            2 AS FEBRERO,
            3 AS MARZO,
            4 AS ABRIL,
            5 AS MAYO,
            6 AS JUNIO,
            7 AS JULIO,
            8 AS AGOSTO,
            9 AS SEPTIEMBRE,
            10 AS OCTUBRE,
            11 AS NOVIEMBRE,
            12 AS DICIEMBRE
        )
    )
)
UNPIVOT (
    ocupacion
    FOR mes IN (
        ENERO AS 'ENERO',
        FEBRERO AS 'FEBRERO',
        MARZO AS 'MARZO',
        ABRIL AS 'ABRIL',
        MAYO AS 'MAYO',
        JUNIO AS 'JUNIO',
        JULIO AS 'JULIO',
        AGOSTO AS 'AGOSTO',
        SEPTIEMBRE AS 'SEPTIEMBRE',
        OCTUBRE AS 'OCTUBRE',
        NOVIEMBRE AS 'NOVIEMBRE',
        DICIEMBRE AS 'DICIEMBRE'
    )
)
ORDER BY
    municipio,
    anio,
    CASE mes
        WHEN 'ENERO' THEN 1
        WHEN 'FEBRERO' THEN 2
        WHEN 'MARZO' THEN 3
        WHEN 'ABRIL' THEN 4
        WHEN 'MAYO' THEN 5
        WHEN 'JUNIO' THEN 6
        WHEN 'JULIO' THEN 7
        WHEN 'AGOSTO' THEN 8
        WHEN 'SEPTIEMBRE' THEN 9
        WHEN 'OCTUBRE' THEN 10
        WHEN 'NOVIEMBRE' THEN 11
        WHEN 'DICIEMBRE' THEN 12
    END;
    
---C2- Ingresos por municipio, tipo de alojamiento y temporada con ROLLUP o CUBE, usando GROUPING para distinguir los subtotales.
--¿Cuánto dinero generó cada combinación de municipio, tipo de alojamiento y temporada, incluyendo los subtotales por municipio, tipo y el total general?

SELECT
    CASE
        WHEN GROUPING(m.nombre) = 1
            THEN 'TOTAL GENERAL'
        ELSE m.nombre
    END AS municipio,

    CASE
        WHEN GROUPING(ta.nombre) = 1
            THEN 'TOTAL MUNICIPIO'
        ELSE ta.nombre
    END AS tipo_alojamiento,

    CASE
        WHEN GROUPING(te.nombre) = 1
            THEN 'TOTAL TIPO'
        ELSE te.nombre
    END AS temporada,

    ROUND(
        SUM(
            p.valor /
            (
                SELECT COUNT(*)
                FROM RESERVA_HABITACION rh2
                WHERE rh2.id_reserva = r.id_reserva
            )
        ),
        2
    ) AS ingreso

FROM RESERVA r

JOIN RESERVA_HABITACION rh
    ON r.id_reserva = rh.id_reserva

JOIN HABITACION h
    ON rh.id_habitacion = h.id_habitacion

JOIN ALOJAMIENTO a
    ON h.id_alojamiento = a.id_alojamiento

JOIN MUNICIPIO m
    ON a.id_municipio = m.id_municipio

JOIN TIPO_ALOJAMIENTO ta
    ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento

JOIN PAGO p
    ON r.id_reserva = p.id_reserva

JOIN TEMPORADA te
    ON r.fecha_checkin >= te.fecha_inicio
   AND r.fecha_checkin < te.fecha_fin

WHERE p.estado = 'APROBADO'
  AND r.fecha_checkin >= DATE '2024-01-01'
  AND r.fecha_checkin < DATE '2027-01-01'

GROUP BY ROLLUP(
    m.nombre,
    ta.nombre,
    te.nombre
)

ORDER BY
    m.nombre,
    ta.nombre,
    te.nombre;
    
--C3- Los tres alojamientos de mayor ingreso de cada municipio
SELECT
    municipio,
    alojamiento,
    ingreso,
    posicion
FROM (
    SELECT
        m.nombre AS municipio,
        a.nombre AS alojamiento,

        ROUND(
            SUM(
                p.valor /
                (
                    SELECT COUNT(*)
                    FROM RESERVA_HABITACION rh2
                    WHERE rh2.id_reserva = r.id_reserva
                )
            ),
            2
        ) AS ingreso,

        RANK() OVER (
            PARTITION BY m.nombre
            ORDER BY
                SUM(
                    p.valor /
                    (
                        SELECT COUNT(*)
                        FROM RESERVA_HABITACION rh3
                        WHERE rh3.id_reserva = r.id_reserva
                    )
                ) DESC
        ) AS posicion

    FROM RESERVA r

    JOIN RESERVA_HABITACION rh
        ON r.id_reserva = rh.id_reserva

    JOIN HABITACION h
        ON rh.id_habitacion = h.id_habitacion

    JOIN ALOJAMIENTO a
        ON h.id_alojamiento = a.id_alojamiento

    JOIN MUNICIPIO m
        ON a.id_municipio = m.id_municipio

    JOIN PAGO p
        ON r.id_reserva = p.id_reserva

    WHERE p.estado = 'APROBADO'
      AND r.fecha_checkin >= DATE '2024-01-01'
      AND r.fecha_checkin < DATE '2027-01-01'

    GROUP BY
        m.nombre,
        a.nombre
)
WHERE posicion <= 3

ORDER BY
    municipio,
    posicion,
    alojamiento;
    
--C4- Variación de ingreso mes contra mes
-- ¿Cuánto ingresó cada mes y cuánto aumentó o disminuyó respecto al mes anterior?
SELECT
    anio,
    mes,
    ingreso,
    ingreso_anterior,

    ROUND(
        ingreso - ingreso_anterior,
        2
    ) AS variacion

FROM (
    SELECT
        anio,
        mes,
        ingreso,

        LAG(ingreso) OVER (
            ORDER BY anio, mes
        ) AS ingreso_anterior

    FROM (
        SELECT
            EXTRACT(YEAR FROM fecha_pago) AS anio,
            EXTRACT(MONTH FROM fecha_pago) AS mes,

            SUM(valor) AS ingreso

        FROM PAGO

        WHERE estado = 'APROBADO'
          AND fecha_pago >= DATE '2024-01-01'
          AND fecha_pago < DATE '2027-01-01'

        GROUP BY
            EXTRACT(YEAR FROM fecha_pago),
            EXTRACT(MONTH FROM fecha_pago)
    )
)

ORDER BY
    anio,
    mes;
    
    
--C5- Consulta parametrizada con variables de enlace para el rango de fecha
SELECT
    COUNT(*) AS cantidad_pagos,
    SUM(valor) AS total_pagado,
    ROUND(AVG(valor), 2) AS promedio_pago,
    MIN(valor) AS pago_minimo,
    MAX(valor) AS pago_maximo

FROM PAGO

WHERE estado = 'APROBADO'

  AND fecha_pago >= TO_DATE(
        :fecha_inicio,
        'DD/MM/YYYY'
      )

  AND fecha_pago < TO_DATE(
        :fecha_fin,
        'DD/MM/YYYY'
      ) + 1;
      
      
---C6- crea la Vista materializada de ocupación mensual
CREATE MATERIALIZED VIEW MV_OCUPACION_MENSUAL
BUILD IMMEDIATE
REFRESH COMPLETE
ON DEMAND
AS

SELECT
    m.nombre AS municipio,

    EXTRACT(YEAR FROM r.fecha_checkin) AS anio,

    EXTRACT(MONTH FROM r.fecha_checkin) AS mes,

    COUNT(*) AS habitaciones_reservadas

FROM RESERVA r

JOIN RESERVA_HABITACION rh
    ON r.id_reserva = rh.id_reserva

JOIN HABITACION h
    ON rh.id_habitacion = h.id_habitacion

JOIN ALOJAMIENTO a
    ON h.id_alojamiento = a.id_alojamiento

JOIN MUNICIPIO m
    ON a.id_municipio = m.id_municipio

WHERE r.fecha_checkin >= DATE '2024-01-01'
  AND r.fecha_checkin < DATE '2027-01-01'

GROUP BY
    m.nombre,
    EXTRACT(YEAR FROM r.fecha_checkin),
    EXTRACT(MONTH FROM r.fecha_checkin);
    
    
--C8- Pregunta de negocio
--Qué municipios recibieron mayor cantidad de reservas entre 2024 y 2026?
SELECT
    m.nombre AS municipio,

    COUNT(DISTINCT r.id_reserva) AS cantidad_reservas

FROM RESERVA r

JOIN RESERVA_HABITACION rh
    ON r.id_reserva = rh.id_reserva

JOIN HABITACION h
    ON rh.id_habitacion = h.id_habitacion

JOIN ALOJAMIENTO a
    ON h.id_alojamiento = a.id_alojamiento

JOIN MUNICIPIO m
    ON a.id_municipio = m.id_municipio

WHERE r.fecha_checkin >= DATE '2024-01-01'
  AND r.fecha_checkin < DATE '2027-01-01'

GROUP BY
    m.nombre

ORDER BY
    cantidad_reservas DESC;