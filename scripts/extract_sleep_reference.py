#!/usr/bin/env python3
"""Offline, narrowly scoped Da Halo sleep/HR/SDNN/oxygen extraction. Never imports into the app."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile
from zoneinfo import ZoneInfo

STAGES = {"HKCategoryValueSleepAnalysisAsleepCore": "Core", "HKCategoryValueSleepAnalysisAsleepREM": "REM",
          "HKCategoryValueSleepAnalysisAsleepDeep": "Deep", "HKCategoryValueSleepAnalysisAwake": "Awake"}
METRICS = {"HKQuantityTypeIdentifierHeartRate": ("heartRate", "count/min"),
           "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": ("sdnn", "ms"),
           "HKQuantityTypeIdentifierOxygenSaturation": ("oxygen", "%")}
SLEEP = "HKCategoryTypeIdentifierSleepAnalysis"
def date(value): return dt.datetime.strptime(value, "%Y-%m-%d %H:%M:%S %z")
def dump(path, value): path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
def extract(archive, night, output):
    zone = ZoneInfo("Asia/Amman")
    end_day = dt.date.fromisoformat(night)
    # A noon-to-noon selection isolates the requested overnight session.
    end = dt.datetime.combine(end_day, dt.time(12), zone)
    start = end - dt.timedelta(days=1)
    rows = []
    with zipfile.ZipFile(archive) as zipped, zipped.open("apple_health_export/export.xml") as stream:
        parser = ET.iterparse(stream, events=("start", "end"))
        _, root = next(parser)
        for event, element in parser:
            if event != "end": continue
            if element.tag == "Record":
                a = element.attrib
                if a.get("sourceName") == "Da Halo" and a.get("type") in {SLEEP, *METRICS}:
                    s, e = date(a["startDate"]), date(a["endDate"])
                    if s < end and e > start:
                        rows.append({k: a[k] for k in ["type", "sourceName", "sourceVersion", "startDate", "endDate", "value", "unit"] if k in a})
            if element.tag in {"Record", "Workout", "ActivitySummary"}: root.clear()
    rows = sorted({json.dumps(r, sort_keys=True): r for r in rows}.values(), key=lambda r: (r["startDate"], r["type"], r["endDate"], r["value"]))
    sleep = [r for r in rows if r["type"] == SLEEP and r["value"] in STAGES]
    if not sleep: raise ValueError("No Da Halo stage intervals in requested night")
    intervals = [{"start": date(r["startDate"]).isoformat(), "end": date(r["endDate"]).isoformat(), "stage": STAGES[r["value"]]} for r in sleep]
    session_start, session_end = date(sleep[0]["startDate"]), max(date(r["endDate"]) for r in sleep)
    rows = [r for r in rows if date(r["startDate"]) < session_end and date(r["endDate"]) > session_start]
    observations = []
    for r in rows:
        if r["type"] not in METRICS: continue
        metric, unit = METRICS[r["type"]]
        if r.get("unit") != unit: raise ValueError(f"Unexpected unit for {metric}: {r.get('unit')}")
        # Export records may span five minutes; retain their interval and place one
        # observation at its recorded start, never expand it into a minute series.
        observations.append({"timestamp": date(r["startDate"]).isoformat(), "end": date(r["endDate"]).isoformat(),
            "metric": metric, "value": float(r["value"]), "unit": unit, "sourceName": "Da Halo",
            "sourceFile": archive.name, "recordID": hashlib.sha256(json.dumps(r, sort_keys=True).encode()).hexdigest()})
    output.mkdir(parents=True, exist_ok=True)
    dump(output / "sleep-reference.json", {"source": f"Da Halo -> Apple Health; {archive.name}; night ending {night}",
        "role": "offline vendor reference only; not independent clinical ground truth", "timeZone": "Asia/Amman", "intervals": intervals})
    dump(output / "vendor-observations.json", observations)
    dump(output / "selected-export-records.json", rows)
    with archive.open('rb') as stream: archive_hash = hashlib.file_digest(stream, 'sha256').hexdigest()
    dump(output / "export-provenance.json", {"archiveName": archive.name, "archiveSHA256": archive_hash,
        "entry": "apple_health_export/export.xml", "sourceNameFilter": "Da Halo", "nightEnding": night,
        "selection": "noon-to-noon, then sleep session overlap; only sleep/HR/SDNN/oxygen; exact duplicate records removed",
        "intervalCount": len(intervals), "observationCount": len(observations),
        "observationTiming": "One point at export start; end retained; no expansion/interpolation. Not raw 020F/0210/0211 evidence."})
    print(f"{night}: {len(intervals)} intervals, {len(observations)} vendor observations")

if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("archive", type=Path); p.add_argument("night", help="ISO date on which sleep ended"); p.add_argument("output", type=Path)
    a = p.parse_args(); extract(a.archive, a.night, a.output)
