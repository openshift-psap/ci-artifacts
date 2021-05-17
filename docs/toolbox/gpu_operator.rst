============
GPU Operator
============

Deployment
==========

* Deploy from OperatorHub

.. code-block:: shell

    toolbox/gpu-operator/deploy_from_operatorhub.sh [<version>]
    toolbox/gpu-operator/undeploy_from_operatorhub.sh


* List the versions available from OperatorHub

(not 100% reliable, the connection may timeout)

.. code-block:: shell

    toolbox/gpu-operator/list_version_from_operator_hub.sh

**Usage:**

.. code-block:: shell

    toolbox/gpu-operator/list_version_from_operator_hub.sh [<package-name> [<catalog-name>]]
    toolbox/gpu-operator/list_version_from_operator_hub.sh --help

*Default values:*

.. code-block:: shell

    package-name: gpu-operator-certified
    catalog-name: certified-operators
    namespace: openshift-marketplace (controlled with NAMESPACE environment variable)


* Deploy from NVIDIA helm repository

.. code-block:: shell

    toolbox/gpu-operator/list_version_from_helm.sh
    toolbox/gpu-operator/deploy_from_helm.sh <helm-version>
    toolbox/gpu-operator/undeploy_from_helm.sh


* Deploy from a custom commit.

.. code-block:: shell

    toolbox/gpu-operator/deploy_from_commit.sh <git repository> <git reference> [gpu_operator_image_tag_uid]

**Example:**

.. code-block:: shell

    toolbox/gpu-operator/deploy_from_commit.sh https://github.com/NVIDIA/gpu-operator.git master

Configuration
=============

* Set a custom repository list to use in the GPU Operator
  ``ClusterPolicy``

*Using a repo-list file*

.. code-block:: shell

   toolbox/gpu-operator/set_repo-config.sh /path/to/repo.list [dest-dir-in-pod]

**Default values**:

- *dest-dir-in-pod*: ``/etc/distro.repos.d``

*Using RHEL 8.4-beta repo-list*

Note that this currently requires the deployment of a Red Hat internal CA PEM `file <https://github.com/openshift/shared-secrets/blob/master/mirror/ops-mirror.pem>`_.

.. code-block:: shell

   toolbox/gpu-operator/set_repo-config.sh --rhel-beta


Testing and Waiting
===================

* Wait for the GPU Operator deployment and validate it

.. code-block:: shell

    toolbox/gpu-operator/wait_deployment.sh


* Run `GPU-burn_` to validate that all the GPUs of all the nodes can
  run workloads

.. code-block:: shell

    toolbox/gpu-operator/run_gpu_burn.sh [gpu-burn runtime, in seconds]

**Default values:**

.. code-block:: shell

  gpu-burn runtime: 30

.. _GPU-burn: https://github.com/openshift-psap/gpu-burn


Troubleshooting
===============

* Capture GPU operator possible issues

(entitlement, NFD labelling, operator deployment, state of resources
in gpu-operator-resources, ...)

.. code-block:: shell

    toolbox/entitlement/test.sh
    toolbox/nfd/has_nfd_labels.sh
    toolbox/nfd/has_gpu_nodes.sh
    toolbox/gpu-operator/wait_deployment.sh
    toolbox/gpu-operator/run_gpu_burn.sh 30
    toolbox/gpu-operator/capture_deployment_state.sh


or all in one step:

.. code-block:: shell

    toolbox/gpu-operator/diagnose.sh

or with the must-gather script:

.. code-block:: shell

    toolbox/gpu-operator/must-gather.sh

or with the must-gather image:

.. code-block:: shell

    oc adm must-gather --image=quay.io/openshift-psap/ci-artifacts:latest --dest-dir=/tmp/must-gather -- gpu-operator_gather


Cleaning Up
===========

* Uninstall and cleanup stalled resources

``helm`` (in particular) fails to deploy when any resource is left from
a previously failed deployment, eg:

.. code-block::

    Error: rendered manifests contain a resource that already
    exists. Unable to continue with install: existing resource
    conflict: namespace: , name: gpu-operator, existing_kind:
    rbac.authorization.k8s.io/v1, Kind=ClusterRole, new_kind:
    rbac.authorization.k8s.io/v1, Kind=ClusterRole

.. code-block::

    toolbox/gpu-operator/cleanup_resources.sh
