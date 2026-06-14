import pandas as pd
from faker import Faker
import random
import json
from datetime import datetime, timedelta
from tqdm import tqdm
import os

fake = Faker('en_IN')
random.seed(42)
Faker.seed(42)

TOTAL_RECORDS = 50_000
OUTPUT_PATH = os.path.join(os.path.dirname(__file__), '..', 'output', 'batch', 'restaurants')

# -- Dirty data injection rate ------------------------------------------
DIRTY_RATE       = 0.05   # 5% of records get at least one corruption
DUPLICATE_RATE   = 0.008  # ~0.8% duplicate restaurant_ids

INDIAN_CITIES = [
    'Mumbai', 'Delhi', 'Bengaluru', 'Hyderabad', 'Chennai',
    'Kolkata', 'Pune', 'Ahmedabad', 'Jaipur', 'Surat',
    'Lucknow', 'Kanpur', 'Nagpur', 'Indore', 'Bhopal'
]

STATES_BY_CITY = {
    'Mumbai': 'Maharashtra', 'Pune': 'Maharashtra', 'Nagpur': 'Maharashtra',
    'Delhi': 'Delhi', 'Jaipur': 'Rajasthan',
    'Bengaluru': 'Karnataka', 'Hyderabad': 'Telangana',
    'Chennai': 'Tamil Nadu', 'Kolkata': 'West Bengal',
    'Ahmedabad': 'Gujarat', 'Surat': 'Gujarat',
    'Lucknow': 'Uttar Pradesh', 'Kanpur': 'Uttar Pradesh',
    'Indore': 'Madhya Pradesh', 'Bhopal': 'Madhya Pradesh'
}

CUISINES = [
    'North Indian', 'South Indian', 'Chinese', 'Pizza', 'Biryani',
    'Burger', 'Desserts', 'Beverages', 'Street Food', 'Rolls',
    'Momos', 'Sandwich', 'Thali', 'Seafood', 'Continental'
]

RESTAURANT_SUFFIXES = [
    'Kitchen', 'House', 'Express', 'Bites', 'Corner',
    'Point', 'Hub', 'Palace', 'Dhaba', 'Cafe'
]


def random_time(start_hour, end_hour):
    hour = random.randint(start_hour, end_hour)
    minute = random.choice([0, 15, 30, 45])
    return f"{hour:02d}:{minute:02d}"


# -- Dirty data injection -----------------------------------------------
def corrupt_restaurant(record):
    """Randomly apply one corruption to a restaurant record."""
    corruption = random.choice([
        'null_restaurant_id',
        'null_restaurant_name',
        'negative_rating',
        'out_of_range_rating',
        'null_cuisine',
        'null_city',
        'negative_commission',
        'negative_prep_time',
        'invalid_time_format',
        'null_pincode',
    ])

    if corruption == 'null_restaurant_id':
        record['restaurant_id'] = None
    elif corruption == 'null_restaurant_name':
        record['restaurant_name'] = None
    elif corruption == 'negative_rating':
        record['rating'] = round(random.uniform(-3.0, -0.1), 1)
    elif corruption == 'out_of_range_rating':
        record['rating'] = round(random.uniform(5.5, 10.0), 1)
    elif corruption == 'null_cuisine':
        record['cuisine_type'] = None
    elif corruption == 'null_city':
        record['city'] = None
        record['state'] = None
    elif corruption == 'negative_commission':
        record['commission_rate'] = round(random.uniform(-15.0, -1.0), 2)
    elif corruption == 'negative_prep_time':
        record['average_prep_time'] = random.randint(-30, -1)
    elif corruption == 'invalid_time_format':
        record['opening_time'] = random.choice(['25:00', 'abc', '99:99', '', None])
    elif corruption == 'null_pincode':
        record['pincode'] = None

    return record


def generate_restaurants(n=TOTAL_RECORDS):
    records = []
    used_ids = []  # track IDs for duplicate injection

    for _ in tqdm(range(n), desc='Generating restaurants'):
        city = random.choice(INDIAN_CITIES)
        cuisine = random.choice(CUISINES)
        is_active = random.random() > 0.08   # ~92% active

        updated_at = datetime(2024, 1, 1) + timedelta(
            days=random.randint(0, 365),
            hours=random.randint(0, 23),
            minutes=random.randint(0, 59)
        )

        rest_id = f"REST_{str(random.randint(1000000, 9999999))}"

        record = {
            'restaurant_id':      rest_id,
            'restaurant_name':    f"{fake.last_name()} {random.choice(RESTAURANT_SUFFIXES)}",
            'cuisine_type':       cuisine,
            'city':               city,
            'state':              STATES_BY_CITY[city],
            'pincode':            str(random.randint(100000, 999999)),
            'rating':             round(random.uniform(2.5, 5.0), 1),
            'average_prep_time':  random.randint(15, 60),
            'commission_rate':    round(random.uniform(5.0, 25.0), 2),
            'opening_time':       random_time(6, 10),
            'closing_time':       random_time(21, 23),
            'is_active':          is_active,
            'updated_at':         updated_at.strftime('%Y-%m-%d %H:%M:%S'),
        }

        # -- Inject dirty data (~5%) --
        if random.random() < DIRTY_RATE:
            record = corrupt_restaurant(record)

        # -- Inject duplicate restaurant_ids (~0.8%) --
        if random.random() < DUPLICATE_RATE and len(used_ids) > 50:
            record['restaurant_id'] = random.choice(used_ids)
        else:
            used_ids.append(rest_id)

        records.append(record)

    return records


if __name__ == '__main__':
    os.makedirs(OUTPUT_PATH, exist_ok=True)
    records = generate_restaurants()
    out_file = os.path.join(OUTPUT_PATH, 'restaurants_catalog.json')
    with open(out_file, 'w') as f:
        json.dump(records, f, indent=2)
    print(f"\nDone. {len(records):,} records saved to {out_file}")

    # -- Dirty data summary --
    df = pd.DataFrame(records)
    print(f"\n{'-'*50}")
    print(f"  DIRTY DATA STATS")
    print(f"{'-'*50}")
    print(f"  Null restaurant_id:   {df['restaurant_id'].isna().sum():,}")
    print(f"  Null restaurant_name: {df['restaurant_name'].isna().sum():,}")
    print(f"  Null cuisine_type:    {df['cuisine_type'].isna().sum():,}")
    print(f"  Null city:            {df['city'].isna().sum():,}")
    print(f"  Negative ratings:     {(df['rating'] < 0).sum():,}")
    print(f"  Ratings > 5.0:        {(df['rating'] > 5.0).sum():,}")
    print(f"  Negative commission:  {(df['commission_rate'] < 0).sum():,}")
    print(f"  Negative prep_time:   {(df['average_prep_time'] < 0).sum():,}")
    print(f"  Duplicate IDs:        {df['restaurant_id'].duplicated().sum():,}")
    total_dirty = df.isnull().any(axis=1).sum() + df['restaurant_id'].duplicated().sum()
    print(f"  Total affected rows:  ~{total_dirty:,} ({total_dirty/len(df)*100:.1f}%)")
    print(f"{'-'*50}")