from matrix_benchmarking import models as matbench_models

class StatusCodeDistribution(matbench_models.ExclusiveModel):
    OK: int
    # Don't know what other status codes there are

class LatencyDistribution(matbench_models.ExclusiveModel):
    percentage: int
    latency: int

class HistogramData(matbench_models.ExclusiveModel):
    mark: float
    count: int
    frequency: float