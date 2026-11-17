## Contenido del repositorio

```
BDOracle/         Scripts SQL numerados en orden de ejecución
TurismoUQ_app/    Interfaz web (Flask + python-oracledb)
docs/             Diagrama entidad-relación

## Orden de ejecución de los scripts

Ejecutar en SQL Developer, en este orden, cada archivo completo con **F5** (salvo los 14a y 14b).

00_sys_tablespace_usuario.sql` | SYSTEM | 1 | Tablespace `TS_HISTORICO_RESERVAS`, usuario `TURISMOUQ` y privilegios |
01_crear_tablas.sql` | TURISMOUQ | 1 | Las 14 tablas con PK, FK, CHECK, NOT NULL y UNIQUE |
02_cargar_datos.sql` | TURISMOUQ | 1 | Carga con PL/SQL y `DBMS_RANDOM` (25.000 reservas, 40.000 líneas de servicio) |
03_consultas1.sql` | TURISMOUQ | 1 | Consultas de práctica (GROUP BY, HAVING, CUBE, GROUPING SETS) |
04_consultasE1.sql` | TURISMOUQ | 1 | Las 8 consultas de análisis y la vista materializada |
05_tablespace_historico.sql` | TURISMOUQ | 1 | Tabla `HISTORICO_RESERVA` en su propio tablespace |
06_ajuste_modelo_E2.sql` | TURISMOUQ | 2 | Calendario completo de temporadas, tablas de auditoría y liquidación, usuarios de prueba |
07_pkg_turismouq.sql` | TURISMOUQ | 2 y 3 | Paquete `PKG_TURISMOUQ` (incluye el bloqueo `SELECT ... FOR UPDATE`) |
08_disparadores.sql` | TURISMOUQ | 2 | Auditoría de `TARIFA` y control de solapes |
09_carga_post_E2.sql` | TURISMOUQ | 2 | Valor de las estadías cargadas, histórico, liquidación 2024–2026 |
10_vista_interfaz.sql` | TURISMOUQ | 2 | Vistas de apoyo |
11_pruebasE2.sql` | TURISMOUQ | 2 | Pruebas de la entrega 2 (cada bloque imprime OK o FALLO) |
12_indices_interfaz.sql` | TURISMOUQ | 2 | Índices para la búsqueda de disponibilidad |
13_transacciones_E3.sql` | TURISMOUQ | 3 | Reserva y pago atómicos con SAVEPOINT, rollback parcial y total |
14c_concurrencia_monitor_SYSTEM.sql` | SYSTEM | 3 | Ver qué sesión bloquea a cuál |
15_indices_E3.sql` | TURISMOUQ | 3 | 3 consultas lentas, planes y tiempos antes/después, índice que no ayuda |
16_consultas_sustentacion.sql` | TURISMOUQ | Sustentación | Habitación con más reservas en temporada alta; clientes con más municipios |
recargoControladores.sql` | TURISMOUQ | Utilidad | Recompila el esquema si se vuelve a correr el 07 sobre una base existente |
TurismoUQ comprobaciones.sql` | TURISMOUQ | Utilidad | Cuenta las filas de las 14 tablas |

Notas:

- **14a y 14b** necesitan dos sesiones reales. En SQL Developer, la segunda se abre con `Ctrl + Shift + N` (hoja no compartida). Se ejecuta bloque por bloque en el orden A1, B1, A2, B2...
- **13, 15 y 16** se pueden repetir: el 13 cancela sus reservas de prueba y el 15 borra y vuelve a crear sus índices.
- Contraseña del usuario `TURISMOUQ` (script 00): Turismo123

## Interfaz web

cd TurismoUQ_app
python -m venv venv
venv\Scripts\activate   
pip install -r requirements.txt
python app.py
Usuarios de prueba (clave Turismo2026*): recepcion1, admin_aloj1, gerente1, auditor1

## Integrantes

- Valentina Gutierrez Camacho
- Karol Melissa Dávila Solorzano
- Lawrence Daniel Ospina Lopez