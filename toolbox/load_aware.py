import sys

from toolbox._common import RunAnsibleRole, AnsibleRole, AnsibleMappedParams, AnsibleConstant, AnsibleSkipConfigGeneration


class LoadAware:
    """
    Commands relating to Trimaran and LoadAware testing
    """

    @AnsibleRole("load_aware_deploy_trimaran")
    @AnsibleMappedParams
    def deploy_trimaran(self):
        """
        WIP Role to deploy the Trimaran load aware scheduler

        Args:
            arg1: ...
            arg2: ...
            ...
        """

        return RunAnsibleRole(locals())
