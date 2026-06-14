# ═══════════════════════════════════════════════════════════════
#   FOOD AGGREGATOR PLATFORM — Live KPI Dashboard
#   No external packages — uses only built-in Streamlit charts
# ═══════════════════════════════════════════════════════════════

import streamlit as st
import pandas as pd
from snowflake.snowpark.context import get_active_session

# ── Page config ─────────────────────────────────────────────────
st.set_page_config(
    page_title = "Food Platform Dashboard",
    page_icon  = "🍔",
    layout     = "wide"
)

# ── Session setup ───────────────────────────────────────────────
session = get_active_session()
session.sql("USE WAREHOUSE ANALYTICS_WH").collect()
session.sql("USE DATABASE FOOD_PLATFORM").collect()
session.sql("USE SCHEMA GOLD").collect()

# ── Helper ──────────────────────────────────────────────────────
@st.cache_data(ttl=300, show_spinner=False)
def q(sql):
    try:
        return session.sql(sql).to_pandas()
    except Exception as e:
        st.error(f"Query failed: {e}")
        return pd.DataFrame()

def safe(df, col, default=0):
    try:
        v = df[col].iloc[0]
        return default if pd.isna(v) else v
    except:
        return default

# ── Sidebar ─────────────────────────────────────────────────────
with st.sidebar:
    st.title("🍔 Food Platform")
    st.markdown("**Analytics Dashboard**")
    st.divider()

    cities_df = q("""
        SELECT DISTINCT delivery_city AS city
        FROM FOOD_PLATFORM.GOLD.FACT_ORDERS
        WHERE delivery_city IS NOT NULL
        ORDER BY city
    """)
    city_list = ["All Cities"] + (
        cities_df["CITY"].tolist() if not cities_df.empty else []
    )
    city = st.selectbox("📍 Filter by City", city_list)

    st.markdown("**Order Status**")
    s_del  = st.checkbox("✅ Delivered", value=True)
    s_can  = st.checkbox("🟡 Cancelled", value=True)
    s_fail = st.checkbox("❌ Failed",    value=True)
    s_pen  = st.checkbox("🔵 Pending",   value=True)

    st.divider()
    if st.button("🔄 Refresh", width='stretch'):
        st.cache_data.clear()
        st.rerun()
    st.caption("Cache refreshes every 5 min")

# ── Build filter strings ─────────────────────────────────────────
city_f = (
    f"AND delivery_city = '{city}'"
    if city != "All Cities" else ""
)
city_fj = (
    f"AND o.delivery_city = '{city}'"
    if city != "All Cities" else ""
)

statuses = []
if s_del:  statuses.append("'DELIVERED'")
if s_can:  statuses.append("'CANCELLED'")
if s_fail: statuses.append("'FAILED'")
if s_pen:  statuses.append("'PENDING'")
status_f = (
    f"AND order_status IN ({','.join(statuses)})"
    if statuses else "AND 1=0"
)

# ════════════════════════════════════════════════════════════════
# HEADER
# ════════════════════════════════════════════════════════════════
st.title("🍔 Food Delivery App Analysis — Live KPI Dashboard")
loc = f"**{city}**" if city != "All Cities" else "**All Cities**"
st.caption(f"Showing {loc} · Source: FOOD_PLATFORM.GOLD · Snowflake + Streamlit")
st.divider()

# ════════════════════════════════════════════════════════════════
# SECTION 1 — KPI METRIC CARDS
# ════════════════════════════════════════════════════════════════
st.subheader("📊 Key Performance Indicators")

kpi = q(f"""
    SELECT
        COUNT(*)                                                AS total_orders,
        ROUND(SUM(total_amount), 0)                            AS total_revenue,
        ROUND(AVG(total_amount), 0)                            AS avg_order_value,
        ROUND(COUNT(CASE WHEN order_status = 'DELIVERED'
              THEN 1 END) * 100.0 / NULLIF(COUNT(*),0), 1)    AS success_rate,
        ROUND(COUNT(CASE WHEN order_status = 'FAILED'
              THEN 1 END) * 100.0 / NULLIF(COUNT(*),0), 1)    AS failed_rate,
        ROUND(AVG(CASE WHEN actual_delivery_time > 0
              THEN actual_delivery_time END), 1)               AS avg_delivery_min,
        COUNT(DISTINCT delivery_city)                          AS active_cities
    FROM FOOD_PLATFORM.GOLD.FACT_ORDERS
    WHERE order_placed_at IS NOT NULL
      AND order_placed_at <= CURRENT_TIMESTAMP()
      {city_f}
      {status_f}
""")

pay_kpi = q("""
    SELECT
        ROUND(
            COUNT(CASE WHEN payment_status = 'SUCCESS' THEN 1 END)
            * 100.0 / NULLIF(COUNT(*), 0), 1
        ) AS pay_success_rate
    FROM FOOD_PLATFORM.GOLD.FACT_PAYMENTS
    WHERE payment_timestamp IS NOT NULL
""")

total_orders  = int(safe(kpi,     "TOTAL_ORDERS"))
total_revenue = float(safe(kpi,   "TOTAL_REVENUE"))
avg_val       = float(safe(kpi,   "AVG_ORDER_VALUE"))
success_rate  = float(safe(kpi,   "SUCCESS_RATE"))
failed_rate   = float(safe(kpi,   "FAILED_RATE"))
avg_del       = float(safe(kpi,   "AVG_DELIVERY_MIN"))
cities_count  = int(safe(kpi,     "ACTIVE_CITIES"))
pay_success   = float(safe(pay_kpi,"PAY_SUCCESS_RATE"))

# Row 1 — 4 cards
c1, c2, c3, c4 = st.columns(4)
c1.metric("📦 Total Orders",    f"{total_orders:,}")
c2.metric("💰 Total Revenue",   f"₹{total_revenue:,.0f}")
c3.metric("🛒 Avg Order Value", f"₹{avg_val:,.0f}")
c4.metric("🏙️ Active Cities",   f"{cities_count}")

# Row 2 — 4 cards
c5, c6, c7, c8 = st.columns(4)
c5.metric(
    "✅ Order Success Rate",
    f"{success_rate}%",
    delta=f"{success_rate - 75:.1f}% vs 75% target"
)
c6.metric(
    "❌ Failed Order Rate",
    f"{failed_rate}%",
    delta=f"{failed_rate - 5:.1f}% vs 5% limit",
    delta_color="inverse"
)
c7.metric("💳 Payment Success",  f"{pay_success}%")
c8.metric("🚴 Avg Delivery Time", f"{avg_del} min")

st.divider()

# ════════════════════════════════════════════════════════════════
# SECTION 2 — REVENUE TREND + ORDER STATUS
# ════════════════════════════════════════════════════════════════
st.subheader("📈 Revenue Trend & Order Distribution")

col_trend, col_status = st.columns([3, 2])

with col_trend:
    trend = q(f"""
        SELECT
            DATE_TRUNC('HOUR', order_placed_at)     AS hour,
            ROUND(SUM(total_amount), 0)              AS revenue
        FROM FOOD_PLATFORM.GOLD.FACT_ORDERS
        WHERE order_placed_at IS NOT NULL
          AND order_placed_at <= CURRENT_TIMESTAMP()
          {city_f}
          {status_f}
        GROUP BY DATE_TRUNC('HOUR', order_placed_at)
        ORDER BY hour
    """)

    if not trend.empty:
        trend = trend.rename(columns={"HOUR": "Hour", "REVENUE": "Revenue (₹)"})
        trend = trend.set_index("Hour")
        # Rolling average
        trend["Rolling Avg (₹)"] = trend["Revenue (₹)"].rolling(
            window=4, min_periods=1
        ).mean().round(0)
        st.area_chart(
            trend,
            height=250,
            color=["#00b4d8", "#ff6b35"]
        )
        st.caption("Blue = Hourly Revenue · Orange = 4-period Rolling Average")
    else:
        st.info("No trend data for selected filters")

with col_status:
    status_df = q(f"""
        SELECT
            order_status    AS "Status",
            COUNT(*)        AS "Orders",
            ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS "Share %"
        FROM FOOD_PLATFORM.GOLD.FACT_ORDERS
        WHERE order_placed_at IS NOT NULL
          {city_f}
        GROUP BY order_status
        ORDER BY "Orders" DESC
    """)

    if not status_df.empty:
        # Show as a styled table
        st.dataframe(
            status_df,
            width='stretch',
            hide_index=True,
            height=180
        )
        # Bar chart of order counts
        chart_df = status_df.set_index("Status")[["Orders"]]
        st.bar_chart(chart_df, height=120)

st.divider()

# ════════════════════════════════════════════════════════════════
# SECTION 3 — CITY REVENUE + PAYMENT BREAKDOWN
# ════════════════════════════════════════════════════════════════
st.subheader("🏙️ City Performance & 💳 Payment Analysis")

col_city, col_pay = st.columns(2)

with col_city:
    city_rev = q("""
        SELECT
            delivery_city               AS "City",
            COUNT(*)                    AS "Orders",
            ROUND(SUM(total_amount), 0) AS "Revenue (₹)",
            ROUND(AVG(total_amount), 0) AS "Avg Order (₹)"
        FROM FOOD_PLATFORM.GOLD.FACT_ORDERS
        WHERE delivery_city IS NOT NULL
          AND order_status = 'DELIVERED'
          AND order_placed_at <= CURRENT_TIMESTAMP()
        GROUP BY delivery_city
        ORDER BY "Revenue (₹)" DESC
        LIMIT 10
    """)

    if not city_rev.empty:
        st.dataframe(
            city_rev,
            width='stretch',
            hide_index=True
        )
        # Bar chart
        chart_city = city_rev.set_index("City")[["Revenue (₹)"]]
        st.bar_chart(chart_city, height=150)

with col_pay:
    pay_df = q("""
        SELECT
            payment_method AS "Method",
            COUNT(*)       AS "Transactions",
            ROUND(SUM(amount), 0) AS "Total (₹)",
            ROUND(COUNT(CASE WHEN payment_status = 'SUCCESS'
                  THEN 1 END) * 100.0 / NULLIF(COUNT(*),0), 1) AS "Success %",
            ROUND(COUNT(CASE WHEN payment_status = 'REFUNDED'
                  THEN 1 END) * 100.0 / NULLIF(COUNT(*),0), 1) AS "Refund %"
        FROM FOOD_PLATFORM.GOLD.FACT_PAYMENTS
        WHERE payment_timestamp IS NOT NULL
        GROUP BY payment_method
        ORDER BY "Transactions" DESC
    """)

    if not pay_df.empty:
        st.dataframe(
            pay_df,
            width='stretch',
            hide_index=True
        )
        # Bar chart
        chart_pay = pay_df.set_index("Method")[["Transactions"]]
        st.bar_chart(chart_pay, height=150)

st.divider()

# ════════════════════════════════════════════════════════════════
# SECTION 4 — CUISINE PERFORMANCE
# ════════════════════════════════════════════════════════════════
st.subheader("🍽️ Cuisine Performance")

col_cuis, col_agent = st.columns(2)

with col_cuis:
    cuisine = q(f"""
        SELECT
            r.cuisine_type                      AS "Cuisine",
            COUNT(*)                            AS "Orders",
            ROUND(SUM(o.total_amount), 0)       AS "Revenue (₹)",
            ROUND(AVG(o.total_amount), 0)       AS "Avg Order (₹)",
            ROUND(COUNT(CASE WHEN o.order_status = 'DELIVERED'
                  THEN 1 END) * 100.0 / NULLIF(COUNT(*),0), 1) AS "Success %"
        FROM FOOD_PLATFORM.GOLD.FACT_ORDERS o
        JOIN FOOD_PLATFORM.GOLD.DIM_RESTAURANT r
          ON o.restaurant_sk = r.restaurant_sk
        WHERE r.cuisine_type IS NOT NULL
          AND o.order_placed_at <= CURRENT_TIMESTAMP()
          {city_fj}
        GROUP BY r.cuisine_type
        ORDER BY "Revenue (₹)" DESC
        LIMIT 10
    """)

    if not cuisine.empty:
        st.dataframe(
            cuisine,
            width='stretch',
            hide_index=True,
            height=300
        )

with col_agent:
    # Vehicle type performance
    vehicle = q(f"""
        SELECT
            d.vehicle_type                      AS "Vehicle",
            COUNT(*)                            AS "Orders",
            ROUND(AVG(o.actual_delivery_time), 1) AS "Avg Delivery (min)",
            ROUND(COUNT(CASE WHEN o.order_status = 'DELIVERED'
                  THEN 1 END) * 100.0 / NULLIF(COUNT(*),0), 1) AS "Success %"
        FROM FOOD_PLATFORM.GOLD.FACT_ORDERS o
        JOIN FOOD_PLATFORM.GOLD.DIM_DELIVERY d
          ON o.delivery_sk = d.delivery_sk
        WHERE d.vehicle_type IS NOT NULL
          AND o.order_placed_at <= CURRENT_TIMESTAMP()
          {city_fj}
        GROUP BY d.vehicle_type
        ORDER BY "Orders" DESC
    """)

    if not vehicle.empty:
        st.markdown("**🚴 Vehicle Type Performance**")
        st.dataframe(
            vehicle,
            width='stretch',
            hide_index=True
        )
        chart_veh = vehicle.set_index("Vehicle")[["Orders"]]
        st.bar_chart(chart_veh, height=150)

st.divider()

# ════════════════════════════════════════════════════════════════
# SECTION 5 — RECENT ORDERS TABLE
# ════════════════════════════════════════════════════════════════
st.subheader("📋 Recent Orders")

recent = q(f"""
    SELECT
        o.order_id                                          AS "Order ID",
        c.customer_segment                                  AS "Segment",
        r.cuisine_type                                      AS "Cuisine",
        o.delivery_city                                     AS "City",
        o.order_status                                      AS "Status",
        CONCAT('₹', TO_CHAR(o.total_amount, '999,990'))    AS "Amount",
        CONCAT(o.actual_delivery_time, ' min')              AS "Delivery",
        d.vehicle_type                                      AS "Vehicle",
        TO_CHAR(o.order_placed_at, 'DD Mon HH24:MI')       AS "Placed At"
    FROM FOOD_PLATFORM.GOLD.FACT_ORDERS o
    LEFT JOIN FOOD_PLATFORM.GOLD.DIM_CUSTOMER    c
           ON o.customer_sk    = c.customer_sk
    LEFT JOIN FOOD_PLATFORM.GOLD.DIM_RESTAURANT  r
           ON o.restaurant_sk  = r.restaurant_sk
    LEFT JOIN FOOD_PLATFORM.GOLD.DIM_DELIVERY    d
           ON o.delivery_sk    = d.delivery_sk
    WHERE o.order_placed_at IS NOT NULL
      {city_fj}
    ORDER BY o.order_placed_at DESC
    LIMIT 25
""")

if not recent.empty:
    st.dataframe(
        recent,
        width='stretch',
        hide_index=True,
        height=400
    )
else:
    st.info("No recent orders found")

st.divider()

# ════════════════════════════════════════════════════════════════
# SECTION 6 — HOURLY KPI TABLE (from pre-aggregated Gold table)
# ════════════════════════════════════════════════════════════════
st.subheader("⏱️ Hourly KPI Summary")

hourly = q("""
    SELECT
        TO_CHAR(kpi_hour, 'DD Mon YYYY HH24:00') AS "Hour",
        total_orders                              AS "Total Orders",
        delivered_orders                          AS "Delivered",
        failed_orders                             AS "Failed",
        CONCAT('₹', TO_CHAR(total_revenue, '999,999,990'))
                                                  AS "Revenue",
        CONCAT(order_success_rate, '%')           AS "Success %",
        CONCAT(failed_order_rate, '%')            AS "Failed %",
        CONCAT(avg_delivery_time, ' min')         AS "Avg Delivery"
    FROM FOOD_PLATFORM.GOLD.AGG_HOURLY_KPI
    ORDER BY kpi_hour DESC
""")

if not hourly.empty:
    st.dataframe(hourly, width='stretch', hide_index=True)

st.divider()