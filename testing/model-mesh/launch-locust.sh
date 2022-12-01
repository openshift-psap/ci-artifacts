#!/bin/bash

START_DATE=$(date +%s)

source "$THIS_DIR/config.sh"

# Locust options
export LOCUST_USERS=100
export LOCUST_SPAWN_RATE=50
export LOCUST_RUN_TIME=120
export LOCUST_STOP_TIMEOUT=10
export LOCUST_RESET_STATS=1
export LOCUST_LOCUSTFILE=locustfile.py
export LOCUST_HOST=example.com
export LOCUST_CSV=Results
export LOCUST_HEADLESS=1
export LOCUST_EXIT_CODE_ON_ERROR=7

# custom options
export DIFF_IS_RESULTS=0

rm -f Results_* 

locust

wget -N https://github.com/benc-uk/locust-reporter/releases/download/v1.2.2/locust-reporter -O reporter
chmod +x reporter

./reporter --prefix ${LOCUST_CSV} -outfile report-${START_DATE}.html

