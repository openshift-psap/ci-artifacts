#!/bin/bash
set -o errexit;
set -o pipefail;
set -x

trap "echo ERROR; sleep inf" ERR

cat ${NODE_PULLSECRET} | jq . > ~/auth.json
export REGISTRY_AUTH_FILE=~/auth.json # podman login must be able to edit the file
export VERSION=4.8

export ARTIFACT_DIR=/storage/catalog
rm -rf "${ARTIFACT_DIR}" # to be improved
mkdir -p "${ARTIFACT_DIR}"

if [[ -z "${CATALOG_NAME:-}" ]]; then
    echo "FATAL: a catalog name must be provided via CATALOG_NAME env var."
    exit 1
fi
if [[ -z "${OPERATORS:-}" ]]; then
    echo "FATAL: a comma-separated list of operators must be provided via OPERATORS env var."
    exit 1
fi


REGISTRY_IP=$(oc get svc/disconnected-registry -n default -ojsonpath={.spec.clusterIP})
#REGISTRY_ADDR=disconnected-registry.default.svc:5000
REGISTRY_ADDR=${REGISTRY_IP}:5000

####

prepare_podman() {
    dnf install --quiet -y podman

    curl --silent https://raw.githubusercontent.com/containers/buildah/master/contrib/buildahimage/stable/containers.conf > /etc/containers/containers.conf

    chmod 644 /etc/containers/containers.conf
    sed -i -e 's|^#mount_program|mount_program|g' -e '/additionalimage.*/a "/var/lib/shared",' -e 's|^mountopt[[:space:]]*=.*$|mountopt = "nodev,fsync=0"|g' /etc/containers/storage.conf

    mkdir -p /var/lib/shared/overlay-images /var/lib/shared/overlay-layers /var/lib/shared/vfs-images /var/lib/shared/vfs-layers
    touch /var/lib/shared/overlay-images/images.lock
    touch /var/lib/shared/overlay-layers/layers.lock
    touch /var/lib/shared/vfs-images/images.lock
    touch /var/lib/shared/vfs-layers/layers.lock
}

wait_for_registry() {
    while ! curl https://${REGISTRY_ADDR}/v2/_catalog -sfS -k; do
        sleep 10
    done
}

###

inspect_catalogs() {
    GRP_CURL_VERSION=1.8.2
    wget --quiet -O - https://github.com/fullstorydev/grpcurl/releases/download/v${GRP_CURL_VERSION}/grpcurl_${GRP_CURL_VERSION}_linux_x86_64.tar.gz | tar xfz -
    chmod u+x grpcurl

    get_catalog() {
        local catalog=$1

        podman run \
               --quiet \
               --authfile $NODE_PULLSECRET \
               --rm \
               --publish 50051:50051 \
               --detach \
               --name catalog \
               registry.redhat.io/redhat/$catalog-index:v$VERSION
        sleep 10

        local dest=${ARTIFACT_DIR}/catalog_${catalog}-${VERSION}_packages.out
        local retries=10

        while ! ./grpcurl -plaintext localhost:50051 \
                api.Registry/ListPackages > $dest;
        do
            echo "Catalog container not ready ... $retries tries left."
            sleep 15
            retries=$(($retries - 1))
            [[ "$retries" == 0 ]] && exit 1
        done
        local count=$(cat "$dest" | grep name | wc -l)
        echo "Found $count entries in $catalog"
        podman kill catalog
    }

    catalog_has_operator() {
        local catalog=$1
        shift
        local operator=$1

        local dest=${ARTIFACT_DIR}/catalog_${catalog}-${VERSION}_packages.out

        if [[ ! -f "$dest" ]]; then
            echo "Catalog $catalog not fetched yet ..."
            return 1
        fi

        grep -q "$operator" "$dest"
    }

    get_catalog $CATALOG_NAME

    for operator in $(echo $OPERATORS | tr , ' '); do
        if ! catalog_has_operator $CATALOG_NAME $operator; then
            echo "ERROR: $operator not in the $CATALOG_NAME catalog ..."
            return 1
        fi
    done
}

prepare_trimmed_down_catalogs() {
    wget --quiet -O - https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest-4.6/opm-linux.tar.gz | tar xfz -

    create_trimmed_down_catalog() {
        local catalog=$1
        shift
        local packages=$1

        dest_idx=${REGISTRY_ADDR}/catalog/$catalog-index:v${VERSION}
        ./opm index prune \
              --from-index registry.redhat.io/redhat/${catalog}-index:v${VERSION} \
              --packages $packages \
              --tag $dest_idx
        podman push $dest_idx \
               --tls-verify=false
    }

    create_trimmed_down_catalog $CATALOG_NAME $OPERATORS
}

mirror_operator_images() {
    mirror_images() {
        local catalog=$1

        local catalog_idx=${REGISTRY_ADDR}/catalog/$catalog-index:v${VERSION}

        local dest_registry=${REGISTRY_ADDR}/operators

        cd "${ARTIFACT_DIR}"
        oc adm catalog mirror \
           --insecure=true \
           --index-filter-by-os='linux/amd64' \
           --registry-config ${REGISTRY_AUTH_FILE} \
           $catalog_idx $dest_registry
    }
    mirror_images $CATALOG_NAME
}

create_olm_catalogs() {
    create_catalog() {
        local catalog=$1
        shift
        operators=$1

        cd "${ARTIFACT_DIR}/manifests-$catalog"-index-*

        oc apply -f imageContentSourcePolicy.yaml
        oc image mirror \
           --filename mapping.txt \
           --registry-config ${REGISTRY_AUTH_FILE} \
           --insecure
        if ! grep -q displayName catalogSource.yaml;
        then
            cat <<EOF >> catalogSource.yaml
  displayName: Disconnected $catalog catalog ($operators)
  publisher: Openshift-PSAP CI-Artifacts
  updateStrategy:
registryPoll:
  interval: 30m
EOF
        fi
        oc apply -f catalogSource.yaml
    }
    create_catalog $CATALOG_NAME $OPERATORS
}

prepare_podman
wait_for_registry

inspect_catalogs
prepare_trimmed_down_catalogs
mirror_operator_images
create_olm_catalogs

touch /tmp/healthy
sleep inf
