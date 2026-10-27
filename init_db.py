"""
init_db.py
Crea (o verifica) la base de datos SQLite y la estructura de carpetas:

    data/
    ├── portfolio.db
    ├── RAW/<plataforma>/         PDFs pendientes de procesar
    └── processed/<plataforma>/   PDFs ya cargados

Es seguro re-ejecutarlo: no borra datos existentes.

Uso:
    python3 init_db.py
"""

import sqlite3
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
DB_PATH = DATA_DIR / "portfolio.db"
SCHEMA_PATH = BASE_DIR / "schema.sql"
RAW_DIR = DATA_DIR / "RAW"
PROCESSED_DIR = DATA_DIR / "processed"

EXPECTED_TABLES = {
    "plataformas",
    "instrumentos",
    "instrumentos_ticker_mapping",
    "posiciones_compra",
    "valor_historico_instrumento",
    "valor_actual_snapshot",
    "xray_cartera_snapshot",
    "xray_sector_snapshot",
    "xray_pais_snapshot",
    "xray_posiciones_snapshot",
    "xray_top_holdings_snapshot",
}

EXPECTED_VIEWS = {"v_posicion_neta", "v_huecos_precio"}


def crear_base_datos() -> sqlite3.Connection:
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    if not SCHEMA_PATH.exists():
        print(f"ERROR: no se encuentra {SCHEMA_PATH}")
        sys.exit(1)

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON;")
    conn.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
    conn.commit()
    return conn


def crear_carpetas(conn: sqlite3.Connection) -> bool:
    """Crea RAW/<plataforma> y processed/<plataforma> para cada plataforma de la BD."""
    plataformas = [r[0] for r in conn.execute("SELECT id FROM plataformas;")]
    for p in plataformas:
        (RAW_DIR / p).mkdir(parents=True, exist_ok=True)
        (PROCESSED_DIR / p).mkdir(parents=True, exist_ok=True)
    print(f"OK - carpetas creadas para {len(plataformas)} plataformas:")
    for p in plataformas:
        print(f"   - data/RAW/{p}  |  data/processed/{p}")
    return True


def comprobar_objetos(conn, tipo: str, esperados: set) -> bool:
    cur = conn.execute(
        "SELECT name FROM sqlite_master WHERE type=? AND name NOT LIKE 'sqlite_%';",
        (tipo,),
    )
    existentes = {r[0] for r in cur.fetchall()}
    faltantes = esperados - existentes
    if faltantes:
        print(f"FALTAN ({tipo}): {faltantes}")
        return False
    print(f"OK - {len(esperados)} {tipo}s correctos")
    return True


def comprobar_claves_foraneas(conn) -> bool:
    violaciones = conn.execute("PRAGMA foreign_key_check;").fetchall()
    if violaciones:
        print(f"VIOLACIONES DE CLAVE FORANEA: {violaciones}")
        return False
    print("OK - sin violaciones de claves foraneas")
    return True


def comprobar_integridad(conn) -> bool:
    res = conn.execute("PRAGMA integrity_check;").fetchone()[0]
    if res != "ok":
        print(f"PROBLEMA DE INTEGRIDAD: {res}")
        return False
    print("OK - integridad del fichero .db verificada")
    return True


def main():
    print(f"Base de datos: {DB_PATH}\n")
    conn = crear_base_datos()

    checks = [
        comprobar_objetos(conn, "table", EXPECTED_TABLES),
        comprobar_objetos(conn, "view", EXPECTED_VIEWS),
        comprobar_claves_foraneas(conn),
        comprobar_integridad(conn),
        crear_carpetas(conn),
    ]
    conn.close()

    print()
    if all(checks):
        print("Todo listo.")
    else:
        print("Revisa los errores anteriores.")
        sys.exit(1)


if __name__ == "__main__":
    main()
