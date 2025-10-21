create DATABASE Thao
/* ==========================================
   Calendar
   ========================================== */
CREATE TABLE dbo.calendar (
    date_id      INT PRIMARY KEY,       -- yyyymmdd
    [date]       DATE NOT NULL,
    [year]       INT NOT NULL,
    [quarter]    TINYINT NOT NULL CHECK ([quarter] BETWEEN 1 AND 4),
    [month]      TINYINT NOT NULL CHECK ([month] BETWEEN 1 AND 12),
    is_weekend   BIT NOT NULL,
    is_month_end BIT NOT NULL
);

/* ==========================================
   Tickers
   ========================================== */
CREATE TABLE dbo.ticker (
    ticker_id  INT IDENTITY(1,1) PRIMARY KEY,
    symbol     NVARCHAR(32) NOT NULL UNIQUE,
    [name]     NVARCHAR(256),
    sector     NVARCHAR(128),
    industry   NVARCHAR(128),
    created_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    updated_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME()
);

/* ==========================================
   Prices
   ========================================== */
CREATE TABLE dbo.price_ohlcv (
    ticker_id INT NOT NULL,
    date_id   INT NOT NULL,
    [open]    DECIMAL(18,6),
    [high]    DECIMAL(18,6),
    [low]     DECIMAL(18,6),
    [close]   DECIMAL(18,6),
    volume    BIGINT,
    CONSTRAINT pk_price_ohlcv PRIMARY KEY (ticker_id, date_id),
    CONSTRAINT fk_price_ticker FOREIGN KEY (ticker_id) REFERENCES dbo.ticker(ticker_id),
    CONSTRAINT fk_price_calendar FOREIGN KEY (date_id) REFERENCES dbo.calendar(date_id)
);

/* ==========================================
   Features
   ========================================== */
CREATE TABLE dbo.feature_definition (
    feature_id   INT IDENTITY(1,1) PRIMARY KEY,
    feature_name NVARCHAR(128) NOT NULL,
    [parameter]  NVARCHAR(MAX),
    [version]    NVARCHAR(32) NOT NULL DEFAULT N'1.0',
    formula_text NVARCHAR(MAX),
    feature_type NVARCHAR(64),
    created_at   DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT uq_feature_name_ver UNIQUE (feature_name, [version])
);

CREATE TABLE dbo.feature_value (
    ticker_id     INT NOT NULL,
    date_id       INT NOT NULL,
    feature_id    INT NOT NULL,
    feature_value DECIMAL(18,8),
    computed_at   DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_feature_value PRIMARY KEY (ticker_id, date_id, feature_id),
    CONSTRAINT fk_fv_ticker FOREIGN KEY (ticker_id) REFERENCES dbo.ticker(ticker_id),
    CONSTRAINT fk_fv_calendar FOREIGN KEY (date_id) REFERENCES dbo.calendar(date_id),
    CONSTRAINT fk_fv_feature FOREIGN KEY (feature_id) REFERENCES dbo.feature_definition(feature_id),
    CONSTRAINT chk_feature_value_range CHECK (feature_value IS NULL OR (feature_value > -1e12 AND feature_value < 1e12))
);

/* ==========================================
   Strategy & runs
   ========================================== */
CREATE TABLE dbo.strategy (
    strategy_id   INT IDENTITY(1,1) PRIMARY KEY,
    strategy_code NVARCHAR(64) NOT NULL UNIQUE,
    [name]        NVARCHAR(256),
    [description] NVARCHAR(MAX)
);

CREATE TABLE dbo.backtest_run (
    run_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    method        NVARCHAR(16) NOT NULL CHECK (method IN (N'SQL',N'Python')),
    start_date_id INT NOT NULL,
    end_date_id   INT NOT NULL,
    entry_rule    NVARCHAR(MAX),
    exit_rule     NVARCHAR(MAX),
    direction     NVARCHAR(8) CHECK (direction IN (N'long',N'short',N'both')),
    fee_bps       DECIMAL(9,4),
    strategy_id   INT NOT NULL,
    created_at    DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT fk_run_strategy FOREIGN KEY (strategy_id) REFERENCES dbo.strategy(strategy_id),
    CONSTRAINT fk_run_start FOREIGN KEY (start_date_id) REFERENCES dbo.calendar(date_id),
    CONSTRAINT fk_run_end FOREIGN KEY (end_date_id) REFERENCES dbo.calendar(date_id)
);

CREATE TABLE dbo.run_universe (
    run_id    BIGINT NOT NULL,
    ticker_id INT NOT NULL,
    CONSTRAINT pk_run_universe PRIMARY KEY (run_id, ticker_id),
    CONSTRAINT fk_ru_run FOREIGN KEY (run_id) REFERENCES dbo.backtest_run(run_id),
    CONSTRAINT fk_ru_ticker FOREIGN KEY (ticker_id) REFERENCES dbo.ticker(ticker_id)
);

/* ==========================================
   Signals & trades
   ========================================== */
CREATE TABLE dbo.signal (
    run_id      BIGINT NOT NULL,
    ticker_id   INT NOT NULL,
    date_id     INT NOT NULL,
    signal      SMALLINT NOT NULL CHECK (signal IN (-1,0,1)),
    signal_type NVARCHAR(64),
    strength    DECIMAL(18,8),
    created_at  DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_signal PRIMARY KEY (run_id, ticker_id, date_id),
    CONSTRAINT fk_sig_ru FOREIGN KEY (run_id, ticker_id) REFERENCES dbo.run_universe(run_id, ticker_id),
    CONSTRAINT fk_sig_date FOREIGN KEY (date_id) REFERENCES dbo.calendar(date_id)
);
CREATE TABLE dbo.trade (
    trade_id      BIGINT IDENTITY(1,1) PRIMARY KEY,
    run_id        BIGINT NOT NULL,
    ticker_id     INT NOT NULL,
    enter_date_id INT NOT NULL,
    exit_date_id  INT,
    enter_price   DECIMAL(18,6) NOT NULL CHECK (enter_price>=0),
    exit_price    DECIMAL(18,6) CHECK (exit_price IS NULL OR exit_price>=0),
    qty           DECIMAL(18,6) CHECK (qty IS NULL OR qty>0),
    side          NVARCHAR(8) NOT NULL CHECK (side IN (N'long',N'short')),
    pnl_pct       DECIMAL(18,8),
    created_at    DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT fk_tr_run FOREIGN KEY (run_id, ticker_id) REFERENCES dbo.run_universe(run_id, ticker_id),
    CONSTRAINT fk_tr_enter FOREIGN KEY (enter_date_id) REFERENCES dbo.calendar(date_id),
    CONSTRAINT fk_tr_exit FOREIGN KEY (exit_date_id) REFERENCES dbo.calendar(date_id),
    CONSTRAINT fk_tr_enter_signal FOREIGN KEY (run_id, ticker_id, enter_date_id)
        REFERENCES dbo.signal(run_id, ticker_id, date_id)
);


/* ==========================================
   Results
   ========================================== */
CREATE TABLE dbo.portfolio_results (
    run_id        BIGINT PRIMARY KEY,
    total_return  DECIMAL(18,8),
    equity_final  DECIMAL(18,8),
    equity_peak   DECIMAL(18,8),
    commission    DECIMAL(18,8),
    max_drawdown  DECIMAL(18,8),
    win_rate      DECIMAL(18,8),
    trades_count  INT,
    created_at    DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT fk_pr_run FOREIGN KEY (run_id) REFERENCES dbo.backtest_run(run_id)
);

CREATE TABLE dbo.benchmark_results (
    run_id       BIGINT PRIMARY KEY,
    [method]     NVARCHAR(16),
    started_at   DATETIME2(3),
    wall_time_ms BIGINT,
    peak_mem_mb  BIGINT,
    notes        NVARCHAR(MAX),
    created_at   DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT fk_br_run FOREIGN KEY (run_id) REFERENCES dbo.backtest_run(run_id)
);


/* ==========================
   STAGING TABLES
   ========================== */
CREATE TABLE dbo.stg_tickers (
    symbol   NVARCHAR(32)  NOT NULL,
    [name]   NVARCHAR(256) NULL,
    sector   NVARCHAR(128) NULL,
    industry NVARCHAR(128) NULL
);

CREATE TABLE dbo.stg_prices(
  symbol NVARCHAR(32),
  [date] NVARCHAR(50), 
  [open] NVARCHAR(50),
  [high] NVARCHAR(50),
  [low]  NVARCHAR(50),
  [close] NVARCHAR(50),
  volume NVARCHAR(50)
);

 /* ======================== */
TRUNCATE TABLE dbo.stg_tickers;
BULK INSERT dbo.stg_tickers
FROM 'C:\Users\Nguyen Thao\Downloads\data\out\tickers.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', CODEPAGE = '65001');

TRUNCATE TABLE dbo.stg_prices;
BULK INSERT dbo.stg_prices
FROM 'C:\Users\Nguyen Thao\Downloads\data\out\prices_all.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', CODEPAGE = '65001');


/* ==========================
   8) ETL
   ========================== */

-- Insert ticker
INSERT INTO dbo.ticker (symbol, [name], sector, industry)
SELECT DISTINCT
    LTRIM(RTRIM(UPPER(s.symbol))) AS symbol,
    LTRIM(RTRIM(s.[name]))        AS [name],
    LTRIM(RTRIM(s.sector))        AS sector,
    LTRIM(RTRIM(s.industry))      AS industry
FROM dbo.stg_tickers AS s;

-- Calendar full range
DECLARE @start date='1990-01-01', @end date='2030-12-31';
WITH d AS (
  SELECT @start AS d
  UNION ALL
  SELECT DATEADD(day,1,d) FROM d WHERE d < @end
)
INSERT INTO dbo.calendar(date_id, [date], [year], [quarter], [month], is_weekend, is_month_end)
SELECT CONVERT(int, FORMAT(d,'yyyyMMdd')),
       d, YEAR(d), DATEPART(quarter,d), MONTH(d),
       CASE WHEN DATENAME(weekday,d) IN ('Saturday','Sunday') THEN 1 ELSE 0 END,
       CASE WHEN EOMONTH(d)=d THEN 1 ELSE 0 END
FROM d
WHERE NOT EXISTS (SELECT 1 FROM dbo.calendar c WHERE c.[date]=d)
OPTION (MAXRECURSION 0);

-- Insert price_ohlcv
WITH map_t AS (SELECT ticker_id, symbol FROM dbo.ticker),
     map_d AS (SELECT date_id, [date] FROM dbo.calendar)
INSERT INTO dbo.price_ohlcv(ticker_id, date_id, [open],[high],[low],[close], volume)
SELECT 
    mt.ticker_id,
    md.date_id,
    TRY_CONVERT(decimal(18,6), sp.[open]),
    TRY_CONVERT(decimal(18,6), sp.[high]),
    TRY_CONVERT(decimal(18,6), sp.[low]),
    TRY_CONVERT(decimal(18,6), sp.[close]),
    TRY_CONVERT(bigint, TRY_CONVERT(float, sp.volume))
FROM dbo.stg_prices sp
JOIN map_t mt ON mt.symbol = LTRIM(RTRIM(sp.symbol))
JOIN map_d md ON md.[date] = TRY_CONVERT(date, LTRIM(RTRIM(sp.[date])), 103); -- dd/MM/yyyy



/* ==========================================
   Indexes
   ========================================== */
CREATE NONCLUSTERED INDEX IX_calendar_date
ON dbo.calendar([date]) INCLUDE(date_id);

CREATE NONCLUSTERED INDEX IX_ticker_symbol
ON dbo.ticker(symbol) INCLUDE(ticker_id);

CREATE NONCLUSTERED INDEX IX_price_ohlcv_tid_did
ON dbo.price_ohlcv(ticker_id, date_id)
INCLUDE([open],[high],[low],[close],volume);

CREATE NONCLUSTERED INDEX IX_price_ohlcv_did_tid
ON dbo.price_ohlcv(date_id, ticker_id)
INCLUDE([open],[high],[low],[close],volume);

CREATE NONCLUSTERED INDEX IX_feature_value_fid_tid_did
ON dbo.feature_value(feature_id, ticker_id, date_id)
INCLUDE(feature_value, computed_at);

CREATE NONCLUSTERED INDEX IX_signal_run_date
ON dbo.signal(run_id, date_id)
INCLUDE(ticker_id, signal);

CREATE NONCLUSTERED INDEX IX_run_universe_run
ON dbo.run_universe(run_id) INCLUDE(ticker_id);

CREATE NONCLUSTERED INDEX IX_feature_definition_name
ON dbo.feature_definition(feature_name) INCLUDE(feature_id, parameter);


/* === Row counts & basic ranges === */
-- Counts
SELECT 'ticker' AS tbl, COUNT(*) AS cnt FROM dbo.ticker
UNION ALL SELECT 'calendar', COUNT(*) FROM dbo.calendar
UNION ALL SELECT 'price_ohlcv', COUNT(*) FROM dbo.price_ohlcv
UNION ALL SELECT 'feature_definition', COUNT(*) FROM dbo.feature_definition
UNION ALL SELECT 'feature_value', COUNT(*) FROM dbo.feature_value;

-- Null checks in price_ohlcv (should be rare for ohlc)
SELECT 
  SUM(CASE WHEN [open]  IS NULL THEN 1 ELSE 0 END) AS null_open,
  SUM(CASE WHEN [high]  IS NULL THEN 1 ELSE 0 END) AS null_high,
  SUM(CASE WHEN [low]   IS NULL THEN 1 ELSE 0 END) AS null_low,
  SUM(CASE WHEN [close] IS NULL THEN 1 ELSE 0 END) AS null_close,
  SUM(CASE WHEN volume  IS NULL THEN 1 ELSE 0 END) AS null_volume
FROM dbo.price_ohlcv;

-- Logical price checks
SELECT TOP (50) *
FROM dbo.price_ohlcv
WHERE [low] > [high]
   OR [open] > [high]
   OR [close] > [high]
   OR [low] > [open]
   OR [low] > [close];

-- Out-of-calendar dates (should be none)
SELECT TOP (50) p.*
FROM dbo.price_ohlcv p
LEFT JOIN dbo.calendar c ON c.date_id = p.date_id
WHERE c.date_id IS NULL;

/* === Duplicate symbol (should be none due to UNIQUE) === */
SELECT symbol, COUNT(*) AS c
FROM dbo.ticker
GROUP BY symbol
HAVING COUNT(*) > 1;

/* === Foreign key coverage for prices === */
-- Missing ticker_id/ticker symbol mismaps: none expected after ETL
SELECT TOP (50) sp.*
FROM dbo.stg_prices sp
LEFT JOIN dbo.ticker t ON t.symbol = LTRIM(RTRIM(sp.symbol))
WHERE t.ticker_id IS NULL;

/* === Basic OHLC sanity: negative or absurd values === */
SELECT TOP (50) *
FROM dbo.price_ohlcv
WHERE [open] < 0 OR [high] < 0 OR [low] < 0 OR [close] < 0 OR volume < 0;

-- Min/Max snapshot
SELECT 
  MIN([close]) AS min_close, MAX([close]) AS max_close,
  MIN(volume)  AS min_vol,   MAX(volume)  AS max_vol
FROM dbo.price_ohlcv;


/* =========================
   Return features (simple, log, cumulative)
   ========================= */

;WITH f(name, ver, ftype) AS (
  SELECT N'RETURN_SIMPLE', N'1.0', N'return' UNION ALL
  SELECT N'RETURN_LOG',    N'1.0', N'return' UNION ALL
  SELECT N'RETURN_CUM',    N'1.0', N'return'
)
INSERT INTO dbo.feature_definition(feature_name, [version], feature_type)
SELECT f.name, f.ver, f.ftype
FROM f
LEFT JOIN dbo.feature_definition d
  ON d.feature_name = f.name AND d.[version] = f.ver
WHERE d.feature_id IS NULL;

DECLARE 
  @fid_simple INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name = N'RETURN_SIMPLE' AND [version] = N'1.0'),
  @fid_log    INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name = N'RETURN_LOG'    AND [version] = N'1.0'),
  @fid_cum    INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name = N'RETURN_CUM'    AND [version] = N'1.0');

;WITH base AS (
  SELECT p.ticker_id, p.date_id, p.[close],
         LAG(p.[close]) OVER (PARTITION BY p.ticker_id ORDER BY p.date_id) AS prev_close
  FROM dbo.price_ohlcv p
),
ret AS (
  SELECT ticker_id, date_id,
         CASE WHEN prev_close > 0 THEN ([close]-prev_close)/prev_close END AS r_simple,
         CASE WHEN [close] > 0 AND prev_close > 0 THEN LOG([close]/prev_close) END AS r_log
  FROM base
),
acc AS (
  SELECT r.*,
         EXP(SUM(CASE WHEN r_simple IS NOT NULL AND (1+r_simple)>0 THEN LOG(1+r_simple) END)
             OVER (PARTITION BY r.ticker_id ORDER BY r.date_id ROWS UNBOUNDED PRECEDING)) - 1 AS r_cum
  FROM ret r
)
INSERT INTO dbo.feature_value (ticker_id, date_id, feature_id, feature_value)
SELECT ticker_id, date_id, @fid_simple, r_simple FROM acc WHERE r_simple IS NOT NULL
UNION ALL
SELECT ticker_id, date_id, @fid_log,    r_log    FROM acc WHERE r_log    IS NOT NULL
UNION ALL
SELECT ticker_id, date_id, @fid_cum,    r_cum    FROM acc WHERE r_cum    IS NOT NULL;

SELECT t.symbol, c.[date], fd.feature_name, fv.feature_value
FROM dbo.feature_value fv
JOIN dbo.feature_definition fd ON fd.feature_id = fv.feature_id
JOIN dbo.ticker t ON t.ticker_id = fv.ticker_id
JOIN dbo.calendar c ON c.date_id = fv.date_id
WHERE t.symbol = N'BID' AND fd.feature_name LIKE N'RETURN_%'
ORDER BY c.[date], fd.feature_name;



/* =========================
   Rolling Annualized Vol (30, 60)
   ========================= */

IF NOT EXISTS (SELECT 1 FROM dbo.feature_definition WHERE feature_name=N'ROLL_VOL30_ANN' AND [version]=N'1.0')
  INSERT INTO dbo.feature_definition(feature_name,[version],feature_type) VALUES (N'ROLL_VOL30_ANN',N'1.0',N'volatility');
IF NOT EXISTS (SELECT 1 FROM dbo.feature_definition WHERE feature_name=N'ROLL_VOL60_ANN' AND [version]=N'1.0')
  INSERT INTO dbo.feature_definition(feature_name,[version],feature_type) VALUES (N'ROLL_VOL60_ANN',N'1.0',N'volatility');

DECLARE 
  @fid_log INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name=N'RETURN_LOG' AND [version]=N'1.0'),
  @fid_v30 INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name=N'ROLL_VOL30_ANN' AND [version]=N'1.0'),
  @fid_v60 INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name=N'ROLL_VOL60_ANN' AND [version]=N'1.0');

IF @fid_log IS NULL BEGIN RAISERROR(N'Missing RETURN_LOG v1.0',16,1); RETURN; END;

IF OBJECT_ID('tempdb..#roll') IS NOT NULL DROP TABLE #roll;
SELECT
  l.ticker_id, l.date_id,
  roll30_ann = CAST(
    CASE WHEN COUNT(l.lr) OVER (PARTITION BY l.ticker_id ORDER BY l.date_id ROWS BETWEEN 29 PRECEDING AND CURRENT ROW)=30
         THEN STDEV(l.lr) OVER (PARTITION BY l.ticker_id ORDER BY l.date_id ROWS BETWEEN 29 PRECEDING AND CURRENT ROW)*SQRT(252.0) END AS DECIMAL(38,6)),
  roll60_ann = CAST(
    CASE WHEN COUNT(l.lr) OVER (PARTITION BY l.ticker_id ORDER BY l.date_id ROWS BETWEEN 59 PRECEDING AND CURRENT ROW)=60
         THEN STDEV(l.lr) OVER (PARTITION BY l.ticker_id ORDER BY l.date_id ROWS BETWEEN 59 PRECEDING AND CURRENT ROW)*SQRT(252.0) END AS DECIMAL(38,6))
INTO #roll
FROM (
  SELECT fv.ticker_id, fv.date_id,
         TRY_CONVERT(FLOAT, fv.feature_value) AS lr,
         ROW_NUMBER() OVER (PARTITION BY fv.ticker_id, fv.date_id, fv.feature_id
                            ORDER BY fv.computed_at DESC, fv.feature_value DESC) AS rn
  FROM dbo.feature_value fv
  WHERE fv.feature_id = @fid_log
) l
WHERE l.rn=1 AND l.lr IS NOT NULL;

DELETE fv
FROM dbo.feature_value fv
JOIN #roll r ON r.ticker_id=fv.ticker_id AND r.date_id=fv.date_id
WHERE fv.feature_id IN (@fid_v30,@fid_v60);

INSERT INTO dbo.feature_value(ticker_id,date_id,feature_id,feature_value,computed_at)
SELECT ticker_id,date_id,@fid_v30,roll30_ann,SYSUTCDATETIME() FROM #roll WHERE roll30_ann IS NOT NULL;

INSERT INTO dbo.feature_value(ticker_id,date_id,feature_id,feature_value,computed_at)
SELECT ticker_id,date_id,@fid_v60,roll60_ann,SYSUTCDATETIME() FROM #roll WHERE roll60_ann IS NOT NULL;

SELECT t.symbol, c.[date],
       v30.feature_value AS roll_vol30_ann, v60.feature_value AS roll_vol60_ann
FROM dbo.ticker t
JOIN dbo.feature_value v30 ON v30.ticker_id=t.ticker_id AND v30.feature_id=@fid_v30
JOIN dbo.feature_value v60 ON v60.ticker_id=t.ticker_id AND v60.date_id=v30.date_id AND v60.feature_id=@fid_v60
JOIN dbo.calendar c ON c.date_id=v30.date_id
WHERE t.symbol=N'BID'
ORDER BY c.[date];


/* ======================================================
   Stored procedure: Compute Simple Moving Average (SMA)
   ====================================================== */

CREATE OR ALTER PROCEDURE dbo.sp_compute_SMA
  @window  INT,
  @symbols NVARCHAR(MAX) = NULL
AS
BEGIN
  SET NOCOUNT ON;

  IF @window < 2 BEGIN RAISERROR(N'Window must be >= 2',16,1); RETURN; END;

  DECLARE @fname NVARCHAR(50) = CONCAT(N'SMA', @window);
  IF NOT EXISTS (SELECT 1 FROM dbo.feature_definition WHERE feature_name=@fname AND [version]=N'1.0')
    INSERT INTO dbo.feature_definition(feature_name,[version],[parameter],feature_type)
    VALUES (@fname,N'1.0',CAST(@window AS NVARCHAR(10)),N'trend');

  DECLARE @fid INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name=@fname AND [version]=N'1.0');

  IF @symbols IS NULL
    DELETE FROM dbo.feature_value WHERE feature_id=@fid;
  ELSE
  BEGIN
    ;WITH syms AS (SELECT TRIM(value) AS symbol FROM STRING_SPLIT(@symbols, N',')) 
    DELETE fv
    FROM dbo.feature_value fv
    JOIN dbo.ticker t ON t.ticker_id=fv.ticker_id
    JOIN syms s ON s.symbol=t.symbol
    WHERE fv.feature_id=@fid;
  END

  DECLARE @sql NVARCHAR(MAX) = N'
;WITH src AS (
  SELECT p.ticker_id, p.date_id, p.[close]
  FROM dbo.price_ohlcv p ' + 
  CASE WHEN @symbols IS NULL THEN N'' ELSE N'
  JOIN dbo.ticker t ON t.ticker_id=p.ticker_id
  WHERE t.symbol IN (SELECT TRIM(value) FROM STRING_SPLIT(@symbols,'',''))' END + N'
),
cte AS (
  SELECT s.ticker_id, s.date_id,
         AVG(s.[close]) OVER (PARTITION BY s.ticker_id ORDER BY s.date_id
                              ROWS BETWEEN ' + CAST(@window-1 AS NVARCHAR(10)) + N' PRECEDING AND CURRENT ROW) AS sma_val,
         COUNT(s.[close]) OVER (PARTITION BY s.ticker_id ORDER BY s.date_id
                              ROWS BETWEEN ' + CAST(@window-1 AS NVARCHAR(10)) + N' PRECEDING AND CURRENT ROW) AS cnt_win
  FROM src s
)
INSERT INTO dbo.feature_value(ticker_id,date_id,feature_id,feature_value)
SELECT ticker_id,date_id,' + CAST(@fid AS NVARCHAR(20)) + N',sma_val
FROM cte
WHERE cnt_win=' + CAST(@window AS NVARCHAR(10)) + N';';

  EXEC sys.sp_executesql @sql, N'@symbols NVARCHAR(MAX)', @symbols=@symbols;
END
GO

EXEC dbo.sp_compute_SMA @window = 20;
EXEC dbo.sp_compute_SMA @window = 50;

SELECT t.symbol, c.[date],
       sma20.feature_value AS SMA20, sma50.feature_value AS SMA50
FROM dbo.ticker t
JOIN dbo.calendar c ON 1=1
LEFT JOIN dbo.feature_value sma20 ON sma20.ticker_id=t.ticker_id AND sma20.date_id=c.date_id
  AND sma20.feature_id=(SELECT feature_id FROM dbo.feature_definition WHERE feature_name=N'SMA20' AND [version]=N'1.0')
LEFT JOIN dbo.feature_value sma50 ON sma50.ticker_id=t.ticker_id AND sma50.date_id=c.date_id
  AND sma50.feature_id=(SELECT feature_id FROM dbo.feature_definition WHERE feature_name=N'SMA50' AND [version]=N'1.0')
WHERE t.symbol=N'BID'
ORDER BY c.[date];



/* ===========================
   EMA12 (recursive, adjust=false)
   =========================== */
SET NOCOUNT ON;

DECLARE @span INT = 12;
DECLARE @alpha FLOAT = 2.0 / (@span + 1.0);

-- 1) Ensure feature definition
DECLARE @feat_name NVARCHAR(128) = CONCAT(N'EMA', @span, N'_BENCH');
IF NOT EXISTS (SELECT 1 FROM dbo.feature_definition WHERE feature_name=@feat_name)
  INSERT INTO dbo.feature_definition(feature_name,[version],[parameter],feature_type,formula_text)
  VALUES (@feat_name,'1.0', CONCAT(N'{"span":',@span,',"method":"recursive"}'),
          'technical','EMA_t = α*Close_t + (1-α)*EMA_{t-1}');
DECLARE @fid INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name=@feat_name);

-- 2) Materialize input
IF OBJECT_ID('tempdb..#xr') IS NOT NULL DROP TABLE #xr;
SELECT
    p.ticker_id,
    p.date_id,
    CAST(p.[close] AS FLOAT) AS close_val,
    ROW_NUMBER() OVER (PARTITION BY p.ticker_id ORDER BY p.date_id) AS rn
INTO #xr
FROM dbo.price_ohlcv p
WHERE p.[close] IS NOT NULL;

CREATE CLUSTERED INDEX IX_xr_tid_rn ON #xr(ticker_id, rn);

-- 3) Delete old EMA12 values in scope
DELETE fv
FROM dbo.feature_value fv
JOIN (SELECT DISTINCT ticker_id FROM #xr) s ON s.ticker_id = fv.ticker_id
WHERE fv.feature_id = @fid;

-- 4) Recursive EMA calculation
;WITH ema AS (
    SELECT x.ticker_id, x.date_id, x.rn, x.close_val AS ema_val
    FROM #xr x WHERE x.rn = 1
    UNION ALL
    SELECT x2.ticker_id, x2.date_id, x2.rn,
           @alpha * x2.close_val + (1 - @alpha) * e.ema_val
    FROM ema e
    JOIN #xr x2 ON x2.ticker_id = e.ticker_id AND x2.rn = e.rn + 1
)
INSERT INTO dbo.feature_value(ticker_id, date_id, feature_id, feature_value)
SELECT ticker_id, date_id, @fid, CAST(ema_val AS DECIMAL(18,8))
FROM ema
OPTION (MAXRECURSION 0);

-- 5) Quick Check
SELECT TOP 50 
    c.[date],
    v.feature_value AS EMA12
FROM dbo.feature_value v
JOIN dbo.ticker t   ON t.ticker_id = v.ticker_id
JOIN dbo.calendar c ON c.date_id   = v.date_id
JOIN dbo.feature_definition f ON f.feature_id = v.feature_id
WHERE t.symbol = N'BID'
  AND f.feature_name = N'EMA12_BENCH'
ORDER BY c.[date];


------------------------------------------------------------
/* ===========================
   EMA26 (recursive, adjust=false)
   =========================== */
SET NOCOUNT ON;

DECLARE @span INT = 26;
DECLARE @alpha FLOAT = 2.0 / (@span + 1.0);

-- 1) Ensure feature definition
DECLARE @feat_name NVARCHAR(128) = CONCAT(N'EMA', @span, N'_BENCH');
IF NOT EXISTS (SELECT 1 FROM dbo.feature_definition WHERE feature_name=@feat_name)
  INSERT INTO dbo.feature_definition(feature_name,[version],[parameter],feature_type,formula_text)
  VALUES (@feat_name,'1.0', CONCAT(N'{"span":',@span,',"method":"recursive"}'),
          'technical','EMA_t = α*Close_t + (1-α)*EMA_{t-1}');
DECLARE @fid INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name=@feat_name);

-- 2) Materialize input
IF OBJECT_ID('tempdb..#xr') IS NOT NULL DROP TABLE #xr;
SELECT
    p.ticker_id,
    p.date_id,
    CAST(p.[close] AS FLOAT) AS close_val,
    ROW_NUMBER() OVER (PARTITION BY p.ticker_id ORDER BY p.date_id) AS rn
INTO #xr
FROM dbo.price_ohlcv p
WHERE p.[close] IS NOT NULL;

CREATE CLUSTERED INDEX IX_xr_tid_rn ON #xr(ticker_id, rn);

-- 3) Delete old EMA26 values in scope
DELETE fv
FROM dbo.feature_value fv
JOIN (SELECT DISTINCT ticker_id FROM #xr) s ON s.ticker_id = fv.ticker_id
WHERE fv.feature_id = @fid;

-- 4) Recursive EMA calculation
;WITH ema AS (
    SELECT x.ticker_id, x.date_id, x.rn, x.close_val AS ema_val
    FROM #xr x WHERE x.rn = 1
    UNION ALL
    SELECT x2.ticker_id, x2.date_id, x2.rn,
           @alpha * x2.close_val + (1 - @alpha) * e.ema_val
    FROM ema e
    JOIN #xr x2 ON x2.ticker_id = e.ticker_id AND x2.rn = e.rn + 1
)
INSERT INTO dbo.feature_value(ticker_id, date_id, feature_id, feature_value)
SELECT ticker_id, date_id, @fid, CAST(ema_val AS DECIMAL(18,8))
FROM ema
OPTION (MAXRECURSION 0);

-- 5) Quick check
SELECT TOP 50 
    c.[date],
    v.feature_value AS EMA26
FROM dbo.feature_value v
JOIN dbo.ticker t   ON t.ticker_id = v.ticker_id
JOIN dbo.calendar c ON c.date_id   = v.date_id
JOIN dbo.feature_definition f ON f.feature_id = v.feature_id
WHERE t.symbol = N'BID'
  AND f.feature_name = N'EMA26_BENCH'
ORDER BY c.[date];


/* ============================================
   Build MACD(12,26), SIGNAL(EMA9 of MACD), HIST
   for ALL tickers (or one ticker if @symbol set)
============================================ */

DECLARE @symbol NVARCHAR(20) = NULL;   -- ví dụ: N'VNM' hoặc NULL = tất cả
DECLARE @start_date_id INT = NULL;     -- có thể đặt khoảng thời gian nếu muốn
DECLARE @end_date_id   INT = NULL;


IF NOT EXISTS (SELECT 1 FROM dbo.feature_definition WHERE feature_name=N'MACD_12_26')
  INSERT INTO dbo.feature_definition(feature_name) VALUES (N'MACD_12_26');
IF NOT EXISTS (SELECT 1 FROM dbo.feature_definition WHERE feature_name=N'SIGNAL_9')
  INSERT INTO dbo.feature_definition(feature_name) VALUES (N'SIGNAL_9');
IF NOT EXISTS (SELECT 1 FROM dbo.feature_definition WHERE feature_name=N'HIST')
  INSERT INTO dbo.feature_definition(feature_name) VALUES (N'HIST');


DECLARE @fid_ema12 INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name=N'EMA12_BENCH');
DECLARE @fid_ema26 INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name=N'EMA26_BENCH');

IF OBJECT_ID('tempdb..#macd_raw') IS NOT NULL DROP TABLE #macd_raw;
SELECT
    e12.ticker_id,
    e12.date_id,
    c.[date]                       AS mdate,
    CAST(e12.feature_value - e26.feature_value AS FLOAT) AS macd_val
INTO #macd_raw
FROM dbo.feature_value e12
JOIN dbo.feature_value e26
  ON e12.ticker_id = e26.ticker_id
 AND e12.date_id  = e26.date_id
JOIN dbo.calendar c
  ON c.date_id = e12.date_id
JOIN dbo.ticker t
  ON t.ticker_id = e12.ticker_id
WHERE e12.feature_id = @fid_ema12
  AND e26.feature_id = @fid_ema26
  AND (@symbol IS NULL OR t.symbol = @symbol)
  AND (@start_date_id IS NULL OR e12.date_id >= @start_date_id)
  AND (@end_date_id   IS NULL OR e12.date_id <= @end_date_id);


IF OBJECT_ID('tempdb..#macd') IS NOT NULL DROP TABLE #macd;
;WITH w AS (
  SELECT r.*,
         cnt26 = COUNT(*) OVER (PARTITION BY r.ticker_id ORDER BY r.date_id
                                ROWS BETWEEN 25 PRECEDING AND CURRENT ROW)
  FROM #macd_raw r
)
SELECT ticker_id, date_id, mdate, macd_val,
       ROW_NUMBER() OVER (PARTITION BY ticker_id ORDER BY date_id) AS rn
INTO #macd
FROM w
WHERE cnt26 = 26;

CREATE CLUSTERED INDEX IX_macd_tid_rn ON #macd(ticker_id, rn);

IF OBJECT_ID('tempdb..#out') IS NOT NULL DROP TABLE #out;
DECLARE @alpha FLOAT = 2.0 / (9 + 1);

;WITH rec AS (
  SELECT m.ticker_id, m.date_id, m.mdate, m.rn,
         m.macd_val,
         sig_val = m.macd_val  
  FROM #macd m WHERE m.rn = 1
  UNION ALL
  SELECT m.ticker_id, m.date_id, m.mdate, m.rn,
         m.macd_val,
         sig_val = @alpha*m.macd_val + (1-@alpha)*r.sig_val
  FROM rec r
  JOIN #macd m
    ON m.ticker_id = r.ticker_id
   AND m.rn       = r.rn + 1
)
SELECT ticker_id, date_id, mdate,
       MACD   = macd_val,
       Signal = CASE WHEN rn >= 9  THEN sig_val END,
       Hist   = CASE WHEN rn >= 9  THEN macd_val - sig_val END
INTO #out
FROM rec
OPTION (MAXRECURSION 0);

-- MACD
INSERT INTO dbo.feature_value(ticker_id,date_id,feature_id,feature_value)
SELECT o.ticker_id, o.date_id, f.feature_id, o.MACD
FROM #out o
CROSS JOIN (SELECT feature_id FROM dbo.feature_definition WHERE feature_name=N'MACD_12_26') f
WHERE o.MACD IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dbo.feature_value v
      WHERE v.ticker_id=o.ticker_id AND v.date_id=o.date_id AND v.feature_id=f.feature_id
  );

-- SIGNAL
INSERT INTO dbo.feature_value(ticker_id,date_id,feature_id,feature_value)
SELECT o.ticker_id, o.date_id, f.feature_id, o.Signal
FROM #out o
CROSS JOIN (SELECT feature_id FROM dbo.feature_definition WHERE feature_name=N'SIGNAL_9') f
WHERE o.Signal IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dbo.feature_value v
      WHERE v.ticker_id=o.ticker_id AND v.date_id=o.date_id AND v.feature_id=f.feature_id
  );

-- HIST
INSERT INTO dbo.feature_value(ticker_id,date_id,feature_id,feature_value)
SELECT o.ticker_id, o.date_id, f.feature_id, o.Hist
FROM #out o
CROSS JOIN (SELECT feature_id FROM dbo.feature_definition WHERE feature_name=N'HIST') f
WHERE o.Hist IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dbo.feature_value v
      WHERE v.ticker_id=o.ticker_id AND v.date_id=o.date_id AND v.feature_id=f.feature_id
  );


-----------------------------------------------
-- 5) Quick check: MACD / Signal / Hist
-----------------------------------------------
SELECT 
    c.[date],
    t.symbol,
    MACD   = MAX(CASE WHEN fd.feature_name=N'MACD_12_26' THEN fv.feature_value END),
    Signal = MAX(CASE WHEN fd.feature_name=N'SIGNAL_9'   THEN fv.feature_value END),
    Hist   = MAX(CASE WHEN fd.feature_name=N'HIST'       THEN fv.feature_value END)
FROM dbo.feature_value fv
JOIN dbo.feature_definition fd ON fv.feature_id=fd.feature_id
JOIN dbo.ticker t ON fv.ticker_id=t.ticker_id
JOIN dbo.calendar c ON fv.date_id=c.date_id
WHERE t.symbol=N'BID'
  AND fd.feature_name IN (N'MACD_12_26',N'SIGNAL_9',N'HIST')
GROUP BY c.[date], t.symbol
ORDER BY c.[date];

/* ============================================
   RSI14 Wilder (seed = SMA14, recursive)
============================================ */
SET NOCOUNT ON;

DECLARE @Period INT = 14;
DECLARE @FeatureName NVARCHAR(128) = N'RSI14_Wilder';
DECLARE @Version NVARCHAR(32) = N'1.0';
DECLARE @FeatureId INT;

IF OBJECT_ID('tempdb..#PriceSeq') IS NOT NULL DROP TABLE #PriceSeq;
IF OBJECT_ID('tempdb..#RSI')      IS NOT NULL DROP TABLE #RSI;

------------------------------------------------------------
-- 1) Materialize prices with Δ, gain, loss
------------------------------------------------------------
SELECT
    p.ticker_id,
    p.date_id,
    ROW_NUMBER() OVER (PARTITION BY p.ticker_id ORDER BY p.date_id) AS RowNum,
    CONVERT(FLOAT, p.[close]) AS CloseVal,
    CONVERT(FLOAT, p.[close] - LAG(p.[close]) OVER (PARTITION BY p.ticker_id ORDER BY p.date_id)) AS Delta
INTO #PriceSeq
FROM dbo.price_ohlcv p
WHERE p.[close] IS NOT NULL;

ALTER TABLE #PriceSeq ADD Gain AS CASE WHEN Delta > 0 THEN Delta ELSE 0 END;
ALTER TABLE #PriceSeq ADD Loss AS CASE WHEN Delta < 0 THEN -Delta ELSE 0 END;

CREATE CLUSTERED INDEX IX_px ON #PriceSeq(ticker_id, RowNum);

------------------------------------------------------------
-- 2) Seed SMA-14 (RowNum = 15), then recursive smoothing
------------------------------------------------------------
;WITH Seed AS (
    SELECT
        x.ticker_id, x.date_id, x.RowNum,
        AvgGain = (SELECT SUM(CONVERT(FLOAT, z.Gain)) / @Period
                   FROM #PriceSeq z
                   WHERE z.ticker_id=x.ticker_id AND z.RowNum BETWEEN x.RowNum-@Period+1 AND x.RowNum),
        AvgLoss = (SELECT SUM(CONVERT(FLOAT, z.Loss)) / @Period
                   FROM #PriceSeq z
                   WHERE z.ticker_id=x.ticker_id AND z.RowNum BETWEEN x.RowNum-@Period+1 AND x.RowNum)
    FROM #PriceSeq x
    WHERE x.RowNum = @Period + 1
),
Rec AS (
    SELECT s.ticker_id, s.date_id, s.RowNum, s.AvgGain, s.AvgLoss
    FROM Seed s
    UNION ALL
    SELECT
        x.ticker_id, x.date_id, x.RowNum,
        ((r.AvgGain * (@Period - 1)) + x.Gain) / @Period,
        ((r.AvgLoss * (@Period - 1)) + x.Loss) / @Period
    FROM Rec r
    JOIN #PriceSeq x ON x.ticker_id = r.ticker_id AND x.RowNum = r.RowNum + 1
)
SELECT
    r.ticker_id,
    r.date_id,
    RSI = CASE
            WHEN r.AvgLoss = 0 AND r.AvgGain = 0 THEN 50.0
            WHEN r.AvgLoss = 0                 THEN 100.0
            WHEN r.AvgGain = 0                 THEN   0.0
            ELSE 100.0 - (100.0 / (1 + (r.AvgGain / NULLIF(r.AvgLoss,0))))
          END
INTO #RSI
FROM Rec r
OPTION (MAXRECURSION 0);

------------------------------------------------------------
-- 3) Ensure feature_definition, get feature_id
------------------------------------------------------------
SELECT @FeatureId = feature_id
FROM dbo.feature_definition
WHERE feature_name=@FeatureName AND [version]=@Version;

IF @FeatureId IS NULL
BEGIN
    INSERT INTO dbo.feature_definition(feature_name, parameter, [version], formula_text, feature_type, created_at)
    VALUES (@FeatureName, CONCAT(N'n=', @Period), @Version,
            N'RSI Wilder (seed SMA, recursive)', N'momentum', SYSUTCDATETIME());
    SET @FeatureId = SCOPE_IDENTITY();
END

------------------------------------------------------------
-- 4) Delete old values in scope, then insert fresh
------------------------------------------------------------
DELETE fv
FROM dbo.feature_value fv
JOIN #RSI r ON fv.ticker_id=r.ticker_id AND fv.date_id=r.date_id
WHERE fv.feature_id=@FeatureId;

INSERT INTO dbo.feature_value (ticker_id, date_id, feature_id, feature_value, computed_at)
SELECT r.ticker_id, r.date_id, @FeatureId, CAST(ROUND(r.RSI,6) AS DECIMAL(18,6)), SYSUTCDATETIME()
FROM #RSI r;

------------------------------------------------------------
-- 5) Quick check
------------------------------------------------------------
SELECT TOP 30 c.[date], t.symbol, fv.feature_value AS RSI14_Wilder
FROM dbo.feature_value fv
JOIN dbo.calendar c ON c.date_id=fv.date_id
JOIN dbo.ticker t ON t.ticker_id=fv.ticker_id
JOIN dbo.feature_definition fd ON fd.feature_id=fv.feature_id
WHERE fd.feature_name=N'RSI14_Wilder'
  AND t.symbol=N'BID'
ORDER BY c.[date];


/* ============================================
   Bollinger Bands (20, k=2)
   Flow: ensure features → compute STD20 → compute BB → upsert
============================================ */
SET NOCOUNT ON;

------------------------------------------------------------
-- 1) Ensure feature_definitions
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.feature_definition WHERE feature_name='STD20')
  INSERT INTO dbo.feature_definition(feature_name,[version],[parameter])
  VALUES ('STD20','1.0','{"window":20,"ddof":0}');

IF NOT EXISTS (SELECT 1 FROM dbo.feature_definition WHERE feature_name='BB_MID20')
  INSERT INTO dbo.feature_definition(feature_name,[version],[parameter])
  VALUES ('BB_MID20','1.0','{"window":20,"k":2}');

IF NOT EXISTS (SELECT 1 FROM dbo.feature_definition WHERE feature_name='BB_UPPER20')
  INSERT INTO dbo.feature_definition(feature_name,[version],[parameter])
  VALUES ('BB_UPPER20','1.0','{"window":20,"k":2}');

IF NOT EXISTS (SELECT 1 FROM dbo.feature_definition WHERE feature_name='BB_LOWER20')
  INSERT INTO dbo.feature_definition(feature_name,[version],[parameter])
  VALUES ('BB_LOWER20','1.0','{"window":20,"k":2}');

DECLARE @fid_sma20 INT  = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name='SMA20');
DECLARE @fid_std20 INT  = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name='STD20');
DECLARE @fid_mid   INT  = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name='BB_MID20');
DECLARE @fid_upper INT  = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name='BB_UPPER20');
DECLARE @fid_lower INT  = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name='BB_LOWER20');

------------------------------------------------------------
-- 2) Compute STD20 (population std, require 20 obs)
------------------------------------------------------------
DELETE FROM dbo.feature_value WHERE feature_id=@fid_std20;

;WITH x AS (
  SELECT 
    p.ticker_id,
    p.date_id,
    std20 = STDEVP(CAST(p.[close] AS FLOAT)) OVER (
              PARTITION BY p.ticker_id
              ORDER BY p.date_id
              ROWS BETWEEN 19 PRECEDING AND CURRENT ROW),
    n20   = COUNT(*) OVER (
              PARTITION BY p.ticker_id
              ORDER BY p.date_id
              ROWS BETWEEN 19 PRECEDING AND CURRENT ROW)
  FROM dbo.price_ohlcv p
)
INSERT INTO dbo.feature_value(ticker_id,date_id,feature_id,feature_value)
SELECT ticker_id, date_id, @fid_std20, std20
FROM x WHERE n20=20;

------------------------------------------------------------
-- 3) Compute Bollinger Bands (mid, upper, lower)
------------------------------------------------------------
DELETE FROM dbo.feature_value WHERE feature_id IN (@fid_mid,@fid_upper,@fid_lower);

;WITH sma AS (
  SELECT fv.ticker_id,fv.date_id,val=fv.feature_value
  FROM dbo.feature_value fv WHERE fv.feature_id=@fid_sma20
),
std AS (
  SELECT fv.ticker_id,fv.date_id,val=fv.feature_value
  FROM dbo.feature_value fv WHERE fv.feature_id=@fid_std20
)
INSERT INTO dbo.feature_value(ticker_id,date_id,feature_id,feature_value)
SELECT s.ticker_id,s.date_id,@fid_mid,s.val
FROM sma s JOIN std v ON v.ticker_id=s.ticker_id AND v.date_id=s.date_id
UNION ALL
SELECT s.ticker_id,s.date_id,@fid_upper,s.val+2*v.val
FROM sma s JOIN std v ON v.ticker_id=s.ticker_id AND v.date_id=s.date_id
UNION ALL
SELECT s.ticker_id,s.date_id,@fid_lower,s.val-2*v.val
FROM sma s JOIN std v ON v.ticker_id=s.ticker_id AND v.date_id=s.date_id;

------------------------------------------------------------
-- 4) Quick check: one symbol (BID)
------------------------------------------------------------
SELECT c.[date],t.symbol,
  MAX(CASE WHEN fd.feature_name='BB_MID20'   THEN fv.feature_value END) AS BB_MID20,
  MAX(CASE WHEN fd.feature_name='BB_UPPER20' THEN fv.feature_value END) AS BB_UPPER20,
  MAX(CASE WHEN fd.feature_name='BB_LOWER20' THEN fv.feature_value END) AS BB_LOWER20
FROM dbo.feature_value fv
JOIN dbo.feature_definition fd ON fd.feature_id=fv.feature_id
JOIN dbo.ticker t ON t.ticker_id=fv.ticker_id
JOIN dbo.calendar c ON c.date_id=fv.date_id
WHERE fd.feature_name IN ('BB_MID20','BB_UPPER20','BB_LOWER20')
  AND t.symbol=N'BID'
GROUP BY t.symbol,c.[date]
ORDER BY c.[date];

/* ============================================
   ATR14 (Wilder’s smoothing)

============================================ */
SET NOCOUNT ON;

DECLARE @N INT = 14;

-- Ensure feature_definition
IF NOT EXISTS (SELECT 1 FROM dbo.feature_definition WHERE feature_name='ATR14')
  INSERT INTO dbo.feature_definition(feature_name,[version],[parameter])
  VALUES ('ATR14','1.0','{"window":14,"method":"Wilder"}');

DECLARE @fid_atr14 INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name='ATR14');

------------------------------------------------------------
-- 1) Materialize OHLC + prev_close
------------------------------------------------------------
IF OBJECT_ID('tempdb..#raw') IS NOT NULL DROP TABLE #raw;
SELECT
  p.ticker_id,
  p.date_id,
  hi   = CAST(p.[high] AS float),
  lo   = CAST(p.[low]  AS float),
  cl   = CAST(p.[close] AS float),
  prev = CAST(ISNULL(LAG(p.[close]) OVER(PARTITION BY p.ticker_id ORDER BY p.date_id), p.[close]) AS float),
  rn   = ROW_NUMBER() OVER (PARTITION BY p.ticker_id ORDER BY p.date_id)
INTO #raw
FROM dbo.price_ohlcv p
WHERE p.[high] IS NOT NULL AND p.[low] IS NOT NULL AND p.[close] IS NOT NULL;

CREATE CLUSTERED INDEX IX_tmp_raw ON #raw(ticker_id, rn);

------------------------------------------------------------
-- 2) True Range (TR)
------------------------------------------------------------
IF OBJECT_ID('tempdb..#px') IS NOT NULL DROP TABLE #px;
SELECT
  r.ticker_id,
  r.date_id,
  r.rn,
  tr = (SELECT MAX(v) FROM (VALUES
           (r.hi - r.lo),
           (ABS(r.hi - r.prev)),
           (ABS(r.lo - r.prev))
       ) AS T(v))
INTO #px
FROM #raw r;

CREATE CLUSTERED INDEX IX_tmp_px ON #px(ticker_id, rn);

------------------------------------------------------------
-- 3) Wilder smoothing: seed SMA(N), recursive ATR
------------------------------------------------------------
IF OBJECT_ID('tempdb..#atr') IS NOT NULL DROP TABLE #atr;

;WITH seed AS (
    SELECT
      x.ticker_id, x.date_id, x.rn,
      ATR = (SELECT SUM(CAST(z.tr AS float))/@N
             FROM #px z
             WHERE z.ticker_id=x.ticker_id AND z.rn BETWEEN x.rn-@N+1 AND x.rn)
    FROM #px x
    WHERE x.rn=@N
),
r AS (
    SELECT s.ticker_id,s.date_id,s.rn,s.ATR FROM seed s
    UNION ALL
    SELECT x.ticker_id,x.date_id,x.rn,
           ((r.ATR*(@N-1))+x.tr)/(1.0*@N)
    FROM r
    JOIN #px x ON x.ticker_id=r.ticker_id AND x.rn=r.rn+1
)
SELECT ticker_id,date_id,ATR
INTO #atr
FROM r
OPTION (MAXRECURSION 0);

------------------------------------------------------------
-- 4) Upsert feature_value
------------------------------------------------------------
DELETE fv
FROM dbo.feature_value fv
JOIN #atr a ON a.ticker_id=fv.ticker_id AND a.date_id=fv.date_id
WHERE fv.feature_id=@fid_atr14;

INSERT INTO dbo.feature_value(ticker_id,date_id,feature_id,feature_value,computed_at)
SELECT a.ticker_id,a.date_id,@fid_atr14,a.ATR,SYSUTCDATETIME()
FROM #atr a;

------------------------------------------------------------
-- 5) Quick check (symbol BID)
------------------------------------------------------------
SELECT TOP 30 t.symbol,c.[date],a.ATR AS ATR14_Wilder
FROM #atr a
JOIN dbo.ticker t ON t.ticker_id=a.ticker_id
JOIN dbo.calendar c ON c.date_id=a.date_id
WHERE t.symbol=N'BID'
ORDER BY c.[date];

/* ============================================
   CMF20 (Chaikin Money Flow, window=20)
   Flow: normalize → MFM/MFV → rolling → materialize → upsert → check
============================================ */
SET NOCOUNT ON;

-- 1) Ensure feature_definition
IF NOT EXISTS (SELECT 1 FROM dbo.feature_definition WHERE feature_name=N'CMF20' AND [version]=N'1.0')
  INSERT INTO dbo.feature_definition(feature_name,[version],[parameter],feature_type,formula_text,created_at)
  VALUES (N'CMF20', N'1.0', N'{"window":20}', N'volume',
          N'CMF = Σ(MFV,20)/Σ(V,20) with MFM = (2C-H-L)/(H-L)', SYSUTCDATETIME());

DECLARE @fid_cmf20 INT = (
  SELECT feature_id FROM dbo.feature_definition WHERE feature_name=N'CMF20' AND [version]=N'1.0'
);

IF OBJECT_ID('tempdb..#cmf') IS NOT NULL DROP TABLE #cmf;

-- 2) Compute & materialize CMF20
;WITH base AS (
  SELECT p.ticker_id, p.date_id,
         H=CONVERT(float,p.[high]), L=CONVERT(float,p.[low]),
         C=CONVERT(float,p.[close]), V=CONVERT(float,p.[volume])
  FROM dbo.price_ohlcv p
  WHERE p.[high] IS NOT NULL AND p.[low] IS NOT NULL
    AND p.[close] IS NOT NULL AND p.[volume] IS NOT NULL
),
m AS (
  SELECT b.ticker_id, b.date_id, b.V,
         MFV = CASE WHEN (b.H-b.L)=0 THEN 0.0
                    ELSE ((2.0*b.C - b.H - b.L)/(b.H - b.L)) * b.V END
  FROM base b
),
w AS (
  SELECT m.ticker_id, m.date_id,
         sum_mfv = SUM(m.MFV) OVER (PARTITION BY m.ticker_id ORDER BY m.date_id ROWS BETWEEN 19 PRECEDING AND CURRENT ROW),
         sum_vol = SUM(m.V)   OVER (PARTITION BY m.ticker_id ORDER BY m.date_id ROWS BETWEEN 19 PRECEDING AND CURRENT ROW),
         cnt     = COUNT(*)   OVER (PARTITION BY m.ticker_id ORDER BY m.date_id ROWS BETWEEN 19 PRECEDING AND CURRENT ROW)
  FROM m
)
SELECT ticker_id, date_id,
       CMF20 = CASE WHEN cnt=20 AND sum_vol<>0.0 THEN sum_mfv/sum_vol END
INTO #cmf
FROM w;

-- 3) Upsert 
DELETE fv
FROM dbo.feature_value fv
JOIN #cmf x ON x.ticker_id=fv.ticker_id AND x.date_id=fv.date_id
WHERE fv.feature_id=@fid_cmf20;

INSERT INTO dbo.feature_value(ticker_id,date_id,feature_id,feature_value,computed_at)
SELECT x.ticker_id, x.date_id, @fid_cmf20, CAST(x.CMF20 AS DECIMAL(18,8)), SYSUTCDATETIME()
FROM #cmf x
WHERE x.CMF20 IS NOT NULL;

-- 4) Quick check (BID)
SELECT c.[date], t.symbol,
       MAX(CASE WHEN fd.feature_name=N'CMF20' THEN fv.feature_value END) AS CMF20
FROM dbo.feature_value fv
JOIN dbo.feature_definition fd ON fd.feature_id=fv.feature_id
JOIN dbo.ticker t ON t.ticker_id=fv.ticker_id
JOIN dbo.calendar c ON c.date_id=fv.date_id
WHERE t.symbol=N'BID' AND fd.feature_name=N'CMF20'
GROUP BY c.[date], t.symbol
ORDER BY c.[date];


/* ============================================
   OBV (scaled by 1e6 to fit DECIMAL(18,8))
   Flow: sign by close change → cumsum(volume) → scale → upsert
============================================ */
SET NOCOUNT ON;

DECLARE @Scale DECIMAL(18,6) = 1000000.0;              -- 1e6
DECLARE @FeatureName NVARCHAR(128) = N'OBV_SCALED_1e6';
DECLARE @Version NVARCHAR(32) = N'1.0';
DECLARE @FeatureId INT;

-- 1) Ensure feature_definition
SELECT @FeatureId = feature_id
FROM dbo.feature_definition
WHERE feature_name=@FeatureName AND [version]=@Version;

IF @FeatureId IS NULL
BEGIN
  INSERT INTO dbo.feature_definition(feature_name,[version],[parameter],feature_type,formula_text,created_at)
  VALUES (@FeatureName,@Version, CONCAT(N'{"scale":',@Scale,N'}'),
          N'volume', N'OBV (scaled by scale)', SYSUTCDATETIME());
  SET @FeatureId = SCOPE_IDENTITY();
END

-- 2) Compute OBV (set-based) and materialize
IF OBJECT_ID('tempdb..#obv') IS NOT NULL DROP TABLE #obv;

;WITH src AS (
  SELECT
    p.ticker_id,
    p.date_id,
    vol = CONVERT(BIGINT, p.volume),
    close_prev = LAG(p.[close]) OVER (PARTITION BY p.ticker_id ORDER BY p.date_id),
    close_curr = p.[close]
  FROM dbo.price_ohlcv p
  WHERE p.volume IS NOT NULL AND p.[close] IS NOT NULL
),
signed AS (
  SELECT
    s.ticker_id,
    s.date_id,
    signed_vol =
      CASE
        WHEN s.close_prev IS NULL                THEN 0
        WHEN s.close_curr >  s.close_prev        THEN vol
        WHEN s.close_curr <  s.close_prev        THEN -vol
        ELSE 0
      END
  FROM src s
)
SELECT
  o.ticker_id,
  o.date_id,
  obv_scaled = CAST(
      1.0 * SUM(o.signed_vol) OVER
        (PARTITION BY o.ticker_id ORDER BY o.date_id ROWS UNBOUNDED PRECEDING)
      / @Scale
    AS DECIMAL(18,8))
INTO #obv
FROM signed o;

-- 3) Upsert (delete scope → insert fresh)
DELETE fv
FROM dbo.feature_value fv
JOIN #obv x ON x.ticker_id=fv.ticker_id AND x.date_id=fv.date_id
WHERE fv.feature_id=@FeatureId;

INSERT INTO dbo.feature_value(ticker_id,date_id,feature_id,feature_value,computed_at)
SELECT x.ticker_id, x.date_id, @FeatureId, x.obv_scaled, SYSUTCDATETIME()
FROM #obv x;

-- 4) Quick check (example: BID) — no DECLARE in SELECT
SELECT c.[date], t.symbol,
       MAX(CASE WHEN fd.feature_name=N'OBV_SCALED_1e6' THEN fv.feature_value END) AS OBV_scaled
FROM dbo.feature_value fv
JOIN dbo.feature_definition fd ON fd.feature_id=fv.feature_id
JOIN dbo.ticker t ON t.ticker_id=fv.ticker_id
JOIN dbo.calendar c ON c.date_id=fv.date_id
WHERE t.symbol=N'BID' AND fd.feature_name=N'OBV_SCALED_1e6'
GROUP BY c.[date], t.symbol
ORDER BY c.[date];

