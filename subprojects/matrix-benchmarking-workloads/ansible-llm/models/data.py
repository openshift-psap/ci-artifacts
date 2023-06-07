from typing import List
import datetime as dt

from . import calculated

from matrix_benchmarking import models as matbench_models


class ResponseDetails(matbench_models.ExclusiveModel):
    timestamp: dt.datetime
    latency: int
    error: str
    status: str #Should upgrade to an enum, but need more info
    worker: str
    response: str

class AnsibleLLMData(matbench_models.ExclusiveModel):
    count: int
    total: int
    average: int
    fastest: int
    slowest: int
    rps: float

    errorDistribution: dict # Don't have any data for this
    statusCodeDistribution: calculated.StatusCodeDistribution
    latencyDistribution: List[calculated.LatencyDistribution]
    histogram: List[calculated.HistogramData]
    details: List[ResponseDetails]