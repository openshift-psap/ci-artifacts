#! /bin/bash -e

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${THIS_DIR}/../_common.sh

export ANSIBLE_OPTS="${ANSIBLE_OPTS} -e @${THIS_DIR}/custom_operands.json"
${THIS_DIR}/deploy_from_operatorhub.sh $@
