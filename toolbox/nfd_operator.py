from toolbox._common import PlaybookRun


class NFDOperator:
    """
    Commands for deploying, building and testing the NFD operator in various ways
    """
    @staticmethod
    def deploy_from_master(git_repo, image_tag=None):
        """
        Deploys the NFD operator from the given git commit

        Args:
            git_repo: The git repository to deploy from, e.g. https://github.com/openshift/cluster-nfd-operator.git
            image_tag: The NFD operator image tag UID.
        """
        opts = {
            "nfd_operator_git_repo": git_repo,
        }

        if image_tag is not None:
            opts["nfd_operator_image_tag"] = image_tag

        return PlaybookRun("nfd_operator_deploy_master", opts)
    
    @staticmethod
    def presubmit_job(git_repo, pull_number, pull_base_ref, pull_pull_sha, image_tag=None):
        """
        Deploys the NFD operator from the given git commit of a presubmit job

        Args:
            git_repo: The git repository to deploy from, e.g. https://github.com/openshift/cluster-nfd-operator.git
            pull_number: Pull request number
            pull_base_ref: Ref name of the base branch
            presubmit_pull_pull_sha: Pull request head SHA
            image_tag: The NFD operator image tag UID
        """
        opts = {
            "nfd_operator_git_repo": git_repo,
            "presubmit_pull_number": pull_number,
            "presubmit_pull_base_ref": pull_base_ref,
            "presubmit_pull_pull_sha": pull_pull_sha,
        }

        if image_tag is not None:
            opts["nfd_operator_image_tag"] = image_tag

        return PlaybookRun("nfd_operator_presubmit", opts)

    @staticmethod
    def deploy_from_operatorhub(channel=None):
        """
        Deploys the GPU Operator from OperatorHub

        Args:
            The operator hub channel to deploy. e.g. 4.7
        """
        opts = {}

        if channel is not None:
            opts["nfd_channel"] = channel

        return PlaybookRun("nfd_operator_deploy_from_operatorhub", opts)

    @staticmethod
    def undeploy_from_operatorhub():
        """
        Undeploys an NFD-operator that was deployed from OperatorHub
        """
        return PlaybookRun("nfd_operator_undeploy")
