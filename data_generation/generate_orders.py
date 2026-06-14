import pandas as pd
from faker import Faker
import random
from datetime import datetime, timedelta
from tqdm import tqdm
import os
import json

fake = Faker('en_IN')
random.seed(42)
Faker.seed(42)

ORDERS_PER_DAY = 15_000
OUTPUT_ORDERS = os.path.join(os.path.dirname(__file__), '..', 'output', 'batch', 'orders')
OUTPUT_ITEMS  = os.path.join(os.path.dirname(__file__), '..', 'output', 'batch', 'order_items')

# -- Dirty data injection rates -----------------------------------------
DIRTY_RATE_ORDERS   = 0.06   # 6% of order records get corrupted
DIRTY_RATE_ITEMS    = 0.04   # 4% of item records get corrupted
DUPLICATE_RATE      = 0.008  # ~0.8% duplicate order_ids
ORPHAN_FK_RATE      = 0.015  # ~1.5% orphan foreign keys

INDIAN_CITIES = [
    'Mumbai', 'Delhi', 'Bengaluru', 'Hyderabad', 'Chennai',
    'Kolkata', 'Pune', 'Ahmedabad', 'Jaipur', 'Surat'
]

ZONES_BY_CITY = {
    'Mumbai':    ['Andheri', 'Bandra', 'Dadar', 'Juhu', 'Powai'],
    'Delhi':     ['Connaught Place', 'Lajpat Nagar', 'Saket', 'Dwarka', 'Rohini'],
    'Bengaluru': ['Koramangala', 'Indiranagar', 'Whitefield', 'HSR Layout', 'Marathahalli'],
    'Hyderabad': ['Banjara Hills', 'Jubilee Hills', 'Madhapur', 'Gachibowli', 'Secunderabad'],
    'Chennai':   ['T Nagar', 'Anna Nagar', 'Adyar', 'Velachery', 'Porur'],
    'Kolkata':   ['Park Street', 'Salt Lake', 'New Town', 'Behala', 'Dunlop'],
    'Pune':      ['Koregaon Park', 'Viman Nagar', 'Hinjewadi', 'Kothrud', 'Baner'],
    'Ahmedabad': ['Navrangpura', 'Satellite', 'Bopal', 'Vastrapur', 'Maninagar'],
    'Jaipur':    ['Malviya Nagar', 'Vaishali Nagar', 'C-Scheme', 'Mansarovar', 'Tonk Road'],
    'Surat':     ['Adajan', 'Athwa', 'Vesu', 'Piplod', 'Katargam'],
}

ORDER_STATUSES  = ['DELIVERED', 'CANCELLED', 'FAILED', 'PENDING']
STATUS_WEIGHTS  = [0.75, 0.14, 0.08, 0.03]
ORDER_SOURCES   = ['APP', 'WEBSITE', 'PHONE']
SOURCE_WEIGHTS  = [0.70, 0.22, 0.08]
PROMO_CODES     = ['SAVE10', 'FLAT50', 'NEWUSER', 'WEEKEND20', None, None, None]  # None = no promo

MENU_ITEMS = {
    'Biryani':     [('Chicken Biryani', 280), ('Mutton Biryani', 350), ('Veg Biryani', 200)],
    'Pizza':       [('Margherita', 250), ('Pepperoni', 320), ('Farmhouse', 300)],
    'Burger':      [('Veg Burger', 120), ('Chicken Burger', 160), ('Double Patty', 200)],
    'Drinks':      [('Cola', 50), ('Juice', 80), ('Water', 30), ('Lassi', 90)],
    'Desserts':    [('Gulab Jamun', 80), ('Ice Cream', 100), ('Brownie', 120)],
    'North Indian':[('Dal Makhani', 180), ('Paneer Butter Masala', 220), ('Roti', 20)],
    'South Indian':[('Masala Dosa', 120), ('Idli Sambar', 90), ('Uttapam', 110)],
    'Momos':       [('Veg Momos', 100), ('Chicken Momos', 130), ('Fried Momos', 140)],
}
ALL_CATEGORIES = list(MENU_ITEMS.keys())


# -- Dirty data injection - Orders --------------------------------------
def corrupt_order(record):
    """Randomly apply one corruption to an order record."""
    corruption = random.choice([
        'null_order_id',
        'negative_total_amount',
        'zero_total_amount',
        'final_amount_mismatch',
        'invalid_status',
        'future_order_date',
        'negative_delivery_fee',
        'negative_distance',
        'null_placed_at',
        'null_delivery_city',
        'invalid_source',
    ])

    if corruption == 'null_order_id':
        record['order_id'] = None
    elif corruption == 'negative_total_amount':
        record['total_amount'] = round(random.uniform(-500, -10), 2)
        record['final_amount'] = record['total_amount']  # cascade the bad value
    elif corruption == 'zero_total_amount':
        record['total_amount'] = 0
        record['final_amount'] = 0
    elif corruption == 'final_amount_mismatch':
        # Intentionally make final_amount != total - discount + fee + tax
        record['final_amount'] = round(record['final_amount'] + random.uniform(50, 500), 2)
    elif corruption == 'invalid_status':
        record['order_status'] = random.choice([
            'DELIVRD', 'COMPLET', 'IN_TRANSIT', 'UNKNOWN', '', 'DONE', 'SUCCESS'
        ])
    elif corruption == 'future_order_date':
        future = datetime.now() + timedelta(days=random.randint(30, 365))
        record['order_placed_at'] = future.strftime('%Y-%m-%d %H:%M:%S')
    elif corruption == 'negative_delivery_fee':
        record['delivery_fee'] = round(random.uniform(-50, -5), 2)
    elif corruption == 'negative_distance':
        record['delivery_distance_km'] = round(random.uniform(-10, -0.5), 2)
    elif corruption == 'null_placed_at':
        record['order_placed_at'] = None
    elif corruption == 'null_delivery_city':
        record['delivery_city'] = None
        record['delivery_pincode'] = None
    elif corruption == 'invalid_source':
        record['order_source'] = random.choice([
            'TELEGRAM', 'WHATSAPP', 'FAX', '', 'UNKNOWN'
        ])

    return record


# -- Dirty data injection - Order Items ---------------------------------
def corrupt_order_item(item):
    """Randomly apply one corruption to an order item record."""
    corruption = random.choice([
        'zero_quantity',
        'negative_quantity',
        'negative_unit_price',
        'total_price_mismatch',
        'null_item_name',
        'null_category',
    ])

    if corruption == 'zero_quantity':
        item['quantity'] = 0
    elif corruption == 'negative_quantity':
        item['quantity'] = random.randint(-5, -1)
    elif corruption == 'negative_unit_price':
        item['unit_price'] = round(random.uniform(-200, -10), 2)
    elif corruption == 'total_price_mismatch':
        # Intentionally make total_price != quantity * unit_price
        item['total_price'] = round(item['total_price'] + random.uniform(50, 300), 2)
    elif corruption == 'null_item_name':
        item['item_name'] = None
    elif corruption == 'null_category':
        item['category'] = None

    return item


def generate_order_items(order_id, num_items):
    items = []
    category = random.choice(ALL_CATEGORIES)
    item_pool = MENU_ITEMS[category]
    chosen = random.choices(item_pool, k=num_items)
    for item_name, unit_price in chosen:
        qty = random.randint(1, 3)
        item = {
            'order_item_id': f"ITEM_{random.randint(10000000, 99999999)}",
            'order_id':      order_id,
            'item_name':     item_name,
            'category':      category,
            'quantity':      qty,
            'unit_price':    unit_price,
            'total_price':   round(qty * unit_price, 2),
            'is_veg':        'Chicken' not in item_name and 'Mutton' not in item_name and 'Pepperoni' not in item_name,
        }

        # -- Inject dirty data into items (~4%) --
        if random.random() < DIRTY_RATE_ITEMS:
            item = corrupt_order_item(item)

        items.append(item)
    return items


def generate_orders_for_date(date_str):
    # Load IDs generated by master scripts so FKs are realistic
    customers_path = os.path.join(os.path.dirname(__file__), '..', 'output', 'batch', 'customers', 'customers_master.csv')
    restaurants_path = os.path.join(os.path.dirname(__file__), '..', 'output', 'batch', 'restaurants', 'restaurants_catalog.json')
    agents_path = os.path.join(os.path.dirname(__file__), '..', 'output', 'batch', 'agents', 'delivery_agents_master.csv')

    customer_ids = pd.read_csv(customers_path, usecols=['customer_id'])['customer_id'].dropna().tolist()
    with open(restaurants_path) as f:
        restaurant_ids = [r['restaurant_id'] for r in json.load(f) if r.get('restaurant_id')]
    agent_ids = pd.read_csv(agents_path, usecols=['agent_id'])['agent_id'].dropna().tolist()

    # Orphan FK pools - IDs that do NOT exist in master data
    orphan_customer_ids  = [f"CUST_INVALID_{i}" for i in range(1, 101)]
    orphan_restaurant_ids = [f"REST_INVALID_{i}" for i in range(1, 101)]
    orphan_agent_ids     = [f"AGT_INVALID_{i}" for i in range(1, 101)]

    date = datetime.strptime(date_str, '%Y-%m-%d')
    orders, all_items = [], []
    used_order_ids = []  # for duplicate injection
    dirty_order_count = 0
    dirty_item_count = 0

    for _ in tqdm(range(ORDERS_PER_DAY), desc=f'Generating orders for {date_str}'):
        order_id = f"ORD_{random.randint(10000000, 99999999)}"
        city = random.choice(INDIAN_CITIES)
        status = random.choices(ORDER_STATUSES, weights=STATUS_WEIGHTS)[0]

        placed_at = date + timedelta(
            hours=random.randint(8, 23),
            minutes=random.randint(0, 59),
            seconds=random.randint(0, 59)
        )

        accepted_at = (placed_at + timedelta(minutes=random.randint(1, 5))) if status != 'CANCELLED' else None
        est_time = random.randint(20, 60)
        actual_time = random.randint(15, 90) if status == 'DELIVERED' else None
        delivered_at = (accepted_at + timedelta(minutes=actual_time)) if status == 'DELIVERED' and accepted_at else None

        total_amount = round(random.uniform(100, 1500), 2)
        discount = round(total_amount * random.uniform(0, 0.20), 2)
        delivery_fee = round(random.uniform(20, 80), 2)
        tax = round(total_amount * 0.05, 2)
        final_amount = round(total_amount - discount + delivery_fee + tax, 2)

        # -- Pick FK values (with orphan injection) --
        cust_id = random.choice(orphan_customer_ids) if random.random() < ORPHAN_FK_RATE else random.choice(customer_ids)
        rest_id = random.choice(orphan_restaurant_ids) if random.random() < ORPHAN_FK_RATE else random.choice(restaurant_ids)
        agt_id  = random.choice(orphan_agent_ids)  if random.random() < ORPHAN_FK_RATE else random.choice(agent_ids)

        record = {
            'order_id':               order_id,
            'customer_id':            cust_id,
            'restaurant_id':          rest_id,
            'agent_id':               agt_id,
            'order_placed_at':        placed_at.strftime('%Y-%m-%d %H:%M:%S'),
            'order_accepted_at':      accepted_at.strftime('%Y-%m-%d %H:%M:%S') if accepted_at else None,
            'order_delivered_at':     delivered_at.strftime('%Y-%m-%d %H:%M:%S') if delivered_at else None,
            'order_status':           status,
            'total_amount':           total_amount,
            'discount_amount':        discount,
            'delivery_fee':           delivery_fee,
            'tax_amount':             tax,
            'final_amount':           final_amount,
            'delivery_distance_km':   round(random.uniform(0.5, 15.0), 2),
            'estimated_delivery_time':est_time,
            'actual_delivery_time':   actual_time,
            'delivery_city':          city,
            'delivery_pincode':       str(random.randint(100000, 999999)),
            'order_source':           random.choices(ORDER_SOURCES, weights=SOURCE_WEIGHTS)[0],
            'promo_code':             random.choice(PROMO_CODES),
        }

        # -- Inject dirty data into orders (~6%) --
        if random.random() < DIRTY_RATE_ORDERS:
            record = corrupt_order(record)
            dirty_order_count += 1

        # -- Inject duplicate order_ids (~0.8%) --
        if random.random() < DUPLICATE_RATE and len(used_order_ids) > 100:
            record['order_id'] = random.choice(used_order_ids)
        else:
            used_order_ids.append(order_id)

        orders.append(record)

        num_items = random.randint(1, 5)
        items = generate_order_items(order_id, num_items)
        dirty_item_count += sum(1 for _ in items if random.random() < 0)  # counted inside generate_order_items
        all_items.extend(items)

    return pd.DataFrame(orders), pd.DataFrame(all_items), dirty_order_count


if __name__ == '__main__':
    import sys
    # Pass a date as argument, e.g.: python generate_orders.py 2024-01-15
    # Defaults to yesterday if no argument given
    if len(sys.argv) > 1:
        date_str = sys.argv[1]
    else:
        date_str = (datetime.today() - timedelta(days=1)).strftime('%Y-%m-%d')

    os.makedirs(OUTPUT_ORDERS, exist_ok=True)
    os.makedirs(OUTPUT_ITEMS, exist_ok=True)

    orders_df, items_df, dirty_count = generate_orders_for_date(date_str)

    orders_file = os.path.join(OUTPUT_ORDERS, f'orders_raw_{date_str}.csv')
    items_file  = os.path.join(OUTPUT_ITEMS,  f'order_items_raw_{date_str}.csv')

    orders_df.to_csv(orders_file, index=False)
    items_df.to_csv(items_file, index=False)

    print(f"\nOrders : {len(orders_df):,} rows -> {orders_file}")
    print(f"Items  : {len(items_df):,} rows -> {items_file}")

    # -- Dirty data summary --
    print(f"\n{'-'*50}")
    print(f"  DIRTY DATA STATS - Orders ({date_str})")
    print(f"{'-'*50}")
    print(f"  Null order_id:        {orders_df['order_id'].isna().sum():,}")
    print(f"  Null placed_at:       {orders_df['order_placed_at'].isna().sum():,}")
    print(f"  Negative amounts:     {(orders_df['total_amount'] <= 0).sum():,}")
    print(f"  Orphan customer_ids:  {orders_df['customer_id'].str.contains('INVALID', na=False).sum():,}")
    print(f"  Orphan restaurant_ids:{orders_df['restaurant_id'].str.contains('INVALID', na=False).sum():,}")
    print(f"  Orphan agent_ids:     {orders_df['agent_id'].str.contains('INVALID', na=False).sum():,}")
    print(f"  Duplicate order_ids:  {orders_df['order_id'].duplicated().sum():,}")
    print(f"  Corrupted orders:     ~{dirty_count:,} ({dirty_count/len(orders_df)*100:.1f}%)")
    print(f"{'-'*50}")
    print(f"  DIRTY DATA STATS - Order Items ({date_str})")
    print(f"{'-'*50}")
    print(f"  Null item_name:       {items_df['item_name'].isna().sum():,}")
    print(f"  Null category:        {items_df['category'].isna().sum():,}")
    print(f"  Zero/neg quantity:    {(items_df['quantity'] <= 0).sum():,}")
    print(f"  Negative unit_price:  {(items_df['unit_price'] < 0).sum():,}")
    print(f"{'-'*50}")
