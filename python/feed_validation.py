#!/usr/bin/env python3
"""
feed_validation.py — lightweight Python validation for the GlowBeauty audience feed.

Reads output/glowbeauty_audience_feed.csv (produced by sql/02_build_audience_feed.sql),
checks required columns, null rates, duplicates, and email/identifier patterns,
prints a data-quality summary table, and exports:
  output/data_quality_summary.csv   — metric / value / threshold / status
  output/glowbeauty_audience_feed_clean.csv — feed + matchable_flag + dq_notes

Usage:
    python python/feed_validation.py
Run from the project root.
"""
import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FEED = ROOT / "output" / "glowbeauty_audience_feed.csv"
SUMMARY_CSV = ROOT / "output" / "data_quality_summary.csv"
CLEAN_CSV = ROOT / "output" / "glowbeauty_audience_feed_clean.csv"

EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$")
REQUIRED_COLUMNS = [
    "customer_id", "email", "hashed_email", "zip_code", "product_category",
    "last_activity_date", "total_purchases", "total_spend",
    "engagement_score", "premium_interaction_flag", "engagement_tier",
]
# Delivery-health completeness is measured on non-identifier required fields;
# hashed_email is a matchability input (see sql/03 section B note).
COMPLETENESS_FIELDS = ["zip_code", "product_category", "last_activity_date",
                       "engagement_score"]
COMPLETENESS_THRESHOLD = 95.0
MATCHABILITY_THRESHOLD = 70.0


def main() -> int:
    if not FEED.exists():
        print(f"Feed not found: {FEED}\nRun sql/02_build_audience_feed.sql first.")
        return 1

    with open(FEED, newline="") as f:
        rows = list(csv.DictReader(f))

    checks = []  # (metric, value, threshold, status)

    # 1. Schema check -----------------------------------------------------
    missing_cols = [c for c in REQUIRED_COLUMNS if c not in (rows[0].keys() if rows else [])]
    checks.append(("required_columns_present",
                   f"{len(REQUIRED_COLUMNS) - len(missing_cols)}/{len(REQUIRED_COLUMNS)}",
                   "all", "PASS" if not missing_cols else f"FAIL: missing {missing_cols}"))

    n = len(rows)
    checks.append(("feed_row_count", n, "n/a (informational)", "INFO"))

    # 2. Duplicate customer_id ---------------------------------------------
    seen, dupes = set(), 0
    for r in rows:
        if r["customer_id"] in seen:
            dupes += 1
        seen.add(r["customer_id"])
    checks.append(("duplicate_customer_ids", dupes, "0", "PASS" if dupes == 0 else "FAIL"))

    # 3. Email validity ------------------------------------------------------
    bad_email = sum(1 for r in rows if not EMAIL_RE.match((r.get("email") or "").strip()))
    checks.append(("invalid_or_missing_email", bad_email, "0",
                   "PASS" if bad_email == 0 else "FAIL"))

    # 4. Field completeness ---------------------------------------------------
    for field in COMPLETENESS_FIELDS:
        nulls = sum(1 for r in rows if not (r.get(field) or "").strip())
        pct = round(100.0 * (n - nulls) / n, 1) if n else 0.0
        checks.append((f"completeness:{field}", f"{pct}%",
                       f">={COMPLETENESS_THRESHOLD}%",
                       "PASS" if pct >= COMPLETENESS_THRESHOLD else "FAIL"))

    # 5. Identifier coverage / matchability -----------------------------------
    with_hash = sum(1 for r in rows if (r.get("hashed_email") or "").strip())
    hash_pct = round(100.0 * with_hash / n, 1) if n else 0.0
    checks.append(("hashed_email_coverage", f"{hash_pct}% ({with_hash}/{n})",
                   f">={MATCHABILITY_THRESHOLD}% (target)",
                   "PASS" if hash_pct >= MATCHABILITY_THRESHOLD else "FAIL"))

    matchable = sum(1 for r in rows
                    if EMAIL_RE.match((r.get("email") or "").strip())
                    and (r.get("hashed_email") or "").strip())
    match_pct = round(100.0 * matchable / n, 1) if n else 0.0
    checks.append(("matchability: valid email + hash", f"{match_pct}% ({matchable}/{n})",
                   f">={MATCHABILITY_THRESHOLD}% (target)",
                   "PASS" if match_pct >= MATCHABILITY_THRESHOLD else "FAIL"))

    # 6. ZIP format sanity ------------------------------------------------------
    bad_zip = sum(1 for r in rows
                  if (r.get("zip_code") or "").strip()
                  and not re.fullmatch(r"\d{5}", r["zip_code"].strip()))
    checks.append(("malformed_zip_present", bad_zip, "0",
                   "PASS" if bad_zip == 0 else "FAIL"))

    # --- print summary -------------------------------------------------------
    print(f"\n{'METRIC':45} {'VALUE':22} {'THRESHOLD':22} STATUS")
    print("-" * 100)
    for metric, value, threshold, status in checks:
        print(f"{metric:45} {str(value):22} {str(threshold):22} {status}")

    # --- write data_quality_summary.csv ---------------------------------------
    with open(SUMMARY_CSV, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["metric", "value", "threshold", "status"])
        w.writerows(checks)
    print(f"\nWrote {SUMMARY_CSV}")

    # --- write cleaned feed ----------------------------------------------------
    # Normalizations only: lowercase/strip emails; add matchable_flag + dq_notes.
    # Rows are NOT dropped — audience membership is a business decision, and the
    # matchability tradeoff is analyzed in docs/evaluation_findings.pdf.
    cleaned = []
    for r in rows:
        r = dict(r)
        email = (r.get("email") or "").strip().lower()
        r["email"] = email
        notes = []
        if not (r.get("hashed_email") or "").strip():
            notes.append("missing_hashed_email:unmatchable")
        if not (r.get("zip_code") or "").strip():
            notes.append("missing_zip")
        r["matchable_flag"] = 1 if (EMAIL_RE.match(email) and (r.get("hashed_email") or "").strip()) else 0
        r["dq_notes"] = ";".join(notes)
        cleaned.append(r)

    with open(CLEAN_CSV, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(cleaned[0].keys()))
        w.writeheader()
        w.writerows(cleaned)
    print(f"Wrote {CLEAN_CSV} ({len(cleaned)} rows)")

    failures = [c for c in checks if c[3] == "FAIL"]
    if failures:
        print(f"\n{len(failures)} check(s) FAILED "
              f"({', '.join(c[0] for c in failures)}). See docs/evaluation_findings.pdf "
              "for diagnosis and recommendations.")
        return 2
    print("\nAll checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
