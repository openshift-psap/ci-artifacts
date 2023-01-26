#!/bin/bash

## add the following to /etc/security/limits.conf
# *                soft    nofile          20000

START_DATE=$(date +%s)
CPU_COUNT=$(grep processor /proc/cpuinfo | wc -l)

# Locust options
export LOCUST_USERS=100
export LOCUST_SPAWN_RATE=50
export LOCUST_RUN_TIME=120
export LOCUST_STOP_TIMEOUT=20
export LOCUST_RESET_STATS=1
export LOCUST_LOCUSTFILE=locustfile.py
export LOCUST_HOST=example.com
export LOCUST_CSV=Results
export LOCUST_HEADLESS=1
export LOCUST_EXIT_CODE_ON_ERROR=7
# distributed locust options
export LOCUST_EXPECT_WORKERS=${CPU_COUNT}
export LOCUST_EXPECT_WORKERS_MAX_WAIT=$((3 + ${CPU_COUNT} / 10))

# custom options
export DIFF_IS_RESULTS=1

rm -f Results_* 

locust --master &
# locust clients don't like that to be set
unset LOCUST_RUN_TIME
# give 1s for the locust coordinator to be ready
sleep 1

# set/unset options for workers
export LOCUST_CSV_FULL_HISTORY=1
for worker in $(seq 1 ${CPU_COUNT})
do
    sleep 0.1
    locust --worker &
done
wait

wget -N https://github.com/benc-uk/locust-reporter/releases/download/v1.2.2/locust-reporter -O reporter
chmod +x reporter

./reporter --prefix ${LOCUST_CSV} -outfile report-${START_DATE}.html

