import os
import pathlib
import time

ARTIFACT_DIR = None

def init():
    global ARTIFACT_DIR

    if "ARTIFACT_DIR" in os.environ:
        ARTIFACT_DIR = pathlib.Path(os.environ["ARTIFACT_DIR"])

    else:
        env_ci_artifact_base_dir = pathlib.Path(os.environ.get("CI_ARTIFACT_BASE_DIR", "/tmp"))
        ARTIFACT_DIR = env_ci_artifact_base_dir / f"ci-artifacts_{time.strftime('%Y%m%d')}"
        ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
        os.environ["ARTIFACT_DIR"] = str(ARTIFACT_DIR)
