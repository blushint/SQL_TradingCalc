---Procedure: backetst for SMA CrossOver strategy

CREATE OR ALTER PROCEDURE dbo.usp_bt_sma20_50
  @Symbol     NVARCHAR(32),
  @StartDate  DATE,
  @EndDate    DATE,
  @InitCash   DECIMAL(19,6) = 100000000,
  @Fee        DECIMAL(9,6)  = 0.001,
  @RunId      BIGINT OUTPUT
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @tid INT = (SELECT ticker_id FROM dbo.ticker WHERE symbol=@Symbol);
  DECLARE @d0  INT = (SELECT date_id  FROM dbo.calendar WHERE [date]=@StartDate);
  DECLARE @d1  INT = (SELECT date_id  FROM dbo.calendar WHERE [date]=@EndDate);

  IF NOT EXISTS (SELECT 1 FROM dbo.strategy WHERE strategy_code=N'SMA20_50_MATCH_PY')
    INSERT dbo.strategy(strategy_code,[name])
    VALUES(N'SMA20_50_MATCH_PY',N'SMA20–SMA50 (match backtesting.py)');
  DECLARE @sid INT = (SELECT strategy_id FROM dbo.strategy WHERE strategy_code=N'SMA20_50_MATCH_PY');

  INSERT dbo.backtest_run(method,start_date_id,end_date_id,entry_rule,exit_rule,direction,fee_bps,strategy_id,created_at)
  VALUES(N'SQL',@d0,@d1,N'cross up: SMA20>SMA50',N'cross down: SMA20<SMA50',N'long',@Fee*10000,@sid,SYSUTCDATETIME());
  SET @RunId = SCOPE_IDENTITY();

  INSERT dbo.run_universe(run_id,ticker_id) VALUES(@RunId,@tid);

  IF OBJECT_ID('tempdb..#bars') IS NOT NULL DROP TABLE #bars;
  CREATE TABLE #bars(rn INT NOT NULL, date_id INT NOT NULL, px DECIMAL(38,12) NOT NULL,
                     sma20 DECIMAL(38,12) NULL, sma50 DECIMAL(38,12) NULL);

  DECLARE @fid20 INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name=N'SMA20');
  DECLARE @fid50 INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name=N'SMA50');

  ;WITH s AS (
    SELECT p.date_id,
           CAST(p.[close] AS DECIMAL(38,12)) AS px,
           sma20 = CAST(MAX(CASE WHEN fv.feature_id=@fid20 THEN fv.feature_value END) AS DECIMAL(38,12)),
           sma50 = CAST(MAX(CASE WHEN fv.feature_id=@fid50 THEN fv.feature_value END) AS DECIMAL(38,12))
    FROM dbo.price_ohlcv p
    LEFT JOIN dbo.feature_value fv
      ON fv.ticker_id=p.ticker_id AND fv.date_id=p.date_id
     AND fv.feature_id IN (@fid20,@fid50)
    WHERE p.ticker_id=@tid AND p.date_id BETWEEN @d0 AND @d1
    GROUP BY p.date_id,p.[close]
  )
  INSERT #bars(rn,date_id,px,sma20,sma50)
  SELECT ROW_NUMBER() OVER(ORDER BY date_id), date_id, px, sma20, sma50
  FROM s ORDER BY date_id;

  IF OBJECT_ID('tempdb..#seq') IS NOT NULL DROP TABLE #seq;
  SELECT b.rn,b.date_id,b.px,
         is_entry = CASE WHEN b.sma20 IS NOT NULL AND b.sma50 IS NOT NULL
                              AND LAG(b.sma20) OVER(ORDER BY b.rn) IS NOT NULL
                              AND LAG(b.sma50) OVER(ORDER BY b.rn) IS NOT NULL
                              AND b.sma20>b.sma50
                              AND LAG(b.sma20) OVER(ORDER BY b.rn) <= LAG(b.sma50) OVER(ORDER BY b.rn)
                         THEN 1 ELSE 0 END,
         is_exit  = CASE WHEN b.sma20 IS NOT NULL AND b.sma50 IS NOT NULL
                              AND LAG(b.sma20) OVER(ORDER BY b.rn) IS NOT NULL
                              AND LAG(b.sma50) OVER(ORDER BY b.rn) IS NOT NULL
                              AND b.sma20<b.sma50
                              AND LAG(b.sma20) OVER(ORDER BY b.rn) >= LAG(b.sma50) OVER(ORDER BY b.rn)
                         THEN 1 ELSE 0 END
  INTO #seq
  FROM #bars b;

  INSERT dbo.signal(run_id,ticker_id,date_id,signal,signal_type,strength,created_at)
  SELECT @RunId,@tid,s.date_id, 1,  N'SMA20_50_ENTRY', NULL, SYSUTCDATETIME()
  FROM #seq s
  WHERE s.is_entry=1
    AND NOT EXISTS (SELECT 1 FROM dbo.signal x WHERE x.run_id=@RunId AND x.ticker_id=@tid AND x.date_id=s.date_id);

  INSERT dbo.signal(run_id,ticker_id,date_id,signal,signal_type,strength,created_at)
  SELECT @RunId,@tid,s.date_id,-1, N'SMA20_50_EXIT',  NULL, SYSUTCDATETIME()
  FROM #seq s
  WHERE s.is_exit=1
    AND NOT EXISTS (SELECT 1 FROM dbo.signal x WHERE x.run_id=@RunId AND x.ticker_id=@tid AND x.date_id=s.date_id);

  IF OBJECT_ID('tempdb..#eq') IS NOT NULL DROP TABLE #eq;
  ;WITH rec AS (
    SELECT rn,date_id,px,is_entry,is_exit,
           cash = CAST(@InitCash AS DECIMAL(38,12)),
           qty  = CAST(0 AS BIGINT)
    FROM #seq WHERE rn=1
    UNION ALL
    SELECT n.rn,n.date_id,n.px,n.is_entry,n.is_exit,
           CAST(
             (CASE WHEN r.qty>0 AND n.is_exit=1
                   THEN r.cash + CAST(r.qty AS DECIMAL(38,12))*n.px*(1-@Fee)
                   ELSE r.cash END)
             -
             (CASE
               WHEN n.is_entry=1
                AND (CASE WHEN r.qty>0 AND n.is_exit=1
                          THEN r.cash + CAST(r.qty AS DECIMAL(38,12))*n.px*(1-@Fee)
                          ELSE r.cash END) >= n.px*(1+@Fee)
               THEN CAST(FLOOR(
                      (CASE WHEN r.qty>0 AND n.is_exit=1
                            THEN r.cash + CAST(r.qty AS DECIMAL(38,12))*n.px*(1-@Fee)
                            ELSE r.cash END) / (n.px*(1+@Fee))
                    ) AS DECIMAL(38,12)) * n.px * (1+@Fee)
               ELSE 0 END)
           AS DECIMAL(38,12)) AS cash,
           CAST(
             (CASE WHEN r.qty>0 AND n.is_exit=1 THEN 0 ELSE r.qty END)
             +
             (CASE
               WHEN n.is_entry=1
                AND (CASE WHEN r.qty>0 AND n.is_exit=1
                          THEN r.cash + CAST(r.qty AS DECIMAL(38,12))*n.px*(1-@Fee)
                          ELSE r.cash END) >= n.px*(1+@Fee)
               THEN FLOOR(
                      (CASE WHEN r.qty>0 AND n.is_exit=1
                            THEN r.cash + CAST(r.qty AS DECIMAL(38,12))*n.px*(1-@Fee)
                            ELSE r.cash END) / (n.px*(1+@Fee))
                    )
               ELSE 0 END)
           AS BIGINT) AS qty
    FROM rec r
    JOIN #seq n ON n.rn=r.rn+1
  )
  SELECT rn,date_id,px,cash,qty,
         equity = CAST(cash + CAST(qty AS DECIMAL(38,12))*px AS DECIMAL(38,12))
  INTO #eq
  FROM rec
  OPTION (MAXRECURSION 0);

  IF OBJECT_ID('tempdb..#q')   IS NOT NULL DROP TABLE #q;
  IF OBJECT_ID('tempdb..#ent') IS NOT NULL DROP TABLE #ent;
  IF OBJECT_ID('tempdb..#ex')  IS NOT NULL DROP TABLE #ex;
  IF OBJECT_ID('tempdb..#tr')  IS NOT NULL DROP TABLE #tr;

  SELECT e.*, LAG(e.qty) OVER(ORDER BY rn) AS prev_qty INTO #q FROM #eq e;

  SELECT q.rn,q.date_id,q.px,q.qty, ROW_NUMBER() OVER(ORDER BY q.rn) AS k
  INTO #ent
  FROM #q q
  WHERE (prev_qty IS NULL OR prev_qty=0) AND qty>0
    AND EXISTS (SELECT 1 FROM dbo.signal s WHERE s.run_id=@RunId AND s.ticker_id=@tid AND s.date_id=q.date_id AND s.signal=1);

  SELECT q.rn,q.date_id,q.px,q.prev_qty AS qty, ROW_NUMBER() OVER(ORDER BY q.rn) AS k
  INTO #ex
  FROM #q q
  WHERE prev_qty>0 AND qty=0
    AND EXISTS (SELECT 1 FROM dbo.signal s WHERE s.run_id=@RunId AND s.ticker_id=@tid AND s.date_id=q.date_id AND s.signal=-1);

  SELECT
    enter_date_id = e.date_id,
    exit_date_id  = x.date_id,
    enter_price   = CAST(e.px AS DECIMAL(19,6)),
    exit_price    = CAST(x.px AS DECIMAL(19,6)),
    qty           = e.qty,
    pnl_pct       = CAST(CASE WHEN x.px IS NULL THEN NULL ELSE x.px/NULLIF(e.px,0)-1 END AS DECIMAL(18,8)),
    pnl_net       = CAST(CASE WHEN x.px IS NULL THEN NULL
                         ELSE CAST(e.qty AS DECIMAL(38,12)) *
                              (CAST(x.px AS DECIMAL(38,12))*(1-@Fee)
                               - CAST(e.px AS DECIMAL(38,12))*(1+@Fee))
                       END AS DECIMAL(38,12))
  INTO #tr
  FROM #ent e
  LEFT JOIN #ex x ON x.k=e.k
  ORDER BY e.rn;

  INSERT dbo.trade(run_id,ticker_id,enter_date_id,exit_date_id,enter_price,exit_price,qty,side,pnl_pct,created_at)
  SELECT @RunId,@tid,enter_date_id,exit_date_id,enter_price,exit_price,qty,N'long',pnl_pct,SYSUTCDATETIME()
  FROM #tr
  WHERE exit_date_id IS NOT NULL;

  DECLARE @equity_final DECIMAL(38,12) = (SELECT TOP 1 equity FROM #eq ORDER BY rn DESC);
  DECLARE @eq_peak      DECIMAL(38,12) = (SELECT MAX(equity) FROM #eq);

  DECLARE @max_dd DECIMAL(38,12) =
  (
    SELECT MIN(e/NULLIF(p,0)-1)
    FROM (SELECT equity AS e, MAX(equity) OVER(ORDER BY rn ROWS UNBOUNDED PRECEDING) AS p FROM #eq) z
  );

  DECLARE @trades  INT = (SELECT COUNT(*) FROM #tr WHERE exit_date_id IS NOT NULL);
  DECLARE @winrate DECIMAL(18,8) =
    (SELECT AVG(CASE WHEN pnl_net > 0 THEN 1.0 ELSE 0.0 END)
     FROM #tr WHERE exit_date_id IS NOT NULL);

  DECLARE @total_ret DECIMAL(38,12) = @equity_final/@InitCash - 1;

  INSERT dbo.portfolio_results
    (run_id,total_return,equity_final,equity_peak,max_drawdown,win_rate,trades_count,created_at)
  VALUES
    (@RunId,
     CAST(@total_ret    AS DECIMAL(19,6)),
     CAST(@equity_final AS DECIMAL(19,6)),
     CAST(@eq_peak      AS DECIMAL(19,6)),
     CAST(@max_dd       AS DECIMAL(18,8)),
     CAST(@winrate      AS DECIMAL(18,8)),
     @trades,
     SYSUTCDATETIME());

  SELECT @RunId AS run_id;
END
GO

--- Execute Procedure SMA CrossOver

DECLARE @rid BIGINT;

EXEC dbo.usp_bt_sma20_50
  @Symbol    = N'VNM',
  @StartDate = '2006-01-01',
  @EndDate   = '2025-12-31',
  @InitCash  = 100000000,
  @Fee       = 0.001,
  @RunId     = @rid OUTPUT;

SELECT * FROM dbo.portfolio_results WHERE run_id=@rid;

SELECT trade_id,enter_date_id,exit_date_id,enter_price,exit_price,qty,pnl_pct
FROM dbo.trade WHERE run_id=@rid ORDER BY trade_id;

;WITH t AS(
  SELECT trade_id, enter_date_id, exit_date_id, enter_price, exit_price, qty, pnl_pct,
         ROW_NUMBER() OVER(ORDER BY trade_id) rn, COUNT(*) OVER() n
  FROM dbo.trade WHERE run_id=@rid
)
SELECT 'first3' AS bucket,* FROM t WHERE rn<=3
UNION ALL
SELECT 'last3',* FROM t WHERE rn>n-3
ORDER BY rn;


---Procedure: BackTest for RSI 

CREATE OR ALTER PROCEDURE dbo.usp_bt_rsi_wilder
  @Symbol     NVARCHAR(32),
  @StartDate  DATE,
  @EndDate    DATE,
  @InitCash   DECIMAL(19,6) = 100000000,
  @Fee        DECIMAL(9,6)  = 0.001,
  @OS         DECIMAL(9,4)  = 30,
  @OB         DECIMAL(9,4)  = 70,
  @RunId      BIGINT OUTPUT
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @tid INT = (SELECT ticker_id FROM dbo.ticker WHERE symbol=@Symbol);
  DECLARE @d0  INT = (SELECT date_id  FROM dbo.calendar WHERE [date]=@StartDate);
  DECLARE @d1  INT = (SELECT date_id  FROM dbo.calendar WHERE [date]=@EndDate);

  IF NOT EXISTS (SELECT 1 FROM dbo.strategy WHERE strategy_code=N'RSI_Wilder_L_MATCH_PY')
    INSERT dbo.strategy(strategy_code,[name]) VALUES(N'RSI_Wilder_L_MATCH_PY',N'RSI Wilder Long (match backtesting.py)');
  DECLARE @sid INT = (SELECT strategy_id FROM dbo.strategy WHERE strategy_code=N'RSI_Wilder_L_MATCH_PY');

  INSERT dbo.backtest_run(method,start_date_id,end_date_id,entry_rule,exit_rule,direction,fee_bps,strategy_id,created_at)
  VALUES(N'SQL',@d0,@d1,N'RSI<OS BUY',N'RSI>OB SELL',N'long',@Fee*10000,@sid,SYSUTCDATETIME());
  SET @RunId = SCOPE_IDENTITY();
  INSERT dbo.run_universe(run_id,ticker_id) VALUES(@RunId,@tid);

  IF OBJECT_ID('tempdb..#bars') IS NOT NULL DROP TABLE #bars;
  CREATE TABLE #bars(rn INT NOT NULL, date_id INT NOT NULL, px DECIMAL(38,12) NOT NULL, rsi DECIMAL(38,12) NULL);

  DECLARE @fid INT = (SELECT feature_id FROM dbo.feature_definition WHERE feature_name=N'RSI14_Wilder' AND [version]=N'1.0');
  IF @fid IS NULL BEGIN RAISERROR(N'Missing RSI14_Wilder.',16,1); RETURN; END;

  ;WITH s AS(
    SELECT p.date_id,
           CAST(p.[close] AS DECIMAL(38,12)) AS px,
           CAST(fv.feature_value AS DECIMAL(38,12)) AS rsi
    FROM dbo.price_ohlcv p
    JOIN dbo.feature_value fv ON fv.ticker_id=@tid AND fv.date_id=p.date_id AND fv.feature_id=@fid
    WHERE p.ticker_id=@tid AND p.date_id BETWEEN @d0 AND @d1
  )
  INSERT #bars(rn,date_id,px,rsi)
  SELECT ROW_NUMBER() OVER(ORDER BY date_id), date_id, px, rsi
  FROM s ORDER BY date_id;

  IF NOT EXISTS (SELECT 1 FROM #bars)
  BEGIN
    INSERT dbo.portfolio_results(run_id,total_return,equity_final,equity_peak,max_drawdown,win_rate,trades_count,created_at)
    VALUES(@RunId,0,@InitCash,@InitCash,0,0,0,SYSUTCDATETIME());
    SELECT @RunId AS run_id; RETURN;
  END;

  IF OBJECT_ID('tempdb..#seq') IS NOT NULL DROP TABLE #seq;
  SELECT rn,date_id,px,
         is_entry = CASE WHEN rsi < @OS THEN 1 ELSE 0 END,
         is_exit  = CASE WHEN rsi > @OB THEN 1 ELSE 0 END
  INTO #seq FROM #bars;

  -- write signals
  INSERT dbo.signal(run_id,ticker_id,date_id,signal,signal_type,created_at)
  SELECT @RunId,@tid,date_id, 1,N'RSI_OS',SYSUTCDATETIME() FROM #seq WHERE is_entry=1
  AND NOT EXISTS (SELECT 1 FROM dbo.signal s WHERE s.run_id=@RunId AND s.ticker_id=@tid AND s.date_id=#seq.date_id);
  INSERT dbo.signal(run_id,ticker_id,date_id,signal,signal_type,created_at)
  SELECT @RunId,@tid,date_id,-1,N'RSI_OB',SYSUTCDATETIME() FROM #seq WHERE is_exit=1
  AND NOT EXISTS (SELECT 1 FROM dbo.signal s WHERE s.run_id=@RunId AND s.ticker_id=@tid AND s.date_id=#seq.date_id);

  IF OBJECT_ID('tempdb..#eq') IS NOT NULL DROP TABLE #eq;
  ;WITH rec AS (
    SELECT rn,date_id,px,is_entry,is_exit,
           cash=CAST(@InitCash AS DECIMAL(38,12)), qty=CAST(0 AS BIGINT)
    FROM #seq WHERE rn=1
    UNION ALL
    SELECT n.rn,n.date_id,n.px,n.is_entry,n.is_exit,
           CAST(
             (CASE WHEN r.qty>0 AND n.is_exit=1 THEN r.cash + CAST(r.qty AS DECIMAL(38,12))*n.px*(1-@Fee) ELSE r.cash END)
             -
             (CASE WHEN n.is_entry=1
                   AND (CASE WHEN r.qty>0 AND n.is_exit=1 THEN r.cash + CAST(r.qty AS DECIMAL(38,12))*n.px*(1-@Fee) ELSE r.cash END) >= n.px*(1+@Fee)
                   THEN CAST(FLOOR((CASE WHEN r.qty>0 AND n.is_exit=1 THEN r.cash + CAST(r.qty AS DECIMAL(38,12))*n.px*(1-@Fee) ELSE r.cash END)/(n.px*(1+@Fee))) AS DECIMAL(38,12))*n.px*(1+@Fee)
                   ELSE 0 END)
           AS DECIMAL(38,12)) AS cash,
           CAST(
             (CASE WHEN r.qty>0 AND n.is_exit=1 THEN 0 ELSE r.qty END)
             +
             (CASE WHEN n.is_entry=1
                   AND (CASE WHEN r.qty>0 AND n.is_exit=1 THEN r.cash + CAST(r.qty AS DECIMAL(38,12))*n.px*(1-@Fee) ELSE r.cash END) >= n.px*(1+@Fee)
                   THEN FLOOR((CASE WHEN r.qty>0 AND n.is_exit=1 THEN r.cash + CAST(r.qty AS DECIMAL(38,12))*n.px*(1-@Fee) ELSE r.cash END)/(n.px*(1+@Fee)))
                   ELSE 0 END)
           AS BIGINT) AS qty
    FROM rec r JOIN #seq n ON n.rn=r.rn+1
  )
  SELECT rn,date_id,px,cash,qty,
         equity=CAST(cash+CAST(qty AS DECIMAL(38,12))*px AS DECIMAL(38,12))
  INTO #eq FROM rec OPTION (MAXRECURSION 0);

  IF OBJECT_ID('tempdb..#q') IS NOT NULL DROP TABLE #q;
  IF OBJECT_ID('tempdb..#ent') IS NOT NULL DROP TABLE #ent;
  IF OBJECT_ID('tempdb..#ex') IS NOT NULL DROP TABLE #ex;
  IF OBJECT_ID('tempdb..#tr') IS NOT NULL DROP TABLE #tr;

  SELECT e.*, LAG(e.qty) OVER(ORDER BY rn) AS prev_qty INTO #q FROM #eq e;

  SELECT rn,date_id,px,qty, ROW_NUMBER() OVER(ORDER BY rn) AS k
  INTO #ent
  FROM #q
  WHERE (prev_qty IS NULL OR prev_qty=0) AND qty>0
    AND EXISTS (SELECT 1 FROM dbo.signal s WHERE s.run_id=@RunId AND s.ticker_id=@tid AND s.date_id=#q.date_id AND s.signal=1);

  SELECT rn,date_id,px,prev_qty AS qty, ROW_NUMBER() OVER(ORDER BY rn) AS k
  INTO #ex
  FROM #q
  WHERE prev_qty>0 AND qty=0
    AND EXISTS (SELECT 1 FROM dbo.signal s WHERE s.run_id=@RunId AND s.ticker_id=@tid AND s.date_id=#q.date_id AND s.signal=-1);

  SELECT
    enter_date_id=e.date_id,
    exit_date_id =x.date_id,
    enter_price  =CAST(e.px AS DECIMAL(19,6)),
    exit_price   =CAST(x.px AS DECIMAL(19,6)),
    qty          =e.qty,
    pnl_pct      =CAST(CASE WHEN x.px IS NULL THEN NULL ELSE x.px/NULLIF(e.px,0)-1 END AS DECIMAL(18,8))
  INTO #tr
  FROM #ent e
  LEFT JOIN #ex x ON x.k=e.k
  ORDER BY e.rn;

  INSERT dbo.trade(run_id,ticker_id,enter_date_id,exit_date_id,enter_price,exit_price,qty,side,pnl_pct,created_at)
  SELECT @RunId,@tid,enter_date_id,exit_date_id,enter_price,exit_price,qty,N'long',pnl_pct,SYSUTCDATETIME()
  FROM #tr
  WHERE exit_date_id IS NOT NULL;

  DECLARE @equity_final DECIMAL(38,12)=(SELECT TOP 1 equity FROM #eq ORDER BY rn DESC);
  DECLARE @eq_peak      DECIMAL(38,12)=(SELECT MAX(equity) FROM #eq);
  DECLARE @max_dd DECIMAL(38,12)=(
    SELECT MIN(e/NULLIF(p,0)-1)
    FROM (SELECT equity AS e, MAX(equity) OVER(ORDER BY rn ROWS UNBOUNDED PRECEDING) AS p FROM #eq) z
  );
  DECLARE @trades INT=(SELECT COUNT(*) FROM #tr);
  DECLARE @winrate DECIMAL(18,8)=(SELECT AVG(CASE WHEN pnl_pct>0 THEN 1.0 ELSE 0.0 END) FROM #tr WHERE pnl_pct IS NOT NULL);
  DECLARE @total_ret DECIMAL(38,12)=@equity_final/@InitCash - 1;

  INSERT dbo.portfolio_results(run_id,total_return,equity_final,equity_peak,max_drawdown,win_rate,trades_count,created_at)
  VALUES(@RunId,CAST(@total_ret AS DECIMAL(19,6)),CAST(@equity_final AS DECIMAL(19,6)),
         CAST(@eq_peak AS DECIMAL(19,6)),CAST(@max_dd AS DECIMAL(18,8)),CAST(@winrate AS DECIMAL(18,8)),@trades,SYSUTCDATETIME());

  SELECT @RunId AS run_id;
END
GO


-- Execute: RSI Wilder
SET NOCOUNT ON;

DECLARE @rid BIGINT;

EXEC dbo.usp_bt_rsi_wilder
  @Symbol    = N'VNM',
  @StartDate = '2006-01-01',
  @EndDate   = '2025-12-31',
  @InitCash  = 100000000,
  @Fee       = 0.001,
  @OS        = 30,
  @OB        = 70,
  @RunId     = @rid OUTPUT;

SELECT run_id = @rid;
SELECT *
FROM dbo.trade
WHERE run_id = @rid
ORDER BY enter_date_id;
SELECT *
FROM dbo.portfolio_results
WHERE run_id = @rid;



--- BackTest for BBands
CREATE OR ALTER PROCEDURE dbo.usp_bt_bband_long_from_feature
  @Symbol     NVARCHAR(32),
  @StartDate  DATE,
  @EndDate    DATE,
  @InitCash   DECIMAL(19,6) = 100000000,
  @Fee        DECIMAL(9,6)  = 0.001,
  @UseLower   BIT           = 0,
  @RunId      BIGINT OUTPUT
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @tid INT = (SELECT ticker_id FROM dbo.ticker WHERE symbol=@Symbol);
  IF @tid IS NULL BEGIN RAISERROR(N'Symbol not found',16,1); RETURN; END;

  DECLARE @d0 INT = (SELECT date_id FROM dbo.calendar WHERE [date]=@StartDate);
  DECLARE @d1 INT = (SELECT date_id FROM dbo.calendar WHERE [date]=@EndDate);

  IF NOT EXISTS (SELECT 1 FROM dbo.strategy WHERE strategy_code=N'BB_LONG_DB')
    INSERT dbo.strategy(strategy_code,[name]) VALUES(N'BB_LONG_DB',N'Bollinger Long breakout');

  DECLARE @sid INT = (SELECT strategy_id FROM dbo.strategy WHERE strategy_code=N'BB_LONG_DB');

  INSERT dbo.backtest_run(method,start_date_id,end_date_id,entry_rule,exit_rule,direction,fee_bps,strategy_id,created_at)
  VALUES(N'SQL',@d0,@d1,N'Close>BB_UPPER20 BUY',N'Close<BB_MID/LOWER SELL',N'long',@Fee*10000,@sid,SYSUTCDATETIME());
  SET @RunId = SCOPE_IDENTITY();

  INSERT dbo.run_universe(run_id,ticker_id) VALUES(@RunId,@tid);

  IF OBJECT_ID('tempdb..#bars') IS NOT NULL DROP TABLE #bars;
  SELECT c.date_id,
         px  = CAST(p.[close] AS DECIMAL(38,12)),
         mid = MAX(CASE WHEN f.feature_name=N'BB_MID20'   THEN CAST(v.feature_value AS DECIMAL(38,12)) END),
         up  = MAX(CASE WHEN f.feature_name=N'BB_UPPER20' THEN CAST(v.feature_value AS DECIMAL(38,12)) END),
         lo  = MAX(CASE WHEN f.feature_name=N'BB_LOWER20' THEN CAST(v.feature_value AS DECIMAL(38,12)) END)
  INTO #bars
  FROM dbo.price_ohlcv p
  JOIN dbo.calendar c           ON c.date_id=p.date_id
  JOIN dbo.feature_value v      ON v.ticker_id=p.ticker_id AND v.date_id=p.date_id
  JOIN dbo.feature_definition f ON f.feature_id=v.feature_id
  WHERE p.ticker_id=@tid
    AND f.feature_name IN (N'BB_MID20',N'BB_UPPER20',N'BB_LOWER20')
    AND c.date_id BETWEEN @d0 AND @d1
  GROUP BY c.date_id,p.[close]
  ORDER BY c.date_id;

  IF NOT EXISTS (SELECT 1 FROM #bars)
  BEGIN
    INSERT dbo.portfolio_results(run_id,total_return,equity_final,equity_peak,max_drawdown,win_rate,trades_count,created_at)
    VALUES(@RunId,0,@InitCash,@InitCash,0,0,0,SYSUTCDATETIME());
    SELECT @RunId AS run_id; RETURN;
  END;

  -- signals
  INSERT dbo.signal(run_id,ticker_id,date_id,signal,signal_type,created_at)
  SELECT @RunId,@tid,b.date_id,1,N'BB_UPPER_BREAK',SYSUTCDATETIME()
  FROM #bars b
  WHERE b.px>b.up
    AND NOT EXISTS (SELECT 1 FROM dbo.signal s WHERE s.run_id=@RunId AND s.ticker_id=@tid AND s.date_id=b.date_id);

  INSERT dbo.signal(run_id,ticker_id,date_id,signal,signal_type,created_at)
  SELECT @RunId,@tid,b.date_id,-1,CASE WHEN @UseLower=1 THEN N'BB_LOWER_EXIT' ELSE N'BB_MID_EXIT' END,SYSUTCDATETIME()
  FROM #bars b
  WHERE (@UseLower=1 AND b.px<b.lo) OR (@UseLower=0 AND b.px<b.mid)
    AND NOT EXISTS (SELECT 1 FROM dbo.signal s WHERE s.run_id=@RunId AND s.ticker_id=@tid AND s.date_id=b.date_id AND s.signal=-1);

  -- sim
  IF OBJECT_ID('tempdb..#eq') IS NOT NULL DROP TABLE #eq;
  CREATE TABLE #eq(rn INT IDENTITY(1,1), date_id INT, px DECIMAL(38,12), cash DECIMAL(38,12), qty BIGINT, equity DECIMAL(38,12));
  DECLARE @cash DECIMAL(38,12)=@InitCash, @qty BIGINT=0, @date_id INT, @px DECIMAL(38,12), @mid DECIMAL(38,12), @up DECIMAL(38,12), @lo DECIMAL(38,12);

  DECLARE cur CURSOR FOR SELECT date_id,px,mid,up,lo FROM #bars ORDER BY date_id;
  OPEN cur; FETCH NEXT FROM cur INTO @date_id,@px,@mid,@up,@lo;
  WHILE @@FETCH_STATUS=0
  BEGIN
    IF @qty>0 AND ( (@UseLower=0 AND @px<@mid) OR (@UseLower=1 AND @px<@lo) )
    BEGIN SET @cash=@cash+@qty*@px*(1-@Fee); SET @qty=0; END;

    IF @qty=0 AND @px>@up
    BEGIN
      DECLARE @size BIGINT=FLOOR(@cash/NULLIF(@px*(1+@Fee),0));
      IF @size>0 BEGIN SET @qty=@size; SET @cash=@cash-@size*@px*(1+@Fee); END
    END;

    INSERT #eq(date_id,px,cash,qty,equity) VALUES(@date_id,@px,@cash,@qty,@cash+@qty*@px);
    FETCH NEXT FROM cur INTO @date_id,@px,@mid,@up,@lo;
  END
  CLOSE cur; DEALLOCATE cur;

  -- derive trades tied to signals
  IF OBJECT_ID('tempdb..#q') IS NOT NULL DROP TABLE #q;
  SELECT e.rn,e.date_id,e.px,e.qty, prev_qty=p.qty
  INTO #q
  FROM #eq e LEFT JOIN #eq p ON p.rn=e.rn-1;

  IF OBJECT_ID('tempdb..#ent') IS NOT NULL DROP TABLE #ent;
  SELECT rn,date_id,px,qty, ROW_NUMBER() OVER(ORDER BY rn) AS k
  INTO #ent
  FROM #q
  WHERE (prev_qty IS NULL OR prev_qty=0) AND qty>0
    AND EXISTS (SELECT 1 FROM dbo.signal s WHERE s.run_id=@RunId AND s.ticker_id=@tid AND s.date_id=#q.date_id AND s.signal=1);

  IF OBJECT_ID('tempdb..#ex') IS NOT NULL DROP TABLE #ex;
  SELECT rn,date_id,px,qty=prev_qty, ROW_NUMBER() OVER(ORDER BY rn) AS k
  INTO #ex
  FROM #q
  WHERE prev_qty>0 AND qty=0
    AND EXISTS (SELECT 1 FROM dbo.signal s WHERE s.run_id=@RunId AND s.ticker_id=@tid AND s.date_id=#q.date_id AND s.signal=-1);

  IF OBJECT_ID('tempdb..#tr') IS NOT NULL DROP TABLE #tr;
  SELECT enter_date_id=e.date_id, exit_date_id=x.date_id,
         enter_price=CAST(e.px AS DECIMAL(19,6)),
         exit_price =CAST(x.px AS DECIMAL(19,6)),
         qty=e.qty,
         pnl_pct=CAST(CASE WHEN x.px IS NULL THEN NULL ELSE x.px/NULLIF(e.px,0)-1 END AS DECIMAL(18,8))
  INTO #tr
  FROM #ent e LEFT JOIN #ex x ON x.k=e.k
  ORDER BY e.rn;

  INSERT dbo.trade(run_id,ticker_id,enter_date_id,exit_date_id,enter_price,exit_price,qty,side,pnl_pct,created_at)
  SELECT @RunId,@tid,enter_date_id,exit_date_id,enter_price,exit_price,qty,N'long',pnl_pct,SYSUTCDATETIME()
  FROM #tr
  WHERE exit_date_id IS NOT NULL;

  -- portfolio
  DECLARE @equity_final DECIMAL(38,12)=(SELECT TOP 1 equity FROM #eq ORDER BY rn DESC);
  DECLARE @eq_peak      DECIMAL(38,12)=(SELECT MAX(equity) FROM #eq);
  DECLARE @max_dd DECIMAL(38,12)=(
    SELECT MIN(e/NULLIF(p,0)-1)
    FROM (SELECT equity AS e, MAX(equity) OVER(ORDER BY rn ROWS UNBOUNDED PRECEDING) AS p FROM #eq) z
  );
  DECLARE @trades INT=(SELECT COUNT(*) FROM #tr);
  DECLARE @winrate DECIMAL(18,8)=(SELECT AVG(CASE WHEN pnl_pct>0 THEN 1.0 ELSE 0.0 END) FROM #tr WHERE pnl_pct IS NOT NULL);
  DECLARE @total_ret DECIMAL(38,12)=@equity_final/@InitCash - 1;

  INSERT dbo.portfolio_results(run_id,total_return,equity_final,equity_peak,max_drawdown,win_rate,trades_count,created_at)
  VALUES(@RunId,CAST(@total_ret AS DECIMAL(19,6)),CAST(@equity_final AS DECIMAL(19,6)),
         CAST(@eq_peak AS DECIMAL(19,6)),CAST(@max_dd AS DECIMAL(18,8)),CAST(@winrate AS DECIMAL(18,8)),@trades,SYSUTCDATETIME());

  SELECT @RunId AS run_id;
END
GO

--- execute BBands

DECLARE @rid BIGINT;
EXEC dbo.usp_bt_bband_long_from_feature
  @Symbol = N'VNM',
  @StartDate='2006-01-01',
  @EndDate  ='2025-12-31',
  @InitCash =100000000,
  @Fee      =0.001,
  @UseLower =0,          -- 0: exit < BB_MID20 ; 1: exit < BB_LOWER20
  @RunId    =@rid OUTPUT;

SELECT * FROM dbo.portfolio_results WHERE run_id=@rid;
SELECT trade_id,enter_date_id,exit_date_id,enter_price,exit_price,qty,pnl_pct
FROM dbo.trade WHERE run_id=@rid ORDER BY trade_id;

select * from feature_definition