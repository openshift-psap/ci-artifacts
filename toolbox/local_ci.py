from toolbox._common import run_ansible_playbook
import secrets
import os


class LocalCI:
    """
    Commands to run the CI scripts in a container environment similar to the one used by the CI
    """
    @staticmethod
    def deploy(ci_command, git_repository, git_reference, tag_uid=None):
        """
        Runs a given CI command

        Args:
            ci_command: The CI command to run, for example "run gpu-ci"
            git_repository: The git repository to run the command from, e.g. https://github.com/openshift-psap/ci-artifacts.git
            git_reference: The git ref to run the command from, e.g. master
            tag_uid: The local CI image tag UID 
        """

        if tag_uid is None:
            tag_uid = secrets.token_hex(4)

        opts = {
            "local_ci_git_repo": git_repository,
            "local_ci_git_ref": git_reference,
            "local_ci_image_tag_uid": tag_uid,
        }

        os.environ["LOCAL_CI_COMMAND"] = ci_command

        run_ansible_playbook("local-ci_deploy", opts)

    @staticmethod
    def cleanup():
        """
        Clean the local CI artifacts
        """
        run_ansible_playbook("local-ci_cleanup")
