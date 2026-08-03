#!/usr/bin/env python3
"""Download the anonymous shared data from CloudKit, as CSV.

The CloudKit Console is fine for looking, but not for analysis. This talks to
CloudKit Web Services with a server-to-server key and pages through every
SharedSet and SharedSurvey record.

Two shapes come out:

  * wide  — one row per logged exercise, weights and reps as they are stored
            ("50,55,55"), which mirrors the records exactly;
  * long  — one row per SET (--long), which is what a regression wants:
            install, timestamp, exercise, set number, weight, reps.

Setup, once:

  1. CloudKit Console -> Tokens & Keys -> Server-to-Server Keys -> add a key.
     Keep the .pem it gives you; it is the secret. The Key ID is not.
  2. Do NOT commit the .pem. tools/.gitignore already excludes *.pem.

Usage:

    tools/export-shared-data.py --key-id <id> --key path/to/key.pem \\
        [--container iCloud.robotex.workout-aicode] \\
        [--environment production|development] \\
        [--out-dir .] [--long]

Requires only Python 3 and openssl, both already on macOS — signing shells out
to openssl so there is no dependency to install.

Note: querying a record type needs a QUERYABLE index on it in the CloudKit
schema (fetching one record by id does not). If the export comes back with a
"not marked queryable" error, add the index in the Console and deploy it.
"""
import argparse
import base64
import csv
import hashlib
import json
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HOST = "https://api.apple-cloudkit.com"
PAGE = 200                       # CloudKit's maximum per query


# ----------------------------------------------------------------- signing

def sign(message: str, key_path: Path) -> str:
    """ECDSA-SHA256 over the message, DER, base64 — what CloudKit expects."""
    try:
        proc = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(key_path)],
                              input=message.encode(), capture_output=True, check=True)
    except FileNotFoundError:
        sys.exit("openssl not found — it ships with macOS; is PATH unusual?")
    except subprocess.CalledProcessError as e:
        sys.exit(f"could not sign with {key_path}:\n{e.stderr.decode().strip()}")
    return base64.b64encode(proc.stdout).decode()


def request(path: str, body: dict, key_id: str, key_path: Path) -> dict:
    """One signed POST. The signed string is date:bodyhash:path, exactly."""
    raw = json.dumps(body).encode()
    body_hash = base64.b64encode(hashlib.sha256(raw).digest()).decode()
    date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    signature = sign(f"{date}:{body_hash}:{path}", key_path)

    req = urllib.request.Request(
        HOST + path, data=raw, method="POST",
        headers={
            "Content-Type": "application/json",
            "X-Apple-CloudKit-Request-KeyID": key_id,
            "X-Apple-CloudKit-Request-ISO8601Date": date,
            "X-Apple-CloudKit-Request-SignatureV1": signature,
        })
    try:
        with urllib.request.urlopen(req) as response:
            return json.load(response)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        # CloudKit explains itself properly in the body; the status alone does not.
        sys.exit(f"CloudKit returned {e.code}:\n{detail}")
    except urllib.error.URLError as e:
        sys.exit(f"could not reach CloudKit: {e.reason}")


# ------------------------------------------------------------------ fetch

def fetch_all(record_type: str, args) -> list:
    """Every record of one type, following continuation markers."""
    path = f"/database/1/{args.container}/{args.environment}/public/records/query"
    records, marker = [], None
    while True:
        body = {"query": {"recordType": record_type}, "resultsLimit": PAGE}
        if marker:
            body["continuationMarker"] = marker
        page = request(path, body, args.key_id, Path(args.key))
        batch = page.get("records", [])
        records += batch
        print(f"  {record_type}: {len(records)} so far")
        marker = page.get("continuationMarker")
        if not marker or not batch:
            return records


def value(record: dict, field: str):
    """One field, with CloudKit's wrapper and timestamps unwrapped."""
    entry = record.get("fields", {}).get(field)
    if entry is None:
        return ""
    v = entry.get("value")
    if entry.get("type") == "TIMESTAMP" and isinstance(v, (int, float)):
        # CloudKit timestamps are milliseconds since the epoch.
        return datetime.fromtimestamp(v / 1000, timezone.utc).isoformat()
    if isinstance(v, list):
        return ",".join(str(x) for x in v)
    return v


# ------------------------------------------------------------------ output

SET_FIELDS = ["install", "ts", "libraryKey", "exerciseHash", "primary", "secondary",
              "setCount", "weights", "reps", "bestOneRM", "hardSets", "formula"]
SURVEY_FIELDS = ["install", "ts", "logsHelpful", "graphsHelpful", "progressHelpful",
                 "wantsAdvanced", "wantsQuestions"]


def write_csv(path: Path, header: list, rows: list):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"  wrote {path}  ({len(rows)} rows)")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--key-id", required=True, help="server-to-server Key ID")
    ap.add_argument("--key", required=True, help="path to the key's .pem file")
    ap.add_argument("--container", default="iCloud.robotex.workout-aicode")
    ap.add_argument("--environment", default="production",
                    choices=["production", "development"])
    ap.add_argument("--out-dir", default=".")
    ap.add_argument("--long", action="store_true",
                    help="also write one row per set, for analysis")
    args = ap.parse_args()

    if not Path(args.key).exists():
        sys.exit(f"key file not found: {args.key}")
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    print(f"  container {args.container} ({args.environment})")

    sets = fetch_all("SharedSet", args)
    write_csv(out / "shared_sets.csv", SET_FIELDS,
              [[value(r, f) for f in SET_FIELDS] for r in sets])

    surveys = fetch_all("SharedSurvey", args)
    write_csv(out / "shared_surveys.csv", SURVEY_FIELDS,
              [[value(r, f) for f in SURVEY_FIELDS] for r in surveys])

    if args.long:
        rows = []
        for r in sets:
            weights = str(value(r, "weights")).split(",") if value(r, "weights") else []
            reps = str(value(r, "reps")).split(",") if value(r, "reps") else []
            # weights and reps are index-aligned; a short one means the set was
            # logged without that half, so pad rather than drop the row.
            for i in range(max(len(weights), len(reps))):
                rows.append([
                    value(r, "install"), value(r, "ts"),
                    value(r, "libraryKey"), value(r, "exerciseHash"),
                    value(r, "primary"), i + 1,
                    weights[i] if i < len(weights) else "",
                    reps[i] if i < len(reps) else "",
                ])
        write_csv(out / "shared_sets_long.csv",
                  ["install", "ts", "libraryKey", "exerciseHash", "primary",
                   "setNumber", "weight", "reps"], rows)

    installs = {value(r, "install") for r in sets}
    print(f"\n  {len(sets)} logged exercises from {len(installs)} installations")
    print("  (an installation is a device, not a person — reinstalling starts a new one)")


if __name__ == "__main__":
    main()
