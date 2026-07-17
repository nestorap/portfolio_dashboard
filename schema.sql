-- =========================================================
-- portfolio-xray :: schema.sql
-- Base de datos SQLite para tracking de inversiones en fondos
-- =========================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------
-- 1. FONDOS (catálogo maestro)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS fondos (
    isin                    TEXT PRIMARY KEY,
    nombre                  TEXT NOT NULL,
    categoria_morningstar   TEXT,
    gastos_corrientes       REAL,
    plataforma              TEXT DEFAULT 'MyInvestor',   -- para multi-plataforma futuro
    activo                  BOOLEAN DEFAULT 1,
    fecha_alta              DATE DEFAULT (date('now'))
);

-- ---------------------------------------------------------
-- 2. MAPEO DE TICKERS (para automatizar precios vía yfinance)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS fondos_ticker_mapping (
    isin                    TEXT PRIMARY KEY REFERENCES fondos(isin),
    yahoo_ticker            TEXT,
    disponible_yahoo        BOOLEAN DEFAULT 0,
    ultima_verificacion     DATE
);

-- ---------------------------------------------------------
-- 3. POSICIONES DE COMPRA (manual, retroactivo permitido)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS posiciones_compra (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    isin                        TEXT NOT NULL REFERENCES fondos(isin),
    fecha_compra                DATE NOT NULL,          -- fecha real de la operación
    importe_invertido           REAL NOT NULL,           -- € aportados (positivo=compra, negativo=venta)
    participaciones             REAL NOT NULL,
    valor_liquidativo_compra    REAL NOT NULL,           -- importe / participaciones
    tipo_operacion               TEXT NOT NULL DEFAULT 'compra'
                                 CHECK (tipo_operacion IN ('compra','venta','traspaso_entrada','traspaso_salida')),
    plataforma                  TEXT DEFAULT 'MyInvestor',
    notas                       TEXT,
    fecha_registro               TIMESTAMP DEFAULT CURRENT_TIMESTAMP  -- cuándo TÚ lo metiste (auditoría)
);

CREATE INDEX IF NOT EXISTS idx_compras_isin_fecha
    ON posiciones_compra(isin, fecha_compra);

-- ---------------------------------------------------------
-- 4. VALOR HISTÓRICO DEL FONDO (precio por fecha, con fuente)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS valor_historico_fondo (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    isin                TEXT NOT NULL REFERENCES fondos(isin),
    fecha               DATE NOT NULL,
    valor_liquidativo   REAL NOT NULL,
    fuente              TEXT NOT NULL DEFAULT 'manual'
                         CHECK (fuente IN ('yahoo_finance','manual','morningstar_pdf','myinvestor')),
    fecha_registro      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(isin, fecha)   -- evita duplicados: un único precio por fondo y día
);

CREATE INDEX IF NOT EXISTS idx_valor_hist_isin_fecha
    ON valor_historico_fondo(isin, fecha);

-- ---------------------------------------------------------
-- 5. SNAPSHOT DE VALOR ACTUAL (foto periódica de tu cartera)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS valor_actual_snapshot (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    fecha_snapshot               DATE NOT NULL,
    isin                        TEXT NOT NULL REFERENCES fondos(isin),
    valor_liquidativo_actual     REAL NOT NULL,
    participaciones_totales      REAL NOT NULL,
    valor_actual                REAL NOT NULL,           -- valor_liquidativo * participaciones
    ganancia_pct                REAL,
    ganancia_eur                REAL,
    fuente                      TEXT DEFAULT 'manual',
    UNIQUE(isin, fecha_snapshot)
);

-- ---------------------------------------------------------
-- 6. X-RAY CARTERA - CABECERA (una fila por PDF descargado)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS xray_cartera_snapshot (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    fecha_informe           DATE NOT NULL UNIQUE,   -- fecha del PDF, ej. 2026-07-17
    pct_acciones            REAL,
    pct_obligaciones        REAL,
    pct_efectivo            REAL,
    pct_otro                REAL,
    pct_no_clasificado      REAL,
    volatilidad_3a          REAL,
    volatilidad_5a          REAL,
    media_aritmetica_3a     REAL,
    media_aritmetica_5a     REAL,
    sharpe_3a               REAL,
    sharpe_5a               REAL,
    beta_3a                 REAL,
    alfa_3a                 REAL,
    r_cuadrado_3a           REAL,
    tracking_error_3a       REAL,
    rent_3_meses            REAL,
    rent_6_meses            REAL,
    rent_1_ano              REAL,
    rent_3_anos_anualizada  REAL,
    rent_5_anos_anualizada  REAL,
    pdf_origen              TEXT,     -- nombre de archivo, para trazabilidad
    fecha_registro          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------
-- 7. X-RAY SECTORES (dimensión: ~11-12 filas por fecha)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS xray_sector_snapshot (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    xray_snapshot_id    INTEGER NOT NULL REFERENCES xray_cartera_snapshot(id) ON DELETE CASCADE,
    sector              TEXT NOT NULL,     -- 'Tecnología', 'Salud', etc.
    supersector         TEXT,              -- 'Cíclico' | 'Sensible al ciclo' | 'Defensivo'
    pct_cartera         REAL,
    pct_benchmark       REAL,
    UNIQUE(xray_snapshot_id, sector)
);

-- ---------------------------------------------------------
-- 8. X-RAY PAÍSES (dimensión: ~10 filas por fecha, ampliable)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS xray_pais_snapshot (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    xray_snapshot_id    INTEGER NOT NULL REFERENCES xray_cartera_snapshot(id) ON DELETE CASCADE,
    pais                TEXT NOT NULL,
    region               TEXT,             -- 'Europa', 'América', 'Asia', etc. (opcional)
    pct_cartera         REAL,
    pct_benchmark       REAL,
    UNIQUE(xray_snapshot_id, pais)
);

-- ---------------------------------------------------------
-- 9. X-RAY POSICIONES DE FONDO (los fondos dentro del X-Ray)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS xray_posiciones_fondo_snapshot (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    xray_snapshot_id            INTEGER NOT NULL REFERENCES xray_cartera_snapshot(id) ON DELETE CASCADE,
    isin                        TEXT REFERENCES fondos(isin),
    nombre                      TEXT NOT NULL,
    peso_pct                    REAL,
    rating_morningstar          INTEGER CHECK (rating_morningstar BETWEEN 1 AND 5),
    rent_1a                     REAL,
    rent_3a_anualizada          REAL,
    rent_5a_anualizada          REAL,
    gastos_corrientes           REAL,
    fecha_cartera_subyacente    DATE,
    UNIQUE(xray_snapshot_id, nombre)
);

-- ---------------------------------------------------------
-- 10. X-RAY TOP HOLDINGS (top 10 acciones subyacentes)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS xray_top_holdings_snapshot (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    xray_snapshot_id    INTEGER NOT NULL REFERENCES xray_cartera_snapshot(id) ON DELETE CASCADE,
    ranking             INTEGER NOT NULL CHECK (ranking BETWEEN 1 AND 10),
    nombre_empresa      TEXT NOT NULL,
    pct_cartera         REAL,
    sector              TEXT,
    pais                TEXT,
    UNIQUE(xray_snapshot_id, ranking)
);

-- =========================================================
-- VISTAS DE UTILIDAD (opcional, pero facilitan el dashboard)
-- =========================================================

-- Resumen de posición neta por fondo (participaciones y coste medio)
CREATE VIEW IF NOT EXISTS v_posicion_neta_fondo AS
SELECT
    isin,
    SUM(CASE WHEN tipo_operacion IN ('compra','traspaso_entrada') THEN participaciones
             WHEN tipo_operacion IN ('venta','traspaso_salida') THEN -participaciones
             ELSE 0 END) AS participaciones_netas,
    SUM(CASE WHEN tipo_operacion IN ('compra','traspaso_entrada') THEN importe_invertido
             WHEN tipo_operacion IN ('venta','traspaso_salida') THEN -importe_invertido
             ELSE 0 END) AS importe_neto_invertido
FROM posiciones_compra
GROUP BY isin;

-- Huecos de precio: compras sin valor histórico en esa fecha exacta
CREATE VIEW IF NOT EXISTS v_huecos_precio AS
SELECT DISTINCT pc.isin, pc.fecha_compra
FROM posiciones_compra pc
LEFT JOIN valor_historico_fondo vh
    ON vh.isin = pc.isin AND vh.fecha = pc.fecha_compra
WHERE vh.id IS NULL;
