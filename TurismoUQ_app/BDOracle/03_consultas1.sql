------ Cuántos clientes hay por tipo de documento --------

SELECT
    tipo_documento,
    COUNT(*) AS cantidad_clientes
FROM CLIENTE
GROUP BY tipo_documento;

------ Cuánto dinero se ha pagado por cada método de pago -----

SELECT
    metodo_pago,
    SUM(valor) AS total_pagado
FROM PAGO
GROUP BY metodo_pago;

--- Cuál es la capacidad promedio de las habitaciones de cada alojamiento ---

SELECT
    a.nombre AS alojamiento,
    AVG(h.capacidad) AS capacidad_promedio
FROM ALOJAMIENTO a
JOIN HABITACION h
    ON a.id_alojamiento = h.id_alojamiento
GROUP BY a.nombre;

---- Cuál es la tarifa más alta de cada temporada ----

SELECT
    t.nombre AS temporada,
    MAX(ta.valor_noche) AS tarifa_maxima
FROM TEMPORADA t
JOIN TARIFA ta
    ON t.id_temporada = ta.id_temporada
GROUP BY t.nombre;

---- Cuál es la tarifa más económica de cada temporada ----

SELECT
    t.nombre AS temporada,
    MIN(ta.valor_noche) AS tarifa_minima
FROM TEMPORADA t
JOIN TARIFA ta
    ON t.id_temporada = ta.id_temporada
GROUP BY t.nombre;

----- Cuántas reservas confirmadas tiene cada año ----

SELECT
    EXTRACT(YEAR FROM fecha_reserva) AS anio,
    COUNT(*) AS cantidad_reservas
FROM RESERVA
WHERE estado = 'CONFIRMADA'
GROUP BY EXTRACT(YEAR FROM fecha_reserva)
ORDER BY anio;

----- Qué estados de reserva tienen más de 5.000 reservas -----

SELECT
    estado,
    COUNT(*) AS cantidad_reservas
FROM RESERVA
GROUP BY estado
HAVING COUNT(*) > 5000;

----- De las reservas confirmadas, qué años tienen más de 2.000 reservas ----

SELECT
    EXTRACT(YEAR FROM fecha_reserva) AS anio,
    COUNT(*) AS cantidad_reservas
FROM RESERVA
WHERE estado = 'CONFIRMADA'
GROUP BY EXTRACT(YEAR FROM fecha_reserva)
HAVING COUNT(*) > 2000
ORDER BY anio;

----- convinaciones posibles entre reservas por año y estado CUBE ----

SELECT
    EXTRACT(YEAR FROM fecha_reserva) AS anio,
    estado,
    COUNT(*) AS cantidad_reservas
FROM RESERVA
GROUP BY CUBE (
    EXTRACT(YEAR FROM fecha_reserva),
    estado
)
ORDER BY
    anio,
    estado;

----- Agrupacion reservas por año ----

SELECT
    EXTRACT(YEAR FROM fecha_reserva) AS anio,
    COUNT(*) AS cantidad_reservas
FROM RESERVA
GROUP BY GROUPING SETS (
    (EXTRACT(YEAR FROM fecha_reserva))
)
ORDER BY
    anio;
    
