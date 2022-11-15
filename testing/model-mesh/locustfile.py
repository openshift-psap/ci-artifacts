"""
TODO
* read some configuration file
* load the url list (csv or json)
* support both triton and openvino (how?)
* support auth and authless
* support different models per url (csv or json)
"""

import csv
import json
import os
import types
from deepdiff import DeepDiff
from locust import HttpUser, task, HttpUser

# necessary for self-signed certs
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

env = types.SimpleNamespace()
env.NS_COUNT = os.getenv("NS_COUNT")
env.MODEL_COUNT = os.getenv("MODEL_COUNT")
env.NS_BASENAME = os.getenv("NS_BASENAME")
env.LOCUST_USERS = os.getenv("LOCUST_USERS")
env.USER_INDEX_OFFSET = int(os.getenv("USER_INDEX_OFFSET", 0))

# Other env variables:
# - LOCUST_USERS (number of users)
# - LOCUST_RUN_TIME (locust test duration)
# - LOCUST_SPAWN_RATE (locust number of new users per seconds)
# - LOCUST_LOCUSTFILE (locustfile.py file that will be executed)


mm_infer_post_input_file = 'input-onnx.json'
mm_infer_expected_output_file = 'expected-output-onnx.json'
with open(mm_infer_post_input_file) as json_file:
    mm_input = json.load(json_file)
with open(mm_infer_expected_output_file) as json_file:
    mm_output = json.load(json_file)

endpoints = []
endpoints_file = "endpoints.txt"
with open(endpoints_file) as csv_file:
    reader = csv.DictReader(csv_file)
    for row in reader:
        endpoints.append(row)


class InferenceServiceUser(HttpUser):

    user_next_id = env.USER_INDEX_OFFSET

    def __init__(self, locust_env):
        HttpUser.__init__(self, locust_env)

        self.locust_env = locust_env

        self.loop = 0
        self.user_id = self.__class__.user_next_id
        self.user_name = f"testuser{self.user_id}"
        self.__class__.user_next_id += 1

        # don't hate me
        self.endpoint = endpoints[
            self.user_id % len(endpoints)
            ].get(
                'endpoint'
            ).removesuffix(
                '/infer'
            )

    def on_start(self):
        """Allows to run against unknown https certs"""
        self.client.verify = False
        self.host = self.endpoint

    @task
    def get_infer(self):
        with self.client.post(
            f"{self.endpoint}/infer",
            name="inference/endpoints",
            json=mm_input,
            catch_response=True
        ) as response:
#        with self.client.post("/infer", json=mm_input, catch_response=True) as response:
            try:
                json_response = response.json()
                # ignore everything but the output itself
                expected_output = mm_output.get("outputs")
                our_output = json_response.get("outputs")
                result_diff = DeepDiff(our_output, expected_output)
                if result_diff != {}:
                    response.failure("Did not get expected output, diff: {0}, complete output: {1}".format(result_diff, json_response))
            except json.JSONDecodeError:
                response.failure("Response could not be decoded as JSON: {0}".format(response.text))
