from . import models

import matrix_benchmarking.store as store


store.register_custom_schema(models.AnsibleLLMPayload)