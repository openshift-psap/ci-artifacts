#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
set -o errtrace
set -x

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "$THIS_DIR/config.sh"


# create namespaces first
for i in $(seq 1 ${NS_COUNT})
do
    NS=${NS_BASENAME}-${i}
    oc create ns ${NS}
    oc label namespace ${NS} modelmesh-enabled=true --overwrite=true
    oc label namespace ${NS} opendatahub.io/dashboard=true --overwrite=true
    oc apply -f ${THIS_DIR}/minio-secret.yaml -n ${NS}
done
unset NS

# start by creating all model mesh instances by adding the first inference endpoint
# of each namespace
for j in $(seq 1 ${MODEL_COUNT})
do
    for i in $(seq 1 ${NS_COUNT})
    do
        NS=${NS_BASENAME}-${i}
        oc apply -n ${NS} -f ${THIS_DIR}/servingruntime.yaml
        sed s/example-onnx-mnist/example-onnx-mnist-${j}/g ${THIS_DIR}/inferenceservice.yaml | oc apply -n ${NS} -f -
        oc apply -f  ${THIS_DIR}/sa_user.yaml -n ${NS}
    done
done
unset NS

# check for model mesh instances
for i in $(seq 1 ${NS_COUNT})
do
    NS=${NS_BASENAME}-${i}

    until [[ "$(oc get pods -n ${NS} | grep '5/5' |grep Running |wc -l)" == ${MM_POD_COUNT} ]]
    do
        echo "NS:${NS}: Waiting for the model mesh pods"
        sleep 1
    done

    unset NS
done

# test inference endpoints
for i in $(seq 1 ${NS_COUNT})
do
    if [[ "$API_ENDPOINT_CHECK" -eq 0 ]]
    then
	NS=${NS_BASENAME}-${i}
        route=$(oc -n ${NS} get routes mm-${i}ovms-1.x-model-route --template={{.spec.host}})
        INFERENCE_TOKEN=$(oc create token user-one -n ${NS})
        for i in $(seq 1 ${MODEL_COUNT})
        do
            echo "NS:${NS}: Smoke-testing endpoint example-onnx-mnist-$i"
            until curl -H "Authorization: Bearer ${INFERENCE_TOKEN}" $CURL_OPTIONS https://${route}/v2/models/example-onnx-mnist-$i/infer -d @${THIS_DIR}/input-onnx.json | jq '.outputs[] | select(.data != null)' &>/dev/null
            do
                echo "S:${NS}: Waiting for inference endpoint example-onnx-mnist-$i"
                sleep 1
            done
        done

	unset NS
    fi
done
