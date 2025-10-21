## SQL-Centric Backtesting and Feature Engineering

This project demonstrates how SQL Server can be used as the primary engine for financial data processing, feature engineering, and backtesting of trading strategies. It focuses on building a complete analytical pipeline for Vietnamese stock market data and benchmarking its performance against Python-based workflows.

## Overview

The system handles around 160,000 historical records from 30 listed companies.
It uses structured SQL techniques such as CTEs, window functions, and stored procedures to extract, transform, and compute technical indicators directly inside the database.
The main goal is to evaluate whether a SQL-first architecture can deliver comparable speed and scalability to Python pipelines for quantitative research and backtesting.

Repository Structure
createDatabase.sql        – defines the core schema and base tables  
bilayer.sql               – builds the BI star schema (DimDate, DimTicker, DimFeature, FactMarket, FactBacktest)  
backtestProcedure.sql     – includes stored procedures for running strategies and logging performance results

## Key Features

Fully SQL-based implementation of feature generation, including indicators such as SMA, EMA, MACD, RSI, Bollinger Bands, ATR, OBV, and CMF.

Comparative benchmarking between SQL and Python to assess execution time, logical reads, and resource usage.

Backtesting procedures that simulate trading strategies and store run-level outputs for analysis.

BI-friendly schema design that integrates smoothly with Power BI or other visualization tools.

## How to Use

Create a SQL Server database.

Run createDatabase.sql to create base tables.

Load historical OHLCV data into the tables.

Run backtestProcedure.sql to enable the backtesting module.

Run bilayer.sql to generate the BI schema.

(Optional) Connect Power BI or another BI tool to visualize the results.

### Example Use Cases

Build a reproducible, SQL-native backtesting framework.

Measure SQL performance versus Python in real-world data pipelines.

Automate feature updates and backtest runs for trading analytics.

Integrate structured financial data into enterprise BI systems.

### Results and Findings

Testing showed that SQL performs efficiently for most window-based calculations such as moving averages (SMA, EMA), volatility indicators, and range-based aggregations.
However, recursive or iterative computations—such as MACD signal lines or multi-step backtesting logic—take longer to execute in SQL compared to Python due to their procedural nature.

While Python pipelines offer greater flexibility for complex loops, the SQL approach provides strong traceability, consistency, and transparency.


