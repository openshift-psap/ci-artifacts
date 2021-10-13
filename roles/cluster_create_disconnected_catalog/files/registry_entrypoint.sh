#!/bin/bash
set -o errexit;
set -o pipefail;
set -x

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


prepare_registry() {
    #dnf install --quiet -y httpd-tools
    #htpasswd -bBc /opt/registry/auth/htpasswd dummy dummy
    #-e "REGISTRY_AUTH=htpasswd" -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm"
    #-e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd
    #podman login localhost:5000 \
    #       --username dummy \
    #       --password dummy \
    #       --tls-verify=false

    mkdir -p /storage/registry/data


    podman run \
           --name myregistry \
           --publish 5000:5000 \
           -v /storage/registry/data:/var/lib/registry:z \
           -v /mnt/registry-cert:/certs:z \
           -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/tls.crt\
           -e REGISTRY_HTTP_TLS_KEY=/certs/tls.key \
           -e REGISTRY_COMPATIBILITY_SCHEMA1_ENABLED=true \
           docker.io/library/registry:2
}

prepare_podman
prepare_registry

sleep inf
