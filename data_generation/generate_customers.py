import pandas as pd
from faker import Faker
from faker.providers import person, address, internet
import random
from datetime import datetime, timedelta
from tqdm import tqdm
import os

fake = Faker('en_IN')  # Indian locale for realistic names, cities, phones
random.seed(42)
Faker.seed(42)

TOTAL_ROWS = 500_000
OUTPUT_PATH = os.path.join(os.path.dirname(__file__), '..', 'output', 'batch', 'customers')

# -- Dirty data injection rate ------------------------------------------
DIRTY_RATE       = 0.05   # 5% of records get at least one corruption
DUPLICATE_RATE   = 0.01   # 1% extra duplicate customer_ids

INDIAN_CITIES = [
    'Mumbai', 'Delhi', 'Bengaluru', 'Hyderabad', 'Chennai',
    'Kolkata', 'Pune', 'Ahmedabad', 'Jaipur', 'Surat',
    'Lucknow', 'Kanpur', 'Nagpur', 'Indore', 'Bhopal'
]

STATES_BY_CITY = {
    'Mumbai': 'Maharashtra', 'Pune': 'Maharashtra', 'Nagpur': 'Maharashtra',
    'Delhi': 'Delhi', 'Jaipur': 'Rajasthan',
    'Bengaluru': 'Karnataka',
    'Hyderabad': 'Telangana',
    'Chennai': 'Tamil Nadu',
    'Kolkata': 'West Bengal',
    'Ahmedabad': 'Gujarat', 'Surat': 'Gujarat',
    'Lucknow': 'Uttar Pradesh', 'Kanpur': 'Uttar Pradesh',
    'Indore': 'Madhya Pradesh', 'Bhopal': 'Madhya Pradesh'
}

SEGMENTS = ['NEW', 'REGULAR', 'PREMIUM', 'CHURNED']
SEGMENT_WEIGHTS = [0.25, 0.40, 0.20, 0.15]

GENDERS = ['M', 'F', 'Other']
GENDER_WEIGHTS = [0.48, 0.48, 0.04]


def random_date(start_year=2019, end_year=2024):
    start = datetime(start_year, 1, 1)
    end = datetime(end_year, 12, 31)
    return start + timedelta(days=random.randint(0, (end - start).days))


# -- Dirty data injection -----------------------------------------------
def corrupt_customer(record):
    """Randomly apply one corruption to a customer record."""
    corruption = random.choice([
        'null_customer_id',
        'null_email',
        'invalid_email',
        'invalid_phone',
        'null_name',
        'future_dob',
        'invalid_gender',
        'null_city',
        'invalid_segment',
        'null_signup_date',
    ])

    if corruption == 'null_customer_id':
        record['customer_id'] = None
    elif corruption == 'null_email':
        record['email'] = None
    elif corruption == 'invalid_email':
        record['email'] = random.choice([
            'not-an-email', 'abc@', '@.com', 'plaintext', '12345',
            'user@@domain.com', 'missing-dot@com'
        ])
    elif corruption == 'invalid_phone':
        record['phone_number'] = random.choice([
            '123', 'INVALID', '+91', '', 'abcdefghij', '0000000000'
        ])
    elif corruption == 'null_name':
        if random.random() > 0.5:
            record['first_name'] = None
        else:
            record['last_name'] = None
    elif corruption == 'future_dob':
        future = datetime.now() + timedelta(days=random.randint(100, 3650))
        record['date_of_birth'] = future.strftime('%Y-%m-%d')
    elif corruption == 'invalid_gender':
        record['gender'] = random.choice(['X', 'Unknown', '0', 'NA', ''])
    elif corruption == 'null_city':
        record['city'] = None
        record['state'] = None
    elif corruption == 'invalid_segment':
        record['customer_segment'] = random.choice([
            'GOLD', 'VIP', 'UNKNOWN', '', 'DIAMOND'
        ])
    elif corruption == 'null_signup_date':
        record['signup_date'] = None

    return record


def generate_customers(n=TOTAL_ROWS):
    records = []
    used_ids = []   # track IDs for duplicate injection

    for _ in tqdm(range(n), desc='Generating customers'):
        city = random.choice(INDIAN_CITIES)
        signup_date = random_date(2019, 2023)
        segment = random.choices(SEGMENTS, weights=SEGMENT_WEIGHTS)[0]
        is_active = segment != 'CHURNED'

        # Last order date only makes sense for non-new customers
        if segment in ['REGULAR', 'PREMIUM']:
            last_order_date = signup_date + timedelta(days=random.randint(30, 365))
        elif segment == 'CHURNED':
            last_order_date = signup_date + timedelta(days=random.randint(10, 180))
        else:
            last_order_date = None

        # updated_at is used for SCD Type 2 delta detection
        updated_at = datetime(2024, 1, 1) + timedelta(
            days=random.randint(0, 365),
            hours=random.randint(0, 23),
            minutes=random.randint(0, 59)
        )

        cust_id = f"CUST_{str(random.randint(1000000, 9999999))}"

        record = {
            'customer_id':       cust_id,
            'first_name':        fake.first_name(),
            'last_name':         fake.last_name(),
            'email':             fake.email(),
            'phone_number':      f"+91{random.randint(7000000000, 9999999999)}",
            'date_of_birth':     fake.date_of_birth(minimum_age=18, maximum_age=60).strftime('%Y-%m-%d'),
            'gender':            random.choices(GENDERS, weights=GENDER_WEIGHTS)[0],
            'address_line1':     fake.street_address(),
            'city':              city,
            'state':             STATES_BY_CITY[city],
            'pincode':           str(random.randint(100000, 999999)),
            'signup_date':       signup_date.strftime('%Y-%m-%d'),
            'customer_segment':  segment,
            'is_active':         is_active,
            'last_order_date':   last_order_date.strftime('%Y-%m-%d') if last_order_date else None,
            'updated_at':        updated_at.strftime('%Y-%m-%d %H:%M:%S'),
        }

        # -- Inject dirty data (~5%) --
        if random.random() < DIRTY_RATE:
            record = corrupt_customer(record)

        # -- Inject duplicate customer_ids (~1%) --
        if random.random() < DUPLICATE_RATE and len(used_ids) > 100:
            record['customer_id'] = random.choice(used_ids)
        else:
            used_ids.append(cust_id)

        records.append(record)
    return pd.DataFrame(records)


if __name__ == '__main__':
    os.makedirs(OUTPUT_PATH, exist_ok=True)
    df = generate_customers()
    out_file = os.path.join(OUTPUT_PATH, 'customers_master.csv')
    df.to_csv(out_file, index=False)
    print(f"\nDone. {len(df):,} rows saved to {out_file}")

    # -- Dirty data summary --
    print(f"\n{'-'*50}")
    print(f"  DIRTY DATA STATS")
    print(f"{'-'*50}")
    print(f"  Null customer_id:    {df['customer_id'].isna().sum():,}")
    print(f"  Null email:          {df['email'].isna().sum():,}")
    print(f"  Null first_name:     {df['first_name'].isna().sum():,}")
    print(f"  Null last_name:      {df['last_name'].isna().sum():,}")
    print(f"  Null city:           {df['city'].isna().sum():,}")
    print(f"  Null signup_date:    {df['signup_date'].isna().sum():,}")
    print(f"  Duplicate IDs:       {df['customer_id'].duplicated().sum():,}")
    total_dirty = df.isnull().any(axis=1).sum() + df['customer_id'].duplicated().sum()
    print(f"  Total affected rows: ~{total_dirty:,} ({total_dirty/len(df)*100:.1f}%)")
    print(f"{'-'*50}")