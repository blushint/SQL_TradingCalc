Here’s a professional, GitHub-ready **README.md** written in English — clean, concise, and structured for your uploaded SQL files (`createDatabase.sql`, `bilayer.sql`, `backtestProcedure.sql`).

---

# SQL-Centric Backtesting & Feature Engineering for Trading Strategies

This project explores a **SQL-first approach** to financial data engineering and backtesting, comparing SQL Server performance against Python workflows using **Vietnamese stock market data**.

---

## 1. Project Overview

The repository demonstrates how complex analytical pipelines — traditionally done in Python — can be implemented efficiently in **SQL Server** using:

* Common Table Expressions (CTEs)
* Window functions
* Stored procedures
* Layered schema design (OLTP + BI + Backtesting layers)

It supports both **feature generation** (technical indicators) and **backtesting** of trading strategies directly in SQL.

---

## 2. Repository Structure

```
/sql/
│
├── createDatabase.sql        -- Defines core tables and schema for financial market data
├── bilayer.sql               -- Creates BI star-schema (DimDate, DimTicker, DimFeature, FactMarket, FactBacktest)
├── backtestProcedure.sql     -- Implements stored procedures for strategy runs and performance logging
```

---

## 3. Data Scope

* ~160K historical records
* 30 listed Vietnamese companies
* Daily OHLCV data (Open, High, Low, Close, Volume)
* Enriched with generated features such as SMA, EMA, MACD, RSI, Bollinger Bands, ATR, OBV, and CMF

---

## 4. Key Features

* **SQL-Centric Feature Engineering:**
  All indicators are calculated directly in SQL using efficient window and aggregation techniques.

* **Performance Benchmarking:**
  SQL workflows are compared with equivalent Python pipelines to evaluate performance, I/O cost, and scalability.

* **Backtesting Framework:**
  Parameterized stored procedures simulate trading strategies and log results for analysis.

* **BI Integration:**
  Fact tables (FactMarket, FactBacktest) are designed for direct integration with BI tools like Power BI or Tableau.

---

## 5. Setup Instructions

1. Create a SQL Server database.
2. Run `createDatabase.sql` to initialize base tables.
3. Execute `bilayer.sql` to generate BI schema objects.
4. Load market data into the core tables (`price_ohlcv`, `ticker`, etc.).
5. Run `backtestProcedure.sql` to enable backtesting modules.

Optional: Export results to Power BI for dashboard visualization.

---

## 6. Example Use Cases

* Compare execution time and resource usage of SQL vs Python pipelines.
* Generate reusable stored procedures for daily feature updates.
* Integrate SQL-calculated indicators into automated trading models.
* Visualize performance metrics and trading outcomes in BI dashboards.

---

## 7. Future Improvements

* Add advanced feature sets (e.g., volatility clustering, rolling correlations).
* Implement hybrid SQL–Python orchestration using Airflow or dbt.
* Expand backtesting layer for multi-asset portfolio simulation.

---

## 8. Author

**Mai Dao**
Graduate Researcher | Data & BI Engineer

> Focus: SQL optimization, backtesting systems, financial analytics.

---

Would you like me to extend this README with a **“Performance Comparison Results”** section (SQL vs Python benchmark summary table)? It would make the project more impressive for recruiters or thesis reviewers.
