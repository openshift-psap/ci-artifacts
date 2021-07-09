from toolbox._common import run_ansible_playbook


class Cluster:
    """
    Commands relating to cluster scaling, upgrading and environment capture
    """
    @staticmethod
    def set_scale(instance_type, scale, force=False):
        """
        Ensures that the cluster has exactly `scale` nodes with instance_type `instance_type`

        If the machinesets of the given instance type already have the required total number of replicas,
        their replica parameters will not be modified.
        Otherwise,
        - If there's only one machineset with the given instance type, its replicas will be set to the value of this parameter.

        - If there are other machinesets with non-zero replicas, the playbook will fail, unless the 'force_scale' parameter is
        set to true. In that case, the number of replicas of the other machinesets will be zeroed before setting the replicas
        of the first machineset to the value of this parameter."

        Args:
            instance_type: The instance type to use, for example, g4dn.xlarge
            scale: The number of required nodes with given instance type
        """
        opts = {
                "machineset_instance_type": instance_type,
                "scale": scale,
            }

        if force:
            opts = {**opts, "force_scale": "true"}

        run_ansible_playbook("cluster_set_scale", opts)

    @staticmethod
    def upgrade_to_image(image):
        """
        Upgrades the cluster to the given image

        Args:
            image: The image to upgrade the cluster to
        """
        run_ansible_playbook("cluster_upgrade_to_image", {"cluster_upgrade_image": image})

    @staticmethod
    def capture_environment():
        """
        Captures the cluster environment

        Args:
            image: The image to upgrade the cluster to
        """
        run_ansible_playbook("capture_environment")
