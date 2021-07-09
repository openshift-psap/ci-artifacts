from toolbox._common import run_ansible_playbook
import secrets


class NFD:
    """
    Commands for NFD related tasks
    """
    @staticmethod
    def has_gpu_nodes():
        """
        Checks if the cluster has GPU nodes
        """
        run_ansible_playbook("nfd_test_gpu")

    @staticmethod
    def has_labels():
        """
        Checks if the cluster has NFD labels
        """
        run_ansible_playbook("nfd_has_labels")

    @staticmethod
    def wait_gpu_nodes():
        """
        Wait until nfd find GPU nodes
        """
        run_ansible_playbook("nfd_wait_gpu")

    @staticmethod
    def wait_labels():
        """
        Wait until nfd labels the nodes
        """
        run_ansible_playbook("nfd_wait_labels")
