SET DEFINE OFF

-- Reserva con todos sus totales en una sola fila
CREATE OR REPLACE VIEW VW_RESERVA_DETALLE AS
SELECT r.id_reserva,
       r.fecha_reserva,
       r.fecha_checkin,
       r.fecha_checkout,
       r.fecha_checkout - r.fecha_checkin                        AS noches,
       r.estado,
       c.id_cliente,
       c.tipo_documento,
       c.numero_documento,
       c.nombres || ' ' || c.apellidos                          AS cliente,
       c.correo                                                 AS correo_cliente,
       hab.id_alojamiento,
       a.nombre                                                 AS alojamiento,
       m.nombre                                                 AS municipio,
       hab.habitaciones,
       hab.num_habitaciones,
       hab.huespedes,
       NVL(hab.valor_estadia, 0)                                AS valor_estadia,
       NVL(srv.total, 0)                                        AS valor_servicios,
       NVL(hab.valor_estadia, 0) + NVL(srv.total, 0)            AS valor_total,
       NVL(pag.total, 0)                                        AS total_pagado,
       NVL(hab.valor_estadia, 0) + NVL(srv.total, 0)
           - NVL(pag.total, 0)                                  AS saldo,
       r.id_usuario_registro
FROM RESERVA r
JOIN CLIENTE c ON c.id_cliente = r.id_cliente
LEFT JOIN (
    SELECT rh.id_reserva,
           MIN(h.id_alojamiento)                                AS id_alojamiento,
           LISTAGG(h.numero, ',' ON OVERFLOW TRUNCATE)
               WITHIN GROUP (ORDER BY h.numero)                 AS habitaciones,
           COUNT(*)                                             AS num_habitaciones,
           SUM(rh.cantidad_huespedes)                           AS huespedes,
           SUM(rh.valor_estadia)                                AS valor_estadia
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
) pag ON pag.id_reserva = r.id_reserva;

-- Catálogo de habitaciones con la tarifa vigente HOY
CREATE OR REPLACE VIEW VW_HABITACION_CATALOGO AS
SELECT h.id_habitacion,
       h.numero,
       h.tipo        AS tipo_habitacion,
       h.capacidad,
       h.estado,
       a.id_alojamiento,
       a.nombre      AS alojamiento,
       a.direccion,
       a.telefono,
       m.id_municipio,
       m.nombre      AS municipio,
       t.nombre      AS tipo_alojamiento,
       tv.temporada  AS temporada_actual,
       tv.valor_noche AS tarifa_hoy
FROM HABITACION h
JOIN ALOJAMIENTO a      ON a.id_alojamiento = h.id_alojamiento
JOIN MUNICIPIO m        ON m.id_municipio = a.id_municipio
JOIN TIPO_ALOJAMIENTO t ON t.id_tipo_alojamiento = a.id_tipo_alojamiento
LEFT JOIN (
    SELECT ta.id_habitacion, te.nombre AS temporada, ta.valor_noche
    FROM TARIFA ta
    JOIN TEMPORADA te ON te.id_temporada = ta.id_temporada
    WHERE TRUNC(SYSDATE) >= te.fecha_inicio
      AND TRUNC(SYSDATE) <  te.fecha_fin
) tv ON tv.id_habitacion = h.id_habitacion;

-- Liquidación mensual con nombres
CREATE OR REPLACE VIEW VW_LIQUIDACION_MENSUAL AS
SELECT l.anio,
       l.mes,
       m.nombre AS municipio,
       a.id_alojamiento,
       a.nombre AS alojamiento,
       l.num_reservas,
       l.noches_vendidas,
       l.ingreso_hospedaje,
       l.ingreso_servicios,
       l.total_bruto,
       l.porcentaje_comision,
       l.valor_comision,
       l.valor_neto,
       l.estadias_sin_tarifa,
       l.fecha_generacion,
       l.usuario_generacion
FROM LIQUIDACION_MENSUAL l
JOIN ALOJAMIENTO a ON a.id_alojamiento = l.id_alojamiento
JOIN MUNICIPIO m   ON m.id_municipio = a.id_municipio;

-- Auditoría de tarifas (encabezado + detalle)
CREATE OR REPLACE VIEW VW_AUDITORIA_TARIFA AS
SELECT au.id_auditoria,
       au.fecha_cambio,
       au.operacion          AS operacion_sentencia,
       au.filas_afectadas,
       au.usuario_bd,
       au.usuario_app,
       au.usuario_so,
       au.equipo,
       au.direccion_ip,
       au.programa,
       d.operacion           AS operacion_fila,
       d.id_tarifa,
       d.id_habitacion,
       h.numero              AS habitacion,
       d.id_temporada,
       te.nombre             AS temporada,
       d.valor_anterior,
       d.valor_nuevo,
       d.valor_nuevo - d.valor_anterior AS diferencia
FROM AUDITORIA_TARIFA au
JOIN AUDITORIA_TARIFA_DETALLE d ON d.id_auditoria = au.id_auditoria
LEFT JOIN HABITACION h ON h.id_habitacion = d.id_habitacion
LEFT JOIN TEMPORADA te ON te.id_temporada = d.id_temporada;

SELECT view_name FROM user_views ORDER BY view_name;