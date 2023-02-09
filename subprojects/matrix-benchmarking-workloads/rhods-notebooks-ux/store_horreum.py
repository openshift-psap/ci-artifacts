import types
import json

def parse_directory_fake(fn_add_to_matrix, dirname, import_settings):
    results = types.SimpleNamespace()

    results.is_horreum_fake_data = True
    with open(dirname / "data.json", "r") as f:
        results.data = json.load(f)

    fn_add_to_matrix(results)
