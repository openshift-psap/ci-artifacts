
source "$THIS_DIR/config.sh"

NB_USERS=100
USER_SPAWN_RATE=10
DESTINATION=Results
RUN_TIME=60
STOP_TIMEOUT=10
LOCUSTFILE=locustfile.py

ROUTE=example.com

rm -f Results_* 

locust --headless --users ${NB_USERS} --spawn-rate ${USER_SPAWN_RATE} --csv ${DESTINATION} --run-time ${RUN_TIME} --stop-timeout ${STOP_TIMEOUT} -f ${LOCUSTFILE} --host https://${ROUTE}

wget -N https://github.com/benc-uk/locust-reporter/releases/download/v1.2.2/locust-reporter -O reporter
chmod +x reporter

./reporter --prefix ${DESTINATION}
