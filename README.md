# 🍔 Enterprise Food Aggregator Data Platform

[![Snowflake](https://img.shields.io/badge/Snowflake-29B5E8?logo=snowflake&logoColor=white)](https://snowflake.com)
[![Azure](https://img.shields.io/badge/Azure-0078D4?logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com)
[![Python](https://img.shields.io/badge/Python-3.10-blue?logo=python)](https://python.org)
[![Streamlit](https://img.shields.io/badge/Streamlit-FF4B4B?logo=streamlit&logoColor=white)](https://streamlit.io)

An enterprise-grade, Snowflake-native data platform for a food delivery
ecosystem modeled after Swiggy/Zomato — demonstrating production-grade
data engineering across ingestion, transformation, governance, and analytics.

---

## 🏗️ Architecture

Azure Event Hubs (streaming)          ADLS Gen2 (batch files)

↓                                      ↓

Snowpipe Streaming              Snowpipe (auto-ingest)

↓                                      ↓

┌─────────────────────────────────────────────┐

│           BRONZE LAYER (raw)                │

│  RAW_ORDERS · RAW_PAYMENTS · RAW_CUSTOMERS  │

│  RAW_RESTAURANTS · RAW_AGENTS · RAW_REVIEWS │

└──────────────────┬──────────────────────────┘

│ Snowflake Streams + Tasks

▼

┌─────────────────────────────────────────────┐

│           SILVER LAYER (clean)              │

│  Null checks · Type casting · Dedup         │

│  Status validation · Quarantine routing     │

└──────────────────┬──────────────────────────┘

│ Snowflake Streams + Tasks

▼

┌─────────────────────────────────────────────┐

│            GOLD LAYER (analytics)           │

│  Star Schema · SCD Type 2 · Hourly KPIs     │

│  FACT_ORDERS · FACT_PAYMENTS · 4 DIMS       │

└──────────────────┬──────────────────────────┘

│

▼

Streamlit Dashboard

(Live KPIs · Revenue Trends · City Analysis)

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Cloud Data Warehouse | Snowflake (Standard Edition) |
| Cloud Storage | Azure Data Lake Storage Gen2 |
| Batch Ingestion | Snowpipe (SAS token authentication) |
| Transformation | Snowflake SQL Stored Procedures + Snowpark Python |
| Orchestration | Snowflake Streams + Tasks |
| Dimensional Model | Star Schema with SCD Type 2 |
| Dashboard | Streamlit in Snowflake |
| Data Generation | Python + Faker |

---

## 📊 Key Features

- **Medallion Architecture** — Bronze → Silver → Gold with progressive data quality
- **Real-time + Batch** — Event Hubs streaming and ADLS batch ingestion
- **Data Quality Framework** — 6 validation rule types, quarantine routing,
  ~34K bad records detected across 6 tables
- **SCD Type 2** — Full historical tracking on DIM_CUSTOMER, DIM_RESTAURANT,
  DIM_DELIVERY with surrogate keys and effective date ranges
- **Star Schema** — FACT_ORDERS (13.7K) + FACT_PAYMENTS (14K) + 4 dimensions
- **Live Dashboard** — 7 KPI cards, revenue trend, city heatmap,
  payment breakdown, cuisine performance

---

## 📁 Repository Structure

├── data_generation/     Python + Faker data generator scripts

├── sql/

│   ├── 01_setup/        Database, schema, warehouse, file format DDL

│   ├── 02_bronze/       Bronze tables, Snowpipes, quarantine table

│   ├── 03_silver/       Silver tables, stored procedures, data quality

│   ├── 04_gold/         Star Schema DDL, SCD2 MERGE, aggregation procs

│   └── 05_automation/   Streams and Tasks for pipeline automation

├── streamlit_dashboard/           Live KPI dashboard code

└── screenshots/               Dashboard screenshots

---

## 🚀 Setup Instructions

### Prerequisites
- Snowflake account (Standard edition or higher)
- Azure subscription (ADLS Gen2)
- Python 3.10+

### Steps
1. Clone this repository
2. Run SQL scripts in order (01_setup → 02_bronze → ...)
3. Run `data_generation/run_all.py` to generate synthetic data
4. Upload generated files to your ADLS container
5. Run the backfill COPY INTO commands in `sql/02_bronze/`
6. Execute Silver and Gold procedures for initial load
7. Create Streamlit app in Snowflake and paste `streamlit_dashbaord/streamlit_app.py`

---

## 📈 Dataset

| Table | Bronze Rows | Silver Rows | Quality Rule |
|---|---|---|---|
| Orders | 105,000 | 13,704 | Status enum, amount > 0, FK validation |
| Customers | 500,000 | 472,168 | Email format, segment validation |
| Restaurants | 50,000 | 48,248 | Rating 0–5, commission ≥ 0 |
| Agents | 100,000 | 96,051 | Rating 0–5, vehicle type enum |
| Payments | 105,000 | 14,044 | Method + status enum validation |
| Order Items | 317,534 | 44,418 | Quantity + price > 0 |
| **Quarantine** | — | **34,178** | Critical violations logged |

---

## 📌 Potential Extensions

- Snowflake Cortex for ML-powered demand forecasting
- Snowflake Native App packaging for marketplace distribution
- Dynamic Tables for simplified incremental refresh
- Row Access Policies for restaurant-level data segmentation
- Real-time anomaly alerting via Snowflake Alerts + Azure Logic Apps