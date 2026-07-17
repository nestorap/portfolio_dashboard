"""
init_db.py
Crea (o verifica) la base de datos SQLite del dashboard a partir de schema.sql.
Incluye comprobaciones básicas de integridad tras la creación.

Uso:
    python init_db.py
"""

import sqlite3
import sys
from pathlib import Path

# --- Configuración de rutas ---------------------------------------------
BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "data" / "portfolio.db"
SCHEMA_PATH = BASE_DIR / "schema.sql"

EXPECTED_TABLES = {
    "fondos",
    "fondos_ticker_mapping",
    "posiciones_compra",
    "valor_historico_fondo",
    "valor_actual_snapshot",
    "xray_cartera_snapshot",
    "xray_sector_snapshot",
    "xray_pais_snapshot",
    "xray_posiciones_fondo_snapshot",
    "xray_top_holdings_snapshot",
}

EXPECTED_VIEWS = {
    "v_posicion_neta_fondo",
    "v_huecos_precio",
}


def crear_base_datos() -> sqlite3.Connection:
    """Crea la carpeta data/ si no existe y ejecuta schema.sql contra la BD."""
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)

    if not SCHEMA_PATH.exists():
        print(f"ERROR: no se encuentra {SCHEMA_PATH}")
        sys.exit(1)

    schema_sql = SCHEMA_PATH.read_text(encoding="utf-8")

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON;")
    conn.executescript(schema_sql)
    conn.commit()
    return conn


def comprobar_tablas(conn: sqlite3.Connection) -> bool:
    """Verifica que todas las tablas esperadas existen."""
    cur = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"
    )
    tablas_existentes = {row[0] for row in cur.fetchall()}
    faltantes = EXPECTED_TABLES - tablas_existentes

    if faltantes:
        print(f"FALTAN TABLAS: {faltantes}")
        return False

    print(f"OK — {len(EXPECTED_TABLES)} tablas creadas correctamente:")
    for t in sorted(tablas_existentes):
        print(f"   - {t}")
    return True


def comprobar_vistas(conn: sqlite3.Connection) -> bool:
    """Verifica que las vistas esperadas existen."""
    cur = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='view';"
    )
    vistas_existentes = {row[0] for row in cur.fetchall()}
    faltantes = EXPECTED_VIEWS - vistas_existentes

    if faltantes:
        print(f"FALTAN VISTAS: {faltantes}")
        return False

    print(f"OK — {len(EXPECTED_VIEWS)} vistas creadas correctamente:")
    for v in sorted(vistas_existentes):
        print(f"   - {v}")
    return True


def comprobar_claves_foraneas(conn: sqlite3.Connection) -> bool:
    """PRAGMA foreign_key_check: detecta violaciones de integridad referencial."""
    cur = conn.execute("PRAGMA foreign_key_check;")
    violaciones = cur.fetchall()
    if violaciones:
        print(f"VIOLACIONES DE CLAVE FORÁNEA: {violaciones}")
        return False
    print("OK — sin violaciones de claves foráneas")
    return True


def comprobar_integridad(conn: sqlite3.Connection) -> bool:
    """PRAGMA integrity_check: verifica que el fichero .db no está corrupto."""
    cur = conn.execute("PRAGMA integrity_check;")
    resultado = cur.fetchone()[0]
    if resultado != "ok":
        print(f"PROBLEMA DE INTEGRIDAD: {resultado}")
        return False
    print("OK — integridad del fichero .db verificada")
    return True


def main():
    print(f"Base de datos: {DB_PATH}\n")

    conn = crear_base_datos()

    checks = [
        comprobar_tablas(conn),
        comprobar_vistas(conn),
        comprobar_claves_foraneas(conn),
        comprobar_integridad(conn),
    ]

    conn.close()

    print()
    if all(checks):
        print("Base de datos lista para usar.")
    else:
        print("Revisa los errores anteriores antes de continuar.")
        sys.exit(1)


if __name__ == "__main__":
    main()
