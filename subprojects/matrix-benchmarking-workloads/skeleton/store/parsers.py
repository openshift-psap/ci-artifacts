import types
import pathlib
import logging
import yaml
import os
import json
import datetime

import jsonpath_ng

import matrix_benchmarking.cli_args as cli_args
import matrix_benchmarking.store.prom_db as store_prom_db

from . import prom as workload_prom


register_important_file = None # will be when importing store/__init__.py

K8S_TIME_FMT = "%Y-%m-%dT%H:%M:%SZ"
SHELL_DATE_TIME_FMT = "%a %b %d %H:%M:%S %Z %Y"
ANSIBLE_LOG_DATE_TIME_FMT = "%Y-%m-%d %H:%M:%S"

IMPORTANT_FILES = [
    "config.yaml",

    "001__cluster__dump_prometheus_db/prometheus.t*",
    "002__cluster__capture_environment/nodes.json",
    "002__cluster__capture_environment/ocp_version.yml"
]

PARSER_VERSION = "2023-05-31"
ARTIFACTS_VERSION = "2023-05-31"

def ignore_file_not_found(fn):
    def decorator(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except FileNotFoundError as e:
            logging.warning(f"{fn.__name__}: FileNotFoundError: {e}")
            return None

    return decorator


def _parse_always(results, dirname, import_settings):
    # parsed even when reloading from the cache file

    results.from_local_env = _parse_local_env(dirname)
    results.test_config = _parse_test_config(dirname)

def _parse_once(results, dirname):
    results.nodes_info = _parse_nodes_info(dirname) or {}
    results.cluster_info = _extract_cluster_info(results.nodes_info)
    results.sutest_ocp_version = _parse_ocp_version(dirname)
    results.metrics = _extract_metrics(dirname)

def _parse_local_env(dirname):
    from_local_env = types.SimpleNamespace()

    from_local_env.artifacts_basedir = None
    from_local_env.source_url = None
    from_local_env.is_interactive = False

    try:
        with open(dirname / "source_url") as f: # not an important file
            from_local_env.source_url = f.read().strip()
            from_local_env.artifacts_basedir = pathlib.Path(from_local_env.source_url.replace("https://gcsweb-ci.apps.ci.l2s4.p1.openshiftapps.com/", "/"))
    except FileNotFoundError as e:
        pass

    if not cli_args.kwargs.get("generate"):
        # running in interactive mode
        from_local_env.is_interactive = True
        from_local_env.artifacts_basedir = dirname
        return from_local_env

    # running in generate mode

    # This must be parsed from the process env (not the file), to
    # properly generate the error report links to the image.
    job_name = os.getenv("JOB_NAME_SAFE", "")

    if job_name.endswith("-plot"):
        # running independently of the test, the source_url file must be available
        if from_local_env.source_url is None:
            logging.warning(f"The source URL should be available when running from '{job_name}'")
            from_local_env.source_url = "/missing/source/url"
            from_local_env.artifacts_basedir = dirname

    elif "ARTIFACT_DIR" in os.environ:

        # os.path.relpath can return '..', but pathlib.Path().relative_to cannot
        from_local_env.source_url = pathlib.Path(os.path.relpath(dirname,
                                                                 pathlib.Path(os.environ["ARTIFACT_DIR"])))
        from_local_env.artifacts_basedir = from_local_env.source_url

    else:
        logging.error(f"Unknown execution environment: JOB_NAME_SAFE={job_name} ARTIFACT_DIR={os.environ.get('ARTIFACT_DIR')}")
        from_local_env.artifacts_basedir = dirname.absolute()

    return from_local_env


def _parse_test_config(dirname):
    test_config = types.SimpleNamespace()

    filename = pathlib.Path("config.yaml")
    test_config.filepath = dirname / filename

    with open(register_important_file(dirname, filename)) as f:
        yaml_file = test_config.yaml_file = yaml.safe_load(f)

    if not yaml_file:
        logging.error("Config file '{filename}' is empty ...")
        yaml_file = test_config.yaml_file = {}

    def get(key, missing=...):
        nonlocal yaml_file
        jsonpath_expression = jsonpath_ng.parse(f'$.{key}')

        match = jsonpath_expression.find(yaml_file)
        if not match:
            if missing != ...:
                return missing

            raise KeyError(f"Key '{key}' not found in {filename} ...")

        return match[0].value

    test_config.get = get

    return test_config


@ignore_file_not_found
def _parse_nodes_info(dirname, sutest_cluster=True):
    nodes_info = {}

    filename = pathlib.Path("002__cluster__capture_environment") / "nodes.json"

    with open(register_important_file(dirname, filename)) as f:
        nodeList = json.load(f)

    for node in nodeList["items"]:
        node_name = node["metadata"]["name"]
        node_info = nodes_info[node_name] = types.SimpleNamespace()

        node_info.name = node_name
        node_info.sutest_cluster = sutest_cluster
        node_info.managed = "managed.openshift.com/customlabels" in node["metadata"]["annotations"]
        node_info.instance_type = node["metadata"]["labels"].get("node.kubernetes.io/instance-type", "N/A")

        node_info.control_plane = "node-role.kubernetes.io/control-plane" in node["metadata"]["labels"] or "node-role.kubernetes.io/master" in node["metadata"]["labels"]

        node_info.infra = \
            not node_info.control_plane

    return nodes_info


@ignore_file_not_found
def _parse_ocp_version(dirname):

    with open(register_important_file(dirname, pathlib.Path("002__cluster__capture_environment") / "ocp_version.yml")) as f:
        sutest_ocp_version_yaml = yaml.safe_load(f)

    return sutest_ocp_version_yaml["openshiftVersion"]


def _extract_metrics(dirname):
    METRICS = {
        "sutest": ("001__cluster__dump_prometheus_db/prometheus.t*", workload_prom.get_sutest_metrics()),
    }

    metrics = {}
    for name, (tarball_glob, metric) in METRICS.items():
        try:
            prom_tarball = list(dirname.glob(tarball_glob))[0]
        except IndexError:
            logging.warning(f"No {tarball_glob} in '{dirname}'.")
            continue

        register_important_file(dirname, prom_tarball.relative_to(dirname))
        metrics[name] = store_prom_db.extract_metrics(prom_tarball, metric, dirname)

    return metrics

def _extract_cluster_info(nodes_info):
    cluster_info = types.SimpleNamespace()

    cluster_info.node_count = [node_info for node_info in nodes_info.values() \
                                     if node_info.sutest_cluster]

    cluster_info.control_plane = [node_info for node_info in nodes_info.values() \
                                 if node_info.sutest_cluster and node_info.control_plane]

    cluster_info.infra = [node_info for node_info in nodes_info.values() \
                                if node_info.sutest_cluster and node_info.infra]

    return cluster_info
