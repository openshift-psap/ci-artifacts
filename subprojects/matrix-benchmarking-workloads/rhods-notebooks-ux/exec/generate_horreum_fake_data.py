#! /bin/python

import sys, types, os
import statistics as stats
import json
import pathlib
import datetime
import logging
logging.getLogger().setLevel(logging.INFO)

import numpy as np
import pandas as pd

ARTIFACT_DIR = pathlib.Path(__file__).parent.parent.parent.parent
BENCHMARK_NAME = "generate_horreum_fake_data"

def prepare_settings():
    settings = types.SimpleNamespace()
    for arg in sys.argv[1:]:
        k, _, v = arg.partition("=")
        settings.__dict__[k] = v

    return settings

def set_artifacts_dir():
    global ARTIFACT_DIR

    if sys.stdout.isatty():
        base_dir = pathlib.Path("/tmp") / ("ci-artifacts_" + datetime.datetime.today().strftime("%Y%m%d"))
        base_dir.mkdir(exist_ok=True)
        current_length = len(list(base_dir.glob("*__*")))
        ARTIFACT_DIR = base_dir / f"{current_length:03d}__{BENCHMARK_NAME}"
        ARTIFACT_DIR.mkdir(exist_ok=True)
    else:
        ARTIFACT_DIR = pathlib.Path(os.getcwd())

    logging.info(f"Saving artifacts files into {ARTIFACT_DIR}")

    os.environ["ARTIFACT_DIR"] = str(ARTIFACT_DIR)

def generate_fake_data(settings):
    df = pd.DataFrame(np.random.randint(0,100,size=(100, 1)), columns=list('A'))

    q1, med, q3 = stats.quantiles(df["A"])
    q90 = stats.quantiles(df["A"], n=10)[8] # 90th percentile
    q100 = max(df["A"])

    payload = {
        "$schema": "urn:rhods-summary:1.0",
        'version': settings.version,
        'user_count': int(settings.user_count),
        'sleep_factor': float(settings.sleep_factor),
        'results_url': None,
        'exec_time': {
            '100%': q100,
            '90%': q90,
            '75%': q3,
            '50%': med,
            '25%': q1
        }
    }

    major, minor = settings.version.split(".")

    start_time = datetime.datetime(2023, int(major), int(minor), 12, 00)
    completion_time = datetime.datetime(2023, int(major), int(minor), 13, 00)

    return payload, start_time, completion_time

def main():
    settings = prepare_settings()
    set_artifacts_dir()

    payload, start, stop = generate_fake_data(settings)

    # Serializing json
    json_object = json.dumps(dict(payload=payload, start=str(start), stop=str(stop)), indent=4)

    # Writing to sample.json
    with open(ARTIFACT_DIR / "data.json", "w") as f:
        print(json_object, file=f)

if __name__ == "__main__":
    sys.exit(main())
