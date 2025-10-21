/* ==========================================================
   BI DATAMART - NEW SCHEMA: bi_v2    (SQL Server)
   - Dimensions: DimDate, DimTicker, DimFeature
   - Facts: FactFeature (long), FactMarket (wide), FactBacktest, FactTrade
   - No ALTER on source tables required
   ========================================================== */

-- 0) Create schema (new)
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bi_v2')
    EXEC('CREATE SCHEMA bi_v2');
GO

----------------------------------------------------------------
-- 1) DIMENSIONS
----------------------------------------------------------------

-- 1.1 DimDate
CREATE OR ALTER VIEW bi_v2.DimDate AS
SELECT 
    date_id,
    [date],
    [year],
    [quarter],
    [month],
    is_weekend,
    is_month_end
FROM dbo.calendar;
GO

-- 1.2 DimTicker
CREATE OR ALTER VIEW bi_v2.DimTicker AS
SELECT 
    ticker_id,
    symbol,
    [name],
    sector,
    industry
FROM dbo.ticker;
GO

/* 1.3 DimFeature
   Map "tên feature gốc" -> code/alias chuẩn để pivot mà KHÔNG cần ALTER bảng gốc.
   Cần thêm feature mới: bổ sung 1 dòng vào VALUES bên dưới là xong.
*/
CREATE OR ALTER VIEW bi_v2.DimFeature AS
WITH FeatureMap AS (
    SELECT *
    FROM (VALUES
        (N'RETURN_LOG'        , N'return_log' , N'Return (log)',       N'Return',     N'v1', N''),
        (N'RETURN_CUM'        , N'return_cum' , N'Return (cum)',       N'Return',     N'v1', N''),
        (N'ROLL_VOL30_ANN'    , N'vol30_ann'  , N'Annualized Vol 30d', N'Volatility', N'v1', N'window=30'),
        (N'SMA20'             , N'sma_20'     , N'SMA',                 N'Trend',      N'v1', N'n=20'),
        (N'SMA50'             , N'sma_50'     , N'SMA',                 N'Trend',      N'v1', N'n=50'),
        (N'RSI14_Wilder'      , N'rsi_14'     , N'RSI (Wilder)',        N'Momentum',   N'v1', N'n=14'),
        (N'MACD_12_26'        , N'macd_12_26' , N'MACD',                N'Trend',      N'v1', N'(12,26)'),
        (N'SIGNAL_9'          , N'signal_9'   , N'MACD Signal',         N'Trend',      N'v1', N'n=9'),
        (N'HIST'              , N'macd_hist'  , N'MACD Histogram',      N'Trend',      N'v1', N''),
        (N'ATR14'             , N'atr_14'     , N'ATR',                  N'Volatility', N'v1', N'n=14'),
        (N'OBV_SCALED_1e6'    , N'obv_scaled' , N'OBV (scaled)',         N'Volume',     N'v1', N'scale=1e6'),
        (N'CMF20'             , N'cmf_20'     , N'Chaikin MF',          N'Volume',     N'v1', N'n=20')
    ) AS M(feature_name, feature_code, feature_name_std, feature_type_std, [version], parameter)
)
SELECT
    fd.feature_id,
    COALESCE(M.feature_code, LOWER(REPLACE(fd.feature_name, ' ', '_')))      AS feature_code,
    COALESCE(M.feature_name_std, fd.feature_name)                             AS feature_name,
    COALESCE(M.feature_type_std, fd.feature_type)                             AS feature_type,
    COALESCE(M.[version], fd.[version])                                       AS [version],
    COALESCE(M.parameter, fd.parameter)                                       AS parameter,
    -- column_alias dùng cho pivot ở FactMarket (tên cột gọn)
    COALESCE(
        NULLIF(
            CASE M.feature_code 
                WHEN N'return_log'  THEN N'return_log'
                WHEN N'return_cum'  THEN N'return_cum'
                WHEN N'vol30_ann'   THEN N'vol30_ann'
                WHEN N'sma_20'      THEN N'sma20'
                WHEN N'sma_50'      THEN N'sma50'
                WHEN N'rsi_14'      THEN N'rsi14'
                WHEN N'macd_12_26'  THEN N'macd'
                WHEN N'signal_9'    THEN N'macd_signal'
                WHEN N'macd_hist'   THEN N'macd_hist'
                WHEN N'atr_14'      THEN N'atr14'
                WHEN N'obv_scaled'  THEN N'obv_scaled'
                WHEN N'cmf_20'      THEN N'cmf20'
            END, N''
        ),
        REPLACE(REPLACE(LOWER(COALESCE(M.feature_code, fd.feature_name)), ' ', ''), '-', '_')
    ) AS column_alias
FROM dbo.feature_definition fd
LEFT JOIN FeatureMap M
  ON M.feature_name = fd.feature_name;
GO

----------------------------------------------------------------
-- 2) FACTS
----------------------------------------------------------------

-- 2.1 FactFeature (long, chuẩn hoá)
CREATE OR ALTER VIEW bi_v2.FactFeature AS
SELECT 
    fv.ticker_id,
    fv.date_id,
    fv.feature_id,
    fv.feature_value AS value
FROM dbo.feature_value fv;
GO

-- Tắt cảnh báo NULL eliminated (chỉ khi tạo view wide)
SET ANSI_WARNINGS OFF;
GO

-- 2.2 FactMarket (wide, pivot nhanh để vẽ)
CREATE OR ALTER VIEW bi_v2.FactMarket AS
WITH base AS (
    SELECT 
        p.ticker_id,
        p.date_id,
        p.[open],
        p.[high],
        p.[low],
        p.[close],
        p.volume
    FROM dbo.price_ohlcv p
),
feat AS (
    SELECT 
        fv.ticker_id,
        fv.date_id,
        MAX(CASE WHEN df.column_alias = N'return_log'   THEN fv.feature_value END) AS return_log,
        MAX(CASE WHEN df.column_alias = N'return_cum'   THEN fv.feature_value END) AS return_cum,
        MAX(CASE WHEN df.column_alias = N'vol30_ann'    THEN fv.feature_value END) AS vol30_ann,
        MAX(CASE WHEN df.column_alias = N'sma20'        THEN fv.feature_value END) AS sma20,
        MAX(CASE WHEN df.column_alias = N'sma50'        THEN fv.feature_value END) AS sma50,
        MAX(CASE WHEN df.column_alias = N'rsi14'        THEN fv.feature_value END) AS rsi14,
        MAX(CASE WHEN df.column_alias = N'macd'         THEN fv.feature_value END) AS macd,
        MAX(CASE WHEN df.column_alias = N'macd_signal'  THEN fv.feature_value END) AS macd_signal,
        MAX(CASE WHEN df.column_alias = N'macd_hist'    THEN fv.feature_value END) AS macd_hist,
        MAX(CASE WHEN df.column_alias = N'atr14'        THEN fv.feature_value END) AS atr14,
        MAX(CASE WHEN df.column_alias = N'obv_scaled'   THEN fv.feature_value END) AS obv_scaled,
        MAX(CASE WHEN df.column_alias = N'cmf20'        THEN fv.feature_value END) AS cmf20
    FROM dbo.feature_value fv
    JOIN bi_v2.DimFeature df ON df.feature_id = fv.feature_id
    GROUP BY fv.ticker_id, fv.date_id
)
SELECT 
    b.ticker_id,
    b.date_id,
    b.[open],
    b.[high],
    b.[low],
    b.[close],
    b.volume,
    f.return_log,
    f.return_cum,
    f.vol30_ann,
    f.sma20,
    f.sma50,
    f.rsi14,
    f.macd,
    f.macd_signal,
    f.macd_hist,
    f.atr14,
    f.obv_scaled,
    f.cmf20
FROM base b
LEFT JOIN feat f 
  ON f.ticker_id = b.ticker_id 
 AND f.date_id   = b.date_id;
GO

SET ANSI_WARNINGS ON;
GO

-- 2.3 FactBacktest (mỗi run)
CREATE OR ALTER VIEW bi_v2.FactBacktest AS
SELECT 
    br.run_id,
    s.strategy_id,
    s.strategy_code,
    s.[name]         AS strategy_name,
    br.method,
    br.start_date_id,
    br.end_date_id,
    pr.total_return,
    pr.equity_final,
    pr.equity_peak,
    pr.max_drawdown,
    pr.win_rate,
    pr.trades_count,
    pr.commission,
    bm.wall_time_ms,
    bm.peak_mem_mb,
    bm.notes
FROM dbo.backtest_run br
JOIN dbo.strategy s            ON s.strategy_id = br.strategy_id
LEFT JOIN dbo.portfolio_results pr ON pr.run_id = br.run_id
LEFT JOIN dbo.benchmark_results bm  ON bm.run_id = br.run_id;
GO

-- 2.4 FactTrade (mỗi lệnh) — dùng *_date_id (để DimDate xử lý)
CREATE OR ALTER VIEW bi_v2.FactTrade AS
SELECT 
    t.trade_id,
    t.run_id,
    t.ticker_id,
    t.enter_date_id,
    t.exit_date_id,
    t.enter_price,
    t.exit_price,
    t.qty,
    t.side,
    t.pnl_pct,
    t.created_at,
    s.strategy_code,
    s.[name] AS strategy_name,
    r.method,
    r.start_date_id,
    r.end_date_id
FROM dbo.trade t
JOIN dbo.backtest_run r ON r.run_id = t.run_id
JOIN dbo.strategy s     ON s.strategy_id = r.strategy_id;
GO

----------------------------------------------------------------
-- 3) PERFORMANCE INDEXES (an toàn: không đụng PK/clustered hiện có)
----------------------------------------------------------------

-- Nonclustered Columnstore cho feature_value (nếu chưa có)
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'NCCI_feature_value' AND object_id = OBJECT_ID('dbo.feature_value')
)
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_feature_value
ON dbo.feature_value (ticker_id, date_id, feature_id, feature_value);
GO

-- Rowstore supporting index (nếu chưa có)
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_feature_value_ticker_date_feature' AND object_id = OBJECT_ID('dbo.feature_value')
)
CREATE INDEX IX_feature_value_ticker_date_feature
ON dbo.feature_value(ticker_id, date_id, feature_id)
INCLUDE (feature_value);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_price_ohlcv_ticker_date' AND object_id = OBJECT_ID('dbo.price_ohlcv')
)
CREATE INDEX IX_price_ohlcv_ticker_date
ON dbo.price_ohlcv(ticker_id, date_id)
INCLUDE ([open],[high],[low],[close], volume);
GO

----------------------------------------------------------------
-- 4) QUICK CHECKS
----------------------------------------------------------------
SELECT 'DimDate' AS tbl, COUNT(*) AS cnt FROM bi_v2.DimDate
UNION ALL SELECT 'DimTicker', COUNT(*) FROM bi_v2.DimTicker
UNION ALL SELECT 'DimFeature', COUNT(*) FROM bi_v2.DimFeature
UNION ALL SELECT 'FactFeature', COUNT(*) FROM bi_v2.FactFeature
UNION ALL SELECT 'FactMarket', COUNT(*) FROM bi_v2.FactMarket
UNION ALL SELECT 'FactBacktest', COUNT(*) FROM bi_v2.FactBacktest
UNION ALL SELECT 'FactTrade', COUNT(*) FROM bi_v2.FactTrade;

-- sample xem nhanh
SELECT TOP 10 * FROM bi_v2.DimFeature ORDER BY feature_code;
SELECT TOP 10 * FROM bi_v2.FactMarket ORDER BY ticker_id, date_id;
SELECT TOP 10 * FROM bi_v2.FactFeature ORDER BY ticker_id, date_id, feature_id;
SELECT TOP 10 * FROM bi_v2.FactBacktest ORDER BY run_id;
SELECT TOP 10 * FROM bi_v2.FactTrade ORDER BY trade_id;
GO


CREATE OR ALTER VIEW bi_v2.FactMarket AS
WITH base AS (
    SELECT p.ticker_id, p.date_id, p.[open], p.[high], p.[low], p.[close], p.volume
    FROM dbo.price_ohlcv p
),
feat AS (
    SELECT 
        fv.ticker_id,
        fv.date_id,
        MAX(CASE WHEN df.feature_name = N'RETURN_LOG'     THEN fv.feature_value END) AS return_log,
        MAX(CASE WHEN df.feature_name = N'RETURN_CUM'     THEN fv.feature_value END) AS return_cum,
        MAX(CASE WHEN df.feature_name = N'ROLL_VOL30_ANN' THEN fv.feature_value END) AS vol30_ann,
        MAX(CASE WHEN df.feature_name = N'SMA20'          THEN fv.feature_value END) AS sma20,
        MAX(CASE WHEN df.feature_name = N'SMA50'          THEN fv.feature_value END) AS sma50,
        MAX(CASE WHEN df.feature_name = N'RSI14_Wilder'   THEN fv.feature_value END) AS rsi14,

        -- MACD block (đổi sang match theo feature_name)
        MAX(CASE WHEN df.feature_name = N'MACD_12_26'     THEN fv.feature_value END) AS macd,
        MAX(CASE WHEN df.feature_name = N'SIGNAL_9'       THEN fv.feature_value END) AS macd_signal,
        MAX(CASE WHEN df.feature_name = N'HIST'           THEN fv.feature_value END) AS macd_hist,

        MAX(CASE WHEN df.feature_name = N'ATR14'          THEN fv.feature_value END) AS atr14,
        MAX(CASE WHEN df.feature_name = N'OBV_SCALED_1e6' THEN fv.feature_value END) AS obv_scaled,
        MAX(CASE WHEN df.feature_name = N'CMF20'          THEN fv.feature_value END) AS cmf20
    FROM dbo.feature_value fv
    JOIN dbo.feature_definition df ON df.feature_id = fv.feature_id
    GROUP BY fv.ticker_id, fv.date_id
)
SELECT b.ticker_id, b.date_id, b.[open], b.[high], b.[low], b.[close], b.volume,
       f.return_log, f.return_cum, f.vol30_ann, f.sma20, f.sma50, f.rsi14,
       f.macd, f.macd_signal, f.macd_hist, f.atr14, f.obv_scaled, f.cmf20
FROM base b
LEFT JOIN feat f ON f.ticker_id = b.ticker_id AND f.date_id = b.date_id;
GO
 select * from ticker
 select * from feature_definition

 select * from feature_value where ticker_id = 19 and feature_id = 10
SELECT TOP 20 *
FROM bi_v2.FactMarket
WHERE macd IS NOT NULL
ORDER BY date_id DESC;
