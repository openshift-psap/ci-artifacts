#! /bin/bash -e

usage() {
    cat <<EOF

Deploys a cluster-wide entitlement key & RHSM config file or a YUM repo client-auth key and certificate with the help of
MachineConfig resources.

Usage: $0 [--pem=<pem_key>] [--yum-client-auth=<pem>]

Arguments:
     --pem=<pem_key>         Deploy <pem_key> PEM key and RHSM config file on the cluster
     --yum-client-auth=<pem> Deploy <pem> yum client-auth PEM key and cert file on the cluster
EOF
    echo ""
}

ENTITLEMENT_PEM=""
YUM_CLIENT_AUTH_FILE=""

until [ "$#" -lt 1 ]; do
  if [[ "$1" != "--"*"="* ]]; then
    echo "FATAL: unknown flag $1, make sure to include an equals sign between the flag and the value"
    usage
    exit 1
  fi

  value=${1#--*=}
  flag=${1%=*}

  if [[ "${flag}" == "--pem" ]]; then
        ENTITLEMENT_PEM="${value}"
  elif [[ "${flag}" == "--yum-client-auth" ]]; then
        YUM_CLIENT_AUTH_FILE="${value}"
  fi

  shift
done

if [[ "$ENTITLEMENT_PEM" ]] && [[ "$YUM_CLIENT_AUTH_FILE" ]]; then
  echo "FATAL: Having both entitlement and yum client auth certificates is currently unsupported"
  usage
  exit 1
fi

if [[ -z "$ENTITLEMENT_PEM" ]] && [[ -z "$YUM_CLIENT_AUTH_FILE" ]]; then
  echo "FATAL: Please provide at least one flag"
  usage
  exit 1
fi

if [[ "$ENTITLEMENT_PEM" ]]; then
  ANSIBLE_OPTS="${ANSIBLE_OPTS} -e entitlement_pem=${ENTITLEMENT_PEM}"
  echo "Using '$ENTITLEMENT_PEM' as PEM key"
fi

if [[ "$YUM_CLIENT_AUTH_FILE" ]]; then
  ANSIBLE_OPTS="${ANSIBLE_OPTS} -e entitlement_repo_yum_client_auth_pem_file=${YUM_CLIENT_AUTH_FILE}"
  echo "Using '$YUM_CLIENT_AUTH_FILE' as yum client auth credentials"
fi


THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${THIS_DIR}/../_common.sh

exec ansible-playbook ${ANSIBLE_OPTS} playbooks/entitlement_deploy.yml
