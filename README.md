# SQL-Centric Backtesting & Feature Engineering (Vietnam Stock Market)

## Overview

This project builds a **SQL-first pipeline** for financial data processing, feature engineering, and backtesting of trading strategies on Vietnamese stocks. By computing technical indicators directly in SQL Server and running strategy procedures inside the database, the system evaluates how SQL compares with typical Python workflows for quantitative research.

The solution covers schema design, data loading, feature generation using window functions, backtesting via stored procedures, and integration with a BI layer for analysis.

## Objectives

- Implement end-to-end feature engineering and backtesting directly in SQL Server  
- Compare SQL workflows with Python implementations for practicality and maintainability  
- Provide a BI-ready star schema for reporting and dashboarding  
- Ensure auditability and reproducibility of all transformations inside the database  

## Dataset

The dataset consists of historical daily OHLCV for around 30 Vietnamese tickers (~160K rows).  
Raw market data is not included due to licensing restrictions. You can load your own CSV or staging tables into the provided schema before running feature generation and backtests.

## Repository Structure

- `createDatabase.sql`: Core schema and base tables (tickers, calendar, OHLCV, reference)  
- `bilayer.sql`: BI star schema (DimDate, DimTicker, DimFeature, FactMarket, FactBacktest)  
- `backtestProcedure.sql`: Stored procedures for strategy runs and result logging  
- `README.md`: Project documentation  

## How to Run

1. Create a SQL Server database and connect with a user that can create objects.  
2. Run `createDatabase.sql` to initialize core tables.  
3. Load your market data into the base tables (e.g., `price_ohlcv`, `ticker`, `calendar`).  
4. Execute `backtestProcedure.sql` to enable strategy modules.  
5. (Optional) Run `bilayer.sql` to generate BI dimensions and fact tables & Connect Power BI or Tableau to visualize backtest results


## Technologies Used

- SQL Server (CTEs, window functions, stored procedures)  
- Python (optional benchmarking pipelines)  
- Power BI for visualization  

## Results and Findings

SQL performs efficiently for most **window-based calculations** such as SMA, EMA, volatility metrics, and rolling aggregates.  

However, **recursive or iterative logic** (e.g., MACD signal construction or multi-step backtesting loops) tends to be slower in SQL than in Python due to its procedural execution model.  

SQL offers clear traceability and determinism, making it well-suited for enterprise-grade analytics where reproducibility and governance are required.

## Limitations and Future Work

- Raw market data not included (must be user-provided).  
- Recursive logic can be further optimized using CTE batching or hybrid SQL–Python orchestration.  
- Planned extensions: additional indicators, portfolio-level backtests, and automated ingestion pipelines.  

## Acknowledgments

I would like to express my sincere thanks to **Mr. Nguyễn An Tế** for his kind guidance and support during the course of this project. His thoughtful advice helped me stay focused and approach each step with care and clarity. I am truly grateful for his time, encouragement, and the trust he placed in my efforts.

## Appendix

### Dashboard Overview

Below is an overview of the dashboards developed in this project.

### 1. Overview Dashboard
*Provides a high-level summary of data coverage, trading universe, and key portfolio metrics across selected tickers and time ranges.*

<img width="1895" height="1054" alt="image" src="https://github.com/user-attachments/assets/03bc3b53-d027-4746-a276-5273ab5292b4" />

### 2. Feature Engineering Dashboard
*Visualizes computed indicators such as SMA, EMA, MACD, RSI, Bollinger Bands, and compares SQL-based feature generation with Python workflows.*

<img width="1875" height="1052" alt="image" src="https://github.com/user-attachments/assets/561e9544-a546-41a2-9d95-92226f1ddadb" />

### 3. Backtesting Dashboard
*Displays backtest results including equity curves, performance metrics, and strategy-level comparisons between SQL and Python implementations.*

<img width="1892" height="1065" alt="image" src="https://github.com/user-attachments/assets/708fae26-7182-469d-8d4a-71af87573625" />




## License

This repository is for educational and non-commercial research purposes only.  
Ensure that any market data you use complies with its license and applicable laws.
