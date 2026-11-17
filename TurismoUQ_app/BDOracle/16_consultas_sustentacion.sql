-- =====================================================================
-- SUSTENTACIÓN · Las dos consultas pedidas por la profesora
-- Ejecutar como: TURISMOUQ (después de los scripts 00 a 15).
-- Corre completo con F5 y se puede repetir: solo hace SELECT.
--
--   CONSULTA 1  ¿Cuál fue la habitación con más reservas en temporada alta?
--   CONSULTA 2  Listado de clientes con más municipios
--               (2A: clientes que han reservado en más municipios distintos;
--                2B: el cliente con más reservas en cada municipio)
--
-- Las dos están también en la interfaz: menú "Consultas", sección
-- "Consultas de la sustentación".
--
-- Criterios usados (para explicarlos si los preguntan):
--   * Las reservas CANCELADAS no cuentan: nunca se ocuparon.
--   * "Temporada alta" = las temporadas con TEMPORADA.tipo = 'ALTA'
--     (julio a septiembre y diciembre de cada año, columna creada en el
--     script 06).
--   * Una reserva está "en temporada alta" si al menos una de sus noches
--     cae dentro de una temporada alta. Dos rangos [a1, b1) y [a2, b2) se
--     cruzan cuando a1 < b2 y a2 < b1 (la misma regla del script 07).
--   * Se usa RANK() y no FETCH FIRST 1 ROW: si dos habitaciones o dos
--     clientes empatan en el primer lugar, salen los dos.
-- =====================================================================
SET LINESIZE 220
SET PAGESIZE 200

-- =====================================================================
-- CONSULTA 1 · Habitación con más reservas en temporada alta
-- =====================================================================
-- Paso a paso:
--   1. Une cada reserva no cancelada con su(s) habitación(es).
--   2. La une con las temporadas ALTA cuyas fechas se cruzan con la
--      estadía.
--   3. Agrupa por habitación y cuenta reservas distintas. COUNT(DISTINCT)
--      evita contar dos veces una reserva si cruzara dos temporadas.
--   4. Calcula también cuántas de esas noches cayeron en temporada alta:
--      LEAST(salida, fin de temporada) - GREATEST(entrada, inicio).
--   5. RANK() ordena de mayor a menor; posición 1 = la respuesta.
-- ---------------------------------------------------------------------
SELECT posicion, id_habitacion, habitacion, tipo_habitacion,
       alojamiento, municipio, reservas_temporada_alta, noches_temporada_alta
FROM (
    SELECT h.id_habitacion,
           h.numero                       AS habitacion,
           h.tipo                         AS tipo_habitacion,
           a.nombre                       AS alojamiento,
           m.nombre                       AS municipio,
           COUNT(DISTINCT r.id_reserva)   AS reservas_temporada_alta,
           SUM(LEAST(r.fecha_checkout, te.fecha_fin)
               - GREATEST(r.fecha_checkin, te.fecha_inicio)) AS noches_temporada_alta,
           RANK() OVER (ORDER BY COUNT(DISTINCT r.id_reserva) DESC) AS posicion
    FROM RESERVA r
    JOIN RESERVA_HABITACION rh ON rh.id_reserva     = r.id_reserva
    JOIN TEMPORADA te          ON te.tipo           = 'ALTA'
                              AND r.fecha_checkin   < te.fecha_fin
                              AND r.fecha_checkout  > te.fecha_inicio
    JOIN HABITACION h          ON h.id_habitacion   = rh.id_habitacion
    JOIN ALOJAMIENTO a         ON a.id_alojamiento  = h.id_alojamiento
    JOIN MUNICIPIO m           ON m.id_municipio    = a.id_municipio
    WHERE r.estado <> 'CANCELADA'
    GROUP BY h.id_habitacion, h.numero, h.tipo, a.nombre, m.nombre
)
WHERE posicion = 1
ORDER BY habitacion;

-- Contexto: las 10 primeras (para mostrar qué tan reñido está el primer lugar)
SELECT posicion, habitacion, alojamiento, municipio, reservas_temporada_alta
FROM (
    SELECT h.numero                     AS habitacion,
           a.nombre                     AS alojamiento,
           m.nombre                     AS municipio,
           COUNT(DISTINCT r.id_reserva) AS reservas_temporada_alta,
           RANK() OVER (ORDER BY COUNT(DISTINCT r.id_reserva) DESC) AS posicion
    FROM RESERVA r
    JOIN RESERVA_HABITACION rh ON rh.id_reserva    = r.id_reserva
    JOIN TEMPORADA te          ON te.tipo          = 'ALTA'
                              AND r.fecha_checkin  < te.fecha_fin
                              AND r.fecha_checkout > te.fecha_inicio
    JOIN HABITACION h          ON h.id_habitacion  = rh.id_habitacion
    JOIN ALOJAMIENTO a         ON a.id_alojamiento = h.id_alojamiento
    JOIN MUNICIPIO m           ON m.id_municipio   = a.id_municipio
    WHERE r.estado <> 'CANCELADA'
    GROUP BY h.numero, a.nombre, m.nombre
)
WHERE posicion <= 10
ORDER BY posicion, habitacion;

-- Variante: la habitación con más reservas en la temporada alta de CADA año
-- (PARTITION BY reinicia el ranking en cada año)
SELECT anio, habitacion, alojamiento, municipio, reservas_temporada_alta
FROM (
    SELECT EXTRACT(YEAR FROM te.fecha_inicio) AS anio,
           h.numero                           AS habitacion,
           a.nombre                           AS alojamiento,
           m.nombre                           AS municipio,
           COUNT(DISTINCT r.id_reserva)       AS reservas_temporada_alta,
           RANK() OVER (PARTITION BY EXTRACT(YEAR FROM te.fecha_inicio)
                        ORDER BY COUNT(DISTINCT r.id_reserva) DESC) AS posicion
    FROM RESERVA r
    JOIN RESERVA_HABITACION rh ON rh.id_reserva    = r.id_reserva
    JOIN TEMPORADA te          ON te.tipo          = 'ALTA'
                              AND r.fecha_checkin  < te.fecha_fin
                              AND r.fecha_checkout > te.fecha_inicio
    JOIN HABITACION h          ON h.id_habitacion  = rh.id_habitacion
    JOIN ALOJAMIENTO a         ON a.id_alojamiento = h.id_alojamiento
    JOIN MUNICIPIO m           ON m.id_municipio   = a.id_municipio
    WHERE r.estado <> 'CANCELADA'
    GROUP BY EXTRACT(YEAR FROM te.fecha_inicio), h.numero, a.nombre, m.nombre
)
WHERE posicion = 1
ORDER BY anio, habitacion;


-- =====================================================================
-- CONSULTA 2A · Clientes que han reservado en más municipios distintos
-- =====================================================================
-- Paso a paso:
--   1. Recorre CLIENTE -> RESERVA -> RESERVA_HABITACION -> HABITACION
--      -> ALOJAMIENTO -> MUNICIPIO (el municipio sale del alojamiento).
--   2. Cuenta municipios DISTINTOS por cliente (no reservas).
--   3. LISTAGG(DISTINCT ...) arma la lista de municipios en un texto.
--   4. RANK() ordena por municipios y, en empate, por número de reservas.
-- ---------------------------------------------------------------------
SELECT posicion, documento, cliente, municipios_distintos, reservas, municipios
FROM (
    SELECT c.tipo_documento || ' ' || c.numero_documento AS documento,
           c.nombres || ' ' || c.apellidos               AS cliente,
           COUNT(DISTINCT m.id_municipio)                AS municipios_distintos,
           COUNT(DISTINCT r.id_reserva)                  AS reservas,
           LISTAGG(DISTINCT m.nombre, ', ')
               WITHIN GROUP (ORDER BY m.nombre)          AS municipios,
           RANK() OVER (ORDER BY COUNT(DISTINCT m.id_municipio) DESC,
                                 COUNT(DISTINCT r.id_reserva)   DESC) AS posicion
    FROM CLIENTE c
    JOIN RESERVA r             ON r.id_cliente      = c.id_cliente
    JOIN RESERVA_HABITACION rh ON rh.id_reserva     = r.id_reserva
    JOIN HABITACION h          ON h.id_habitacion   = rh.id_habitacion
    JOIN ALOJAMIENTO a         ON a.id_alojamiento  = h.id_alojamiento
    JOIN MUNICIPIO m           ON m.id_municipio    = a.id_municipio
    WHERE r.estado <> 'CANCELADA'
    GROUP BY c.id_cliente, c.tipo_documento, c.numero_documento, c.nombres, c.apellidos
)
WHERE posicion <= 20
ORDER BY posicion, cliente;


-- =====================================================================
-- CONSULTA 2B · El cliente con más reservas en cada municipio
-- =====================================================================
-- Misma ruta de uniones, pero agrupando por municipio y cliente.
-- PARTITION BY municipio reinicia el ranking en cada municipio, así que
-- sale el primero (o los empatados en primer lugar) de cada uno.
-- ---------------------------------------------------------------------
SELECT municipio, documento, cliente, reservas
FROM (
    SELECT m.nombre                                      AS municipio,
           c.tipo_documento || ' ' || c.numero_documento AS documento,
           c.nombres || ' ' || c.apellidos               AS cliente,
           COUNT(DISTINCT r.id_reserva)                  AS reservas,
           RANK() OVER (PARTITION BY m.id_municipio
                        ORDER BY COUNT(DISTINCT r.id_reserva) DESC) AS posicion
    FROM CLIENTE c
    JOIN RESERVA r             ON r.id_cliente      = c.id_cliente
    JOIN RESERVA_HABITACION rh ON rh.id_reserva     = r.id_reserva
    JOIN HABITACION h          ON h.id_habitacion   = rh.id_habitacion
    JOIN ALOJAMIENTO a         ON a.id_alojamiento  = h.id_alojamiento
    JOIN MUNICIPIO m           ON m.id_municipio    = a.id_municipio
    WHERE r.estado <> 'CANCELADA'
    GROUP BY m.id_municipio, m.nombre, c.id_cliente, c.tipo_documento,
             c.numero_documento, c.nombres, c.apellidos
)
WHERE posicion = 1
ORDER BY municipio, cliente;