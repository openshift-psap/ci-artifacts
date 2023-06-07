from matrix_benchmarking import models as matbench_models

from . import data
from . import metadata

class AnsibleLLMPayload(matbench_models.create_PSAPPayload('ansible-llm')):
    data: data.AnsibleLLMData
    metadata: metadata.AnsibleLLMMetadata
