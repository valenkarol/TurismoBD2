import hashlib
import os
import time
import uuid
from datetime import date, datetime, timedelta
from functools import wraps

import oracledb
from flask import Flask, flash, redirect, render_template, request, session, url_for

import db

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "clave-de-desarrollo")

PKG = "PKG_TURISMOUQ"
PKG_TX = "PKG_TURISMOUQ_TX"   # Entrega 3: reserva + pago en una sola transacción
METODOS_PAGO = ["EFECTIVO", "TARJETA", "TRANSFERENCIA", "PSE"]
ESTADOS_RESERVA = ["PENDIENTE", "CONFIRMADA", "CANCELADA", "FINALIZADA"]
TIPOS_DOCUMENTO = ["CC", "CE", "PASAPORTE"]
ESTADOS_PAGO = ["APROBADO", "PENDIENTE", "RECHAZADO"]

# Entrega 3 · Demostración de concurrencia desde la interfaz.
# Con DEMO_CONCURRENCIA_SEG=10 en el archivo .env, al confirmar una reserva la
# transacción se queda abierta 10 segundos ANTES del COMMIT (la habitación sigue
# bloqueada por SELECT ... FOR UPDATE). Así dos navegadores pueden intentar
# reservar la misma habitación "al mismo tiempo". En 0 (o sin la variable) la
# app funciona normal.
PAUSA_DEMO_SEG = min(int(os.getenv("DEMO_CONCURRENCIA_SEG", "0") or 0), 15)

# Qué rol puede entrar a cada sección
ROLES_OPERACION = ("RECEPCION", "ADMINISTRADOR", "GERENTE")
ROLES_CONSULTA = ("RECEPCION", "ADMINISTRADOR", "GERENTE", "AUDITOR")
ROLES_LIQUIDACION = ("ADMINISTRADOR", "GERENTE", "AUDITOR")
ROLES_AUDITORIA = ("GERENTE", "AUDITOR")


# ---------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------
@app.template_filter("dinero")
def filtro_dinero(valor):
    if valor is None:
        return "—"
    return "$ " + f"{float(valor):,.0f}".replace(",", ".")


@app.template_filter("fecha")
def filtro_fecha(valor):
    if not valor:
        return "—"
    return valor.strftime("%d/%m/%Y")


@app.template_filter("fecha_hora")
def filtro_fecha_hora(valor):
    if not valor:
        return "—"
    return valor.strftime("%d/%m/%Y %H:%M")


@app.context_processor
def variables_globales():
    return {"usuario": session.get("usuario"), "ROLES_OPERACION": ROLES_OPERACION,
            "ROLES_LIQUIDACION": ROLES_LIQUIDACION, "ROLES_AUDITORIA": ROLES_AUDITORIA,
            "PAUSA_DEMO_SEG": PAUSA_DEMO_SEG}


def a_fecha(texto):
    """'2026-10-25' -> date(2026, 10, 25). Devuelve None si viene vacío."""
    return date.fromisoformat(texto) if texto else None


def a_entero(texto):
    try:
        return int(texto) if texto not in (None, "") else None
    except ValueError:
        return None


def login_requerido(*roles):
    """Decorador: exige sesión iniciada y (opcional) uno de los roles dados."""
    def decorador(vista):
        @wraps(vista)
        def envoltura(*args, **kwargs):
            usuario = session.get("usuario")
            if not usuario:
                return redirect(url_for("login"))
            if roles and usuario["rol"] not in roles:
                flash("Tu rol no tiene acceso a esa sección.", "error")
                return redirect(url_for("inicio"))
            return vista(*args, **kwargs)
        return envoltura
    return decorador


@app.errorhandler(oracledb.DatabaseError)
def error_de_oracle(e):
    """Cualquier error de Oracle no manejado se muestra como mensaje, no como pantalla rota."""
    flash(db.mensaje_error(e), "error")
    return render_template("base.html"), 500


# ---------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------
@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        nombre = request.form.get("usuario", "").strip()
        clave = request.form.get("clave", "")
        try:
            u = db.consultar_uno(
                """SELECT id_usuario, nombre_usuario, nombre_completo, rol,
                          activo, clave_hash, id_alojamiento
                   FROM USUARIO_SISTEMA
                   WHERE nombre_usuario = :nombre""",
                {"nombre": nombre},
            )
        except oracledb.DatabaseError as e:
            flash("No se pudo conectar a Oracle: " + db.mensaje_error(e), "error")
            return render_template("login.html")

        # El script 06 guarda la clave como SHA-256 en hexadecimal (mayúsculas)
        clave_hash = hashlib.sha256(clave.encode("utf-8")).hexdigest().upper()
        if not u or (u["clave_hash"] or "").upper() != clave_hash:
            flash("Usuario o clave incorrectos.", "error")
        elif u["activo"] != "S":
            flash("El usuario está inactivo.", "error")
        else:
            session["usuario"] = {
                "id": u["id_usuario"],
                "login": u["nombre_usuario"],
                "nombre": u["nombre_completo"],
                "rol": u["rol"],
                "id_alojamiento": u["id_alojamiento"],
            }
            with db.conexion() as con:
                with con.cursor() as cur:
                    cur.execute("UPDATE USUARIO_SISTEMA SET ultimo_acceso = SYSDATE "
                                "WHERE id_usuario = :id", {"id": u["id_usuario"]})
                con.commit()
            return redirect(url_for("inicio"))
    return render_template("login.html")


@app.route("/salir")
def salir():
    session.clear()
    return redirect(url_for("login"))


# ---------------------------------------------------------------------
# Inicio (resumen)
# ---------------------------------------------------------------------
@app.route("/")
@login_requerido()
def inicio():
    totales = db.consultar_uno(
        """SELECT (SELECT COUNT(*) FROM CLIENTE)     AS clientes,
                  (SELECT COUNT(*) FROM ALOJAMIENTO) AS alojamientos,
                  (SELECT COUNT(*) FROM HABITACION)  AS habitaciones,
                  (SELECT COUNT(*) FROM RESERVA)     AS reservas
           FROM dual"""
    )
    por_estado = db.consultar(
        "SELECT estado, COUNT(*) AS cantidad FROM RESERVA GROUP BY estado ORDER BY estado"
    )
    llegadas = db.consultar(
        """SELECT r.id_reserva, r.fecha_checkin, r.fecha_checkout, r.estado,
                  c.nombres || ' ' || c.apellidos AS cliente
           FROM RESERVA r
           JOIN CLIENTE c ON c.id_cliente = r.id_cliente
           WHERE r.estado IN ('PENDIENTE', 'CONFIRMADA')
             AND r.fecha_checkin >= TRUNC(SYSDATE)
             AND r.fecha_checkin <  TRUNC(SYSDATE) + 7
           ORDER BY r.fecha_checkin
           FETCH FIRST 10 ROWS ONLY"""
    )
    return render_template("inicio.html", totales=totales,
                           por_estado=por_estado, llegadas=llegadas)


# ---------------------------------------------------------------------
# Buscar habitaciones disponibles  ->  PKG_TURISMOUQ.sp_buscar_disponibles
# ---------------------------------------------------------------------
@app.route("/buscar")
@login_requerido(*ROLES_OPERACION)
def buscar():
    municipios = db.consultar("SELECT id_municipio, nombre FROM MUNICIPIO ORDER BY nombre")
    tipos = db.consultar(
        "SELECT id_tipo_alojamiento, nombre FROM TIPO_ALOJAMIENTO ORDER BY nombre")

    hoy = date.today()
    filtros = {
        "fecha_in": request.args.get("fecha_in") or (hoy + timedelta(days=1)).isoformat(),
        "fecha_out": request.args.get("fecha_out") or (hoy + timedelta(days=3)).isoformat(),
        "huespedes": request.args.get("huespedes") or "2",
        "id_municipio": request.args.get("id_municipio", ""),
        "id_tipo": request.args.get("id_tipo", ""),
    }
    resultados = None

    if "buscar" in request.args:
        try:
            resultados = db.llamar_con_cursor(
                f"{PKG}.sp_buscar_disponibles",
                p_fecha_in=a_fecha(filtros["fecha_in"]),
                p_fecha_out=a_fecha(filtros["fecha_out"]),
                p_huespedes=a_entero(filtros["huespedes"]),
                p_id_municipio=a_entero(filtros["id_municipio"]),
                p_id_tipo_alojamiento=a_entero(filtros["id_tipo"]),
            )[:100]
        except (oracledb.DatabaseError, ValueError) as e:
            msg = db.mensaje_error(e) if isinstance(e, oracledb.DatabaseError) else "Fechas no válidas."
            flash(msg, "error")

    return render_template("buscar.html", municipios=municipios, tipos=tipos,
                           filtros=filtros, resultados=resultados)


# ---------------------------------------------------------------------
# Crear reserva (una sola transacción)
#   Sin pago inicial -> sp_registrar_cliente + sp_crear_reserva
#   Con pago inicial -> sp_registrar_cliente + PKG_TURISMOUQ_TX.sp_reservar_con_pago
#                       (Entrega 3: reserva y pago atómicos, con SAVEPOINT)
# ---------------------------------------------------------------------
@app.route("/reservar", methods=["GET", "POST"])
@login_requerido(*ROLES_OPERACION)
def reservar():
    datos = request.values
    id_habitacion = a_entero(datos.get("id_habitacion"))
    huespedes = a_entero(datos.get("huespedes"))
    try:
        fecha_in, fecha_out = a_fecha(datos.get("fecha_in")), a_fecha(datos.get("fecha_out"))
    except ValueError:
        fecha_in = fecha_out = None
    if not (id_habitacion and huespedes and fecha_in and fecha_out):
        flash("Primero busca una habitación disponible.", "error")
        return redirect(url_for("buscar"))

    habitacion = db.consultar_uno(
        """SELECT h.id_habitacion, h.numero, h.tipo, h.capacidad,
                  a.nombre AS alojamiento, m.nombre AS municipio
           FROM HABITACION h
           JOIN ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
           JOIN MUNICIPIO m   ON m.id_municipio = a.id_municipio
           WHERE h.id_habitacion = :id""",
        {"id": id_habitacion},
    )

    if request.method == "POST":
        f = request.form
        # Pago inicial (opcional). Si viene, reserva y pago van en la misma transacción.
        texto_pago = f.get("valor_pago", "").replace(".", "").replace(",", "").strip()
        valor_pago = float(texto_pago) if texto_pago.isdigit() and int(texto_pago) > 0 else None
        aviso = None
        try:
            with db.conexion() as con:
                with con.cursor() as cur:
                    id_cliente = cur.var(oracledb.DB_TYPE_NUMBER)
                    cur.callproc(f"{PKG}.sp_registrar_cliente", [
                        f.get("tipo_documento"), f.get("numero_documento"),
                        f.get("nombres"), f.get("apellidos"),
                        f.get("telefono"), f.get("correo"), id_cliente, "N",
                    ])
                    id_reserva = cur.var(oracledb.DB_TYPE_NUMBER)
                    if valor_pago:
                        # Entrega 3 · Transacciones. Parámetros en el orden del paquete:
                        # cliente, habitación, fechas, huéspedes, valor y método del pago,
                        # (salidas) reserva, pago, aviso, servicio, cantidad, usuario, commit
                        id_pago = cur.var(oracledb.DB_TYPE_NUMBER)
                        aviso_bd = cur.var(oracledb.DB_TYPE_VARCHAR, 600)
                        cur.callproc(f"{PKG_TX}.sp_reservar_con_pago", [
                            int(id_cliente.getvalue()), id_habitacion, fecha_in, fecha_out,
                            huespedes, valor_pago, f.get("metodo_pago"),
                            id_reserva, id_pago, aviso_bd,
                            a_entero(f.get("id_servicio")),
                            # 0 se envía tal cual: Oracle lo rechaza y se ve el ROLLBACK PARCIAL
                            1 if a_entero(f.get("cantidad_servicio")) is None
                            else a_entero(f.get("cantidad_servicio")),
                            session["usuario"]["id"], "N",
                        ])
                        aviso = aviso_bd.getvalue()
                    else:
                        valor = cur.var(oracledb.DB_TYPE_NUMBER)
                        cur.callproc(f"{PKG}.sp_crear_reserva", [
                            int(id_cliente.getvalue()), id_habitacion, fecha_in, fecha_out,
                            huespedes, id_reserva, valor, session["usuario"]["id"], "N",
                        ])
                # Demostración de concurrencia: la habitación sigue bloqueada mientras dura la pausa
                if PAUSA_DEMO_SEG:
                    time.sleep(PAUSA_DEMO_SEG)
                # Único COMMIT: cliente + reserva (+ pago) quedan juntos o no queda nada.
                # Si hubo error no se llega aquí y Oracle descarta todo al devolver la conexión.
                con.commit()
            nueva = int(id_reserva.getvalue())
            if valor_pago:
                flash(f"Reserva #{nueva} creada y pago de {filtro_dinero(valor_pago)} "
                      "registrado en una sola transacción.", "ok")
                if aviso:
                    flash(aviso, "error")   # rollback parcial: el servicio no se agregó
            else:
                flash(f"Reserva #{nueva} creada por {filtro_dinero(valor.getvalue())}. "
                      "Registra un pago del 30 % para confirmarla.", "ok")
            return redirect(url_for("reserva_detalle", id_reserva=nueva))
        except oracledb.DatabaseError as e:
            flash(db.mensaje_error(e), "error")

    # Desglose por temporada  ->  sp_detalle_estadia
    desglose, total = [], 0
    try:
        desglose = db.llamar_con_cursor(
            f"{PKG}.sp_detalle_estadia",
            p_id_habitacion=id_habitacion, p_fecha_in=fecha_in, p_fecha_out=fecha_out,
        )
        total = sum(float(d["subtotal"] or 0) for d in desglose)
    except oracledb.DatabaseError as e:
        flash(db.mensaje_error(e), "error")

    catalogo = db.consultar("SELECT id_servicio, nombre, precio FROM SERVICIO ORDER BY nombre")
    return render_template("reservar.html", habitacion=habitacion, fecha_in=fecha_in,
                           fecha_out=fecha_out, huespedes=huespedes, desglose=desglose,
                           total=total, tipos_documento=TIPOS_DOCUMENTO, form=request.form,
                           metodos=METODOS_PAGO, catalogo=catalogo)


# ---------------------------------------------------------------------
# Listado de reservas
# ---------------------------------------------------------------------
@app.route("/reservas")
@login_requerido(*ROLES_CONSULTA)
def reservas():
    filtros = {
        "id_reserva": request.args.get("id_reserva", "").strip(),
        "documento": request.args.get("documento", "").strip(),
        "estado": request.args.get("estado", ""),
    }
    filas = db.consultar(
        """SELECT r.id_reserva, r.fecha_reserva, r.fecha_checkin, r.fecha_checkout,
                  r.estado, c.nombres || ' ' || c.apellidos AS cliente,
                  c.tipo_documento, c.numero_documento
           FROM RESERVA r
           JOIN CLIENTE c ON c.id_cliente = r.id_cliente
           WHERE (:id_reserva IS NULL OR r.id_reserva = :id_reserva)
             AND (:documento  IS NULL OR c.numero_documento = :documento)
             AND (:estado     IS NULL OR r.estado = :estado)
           ORDER BY r.id_reserva DESC
           FETCH FIRST 50 ROWS ONLY""",
        {"id_reserva": a_entero(filtros["id_reserva"]),
         "documento": filtros["documento"] or None,
         "estado": filtros["estado"] or None},
    )
    return render_template("reservas.html", reservas=filas, filtros=filtros,
                           estados=ESTADOS_RESERVA)


# ---------------------------------------------------------------------
# Detalle de una reserva + pagos, servicios y cancelación
# ---------------------------------------------------------------------
@app.route("/reservas/<int:id_reserva>")
@login_requerido(*ROLES_CONSULTA)
def reserva_detalle(id_reserva):
    reserva = db.consultar_uno(
        f"""SELECT r.*, c.tipo_documento, c.numero_documento,
                   c.nombres || ' ' || c.apellidos AS cliente, c.telefono, c.correo,
                   {PKG}.fn_total_reserva(r.id_reserva) AS total,
                   (SELECT NVL(SUM(p.valor), 0) FROM PAGO p
                     WHERE p.id_reserva = r.id_reserva AND p.estado = 'APROBADO') AS pagado
            FROM RESERVA r
            JOIN CLIENTE c ON c.id_cliente = r.id_cliente
            WHERE r.id_reserva = :id""",
        {"id": id_reserva},
    )
    if not reserva:
        flash(f"La reserva {id_reserva} no existe.", "error")
        return redirect(url_for("reservas"))

    reserva["saldo"] = float(reserva["total"] or 0) - float(reserva["pagado"] or 0)
    p = {"id": id_reserva}
    habitaciones = db.consultar(
        """SELECT h.numero, h.tipo, a.nombre AS alojamiento, m.nombre AS municipio,
                  rh.cantidad_huespedes, rh.valor_estadia
           FROM RESERVA_HABITACION rh
           JOIN HABITACION h  ON h.id_habitacion = rh.id_habitacion
           JOIN ALOJAMIENTO a ON a.id_alojamiento = h.id_alojamiento
           JOIN MUNICIPIO m   ON m.id_municipio = a.id_municipio
           WHERE rh.id_reserva = :id""", p)
    servicios = db.consultar(
        """SELECT s.nombre, rs.cantidad, rs.precio_unitario,
                  rs.cantidad * rs.precio_unitario AS subtotal
           FROM RESERVA_SERVICIO rs
           JOIN SERVICIO s ON s.id_servicio = rs.id_servicio
           WHERE rs.id_reserva = :id ORDER BY s.nombre""", p)
    pagos = db.consultar(
        """SELECT id_pago, fecha_pago, valor, metodo_pago, estado
           FROM PAGO WHERE id_reserva = :id ORDER BY fecha_pago""", p)
    catalogo = db.consultar("SELECT id_servicio, nombre, precio FROM SERVICIO ORDER BY nombre")

    return render_template("reserva_detalle.html", r=reserva, habitaciones=habitaciones,
                           servicios=servicios, pagos=pagos, catalogo=catalogo,
                           metodos=METODOS_PAGO)


def _ejecutar_en_reserva(id_reserva, procedimiento, parametros, mensaje_ok,
                         salida_numero=False):
    """Llama un procedimiento del paquete y vuelve al detalle de la reserva.
    salida_numero=True agrega al final un parámetro OUT numérico (p. ej. p_id_pago)."""
    try:
        with db.conexion() as con:
            with con.cursor() as cur:
                if salida_numero:
                    parametros = parametros + [cur.var(oracledb.DB_TYPE_NUMBER)]
                cur.callproc(f"{PKG}.{procedimiento}", parametros)
        flash(mensaje_ok, "ok")
    except oracledb.DatabaseError as e:
        flash(db.mensaje_error(e), "error")
    return redirect(url_for("reserva_detalle", id_reserva=id_reserva))


@app.route("/reservas/<int:id_reserva>/pago", methods=["POST"])
@login_requerido(*ROLES_OPERACION)
def registrar_pago(id_reserva):
    texto = request.form.get("valor", "0").replace(".", "").replace(",", "").strip()
    valor = float(texto) if texto.isdigit() else 0
    return _ejecutar_en_reserva(
        id_reserva, "sp_registrar_pago",
        [id_reserva, valor, request.form.get("metodo")],
        "Pago registrado.", salida_numero=True)


@app.route("/reservas/<int:id_reserva>/servicio", methods=["POST"])
@login_requerido(*ROLES_OPERACION)
def agregar_servicio(id_reserva):
    return _ejecutar_en_reserva(
        id_reserva, "sp_agregar_servicio",
        [id_reserva, a_entero(request.form.get("id_servicio")),
         a_entero(request.form.get("cantidad"))],
        "Servicio agregado.")


@app.route("/reservas/<int:id_reserva>/cancelar", methods=["POST"])
@login_requerido(*ROLES_OPERACION)
def cancelar_reserva(id_reserva):
    return _ejecutar_en_reserva(id_reserva, "sp_cancelar_reserva", [id_reserva],
                                "Reserva cancelada.")


# ---------------------------------------------------------------------
# Clientes
# ---------------------------------------------------------------------
@app.route("/clientes")
@login_requerido(*ROLES_CONSULTA)
def clientes():
    texto = request.args.get("q", "").strip()
    filas = db.consultar(
        """SELECT c.id_cliente, c.tipo_documento, c.numero_documento, c.nombres,
                  c.apellidos, c.telefono, c.correo,
                  (SELECT COUNT(*) FROM RESERVA r WHERE r.id_cliente = c.id_cliente) AS reservas
           FROM CLIENTE c
           WHERE :q IS NULL
              OR c.numero_documento = :q
              OR UPPER(c.nombres || ' ' || c.apellidos) LIKE '%' || UPPER(:q) || '%'
           ORDER BY c.apellidos, c.nombres
           FETCH FIRST 50 ROWS ONLY""",
        {"q": texto or None},
    )
    return render_template("clientes.html", clientes=filas, q=texto)


# ---------------------------------------------------------------------
# Liquidación mensual  ->  sp_liquidar_mes  /  tabla LIQUIDACION_MENSUAL
# ---------------------------------------------------------------------
@app.route("/liquidacion", methods=["GET", "POST"])
@login_requerido(*ROLES_LIQUIDACION)
def liquidacion():
    usuario = session["usuario"]
    hoy = date.today()
    anio = a_entero(request.values.get("anio")) or hoy.year
    mes = a_entero(request.values.get("mes")) or hoy.month
    comision = request.values.get("comision") or "10"

    if request.method == "POST":
        if usuario["rol"] != "GERENTE":
            flash("Solo el gerente puede ejecutar la liquidación.", "error")
        else:
            try:
                with db.conexion() as con:
                    with con.cursor() as cur:
                        cur.callproc(f"{PKG}.sp_liquidar_mes", [anio, mes, float(comision)])
                flash(f"Liquidación de {mes:02d}/{anio} generada.", "ok")
            except (oracledb.DatabaseError, ValueError) as e:
                flash(db.mensaje_error(e) if isinstance(e, oracledb.DatabaseError)
                      else "Comisión no válida.", "error")

    # El administrador solo ve su propio alojamiento
    solo_aloj = usuario["id_alojamiento"] if usuario["rol"] == "ADMINISTRADOR" else None
    filas = db.consultar(
        """SELECT a.nombre AS alojamiento, l.num_reservas, l.noches_vendidas,
                  l.ingreso_hospedaje, l.ingreso_servicios, l.total_bruto,
                  l.porcentaje_comision, l.valor_comision, l.valor_neto,
                  l.estadias_sin_tarifa, l.fecha_generacion
           FROM LIQUIDACION_MENSUAL l
           JOIN ALOJAMIENTO a ON a.id_alojamiento = l.id_alojamiento
           WHERE l.anio = :anio AND l.mes = :mes
             AND (:aloj IS NULL OR l.id_alojamiento = :aloj)
           ORDER BY l.valor_neto DESC""",
        {"anio": anio, "mes": mes, "aloj": solo_aloj},
    )
    totales = {k: sum(float(f[k] or 0) for f in filas)
               for k in ("total_bruto", "valor_comision", "valor_neto")}
    return render_template("liquidacion.html", filas=filas, totales=totales,
                           anio=anio, mes=mes, comision=comision)


# ---------------------------------------------------------------------
# Auditoría de tarifas (lo que registran los disparadores del script 08)
# ---------------------------------------------------------------------
@app.route("/auditoria")
@login_requerido(*ROLES_AUDITORIA)
def auditoria():
    filas = db.consultar(
        """SELECT a.id_auditoria, a.fecha_cambio, a.operacion, a.usuario_bd,
                  a.usuario_so, a.equipo, a.programa,
                  d.id_tarifa, d.id_habitacion, d.id_temporada,
                  d.valor_anterior, d.valor_nuevo
           FROM AUDITORIA_TARIFA a
           JOIN AUDITORIA_TARIFA_DETALLE d ON d.id_auditoria = a.id_auditoria
           ORDER BY a.fecha_cambio DESC, d.id_detalle
           FETCH FIRST 100 ROWS ONLY"""
    )
    return render_template("auditoria.html", filas=filas)


# ---------------------------------------------------------------------
# Entrega 3 · Intentos fallidos de reserva con pago
# (bitácora que llena la transacción autónoma del script 13)
# ---------------------------------------------------------------------
@app.route("/intentos")
@login_requerido(*ROLES_AUDITORIA)
def intentos():
    filas = db.consultar(
        """SELECT l.id_intento, l.fecha_intento, l.usuario_bd,
                  u.nombre_usuario AS usuario_app,
                  l.id_cliente, l.id_habitacion, l.fecha_checkin, l.fecha_checkout,
                  l.valor_pago, l.metodo_pago, l.codigo_error, l.mensaje_error
           FROM LOG_INTENTO_FALLIDO l
           LEFT JOIN USUARIO_SISTEMA u ON u.id_usuario = l.id_usuario_app
           ORDER BY l.id_intento DESC
           FETCH FIRST 100 ROWS ONLY"""
    )
    return render_template("intentos.html", filas=filas)


# ---------------------------------------------------------------------
# Entrega 3 · Índices + consultas de la sustentación
#   C1, C2, C3 = las tres consultas lentas del script 15 (mismo texto, con
#   variables de enlace). Se muestra el resultado, cuánto tardó Oracle y el
#   plan de ejecución, donde se ve qué índice usó.
#   Q1, Q2A, Q2B = las consultas de la profesora (script 16).
# ---------------------------------------------------------------------
SQL_C1 = """SELECT id_pago, id_reserva, fecha_pago, valor
FROM PAGO
WHERE metodo_pago = :metodo
  AND estado = :estado
  AND fecha_pago >= :desde
  AND fecha_pago <  :hasta
ORDER BY fecha_pago"""

SQL_C2 = """SELECT id_cliente, tipo_documento, numero_documento, nombres, apellidos, telefono, correo
FROM CLIENTE
WHERE UPPER(apellidos) = UPPER(:apellido)"""

SQL_C3 = """SELECT COUNT(*) AS lineas,
       SUM(cantidad) AS unidades,
       SUM(cantidad * precio_unitario) AS ingreso
FROM RESERVA_SERVICIO
WHERE id_servicio = :id_servicio"""

SQL_Q1 = """SELECT posicion, habitacion, tipo_habitacion, alojamiento, municipio,
       reservas_temporada_alta, noches_temporada_alta
FROM (
    SELECT h.numero                     AS habitacion,
           h.tipo                       AS tipo_habitacion,
           a.nombre                     AS alojamiento,
           m.nombre                     AS municipio,
           COUNT(DISTINCT r.id_reserva) AS reservas_temporada_alta,
           SUM(LEAST(r.fecha_checkout, te.fecha_fin)
               - GREATEST(r.fecha_checkin, te.fecha_inicio)) AS noches_temporada_alta,
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
      AND (:anio IS NULL OR EXTRACT(YEAR FROM te.fecha_inicio) = :anio)
    GROUP BY h.id_habitacion, h.numero, h.tipo, a.nombre, m.nombre
)
WHERE posicion <= 10
ORDER BY posicion, habitacion"""

SQL_Q2A = """SELECT posicion, documento, cliente, municipios_distintos, reservas, municipios
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
    JOIN RESERVA r             ON r.id_cliente     = c.id_cliente
    JOIN RESERVA_HABITACION rh ON rh.id_reserva    = r.id_reserva
    JOIN HABITACION h          ON h.id_habitacion  = rh.id_habitacion
    JOIN ALOJAMIENTO a         ON a.id_alojamiento = h.id_alojamiento
    JOIN MUNICIPIO m           ON m.id_municipio   = a.id_municipio
    WHERE r.estado <> 'CANCELADA'
    GROUP BY c.id_cliente, c.tipo_documento, c.numero_documento, c.nombres, c.apellidos
)
WHERE posicion <= 20
ORDER BY posicion, cliente"""

SQL_Q2B = """SELECT municipio, documento, cliente, reservas
FROM (
    SELECT m.nombre                                      AS municipio,
           c.tipo_documento || ' ' || c.numero_documento AS documento,
           c.nombres || ' ' || c.apellidos               AS cliente,
           COUNT(DISTINCT r.id_reserva)                  AS reservas,
           RANK() OVER (PARTITION BY m.id_municipio
                        ORDER BY COUNT(DISTINCT r.id_reserva) DESC) AS posicion
    FROM CLIENTE c
    JOIN RESERVA r             ON r.id_cliente     = c.id_cliente
    JOIN RESERVA_HABITACION rh ON rh.id_reserva    = r.id_reserva
    JOIN HABITACION h          ON h.id_habitacion  = rh.id_habitacion
    JOIN ALOJAMIENTO a         ON a.id_alojamiento = h.id_alojamiento
    JOIN MUNICIPIO m           ON m.id_municipio   = a.id_municipio
    WHERE r.estado <> 'CANCELADA'
    GROUP BY m.id_municipio, m.nombre, c.id_cliente, c.tipo_documento,
             c.numero_documento, c.nombres, c.apellidos
)
WHERE posicion = 1
ORDER BY municipio, cliente"""


def _literal_texto(valor):
    """Texto -> literal SQL seguro ('O''Brien'). Solo se usa para EXPLAIN PLAN."""
    return "'" + str(valor).replace("'", "''")[:100] + "'"


def _literal_fecha(valor):
    return "DATE '" + valor.isoformat() + "'"


def plan_ejecucion(sql_con_literales):
    """Plan de ejecución de una consulta (EXPLAIN PLAN + DBMS_XPLAN.DISPLAY).
    EXPLAIN PLAN no ejecuta la consulta: solo pide a Oracle el plan que usaría.
    Los valores van como literales ya validados porque EXPLAIN PLAN no recibe
    variables de enlace con valor."""
    id_plan = "WEB_" + uuid.uuid4().hex[:12].upper()
    try:
        with db.conexion() as con:
            with con.cursor() as cur:
                cur.execute(f"EXPLAIN PLAN SET STATEMENT_ID = '{id_plan}' FOR {sql_con_literales}")
                cur.execute("SELECT plan_table_output "
                            "FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', :id, 'TYPICAL'))",
                            {"id": id_plan})
                lineas = [fila[0] for fila in cur.fetchall()]
                cur.execute("DELETE FROM plan_table WHERE statement_id = :id", {"id": id_plan})
            con.commit()
        return "\n".join(lineas)
    except oracledb.DatabaseError as e:
        return "No se pudo obtener el plan: " + db.mensaje_error(e)


def _medir(sql, params):
    """Ejecuta la consulta y devuelve (filas, milisegundos)."""
    inicio = time.perf_counter()
    filas = db.consultar(sql, params)
    return filas, round((time.perf_counter() - inicio) * 1000, 1)


@app.route("/consultas")
@login_requerido(*ROLES_CONSULTA)
def consultas():
    ver = request.args.get("ver", "")
    servicios = db.consultar("SELECT id_servicio, nombre FROM SERVICIO ORDER BY id_servicio")
    p = {   # valores del formulario (con los del script 15 por defecto)
        "metodo": request.args.get("metodo") or "PSE",
        "estado": request.args.get("estado") or "APROBADO",
        "desde": request.args.get("desde") or "2026-03-20",
        "hasta": request.args.get("hasta") or "2026-03-23",
        "apellido": (request.args.get("apellido") or "Apellido1500").strip(),
        "id_servicio": a_entero(request.args.get("id_servicio")) or 7,
        "anio": a_entero(request.args.get("anio")),
    }
    r = {"ver": ver}   # resultado de la consulta pedida

    try:
        if ver == "c1":
            if p["metodo"] not in METODOS_PAGO or p["estado"] not in ESTADOS_PAGO:
                raise ValueError("Método o estado no válido.")
            desde = a_fecha(p["desde"])
            hasta = a_fecha(p["hasta"]) + timedelta(days=1)   # "hasta" incluye ese día
            r["filas"], r["ms"] = _medir(SQL_C1, {"metodo": p["metodo"], "estado": p["estado"],
                                                  "desde": desde, "hasta": hasta})
            r["plan"] = plan_ejecucion(
                SQL_C1.replace(":metodo", _literal_texto(p["metodo"]))
                      .replace(":estado", _literal_texto(p["estado"]))
                      .replace(":desde", _literal_fecha(desde))
                      .replace(":hasta", _literal_fecha(hasta)))
        elif ver == "c2":
            if not p["apellido"]:
                raise ValueError("Escribe un apellido.")
            r["filas"], r["ms"] = _medir(SQL_C2, {"apellido": p["apellido"]})
            r["plan"] = plan_ejecucion(SQL_C2.replace(":apellido", _literal_texto(p["apellido"])))
        elif ver == "c3":
            r["filas"], r["ms"] = _medir(SQL_C3, {"id_servicio": p["id_servicio"]})
            r["plan"] = plan_ejecucion(SQL_C3.replace(":id_servicio", str(int(p["id_servicio"]))))
        elif ver == "q1":
            r["filas"], r["ms"] = _medir(SQL_Q1, {"anio": p["anio"]})
        elif ver == "q2a":
            r["filas"], r["ms"] = _medir(SQL_Q2A, {})
        elif ver == "q2b":
            r["filas"], r["ms"] = _medir(SQL_Q2B, {})
    except ValueError as e:
        flash(str(e) if str(e) else "Datos no válidos.", "error")
        r = {"ver": ""}
    except oracledb.DatabaseError as e:
        flash(db.mensaje_error(e), "error")
        r = {"ver": ""}

    # Medición antes/después que dejó el script 15 (si ya se ejecutó)
    try:
        medicion = db.consultar(
            """SELECT c.codigo, c.descripcion, c.repeticiones,
                      a.costo AS costo_antes, d.costo AS costo_despues,
                      a.tiempo_ms AS ms_antes, d.tiempo_ms AS ms_despues,
                      a.acceso AS acceso_antes, d.acceso AS acceso_despues
               FROM E3_CONSULTA c
               JOIN E3_MEDICION a ON a.codigo = c.codigo AND a.momento = 'ANTES'
               JOIN E3_MEDICION d ON d.codigo = c.codigo AND d.momento = 'DESPUES'
               ORDER BY c.codigo""")
    except oracledb.DatabaseError:
        medicion = None   # el script 15 todavía no se ha ejecutado

    return render_template("consultas.html", p=p, r=r, servicios=servicios,
                           medicion=medicion, metodos=METODOS_PAGO, estados_pago=ESTADOS_PAGO,
                           sql={"c1": SQL_C1, "c2": SQL_C2, "c3": SQL_C3,
                                "q1": SQL_Q1, "q2a": SQL_Q2A, "q2b": SQL_Q2B})


# ---------------------------------------------------------------------
if __name__ == "__main__":
    # threaded=True: atiende varias peticiones a la vez (necesario para la
    # demostración de concurrencia con dos navegadores)
    app.run(debug=True, threaded=True)
