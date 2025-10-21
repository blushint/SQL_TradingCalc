# SQL-Centric Backtesting & Feature Engineering (Vietnam Stock Market)
## Overview

This project builds a SQL-first pipeline for financial data processing, feature engineering, and backtesting of trading strategies on Vietnamese stocks. It demonstrates how far SQL Server can go for analytics typically handled in Python, and benchmarks SQL workflows against equivalent Python implementations.

The system processes ~160,000 historical records from 30 listed companies (daily OHLCV). Technical indicators are computed directly in SQL using CTEs and window functions; backtesting is executed via stored procedures with run-level logging for analysis.

## Objectives

Implement end-to-end feature engineering and backtesting directly in SQL Server

Compare performance and maintainability of SQL workflows against Python pipelines

Provide a BI-ready schema for downstream analytics and dashboards

Ensure auditability and reproducibility of all transformation steps inside the database

## Dataset

Data consists of historical daily OHLCV for ~30 Vietnamese tickers. The repository does not include raw market data due to licensing constraints. You can load your own data (CSV or staging tables) into the provided schema before running feature generation and backtests.

## Repository Structure
createDatabase.sql   -- Core schema and base tables (tickers, calendar, OHLCV, reference)  
bilayer.sql          -- BI star schema (DimDate, DimTicker, DimFeature, FactMarket, FactBacktest)  
backtestProcedure.sql -- Stored procedures for strategy runs and result logging  
README.md            -- Project documentation

## How to Run

Create a SQL Server database and connect with a user that can create objects.

Execute createDatabase.sql to create core tables and reference objects.

Load historical OHLCV data into the core tables.

Execute backtestProcedure.sql to enable strategy execution and logging.

(Optional) 
Execute bilayer.sql to build BI dimensions and fact tables.

Connect Power BI/Tableau to the BI layer (FactMarket, FactBacktest) for reporting.

## Technologies Used

SQL Server (CTEs, window functions, stored procedures)

Python (benchmark notebooks/pipelines for comparison, optional)

BI tools (Power BI/Tableau) for visualization on top of the BI schema

## Results and Findings

SQL performs efficiently for window-based calculations (e.g., SMA/EMA, volatility metrics, rolling aggregates) and works well for indicator feature engineering using window functions.

Recursive or iterative logic (e.g., multi-step signal construction or loop-style backtesting) generally runs slower in SQL than in Python due to procedural patterns.

SQL offers strong traceability and determinism: every step is auditable within the database, which benefits governance, debugging, and reproducibility in enterprise settings.

## Limitations and Future Work

Raw data is not included; users must supply their own historical OHLCV.

Recursive procedures can be optimized further (batching in CTEs, memoization patterns).

A hybrid orchestration (SQL for window features, Python for iterative steps) may improve overall throughput.

Planned additions: more indicators (rolling correlations, regimes), portfolio-level backtests, and automated data ingestion.

## Acknowledgments

I would like to sincerely thank Mr. Nguyễn An Tế for his kind guidance and support during the course of this project. His thoughtful advice helped me stay focused and approach each step with care and clarity. I am truly grateful for his time, encouragement, and the trust he placed in my efforts.

License
This repository is for educational and non-commercial research purposes only. The authors do not publish, distribute, or license any dataset. Use of the crawling script must comply with the source website’s terms and applicable laws.
