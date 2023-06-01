import logging
logging.getLogger().setLevel(logging.INFO)
import os
import pathlib
import yaml
import shutil
import subprocess

import jsonpath_ng

from . import env

VARIABLE_OVERRIDES_FILENAME = "variable_overrides"

ci_artifacts = None # will be set in init()

class Config:
    def __init__(self, config_path):
        self.config_path = config_path
        with open(self.config_path) as config_f:
            self.config = yaml.safe_load(config_f)

    def apply_config_overrides(self):
        variable_overrides_path = env.ARTIFACT_DIR / VARIABLE_OVERRIDES_FILENAME

        if not variable_overrides_path.exists():
            logging.info(f"apply_config_overrides: {variable_overrides_path} does not exist, nothing to override.")
            return

        with open(variable_overrides_path) as f:
            for line in f.readlines():
                key, found, _value = line.strip().partition("=")
                if not found:
                    logging.warning(f"apply_config_overrides: Invalid line: '{line.strip()}', ignoring it.")
                    continue
                value = _value.strip("'")

                MAGIC_DEFAULT_VALUE = object()
                current_value = self.get_config(key, MAGIC_DEFAULT_VALUE)
                if current_value == MAGIC_DEFAULT_VALUE:
                    if "." in key:
                        raise ValueError(f"Config key '{key}' does not exist, and cannot create it at the moment :/")
                    self.config[key] = None

                self.set_config(key, value)
                actual_value = self.get_config(key) # ensure that key has been set, raises an exception otherwise
                logging.info(f"config override: {key} --> {actual_value}")

    def apply_preset(self, name):
        values = self.get_config(f"ci_presets.{name}")
        logging.info(f"Appling preset '{name}' ==> {values}")
        if not values:
            raise ValueError("Preset '{name}' does not exists")

        for key, value in values.items():
            if key == "extends":
                for extend_name in value:
                    self.apply_preset(extend_name)
                continue

            msg = f"preset[{name}] --> {value}"
            logging.info(msg)
            with open(env.ARTIFACT_DIR / "presets_applied", "a") as f:
                print(msg, file=f)

            self.set_config(key, value)


    def get_config(self, jsonpath, default_value=...):
        try:
            value = jsonpath_ng.parse(jsonpath).find(self.config)[0].value
        except Exception as ex:
            if default_value != ...:
                logging.warning(f"get_config: {jsonpath} --> missing. Returning the default value: {default_value}")
                return default_value
            logging.error(f"get_config: {jsonpath} --> {ex}")
            raise ex

        logging.info(f"get_config: {jsonpath} --> {value}")

        return value


    def set_config(self, jsonpath, value):
        try:
            self.get_config(jsonpath, value) # will raise an exception if the jsonpath does not exist
            jsonpath_ng.parse(jsonpath).update(self.config, value)
        except Exception as ex:
            logging.error(f"set_config: {jsonpath}={value} --> {ex}")
            raise

        logging.info(f"set_config: {jsonpath} --> {value}")

        with open(self.config_path, "w") as f:
            yaml.dump(self.config, f, indent=4)

        if (shared_dir := os.environ.get("SHARED_DIR")) and (shared_dir_path := pathlib.Path(shared_dir)) and shared_dir_path.exists():

            with open(shared_dir_path / "config.yaml", "w") as f:
                yaml.dump(self.config, f, indent=4)

    def apply_preset_from_pr_args(self):
        PR_ARG_KEY = "PR_POSITIONAL_ARG_"

        idx = 1
        while True:
            preset = self.get_config(f"{PR_ARG_KEY}{idx}", None)
            if not preset:
                return

            self.apply_preset(preset)
            idx += 1

def _set_config_environ(base_dir):
    config_path = env.ARTIFACT_DIR / "config.yaml"

    os.environ["CI_ARTIFACTS_FROM_CONFIG_FILE"] = str(config_path)
    os.environ["CI_ARTIFACTS_FROM_COMMAND_ARGS_FILE"] = str(base_dir / "command_args.yaml")

    # make sure we're using a clean copy of the configuration file
    config_path.unlink(missing_ok=True)

    if shared_dir := os.environ.get("SHARED_DIR"):
        shared_dir_config_path = pathlib.Path(shared_dir) / "config.yaml"
        if shared_dir_config_path.exists():
            logging.info(f"Reloading the config file from {shared_dir_config_path} ...")
            shutil.copyfile(shared_dir_config_path, config_path)

    if not config_path.exists():
        shutil.copyfile(base_dir / "config.yaml", config_path)


    return config_path


def get_command_arg(command, args):
    try:
        logging.info(f"get_command_arg: {command} {args}")
        proc = subprocess.run(f'./run_toolbox.py from_config {command} --show_args "{args}"', check=True, shell=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        logging.error(e.stderr.decode("utf-8").strip())
        raise

    return proc.stdout.decode("utf-8").strip()


def init(base_dir):
    global ci_artifacts

    if ci_artifacts:
        logging.info("config.init: already configured.")
        return

    config_path = _set_config_environ(base_dir)
    ci_artifacts = Config(config_path)

    logging.info("config.init: apply the ci-artifacts config overrides")
    ci_artifacts.apply_config_overrides()
