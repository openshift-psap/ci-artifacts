#! /usr/bin/env bash


THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"


ocm_login() {
    export OCM_ENV
    export PSAP_ODS_SECRET_PATH

    # do it in a subshell to avoid leaking the `OCM_TOKEN` secret because of `set -x`
    bash -c '
      set -o errexit
      set -o nounset

      OCM_TOKEN=$(cat "$PSAP_ODS_SECRET_PATH/ocm.token" | grep "^${OCM_ENV}=" | cut -d= -f2-)
      exec ocm login --token="$OCM_TOKEN" --url="$OCM_ENV"
      '
}


PSAP_ODS_SECRET_PATH="/var/run/psap-ods-secret-1"

for i in $(cat $PSAP_ODS_SECRET_PATH/ocm.token); do
    echo "$i" | wc -c;
    echo "$i" | cut -d= -f1;
done

set -x
md5sum $PSAP_ODS_SECRET_PATH/ocm.token

export OCM_ENV=staging
ocm_login

export OCM_ENV=production
ocm_login

export OCM_ENV=integration
ocm_login
