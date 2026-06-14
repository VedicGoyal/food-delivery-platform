import pandas as pd
from faker import Faker
import random
from datetime import datetime, timedelta
from tqdm import tqdm
import os
import sys

fake = Faker('en_IN')
random.seed(42)
Faker.seed(42)

OUTPUT_PATH = os.path.join(os.path.dirname(__file__), '..', 'output', 'batch', 'payments')

# -- Dirty data injection rates -----------------------------------------
DIRTY_RATE       = 0.05   # 5% of payment records get corrupted
DUPLICATE_RATE   = 0.008  # ~0.8% duplicate payment_ids
ORPHAN_FK_RATE   = 0.012  # ~1.2% orphan order_ids

PAYMENT_METHODS  = ['UPI', 'CARD', 'CASH', 'WALLET']
METHOD_WEIGHTS   = [0.45, 0.25, 0.20, 0.10]
GATEWAYS         = ['Razorpay', 'Paytm', 'Stripe']
GATEWAY_WEIGHTS  = [0.50, 0.35, 0.15]
PAY_STATUSES     = ['SUCCESS', 'FAILED', 'PENDING', 'REFUNDED']
STATUS_WEIGHTS   = [0.80, 0.10, 0.05, 0.05]
REFUND_STATUSES  = ['NONE', 'INITIATED', 'COMPLETED']


# -- Dirty data injection -----------------------------------------------
def corrupt_payment(record):
    """Randomly apply one corruption to a payment record."""
    corruption = random.choice([
        'null_payment_id',
        'negative_amount',
        'zero_amount',
        'invalid_payment_method',
        'invalid_payment_status',
        'null_payment_timestamp',
        'amount_mismatch',
        'invalid_gateway',
        'negative_refund_amount',
        'null_card_last4_for_card',
    ])

    if corruption == 'null_payment_id':
        record['payment_id'] = None
    elif corruption == 'negative_amount':
        record['amount'] = round(random.uniform(-1000, -10), 2)
    elif corruption == 'zero_amount':
        record['amount'] = 0
    elif corruption == 'invalid_payment_method':
        record['payment_method'] = random.choice([
            'BITCOIN', 'CHEQUE', 'PAYPAL', '', 'UNKNOWN', 'CRYPTO'
        ])
    elif corruption == 'invalid_payment_status':
        record['payment_status'] = random.choice([
            'SUCESS', 'COMPLETD', 'DONE', '', 'PROCESSED', 'APPROVED'
        ])
    elif corruption == 'null_payment_timestamp':
        record['payment_timestamp'] = None
    elif corruption == 'amount_mismatch':
        # Payment amount doesn't match the order's final_amount
        record['amount'] = round(record['amount'] + random.uniform(100, 800), 2)
    elif corruption == 'invalid_gateway':
        record['payment_gateway'] = random.choice([
            'UnknownGW', '', None, 'TestGateway', 'DEPRECATED'
        ])
    elif corruption == 'negative_refund_amount':
        record['refund_amount'] = round(random.uniform(-500, -10), 2)
        record['refund_status'] = 'COMPLETED'
    elif corruption == 'null_card_last4_for_card':
        # Force card_last4 to None even when payment_method is CARD
        if record['payment_method'] == 'CARD':
            record['card_last4'] = None

    return record


def generate_payments_for_date(date_str):
    orders_path = os.path.join(
        os.path.dirname(__file__), '..', 'output', 'batch', 'orders', f'orders_raw_{date_str}.csv'
    )
    if not os.path.exists(orders_path):
        print(f"ERROR: Orders file not found at {orders_path}")
        print("Run generate_orders.py first for this date.")
        sys.exit(1)

    orders_df = pd.read_csv(orders_path, usecols=['order_id', 'final_amount', 'order_placed_at'])
    records = []
    used_ids = []   # for duplicate injection
    dirty_count = 0

    # Orphan order_id pool - IDs that do NOT exist in orders
    orphan_order_ids = [f"ORD_INVALID_{i}" for i in range(1, 101)]

    for _, row in tqdm(orders_df.iterrows(), total=len(orders_df), desc=f'Generating payments for {date_str}'):
        method = random.choices(PAYMENT_METHODS, weights=METHOD_WEIGHTS)[0]
        status = random.choices(PAY_STATUSES, weights=STATUS_WEIGHTS)[0]
        is_refunded = status == 'REFUNDED'

        # Handle potential NULL order_placed_at from dirty orders
        try:
            placed_at = datetime.strptime(str(row['order_placed_at']), '%Y-%m-%d %H:%M:%S')
        except (ValueError, TypeError):
            placed_at = datetime(2024, 6, 15, 12, 0, 0)  # fallback timestamp

        pay_timestamp = placed_at + timedelta(seconds=random.randint(10, 120))

        pay_id = f"PAY_{random.randint(10000000, 99999999)}"

        # -- Pick order_id (with orphan injection) --
        order_id = random.choice(orphan_order_ids) if random.random() < ORPHAN_FK_RATE else row['order_id']

        # Handle potential NaN final_amount from dirty orders
        try:
            amount = float(row['final_amount'])
        except (ValueError, TypeError):
            amount = round(random.uniform(100, 1500), 2)

        record = {
            'payment_id':       pay_id,
            'order_id':         order_id,
            'amount':           amount,
            'payment_method':   method,
            'payment_gateway':  random.choices(GATEWAYS, weights=GATEWAY_WEIGHTS)[0],
            'payment_status':   status,
            'payment_timestamp':pay_timestamp.strftime('%Y-%m-%d %H:%M:%S'),
            'refund_status':    random.choice(['INITIATED', 'COMPLETED']) if is_refunded else 'NONE',
            'refund_amount':    round(amount * random.uniform(0.5, 1.0), 2) if is_refunded else None,
            'card_last4':       str(random.randint(1000, 9999)) if method == 'CARD' else None,
        }

        # -- Inject dirty data (~5%) --
        if random.random() < DIRTY_RATE:
            record = corrupt_payment(record)
            dirty_count += 1

        # -- Inject duplicate payment_ids (~0.8%) --
        if random.random() < DUPLICATE_RATE and len(used_ids) > 100:
            record['payment_id'] = random.choice(used_ids)
        else:
            used_ids.append(pay_id)

        records.append(record)

    return pd.DataFrame(records), dirty_count


if __name__ == '__main__':
    if len(sys.argv) > 1:
        date_str = sys.argv[1]
    else:
        date_str = (datetime.today() - timedelta(days=1)).strftime('%Y-%m-%d')

    os.makedirs(OUTPUT_PATH, exist_ok=True)
    df, dirty_count = generate_payments_for_date(date_str)

    out_file = os.path.join(OUTPUT_PATH, f'payments_{date_str}.parquet')
    df.to_parquet(out_file, index=False)
    print(f"\nDone. {len(df):,} rows saved to {out_file}")

    # -- Dirty data summary --
    print(f"\n{'-'*50}")
    print(f"  DIRTY DATA STATS - Payments ({date_str})")
    print(f"{'-'*50}")
    print(f"  Null payment_id:      {df['payment_id'].isna().sum():,}")
    print(f"  Null timestamp:       {df['payment_timestamp'].isna().sum():,}")
    print(f"  Negative amounts:     {(df['amount'] < 0).sum():,}")
    print(f"  Zero amounts:         {(df['amount'] == 0).sum():,}")
    print(f"  Orphan order_ids:     {df['order_id'].astype(str).str.contains('INVALID', na=False).sum():,}")
    print(f"  Duplicate payment_ids:{df['payment_id'].duplicated().sum():,}")
    print(f"  Corrupted records:    ~{dirty_count:,} ({dirty_count/len(df)*100:.1f}%)")
    print(f"{'-'*50}")
