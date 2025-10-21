SQL-Centric Backtesting and Feature Engineering

This project demonstrates how SQL Server can be used as the primary engine for financial data processing, feature engineering, and backtesting of trading strategies. It focuses on building a complete analytical pipeline for Vietnamese stock market data and benchmarking its performance against Python-based workflows.

Overview

The system handles around 160,000 historical records from 30 listed companies. It uses structured SQL techniques such as CTEs, window functions, and stored procedures to extract, transform, and compute technical indicators directly inside the database.
The main goal is to evaluate whether a SQL-first architecture can deliver comparable speed and scalability to Python pipelines for quantitative research and backtesting.

Repository Structure
createDatabase.sql        – defines the core schema and base tables  
bilayer.sql               – builds the BI star schema (DimDate, DimTicker, DimFeature, FactMarket, FactBacktest)  
backtestProcedure.sql     – includes stored procedures for running strategies and logging performance results

Key Features

Fully SQL-based implementation of feature generation, including indicators such as SMA, EMA, MACD, RSI, Bollinger Bands, ATR, OBV, and CMF.

Comparative benchmarking between SQL and Python to assess execution time, logical reads, and resource usage.

Backtesting procedures that simulate trading strategies and store run-level outputs for analysis.

A BI-friendly schema design that integrates smoothly with Power BI or other visualization tools.

How to Use

Create a SQL Server database.

Run createDatabase.sql to create base tables.

Run bilayer.sql to generate the BI schema.

Load your historical OHLCV data into the database.

Run backtestProcedure.sql to enable the backtesting module.

Optionally, connect Power BI to visualize the results.

Use Cases

Building a reproducible and database-native backtesting framework.

Measuring SQL performance versus Python in real-world data pipelines.

Automating feature updates and backtest runs for daily trading analytics.

Integrating structured financial data into enterprise BI systems.

Author

Mai Dao
Graduate Researcher / Data & BI Engineer
Focus areas: SQL optimization, feature engineering, backtesting frameworks, and data-driven analytics.
