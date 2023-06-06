#!/usr/bin/env python3

import sys, os
import pathlib
import subprocess
import logging
logging.getLogger().setLevel(logging.INFO)
import datetime
import time
import functools

import yaml
import fire

TESTING_THIS_DIR = pathlib.Path(__file__).absolute().parent
TESTING_UTILS_DIR = TESTING_THIS_DIR.parent / "utils"
PSAP_ODS_SECRET_PATH = pathlib.Path(os.environ.get("PSAP_ODS_SECRET_PATH", "/env/PSAP_ODS_SECRET_PATH/not_set"))
LIGHT_PROFILE = "light"

sys.path.append(str(TESTING_THIS_DIR.parent))
from common import env, config, run, rhods, visualize


initialized = False
def init(ignore_secret_path=False, apply_preset_from_pr_args=True):
    global initialized
    if initialized:
        logging.debug("Already initialized.")
        return
    initialized = True

    env.init()
    config.init(TESTING_THIS_DIR)

    if apply_preset_from_pr_args:
        config.ci_artifacts.apply_preset_from_pr_args()

    if not ignore_secret_path and not PSAP_ODS_SECRET_PATH.exists():
        raise RuntimeError("Path with the secrets (PSAP_ODS_SECRET_PATH={PSAP_ODS_SECRET_PATH}) does not exists.")

    if os.environ.get("JOB_NAME_SAFE", "").endswith("-light"):
        logging.info(f"Running a light test, applying the '{LIGHT_PROFILE}' profile")
        config.ci_artifacts.apply_preset(LIGHT_PROFILE)


def entrypoint(ignore_secret_path=False, apply_preset_from_pr_args=True):
    def decorator(fct):
        @functools.wraps(fct)
        def wrapper(*args, **kwargs):
            init(ignore_secret_path, apply_preset_from_pr_args)
            fct(*args, **kwargs)

        return wrapper
    return decorator

# ---

@entrypoint()
def prepare_ci():
    """
    Prepares the cluster and the namespace for running Load-Aware scale tests
    """

    install_ocp_pipelines()

    run.run("./run_toolbox.py from_config cluster capture_environment --suffix sample")


@entrypoint()
def test_ci():
    """
    Runs the Load-Aware scale test from the CI
    """

    logging.info("Nothing to do to run the test.")

    run.run("./run_toolbox.py from_config cluster capture_environment --suffix sample")


@entrypoint(ignore_secret_path=True, apply_preset_from_pr_args=False)
def generate_plots_from_pr_args():
    """
    Generates the Load-Aware plots from the PR arguments
    """

    visualize.download_and_generate_visualizations()


@entrypoint()
def cleanup_cluster():
    """
    Restores the cluster to its original state
    """
    # _Not_ executed in OpenShift CI cluster (running on AWS). Only required for running on bare-metal environments.
    logging.info("Cleaning up cluster and uninstall pipelines")

    uninstall_ocp_pipelines()



def install_ocp_pipelines():
    installed_csv_cmd = run.run("oc get csv -oname", capture_stdout=True)
    if PIPELINES_OPERATOR_MANIFEST_NAME in installed_csv_cmd.stdout:
        logging.info(f"Operator '{PIPELINES_OPERATOR_MANIFEST_NAME}' is already installed.")
        return

    run.run(f"ARTIFACT_TOOLBOX_NAME_SUFFIX=_pipelines ./run_toolbox.py cluster deploy_operator redhat-operators {PIPELINES_OPERATOR_MANIFEST_NAME} all")

def uninstall_ocp_pipelines():
    installed_csv_cmd = run.run("oc get csv -oname", capture_stdout=True)
    if PIPELINES_OPERATOR_MANIFEST_NAME not in installed_csv_cmd.stdout:
        logging.info("Pipelines Operator is not installed")
        return

    run.run(f"oc delete tektonconfigs.operator.tekton.dev --all")
    PIPELINES_OPERATOR_NAMESPACE = "openshift-operators"
    run.run(f"oc delete sub/{PIPELINES_OPERATOR_MANIFEST_NAME} -n {PIPELINES_OPERATOR_NAMESPACE}")
    run.run(f"oc delete csv -n {PIPELINES_OPERATOR_NAMESPACE} -loperators.coreos.com/{PIPELINES_OPERATOR_MANIFEST_NAME}.{PIPELINES_OPERATOR_NAMESPACE}")
# ---

class Entrypoint:
    """
    Commands for launching the Load-Aware CI tests
    """

    def __init__(self):
        self.cleanup_cluster_ci = cleanup_cluster

        self.prepare_ci = prepare_ci
        self.test_ci = test_ci

        self.generate_plots_from_pr_args = generate_plots_from_pr_args


def main():
    # Print help rather than opening a pager
    fire.core.Display = lambda lines, out: print(*lines, file=out)

    fire.Fire(Entrypoint())


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as e:
        logging.error(f"Command '{e.cmd}' failed --> {e.returncode}")
        sys.exit(1)
    except KeyboardInterrupt:
        print() # empty line after ^C
        logging.error(f"Interrupted.")
        sys.exit(1)
