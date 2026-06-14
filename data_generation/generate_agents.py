import pandas as pd
from faker import Faker
import random
from datetime import datetime, timedelta
from tqdm import tqdm
import os

fake = Faker('en_IN')
random.seed(42)
Faker.seed(42)

TOTAL_ROWS = 100_000
OUTPUT_PATH = os.path.join(os.path.dirname(__file__), '..', 'output', 'batch', 'agents')

# -- Dirty data injection rate ------------------------------------------
DIRTY_RATE       = 0.05   # 5% of records get at least one corruption
DUPLICATE_RATE   = 0.01   # 1% duplicate agent_ids

INDIAN_CITIES = [
    'Mumbai', 'Delhi', 'Bengaluru', 'Hyderabad', 'Chennai',
    'Kolkata', 'Pune', 'Ahmedabad', 'Jaipur', 'Surat',
    'Lucknow', 'Kanpur', 'Nagpur', 'Indore', 'Bhopal'
]

VEHICLE_TYPES = ['BIKE', 'SCOOTER', 'CYCLE']
VEHICLE_WEIGHTS = [0.55, 0.35, 0.10]

AVAILABILITY = ['ONLINE', 'OFFLINE', 'BUSY']
AVAILABILITY_WEIGHTS = [0.50, 0.35, 0.15]


# -- Dirty data injection -----------------------------------------------
def corrupt_agent(record):
    """Randomly apply one corruption to an agent record."""
    corruption = random.choice([
        'null_agent_id',
        'null_agent_name',
        'invalid_phone',
        'invalid_vehicle_type',
        'negative_rating',
        'out_of_range_rating',
        'invalid_availability',
        'null_city',
        'future_joining_date',
        'null_updated_at',
    ])

    if corruption == 'null_agent_id':
        record['agent_id'] = None
    elif corruption == 'null_agent_name':
        record['agent_name'] = None
    elif corruption == 'invalid_phone':
        record['phone_number'] = random.choice([
            '000', 'INVALID_NUM', '+91', '', '12345', 'N/A'
        ])
    elif corruption == 'invalid_vehicle_type':
        record['vehicle_type'] = random.choice([
            'CAR', 'TRUCK', 'AUTO', 'HELICOPTER', '', 'UNKNOWN'
        ])
    elif corruption == 'negative_rating':
        record['agent_rating'] = round(random.uniform(-5.0, -0.1), 1)
    elif corruption == 'out_of_range_rating':
        record['agent_rating'] = round(random.uniform(5.5, 10.0), 1)
    elif corruption == 'invalid_availability':
        record['availability_status'] = random.choice([
            'ACTIVE', 'INACTIVE', 'ON_BREAK', '', 'UNKNOWN'
        ])
    elif corruption == 'null_city':
        record['city'] = None
    elif corruption == 'future_joining_date':
        future = datetime.now() + timedelta(days=random.randint(100, 3650))
        record['joining_date'] = future.strftime('%Y-%m-%d')
    elif corruption == 'null_updated_at':
        record['updated_at'] = None

    return record


def generate_agents(n=TOTAL_ROWS):
    records = []
    used_ids = []  # track IDs for duplicate injection

    for _ in tqdm(range(n), desc='Generating delivery agents'):
        joining_date = datetime(2019, 1, 1) + timedelta(days=random.randint(0, 1800))
        updated_at = datetime(2024, 1, 1) + timedelta(
            days=random.randint(0, 365),
            hours=random.randint(0, 23),
            minutes=random.randint(0, 59)
        )

        agt_id = f"AGT_{str(random.randint(1000000, 9999999))}"

        record = {
            'agent_id':            agt_id,
            'agent_name':          fake.name(),
            'phone_number':        f"+91{random.randint(7000000000, 9999999999)}",
            'city':                random.choice(INDIAN_CITIES),
            'vehicle_type':        random.choices(VEHICLE_TYPES, weights=VEHICLE_WEIGHTS)[0],
            'joining_date':        joining_date.strftime('%Y-%m-%d'),
            'agent_rating':        round(random.uniform(2.0, 5.0), 1),
            'availability_status': random.choices(AVAILABILITY, weights=AVAILABILITY_WEIGHTS)[0],
            'updated_at':          updated_at.strftime('%Y-%m-%d %H:%M:%S'),
        }

        # -- Inject dirty data (~5%) --
        if random.random() < DIRTY_RATE:
            record = corrupt_agent(record)

        # -- Inject duplicate agent_ids (~1%) --
        if random.random() < DUPLICATE_RATE and len(used_ids) > 100:
            record['agent_id'] = random.choice(used_ids)
        else:
            used_ids.append(agt_id)

        records.append(record)
    return pd.DataFrame(records)


if __name__ == '__main__':
    os.makedirs(OUTPUT_PATH, exist_ok=True)
    df = generate_agents()
    out_file = os.path.join(OUTPUT_PATH, 'delivery_agents_master.csv')
    df.to_csv(out_file, index=False)
    print(f"\nDone. {len(df):,} rows saved to {out_file}")

    # -- Dirty data summary --
    print(f"\n{'-'*50}")
    print(f"  DIRTY DATA STATS")
    print(f"{'-'*50}")
    print(f"  Null agent_id:        {df['agent_id'].isna().sum():,}")
    print(f"  Null agent_name:      {df['agent_name'].isna().sum():,}")
    print(f"  Null city:            {df['city'].isna().sum():,}")
    print(f"  Null updated_at:      {df['updated_at'].isna().sum():,}")
    print(f"  Negative ratings:     {(df['agent_rating'] < 0).sum():,}")
    print(f"  Ratings > 5.0:        {(df['agent_rating'] > 5.0).sum():,}")
    print(f"  Duplicate IDs:        {df['agent_id'].duplicated().sum():,}")
    total_dirty = df.isnull().any(axis=1).sum() + df['agent_id'].duplicated().sum()
    print(f"  Total affected rows:  ~{total_dirty:,} ({total_dirty/len(df)*100:.1f}%)")
    print(f"{'-'*50}")
