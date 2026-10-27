-- =========================================================
-- portfolio-xray :: schema.sql  (v2: multi-plataforma)
-- =========================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------
-- 0. PLATAFORMAS (lista maestra; el nombre coincide con la
--    subcarpeta de data/RAW/ y data/processed/)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS plataformas (
    id          TEXT PRIMARY KEY,        -- 'myinvestor', 'interactive_brokers'...
    nombre      TEXT NOT NULL,
    activa      BOOLEAN DEFAULT 1
);

INSERT OR IGNORE INTO plataformas (id, nombre) VALUES
    ('myinvestor',          'MyInvestor'),
    ('interactive_brokers', 'Interactive Brokers');

-- ---------------------------------------------------------
-- 1. INSTRUMENTOS (fondos, ETFs, acciones...) - catálogo maestro
--    Un ISIN es independiente de la plataforma donde lo tengas.
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS instrumentos (
    isin                    TEXT PRIMARY KEY,
    nombre                  TEXT NOT NULL,
    tipo                    TEXT NOT NULL DEFAULT 'fondo'
                             CHECK (tipo IN ('fondo','etf','accion','otro')),
    categoria_morningstar   TEXT,
    gastos_corrientes       REAL,
    activo                  BOOLEAN DEFAULT 1,
    fecha_alta              DATE DEFAULT (date('now'))
);

-- ---------------------------------------------------------
-- 2. MAPEO DE TICKERS (para precios vía yfinance)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS instrumentos_ticker_mapping (
    isin                    TEXT PRIMARY KEY REFERENCES instrumentos(isin),
    yahoo_ticker            TEXT,
    disponible_yahoo        BOOLEAN DEFAULT 0,
    ultima_verificacion     DATE
);

-- ---------------------------------------------------------
-- 3. OPERACIONES (manual, retroactivo permitido)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS posiciones_compra (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    plataforma                  TEXT NOT NULL REFERENCES plataformas(id),
    isin                        TEXT NOT NULL REFERENCES instrumentos(isin),
    fecha_compra                DATE NOT NULL,
    importe_invertido           REAL NOT NULL,
    participaciones             REAL NOT NULL,
    valor_liquidativo_compra    REAL NOT NULL,
    tipo_operacion              TEXT NOT NULL DEFAULT 'compra'
                                 CHECK (tipo_operacion IN ('compra','venta','traspaso_entrada','traspaso_salida')),
    notas                       TEXT,
    fecha_registro              TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_compras_plat_isin_fecha
    ON posiciones_compra(plataforma, isin, fecha_compra);

-- ---------------------------------------------------------
-- 4. VALOR HISTÓRICO (precio por fecha; no depende de plataforma)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS valor_historico_instrumento (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    isin                TEXT NOT NULL REFERENCES instrumentos(isin),
    fecha               DATE NOT NULL,
    valor_liquidativo   REAL NOT NULL,
    fuente              TEXT NOT NULL DEFAULT 'manual'
                         CHECK (fuente IN ('yahoo_finance','manual','morningstar_pdf','broker')),
    fecha_registro      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(isin, fecha)
);

CREATE INDEX IF NOT EXISTS idx_valor_hist_isin_fecha
    ON valor_historico_instrumento(isin, fecha);

-- ---------------------------------------------------------
-- 5. SNAPSHOT DE VALOR ACTUAL (foto periódica por plataforma)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS valor_actual_snapshot (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    fecha_snapshot              DATE NOT NULL,
    plataforma                  TEXT NOT NULL REFERENCES plataformas(id),
    isin                        TEXT NOT NULL REFERENCES instrumentos(isin),
    valor_liquidativo_actual    REAL NOT NULL,
    participaciones_totales     REAL NOT NULL,
    valor_actual                REAL NOT NULL,
    ganancia_pct                REAL,
    ganancia_eur                REAL,
    fuente                      TEXT DEFAULT 'manual',
    UNIQUE(plataforma, isin, fecha_snapshot)
);

-- ---------------------------------------------------------
-- 6. X-RAY CABECERA (una fila por PDF)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS xray_cartera_snapshot (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    fecha_informe           DATE NOT NULL,
    plataforma              TEXT NOT NULL REFERENCES plataformas(id),
    tipo_inversion          TEXT NOT NULL
                             CHECK (tipo_inversion IN ('fondos','cartera_standard','etf')),
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
    pdf_origen              TEXT,
    fecha_registro          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(fecha_informe, plataforma, tipo_inversion)
);

-- ---------------------------------------------------------
-- 7. X-RAY SECTORES
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS xray_sector_snapshot (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    xray_snapshot_id    INTEGER NOT NULL REFERENCES xray_cartera_snapshot(id) ON DELETE CASCADE,
    sector              TEXT NOT NULL,
    supersector         TEXT,
    pct_cartera         REAL,
    pct_benchmark       REAL,
    UNIQUE(xray_snapshot_id, sector)
);

-- ---------------------------------------------------------
-- 8. X-RAY PAÍSES
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS xray_pais_snapshot (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    xray_snapshot_id    INTEGER NOT NULL REFERENCES xray_cartera_snapshot(id) ON DELETE CASCADE,
    pais                TEXT NOT NULL,
    region              TEXT,
    pct_cartera         REAL,
    pct_benchmark       REAL,
    UNIQUE(xray_snapshot_id, pais)
);

-- ---------------------------------------------------------
-- 9. X-RAY POSICIONES (instrumentos dentro del X-Ray)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS xray_posiciones_snapshot (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    xray_snapshot_id            INTEGER NOT NULL REFERENCES xray_cartera_snapshot(id) ON DELETE CASCADE,
    isin                        TEXT REFERENCES instrumentos(isin),
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
-- 10. X-RAY TOP HOLDINGS
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
-- VISTAS
-- =========================================================

-- Posición neta por plataforma e instrumento
CREATE VIEW IF NOT EXISTS v_posicion_neta AS
SELECT
    plataforma,
    isin,
    SUM(CASE WHEN tipo_operacion IN ('compra','traspaso_entrada') THEN participaciones
             WHEN tipo_operacion IN ('venta','traspaso_salida') THEN -participaciones
             ELSE 0 END) AS participaciones_netas,
    SUM(CASE WHEN tipo_operacion IN ('compra','traspaso_entrada') THEN importe_invertido
             WHEN tipo_operacion IN ('venta','traspaso_salida') THEN -importe_invertido
             ELSE 0 END) AS importe_neto_invertido
FROM posiciones_compra
GROUP BY plataforma, isin;

-- Compras sin precio histórico en esa fecha
CREATE VIEW IF NOT EXISTS v_huecos_precio AS
SELECT DISTINCT pc.isin, pc.fecha_compra
FROM posiciones_compra pc
LEFT JOIN valor_historico_instrumento vh
    ON vh.isin = pc.isin AND vh.fecha = pc.fecha_compra
WHERE vh.id IS NULL;
