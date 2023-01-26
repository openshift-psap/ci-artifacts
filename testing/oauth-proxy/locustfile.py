"""
TODO
* support both triton and openvino (how?)
* support auth and authless
* support different models per url (csv or json)
"""

import csv
import os
import types
import sys
from locust import HttpUser, task

# necessary for self-signed certs
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

env = types.SimpleNamespace()
env.LOCUST_USERS = os.getenv("LOCUST_USERS")
env.USER_INDEX_OFFSET = int(os.getenv("USER_INDEX_OFFSET", "0"))


class InferenceServiceUser(HttpUser):
    """ Inference Service User...
    """

    user_next_id = env.USER_INDEX_OFFSET

    def __init__(self, locust_env):
        """ Determine which IF to hit
        """

        HttpUser.__init__(self, locust_env)
        # self-signed certs are allowed
        self.client.verify = False

        self.locust_env = locust_env

        self.loop = 0
        self.user_id = self.__class__.user_next_id
        self.user_name = f"testuser{self.user_id}"
        self.__class__.user_next_id += 1

        endpoints = []
        endpoints_file = "endpoints.txt"
        with open(endpoints_file, 'r', encoding="utf-8") as csv_file:
            reader = csv.DictReader(csv_file)
            for row in reader:
                endpoints.append(row)

        if int(env.LOCUST_USERS) < len(endpoints):
            # no way we can reach all the endpoints
            print(
                f"Cannot test {len(endpoints)} endpoints "
                f"with {env.LOCUST_USERS} users, exiting."
            )
            sys.exit(1)

        # don't hate me
        self.host = endpoints[
            self.user_id % len(endpoints)
            ].get(
                'endpoint'
            )

    def on_start(self):
        """ No-op for now
        """
        pass

    @task
    def get_ready(self):
        """ Very basic HTTP client
        """
        self.client.get(f"{self.host}/ready")
