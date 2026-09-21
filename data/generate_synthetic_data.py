#!/usr/bin/env python3
"""
Synthetic data generator for the GlowBeauty Premium Skincare Audience Feed project.

ALL DATA IS SYNTHETIC. Names, emails, addresses, and identifiers are randomly
generated and do not correspond to real people.

Generates:
  customers.csv  (300 unique customers + 6 duplicate rows)
  events.csv     (500 events)
  products.csv   (30 products)
  orders.csv     (150 orders)

Intentionally injected quality problems (see README for the full list):
  - missing emails, invalid email formats
  - duplicate customer_id rows
  - missing ZIP codes
  - events with missing / unknown customer_ids
  - orders tied to unknown products / customers
  - opted-out customers with recent engagement (must be excluded from feed)
  - outdated events (> 90 days) and a few future-dated events

Deterministic: random.seed(42). Reference date: 2026-09-21 (90-day window).
"""
import csv
import hashlib
import random
from datetime import date, timedelta

random.seed(42)
TODAY = date(2026, 9, 21)
WINDOW_DAYS = 90
WINDOW_START = TODAY - timedelta(days=WINDOW_DAYS)
OUT = "/home/hatch/workspace/your_files/klickly-data-feed-evaluation/data"

FIRST = ["Ava", "Liam", "Maya", "Noah", "Zoe", "Ethan", "Priya", "Lucas", "Mila",
         "Arjun", "Sofia", "Mateo", "Aisha", "Leo", "Nina", "Omar", "Elena",
         "Kai", "Ruby", "Dev"]
LAST = ["Chen", "Patel", "Garcia", "Kim", "Nguyen", "Sharma", "Lopez", "Singh",
        "Rossi", "Khan", "Murphy", "Ali", "Brooks", "Das", "Fernandez", "Gupta",
        "Haddad", "Iyer", "Jones", "Kaur"]
DOMAINS = ["gmail.com", "yahoo.com", "outlook.com", "icloud.com", "protonmail.com"]
ZIPS = ["10001", "90001", "60601", "94102", "30301", "75201", "02108", "98101",
        "20001", "33101", "78701", "19103", "48201", "80202", "85001"]


def make_email(fn, ln):
    return f"{fn.lower()}.{ln.lower()}{random.randint(1, 99)}@{random.choice(DOMAINS)}"


def corrupt_email(email):
    """Produce a realistic invalid email format."""
    local, _, dom = email.partition("@")
    kind = random.choice(["no_at", "double_at", "trailing_dot", "space", "no_tld"])
    if kind == "no_at":
        return f"{local}{dom}.com"
    if kind == "double_at":
        return f"{local}@@{dom}"
    if kind == "trailing_dot":
        return f"{local}@{dom}."
    if kind == "space":
        return f"{local} @ {dom}"
    return f"{local}@mail"  # missing TLD


def sha256_hex(value):
    return hashlib.sha256(value.lower().encode()).hexdigest()


# ---------------------------------------------------------------- customers
customers = []
for i in range(1, 301):
    cid = f"C{i:04d}"
    fn, ln = random.choice(FIRST), random.choice(LAST)
    email = make_email(fn, ln)

    email_missing = (i % 13 == 4)          # ~7.7% missing email
    email_invalid = (i % 20 == 7)          # ~5% invalid format
    if email_missing:
        email = ""
    elif email_invalid:
        email = corrupt_email(email)

    # hashed_email missing for ~44% of customers with a usable email, so that
    # final-feed hashed coverage lands clearly below the 70% matchability target
    hashed = ""
    if email and not email_missing and not email_invalid:
        if i % 16 not in (0, 1, 3, 5, 6, 9, 11):
            hashed = sha256_hex(email)

    zip_code = "" if (i % 41 == 9) else random.choice(ZIPS)          # ~2.4% missing
    opt_out = 1 if (i % 12 == 0) else 0                              # ~8.3% opted out
    created = date(2022, 1, 1) + timedelta(days=random.randint(0, (TODAY - date(2022, 1, 1)).days))

    customers.append({
        "customer_id": cid, "email": email, "hashed_email": hashed,
        "zip_code": zip_code, "opt_out_flag": opt_out,
        "created_date": created.isoformat(),
    })

# Duplicate customer_id rows (survivorship rule needed downstream)
for dup_idx, src in enumerate([10, 40, 90, 140, 190, 240]):
    row = dict(customers[src - 1])
    row["zip_code"] = random.choice(ZIPS) if row["zip_code"] == "" else ""
    row["created_date"] = (TODAY - timedelta(days=random.randint(1, 60))).isoformat()
    customers.append(row)

random.shuffle(customers)
with open(f"{OUT}/customers.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["customer_id", "email", "hashed_email",
                                      "zip_code", "opt_out_flag", "created_date"])
    w.writeheader()
    w.writerows(customers)

# ---------------------------------------------------------------- products
PRODUCT_DEFS = [
    # (name, category, price, premium)
    ("Lumiere Renewal Serum", "Skincare", 120.0, 1),
    ("Hydra Dew Moisturizer", "Skincare", 95.0, 1),
    ("Vitamin C Brightening Drops", "Skincare", 88.0, 1),
    ("Retinol Night Repair", "Skincare", 110.0, 1),
    ("Peptide Eye Cream", "Skincare", 76.0, 1),
    ("Ceramide Barrier Cream", "Skincare", 64.0, 0),
    ("Gentle Foam Cleanser", "Skincare", 28.0, 0),
    ("Rosewater Toning Mist", "Skincare", 32.0, 0),
    ("Clay Detox Mask", "Skincare", 42.0, 0),
    ("SPF 50 Mineral Sunscreen", "Skincare", 38.0, 0),
    ("AHA Exfoliating Pads", "Skincare", 48.0, 0),
    ("Niacinamide Pore Serum", "Skincare", 54.0, 0),
    ("Velvet Matte Lipstick", "Makeup", 34.0, 0),
    ("Silk Finish Foundation", "Makeup", 46.0, 1),
    ("Lash Lift Mascara", "Makeup", 29.0, 0),
    ("Glow Highlighter Duo", "Makeup", 39.0, 0),
    ("Blush Cloud Stick", "Makeup", 26.0, 0),
    ("Setting Mist Pro", "Makeup", 31.0, 0),
    ("Citrus Bloom Eau de Parfum", "Fragrance", 130.0, 1),
    ("Amber Noir Parfum", "Fragrance", 145.0, 1),
    ("Fresh Linen Body Spray", "Fragrance", 24.0, 0),
    ("Santal Mist", "Fragrance", 58.0, 0),
    ("Travel Perfume Set", "Fragrance", 45.0, 0),
    ("Argan Repair Shampoo", "Haircare", 27.0, 0),
    ("Keratin Smooth Conditioner", "Haircare", 29.0, 0),
    ("Scalp Renewal Scrub", "Haircare", 36.0, 0),
    ("Leave-In Silk Cream", "Haircare", 33.0, 0),
    ("Jade Roller Set", "Tools", 22.0, 0),
    ("LED Light Therapy Mask", "Tools", 189.0, 1),
    ("Microcurrent Facial Device", "Tools", 249.0, 1),
]
products = [{"product_id": f"P{i+1:03d}", "product_name": n, "category": c,
             "price": f"{p:.2f}", "premium_flag": fl}
            for i, (n, c, p, fl) in enumerate(PRODUCT_DEFS)]
with open(f"{OUT}/products.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["product_id", "product_name", "category",
                                      "price", "premium_flag"])
    w.writeheader()
    w.writerows(products)

valid_pids = [p["product_id"] for p in products]
price_by_pid = {p["product_id"]: float(p["price"]) for p in products}
skincare_pids = [p["product_id"] for p in products if p["category"] == "Skincare"]
premium_pids = {p["product_id"] for p in products if p["premium_flag"] == 1}
valid_cids = [f"C{i:04d}" for i in range(1, 301)]

# ---------------------------------------------------------------- events
EVENT_TYPES = ["page_view", "product_view", "add_to_cart", "purchase"]
EVENT_W = [0.45, 0.30, 0.15, 0.10]


def random_event_date():
    r = random.random()
    if r < 0.93:   # in-window
        return TODAY - timedelta(days=random.randint(0, WINDOW_DAYS))
    if r < 0.99:   # outdated (> 90 days)
        return TODAY - timedelta(days=random.randint(WINDOW_DAYS + 1, 200))
    return TODAY + timedelta(days=random.randint(1, 7))  # future (invalid)


def pick_product():
    r = random.random()
    if r < 0.55:
        return random.choice(skincare_pids)
    if r < 0.75:
        return random.choice([p for p in valid_pids
                              if products[int(p[1:]) - 1]["category"] == "Makeup"])
    if r < 0.87:
        return random.choice([p for p in valid_pids
                              if products[int(p[1:]) - 1]["category"] == "Fragrance"])
    if r < 0.95:
        return random.choice([p for p in valid_pids
                              if products[int(p[1:]) - 1]["category"] == "Haircare"])
    return random.choice([p for p in valid_pids
                          if products[int(p[1:]) - 1]["category"] == "Tools"])


events = []
for i in range(1, 501):
    r = random.random()
    if r < 0.03:
        cid = ""                                   # missing customer_id
    elif r < 0.05:
        cid = f"C9{random.randint(100, 999)}"       # unknown customer_id
    else:
        cid = random.choice(valid_cids)

    pid = f"P9{random.randint(10, 99)}" if random.random() < 0.03 else pick_product()  # ~3% unknown product
    events.append({
        "event_id": f"E{i:05d}",
        "customer_id": cid,
        "event_type": random.choices(EVENT_TYPES, EVENT_W)[0],
        "event_date": random_event_date().isoformat(),
        "product_id": pid,
        "session_id": f"S{random.randint(100000, 999999)}",
    })

random.shuffle(events)
with open(f"{OUT}/events.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["event_id", "customer_id", "event_type",
                                      "event_date", "product_id", "session_id"])
    w.writeheader()
    w.writerows(events)

# ---------------------------------------------------------------- orders
orders = []
for i in range(1, 151):
    r = random.random()
    if r < 0.03:
        cid = f"C9{random.randint(100, 999)}"       # orphaned order
    else:
        cid = random.choice(valid_cids)
    pid = f"P9{random.randint(10, 99)}" if random.random() < 0.04 else pick_product()
    odate = TODAY - timedelta(days=random.randint(0, 120))
    value = round(price_by_pid.get(pid, 50.0) * random.randint(1, 3), 2)
    orders.append({
        "order_id": f"O{i:05d}",
        "customer_id": cid,
        "order_date": odate.isoformat(),
        "order_value": f"{value:.2f}",
        "product_id": pid,
    })

random.shuffle(orders)
with open(f"{OUT}/orders.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["order_id", "customer_id", "order_date",
                                      "order_value", "product_id"])
    w.writeheader()
    w.writerows(orders)

print(f"customers: {len(customers)} rows, events: {len(events)}, "
      f"products: {len(products)}, orders: {len(orders)}")
