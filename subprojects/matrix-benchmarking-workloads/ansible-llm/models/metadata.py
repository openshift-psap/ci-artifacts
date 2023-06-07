from typing import List
import datetime as dt

from matrix_benchmarking import models as matbench_models

class AnsibleLLMOptionData(matbench_models.ExclusiveModel):
    context: str
    prompt: str


class AnsibleLLMOptionMetadata(matbench_models.ExclusiveModel):
    mm_vmodel_id: str


class AnsibleLLMOptions(matbench_models.ExclusiveModel):
    call: str
    host: str
    proto: str
    import_paths: List[str]
    insecure: bool
    
    load_schedule: str #Enum
    load_start: int
    load_end: int
    load_step: int
    load_step_duration: int
    load_max_duration: int

    concurrency: int
    concurrency_schedule: str #Enum
    concurrency_start: int
    concurrency_end: int
    concurrency_step: int
    concurrency_step_duration: int
    concurrency_max_duration: int

    total: int
    connections: int
    timeout: int
    dial_timeout: int

    metadata: AnsibleLLMOptionMetadata

    data: AnsibleLLMOptionData
    binary: bool
    CPUs: int

    class Config:
        fields = {
            'load_schedule': 'load-schedule',
            'load_start': 'load-start',
            'load_end': 'load-end',
            'load_step': 'load-step',
            'load_step_duration': 'load-step-duration',
            'load_max_duration': 'load-max-duration',
            'concurrency_schedule': 'concurrency-schedule',
            'concurrency_start': 'concurrency-start',
            'concurrency_end': 'concurrency-end', 
            'concurrency_step': 'concurrency-step',
            'concurrency_step_duration': 'concurrency-step-duration',
            'concurrency_max_duration': 'concurrency-max-duration'
        }


class AnsibleLLMMetadata(matbench_models.Metadata):
    date: dt.datetime
    endReason: str #Convert to enum
    options: AnsibleLLMOptions