#! /bin/bash -x

source /host-etc/os-release

buildah rm nvidia-driver-container || true
buildah from --name nvidia-driver-container nvcr.io/nvidia/driver:${DRIVER_VERSION}-rhcos${VERSION_ID}

buildah run nvidia-driver-container mkdir /shared/nvidia/bin -p
buildah run nvidia-driver-container cp /tmp/install.sh /shared/nvidia/
buildah run nvidia-driver-container cp -r /usr/local/bin/nvidia-driver /usr/local/bin/extract-vmlinux /shared/nvidia/bin
buildah run nvidia-driver-container cp -r /drivers /shared/nvidia/

#buildah run nvidia-driver-container 'env | sed \'s/=/="/\' | sed \'s/$/"/\' > /shared/nvidia/env'

mkdir /tmp/nvidia -p
NVIDIA_CNT_MNT=$(buildah mount nvidia-driver-container)
cp $NVIDIA_CNT_MNT/shared/nvidia /tmp/ -rv
buildah umount nvidia-driver-container

nvidia_env=$(buildah run nvidia-driver-container env)

echo "$nvidia_env" | sed 's/=/="/' | sed 's/$/"/' > /tmp/nvidia/env

source /host-etc/os-release
echo "RESOLVE_OCP_VERSION=false" >> /tmp/nvidia/env
echo "OPENSHIFT_VERSION=$OPENSHIFT_VERSION" >> /tmp/nvidia/env
echo "RHEL_VERSION=$RHEL_VERSION" >> /tmp/nvidia/env

# ---


sed 's/elfutils-libelf.x86_64//' -i /tmp/nvidia/bin/nvidia-driver
sed 's|rm -rf /lib/modules/${KERNEL_VERSION}/video||' -i /tmp/nvidia/bin/nvidia-driver
sed 's|rm -rf /lib/modules/${KERNEL_VERSION}||' -i /tmp/nvidia/bin/nvidia-driver
sed 's|dnf install -q -y --releasever=${RHEL_VERSION} "gcc-${gcc_version}"|dnf install -q -y --releasever=${RHEL_VERSION} "gcc"|' -i /tmp/nvidia/bin/nvidia-driver

# ---

OCP_CLI_VERSION=latest
OCP_CLI_URL=https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OCP_CLI_VERSION}/openshift-client-linux.tar.gz
curl -s ${OCP_CLI_URL} | tar xfz - -C /usr/local/bin oc

#OCP_VERSION=$(oc get clusterversion/version -ojsonpath={.status.desired.version})
#DRIVER_TOOLKIT_IMAGE=$(oc adm release info $OCP_VERSION --image-for=driver-toolkit)

DRIVER_TOOLKIT_IMAGE=image-registry.openshift-image-registry.svc:5000/gpu-operator-resources/entitled-driver:driver-toolkit


BUILDER_SECRETNAME=$(oc get secrets -oname | grep builder-dockercf)
DOCKER_SECRET=$(oc get $BUILDER_SECRETNAME -ojsonpath={.data.'\.dockercfg'} | base64 -d)

(echo "{ \"auths\": " ; echo "$DOCKER_SECRET" ; echo "}") > /tmp/.dockercfg
AUTH="--tls-verify=false --authfile /tmp/.dockercfg"

buildah rm ocp-driver-toolkit || true
buildah from $AUTH --name ocp-driver-toolkit $DRIVER_TOOLKIT_IMAGE

# ---

buildah run ocp-driver-toolkit mkdir -p /run/nvidia/ /shared/
buildah copy ocp-driver-toolkit /tmp/nvidia/ /shared/nvidia/
buildah copy ocp-driver-toolkit /tmp/nvidia/install.sh /tmp/
buildah run ocp-driver-toolkit dnf install -yq jq
buildah run ocp-driver-toolkit sed -i 's/_load_driver$/trap - EXIT;exit 0/' /shared/nvidia/bin/nvidia-driver
buildah run ocp-driver-toolkit bash -xc 'cd /shared/nvidia/drivers; set -o allexport; source /shared/nvidia/env; set +o allexport; export "PATH=/shared/nvidia/bin:$PATH"; rm -rf NVIDIA-Linux-x86_64-$DRIVER_VERSION ; bash -ex nvidia-driver init'

MNT=$(buildah mount ocp-driver-toolkit)
cp $MNT/usr/src/nvidia-$DRIVER_VERSION/kernel/*.ko /tmp/nvidia
buildah umount ocp-driver-toolkit
md5sum /tmp/nvidia/*.ko
