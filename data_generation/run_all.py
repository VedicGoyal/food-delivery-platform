import subprocess
import sys
import os
from datetime import datetime, timedelta

# Dates to generate daily files for (last 7 days by default)
NUM_DAYS = 7
dates = [
    (datetime.today() - timedelta(days=i)).strftime('%Y-%m-%d')
    for i in range(1, NUM_DAYS + 1)
]

scripts_dir = os.path.dirname(__file__)

def run(script, *args):
    cmd = [sys.executable, os.path.join(scripts_dir, script)] + list(args)
    print(f"\n{'='*60}")
    print(f"Running: {' '.join(cmd)}")
    print('='*60)
    result = subprocess.run(cmd)
    if result.returncode != 0:
        print(f"ERROR: {script} failed. Stopping.")
        sys.exit(1)

# Step 1: Master data (no date dependency)
run('generate_customers.py')
run('generate_restaurants.py')
run('generate_agents.py')

# Step 2: Daily transactional data (date-dependent, orders before payments)
for date in dates:
    run('generate_orders.py', date)
    run('generate_payments.py', date)

print("\n" + "="*60)
print("ALL DATA GENERATION COMPLETE.")
print("="*60)