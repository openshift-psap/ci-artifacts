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

PIPELINES_OPERATOR_MANIFEST_NAME = "openshift-pipelines-operator-rh"

TESTING_PIPELINES_DIR = pathlib.Path(__file__).absolute().parent
TESTING_UTILS_DIR = TESTING_PIPELINES_DIR.parent / "utils"
PSAP_ODS_SECRET_PATH = pathlib.Path(os.environ.get("PSAP_ODS_SECRET_PATH", "/env/PSAP_ODS_SECRET_PATH/not_set"))
LIGHT_PROFILE = "light"

sys.path.append(str(TESTING_PIPELINES_DIR.parent))
from common import env, config, run, rhods, visualize

initialized = False
def init(ignore_secret_path=False):
    global initialized
    if initialized:
        logging.debug("Already initialized.")
        return
    initialized = True

    env.init()
    config.init(TESTING_PIPELINES_DIR)

    if not ignore_secret_path and not PSAP_ODS_SECRET_PATH.exists():
        raise RuntimeError("Path with the secrets (PSAP_ODS_SECRET_PATH={PSAP_ODS_SECRET_PATH}) does not exists.")

    server_url = run.run("oc whoami --show-server", capture_stdout=True).stdout.strip()

    if server_url.endswith("apps.bm.example.com:6443") or "kubernetes.default" in server_url:
        ICELAKE_PROFILE = "icelake"
        logging.info(f"Running in the Icelake cluster, applying the '{ICELAKE_PROFILE}' profile")
        config.ci_artifacts.apply_preset(ICELAKE_PROFILE)

    if os.environ.get("JOB_NAME_SAFE", "").endswith("-light"):
        logging.info(f"Running a light test, applying the '{LIGHT_PROFILE}' profile")
        config.ci_artifacts.apply_preset(LIGHT_PROFILE)


def entrypoint(ignore_secret_path=False):
    def decorator(fct):
        @functools.wraps(fct)
        def wrapper(*args, **kwargs):
            init(ignore_secret_path)
            fct(*args, **kwargs)

        return wrapper
    return decorator
# ---

def customize_rhods():
    if not config.ci_artifacts.get_config("rhods.operator.stop"):
        return

    run.run("oc scale deploy/rhods-operator --replicas=0 -n redhat-ods-operator")
    time.sleep(10)


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


def create_dsp_application():
    run.run("./run_toolbox.py from_config pipelines deploy_application")


@entrypoint()
def prepare_rhods():
    """
    Prepares the cluster for running RHODS pipelines scale tests.
    """
    install_ocp_pipelines()

    token_file = PSAP_ODS_SECRET_PATH / config.ci_artifacts.get_config("secrets.brew_registry_redhat_io_token_file")
    rhods.install(token_file)

    run.run("./run_toolbox.py rhods wait_ods")
    customize_rhods()
    run.run("./run_toolbox.py rhods wait_ods")

    run.run("./run_toolbox.py from_config cluster deploy_ldap")


def compute_node_requirement(driver=False, sutest=False):
    if (not driver and not sutest) or (sutest and driver):
        raise ValueError("compute_node_requirement must be called with driver=True or sutest=True")

    if driver:
        cluster_role = "driver"
        # from the right namespace, get a hint of the resource request with these commands:
        # oc get pods -oyaml | yq .items[].spec.containers[].resources.requests.cpu -r | awk NF | grep -v null | python -c "import sys; print(sum(int(l.strip()[:-1]) for l in sys.stdin))"
        # --> 1090
        # oc get pods -oyaml | yq .items[].spec.containers[].resources.requests.memory -r | awk NF | grep -v null | python -c "import sys; print(sum(int(l.strip()[:-2]) for l in sys.stdin))"
        # --> 2668
        cpu_count = 1.5
        memory = 3

    if sutest:
        cluster_role = "sutest"
        # must match 'roles/local_ci_run_multi/templates/job.yaml.j2'
        cpu_count = 1
        memory = 2

    machine_type = config.ci_artifacts.get_config("clusters.create.ocp.compute.type")
    user_count = config.ci_artifacts.get_config("tests.pipelines.user_count")

    logfile = env.ARTIFACT_DIR / f'sizing_{cluster_role}'
    proc = run.run(f"{TESTING_UTILS_DIR / 'sizing' / 'sizing'} {machine_type} {user_count} {cpu_count} {memory} > {logfile}", check=False)

    return proc.returncode


@entrypoint()
def prepare_pipelines_namespace():
    """
    Prepares the namespace for running a pipelines scale test.
    """

    namespace = config.ci_artifacts.get_config("rhods.pipelines.namespace")
    if run.run(f'oc get project "{namespace}" 2>/dev/null', check=False).returncode != 0:
        run.run(f'oc new-project "{namespace}" --skip-config-write >/dev/null')
    else:
        logging.warning(f"Project {namespace} already exists.")
        (env.ARTIFACT_DIR / "PROJECT_ALREADY_EXISTS").touch()

    run.run(f"oc label namespace/{namespace} opendatahub.io/dashboard=true --overwrite")

    label_key = config.ci_artifacts.get_config("rhods.pipelines.namespace_label.key")
    label_value = config.ci_artifacts.get_config("rhods.pipelines.namespace_label.value")
    run.run(f"oc label namespace/{namespace} '{label_key}={label_value}' --overwrite")

    dedicated = "{}" if config.ci_artifacts.get_config("clusters.sutest.compute.dedicated") \
        else '{value: ""}' # delete the toleration/node-selector annotations, if it exists

    run.run(f"./run_toolbox.py from_config cluster set_project_annotation --prefix sutest --suffix pipelines_node_selector --extra '{dedicated}'")
    run.run(f"./run_toolbox.py from_config cluster set_project_annotation --prefix sutest --suffix pipelines_toleration --extra '{dedicated}'")

    create_dsp_application()


@entrypoint()
def prepare_test_driver_namespace():
    """
    Prepares the cluster for running the multi-user ci-artifacts operations
    """

    namespace = config.ci_artifacts.get_config("base_image.namespace")
    service_account = config.ci_artifacts.get_config("base_image.user.service_account")
    role = config.ci_artifacts.get_config("base_image.user.role")

    #
    # Prepare the driver namespace
    #
    run.run(f"oc new-project '{namespace}' --skip-config-write >/dev/null 2>/dev/null || true")

    dedicated = "{}" if config.ci_artifacts.get_config("clusters.driver.compute.dedicated") \
        else '{value: ""}' # delete the toleration/node-selector annotations, if it exists

    run.run(f"./run_toolbox.py from_config cluster set_project_annotation --prefix driver --suffix test_node_selector --extra '{dedicated}'")
    run.run(f"./run_toolbox.py from_config cluster set_project_annotation --prefix driver --suffix test_toleration --extra '{dedicated}'")

    #
    # Prepare the driver machineset
    #

    if not config.ci_artifacts.get_config("clusters.driver.is_metal"):
        nodes_count = config.ci_artifacts.get_config("clusters.driver.compute.machineset.count")
        extra = ""
        if nodes_count is None:
            node_count = compute_node_requirement(driver=True)
            extra = f"--extra '{{scale: {node_count}}}'"

        run.run(f"./run_toolbox.py from_config cluster set_scale --prefix=driver {extra}")

    #
    # Prepare the container image
    #

    if config.ci_artifacts.get_config("base_image.repo.ref_prefer_pr") and (pr_number := os.environ.get("PULL_NUMBER")):
        pr_ref = f"refs/pull/{pr_number}/head"

        logging.info(f"Setting '{pr_ref}' as ref for building the base image")
        config.ci_artifacts.set_config("base_image.repo.ref", pr_ref)
        config.ci_artifacts.set_config("base_image.repo.tag", f"pr-{pr_number}")

    istag = config.get_command_arg("utils build_push_image --prefix base_image", "_istag")

    if run.run(f"oc get istag {istag} -n {namespace} -oname 2>/dev/null", check=False).returncode == 0:
        logging.info(f"Image {istag} already exists in namespace {namespace}. Don't build it.")
    else:
        run.run(f"./run_toolbox.py from_config utils build_push_image --prefix base_image")

    #
    # Deploy Redis server for Pod startup synchronization
    #

    run.run("./run_toolbox.py from_config cluster deploy_redis_server")

    #
    # Deploy Minio
    #

    run.run(f"./run_toolbox.py from_config cluster deploy_minio_s3_server")

    #
    # Prepare the ServiceAccount
    #

    run.run(f"oc create serviceaccount {service_account} -n {namespace} --dry-run=client -oyaml | oc apply -f-")
    run.run(f"oc adm policy add-cluster-role-to-user {role} -z {service_account} -n {namespace}")

    #
    # Prepare the Secret
    #

    secret_name = config.ci_artifacts.get_config("secrets.dir.name")
    secret_env_key = config.ci_artifacts.get_config("secrets.dir.env_key")

    run.run(f"oc create secret generic {secret_name} --from-file=$(echo ${secret_env_key}/* | tr ' ' ,) -n {namespace} --dry-run=client -oyaml | oc apply -f-")


@entrypoint()
def prepare_sutest_scale_up():
    """
    Scales up the SUTest cluster with the right number of nodes
    """

    if config.ci_artifacts.get_config("clusters.sutest.is_metal"):
        return

    node_count = config.ci_artifacts.get_config("clusters.sutest.compute.machineset.count")
    extra = ""
    if node_count is None:
        node_count = compute_node_requirement(sutest=True)
        extra = f"--extra '{{scale: {node_count}}}'"

    run.run(f"./run_toolbox.py from_config cluster set_scale --prefix=sutest {extra}")

@entrypoint()
def prepare_cluster():
    """
    Prepares the cluster and the namespace for running pipelines scale tests
    """

    prepare_test_driver_namespace()
    prepare_sutest_scale_up()
    prepare_rhods()

@entrypoint()
def pipelines_run_one():
    """
    Runs a single Pipeline scale test.
    """

    if job_index := os.environ.get("JOB_COMPLETION_INDEX"):
        namespace = config.ci_artifacts.get_config("rhods.pipelines.namespace")
        new_namespace = f"{namespace}-user-{job_index}"
        logging.info(f"Running in a parallel job. Changing the pipeline test namespace to '{new_namespace}'")
        config.ci_artifacts.set_config("rhods.pipelines.namespace", new_namespace)

    try:
        prepare_pipelines_namespace()
        run.run(f"./run_toolbox.py from_config pipelines run_kfp_notebook")
    finally:
        run.run(f"./run_toolbox.py from_config pipelines capture_state > /dev/null")


@entrypoint()
def pipelines_run_many():
    """
    Runs multiple concurrent Pipelines scale test.
    """

    failed = True
    try:
        run.run(f"./run_toolbox.py from_config pipelines run_scale_test")
        failed = False
    finally:
        scale_test_dir = list(env.ARTIFACT_DIR.glob("*__local_ci__run_multi"))
        if scale_test_dir:
            user_count = config.ci_artifacts.get_config("tests.pipelines.user_count")
            with open(scale_test_dir[0] / "settings", "w") as f:
                print(f"user_count={user_count}", file=f)
            with open(scale_test_dir[0] / "exit_code", "w") as f:
                print("1" if failed else "0", file=f)
            with open(scale_test_dir[0] / "config.yaml", "w") as f:
                yaml.dump(config.ci_artifacts.config, f, indent=4)

        run.run(f"./run_toolbox.py cluster capture_environment > /dev/null")


@entrypoint()
def cleanup_scale_test():
    """
    Cleanups the pipelines scale test namespaces
    """

    #
    # delete the pipelines namespaces
    #
    label_key = config.ci_artifacts.get_config("rhods.pipelines.namespace_label.key")
    label_value = config.ci_artifacts.get_config("rhods.pipelines.namespace_label.value")
    run.run(f"oc delete ns -l{label_key}={label_value} --ignore-not-found")


@entrypoint()
def cleanup_cluster():
    """
    Restores the cluster to its original state
    """

    cleanup_scale_test()

    #
    # uninstall RHODS
    #

    rhods.uninstall()

    #
    # uninstall LDAP
    #

    rhods.uninstall_ldap()

    #
    # uninstall the pipelines operator
    #

    uninstall_ocp_pipelines()

    #
    # delete the test driver namespace
    #
    base_image_ns = config.ci_artifacts.get_config("base_image.namespace")
    run.run(f"oc delete ns '{base_image_ns}' --ignore-not-found")


@entrypoint()
def test_ci():
    """
    Runs the Pipelines scale test from the CI
    """

    try:
        try:
            pipelines_run_many()
        finally:
            next_count = env.next_artifact_index()
            results_artifacts_dir = env.ARTIFACT_DIR
            with env.TempArtifactDir(env.ARTIFACT_DIR / f"{next_count:03d}__plots"):
                visualize.prepare_matbench()
                generate_plots(results_artifacts_dir)
    finally:
        if config.ci_artifacts.get_config("clusters.cleanup_on_exit"):
            pipelines_cleanup_cluster()


def generate_plots_from_pr_args():
    visualize.download_and_generate_visualizations()


@entrypoint(ignore_secret_path=True)
def generate_plots(results_dirname):
    visualize.generate_from_dir(str(results_dirname))


class Pipelines:
    """
    Commands for launching the Pipeline Perf & Scale tests
    """

    def __init__(self):
        self.prepare_cluster = prepare_cluster
        self.prepare_rhods = prepare_rhods
        self.prepare_pipelines_namespace = prepare_pipelines_namespace
        self.prepare_test_driver_namespace = prepare_test_driver_namespace
        self.prepare_sutest_scale_up = prepare_sutest_scale_up

        self.run_one = pipelines_run_one
        self.run = pipelines_run_many

        self.cleanup_cluster = cleanup_cluster
        self.cleanup_scale_test = cleanup_scale_test

        self.prepare_ci = prepare_cluster
        self.test_ci = test_ci

        self.generate_plots = generate_plots
        self.generate_plots_from_pr_args = generate_plots_from_pr_args

def main():
    # Print help rather than opening a pager
    fire.core.Display = lambda lines, out: print(*lines, file=out)

    fire.Fire(Pipelines())


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
