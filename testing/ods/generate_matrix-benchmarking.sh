#! /bin/bash

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

MATBENCH_EXPE_NAME=rhods-ci
ARTIFACT_DIR=${ARTIFACT_DIR:-/tmp/ci-artifacts_$(date +%Y%m%d)}
MATBENCH_RESULTS_DIR="/tmp/matrix_benchmarking_results"

# https://github.com/openshift-psap/matrix-benchmarking
MATRIX_BENCHMARKING_COMMIT=1b760012ece2739d155ab77c6883d644a2f03836

generate_matbench::get_matrix_benchmarking() {
    cd /tmp
    git clone https://github.com/openshift-psap/matrix-benchmarking --depth 1
    cd matrix-benchmarking/
    git fetch --depth=1 origin "$MATRIX_BENCHMARKING_COMMIT"
    git checkout "$MATRIX_BENCHMARKING_COMMIT"
    git show --quiet

    pip install --quiet --requirement requirements.txt

    cd matrix_benchmarking
    rm workloads/ -rf

    MATBENCH_WORKLOAD_NAME=rhods-ci
    mkdir workloads/
    cd workloads/
    ln -s "$THIS_DIR/../../subprojects/matrix-benchmarking-workloads/$MATBENCH_WORKLOAD_NAME"

    cd "$MATBENCH_WORKLOAD_NAME"
    pip install --quiet --requirement requirements.txt

    mkdir -p /tmp/bin
    ln -s /tmp/matrix-benchmarking/bin/matbench /tmp/bin
}

_get_data_from_pr() {
    cluster_type=$1
    shift;
    results_dir=$1
    shift

    if [[ -z "${PULL_NUMBER:-}" ]]; then
        echo "ERROR: PULL_NUMBER not set :/"
        exit 1
    fi

    MATBENCH_URL_ANCHOR="matbench-data-url: "
    MATBENCH_BUILD_ANCHOR="matbench-data-build: "

    pr_body="$(curl -sSf "https://api.github.com/repos/openshift-psap/ci-artifacts/pulls/$PULL_NUMBER" | jq -r .body | tr -d '\r')"

    get_anchor_value() {
        anchor=$1
        shift || true
        default=${1:-}

        value=$(echo "$pr_body" | { grep "$anchor" || true;} | cut -b$(echo "$anchor" | wc -c)-)

        [[ "$value" ]] && echo "$value" || echo "$default"
    }

    matbench_url=$(get_anchor_value "$MATBENCH_URL_ANCHOR")

    if [[ -z "$matbench_url" ]]; then
        base_url="https://gcsweb-ci.apps.ci.l2s4.p1.openshiftapps.com/gcs/origin-ci-test/pr-logs/pull/openshift-psap_ci-artifacts/$PULL_NUMBER/pull-ci-openshift-psap-ci-artifacts-master-ods-jh-on-${cluster_type}"

        build=$(get_anchor_value "$MATBENCH_BUILD_ANCHOR")
        if [[ -z "$build" ]]; then
            build=$(curl --silent -Ssf "${base_url}/latest-build.txt")
        fi

        matbench_url="${base_url}/${build}/artifacts/jh-on-${cluster_type}/test/artifacts/"
    fi

    echo "$matbench_url" > "${ARTIFACT_DIR}/source_url"

    _download_data_from_url "$results_dir" "$matbench_url"
}

_download_data_from_url() {
    results_dir=$1
    shift
    url=$1
    shift

    if [[ "${url: -1}" != "/" ]]; then
        url="${url}/"
    fi

    mkdir -p "$results_dir"

    dl_dir=$(echo "$url" | cut -d/ -f4-)
    (cd "$results_dir"; wget --recursive --no-host-directories --no-parent --execute robots=off --quiet \
                             --cut-dirs=$(echo "${dl_dir}" | tr -cd / | wc -c) \
                             "$url")
}

_prepare_data_from_artifacts_dir() {
    artifact_dir=$1

    if ! ls "$artifact_dir"/*__driver_rhods__test_jupyterlab -d >/dev/null 2>&1; then
        echo "FATAL: No result available, aborting."
        exit 1
    fi

    mkdir -p "$MATBENCH_RESULTS_DIR"
    ln -s "$artifact_dir" "$MATBENCH_RESULTS_DIR/$MATBENCH_EXPE_NAME"
}

generate_matbench::get_prometheus() {
    PROMETHEUS_VERSION=2.36.0
    cd /tmp
    wget --quiet "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" -O/tmp/prometheus.tar.gz
    tar xf "/tmp/prometheus.tar.gz" -C /tmp
    mkdir -p /tmp/bin
    ln -s "/tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /tmp/bin
    ln -s "/tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus.yml" /tmp/
}

generate_matbench::generate_plots() {
    workload_dir=/tmp/matrix-benchmarking/workloads/rhods-ci

    ln -s /tmp/prometheus.yml "$workload_dir"

    export PATH="/tmp/bin:$PATH"
    python3 --version

    cat > "$workload_dir/.env" <<EOF
MATBENCH_RESULTS_DIRNAME=$MATBENCH_RESULTS_DIR
MATBENCH_FILTERS=expe=$MATBENCH_EXPE_NAME
EOF

    cat "$workload_dir/.env"

    _matbench() {
        (cd  "$workload_dir"; matbench "$@")
    }

    stats_content="$(cat "$workload_dir/data/ci-artifacts.plots")"

    echo "$stats_content"

    generate_url="stats=$(echo -n "$stats_content" | tr '\n' '&' | sed 's/&/&stats=/g')"

    _matbench parse
    retcode=0
    VISU_LOG_FILE="$ARTIFACT_DIR/matbench_visualize.log"
    if ! _matbench visualize --generate="$generate_url" |& tee > "$VISU_LOG_FILE"; then
        echo "Visualization generation failed :("
        retcode=1
    fi

    mkdir "$ARTIFACT_DIR"/figures_{png,html}

    mv fig_*.png "$ARTIFACT_DIR/figures_png" || true
    mv fig_*.html "$ARTIFACT_DIR/figures_html" || true
    mv report_* "$ARTIFACT_DIR" || true

    if grep -q "^ERROR" "$VISU_LOG_FILE"; then
        echo "An error happened during the report generation, aborting."
        exit 1
    fi

    return $retcode
}

if [[ "$JOB_NAME_SAFE" == "jh-on-"* ]]; then
    set -o errexit
    set -o pipefail
    set -o nounset
    set -x

    cluster_type=$(echo "$JOB_NAME_SAFE" | cut -d- -f3 )

    _prepare_data_from_artifacts_dir "$ARTIFACT_DIR/.."

    generate_matbench::get_prometheus
    generate_matbench::get_matrix_benchmarking

    generate_matbench::generate_plots

elif [[ "$JOB_NAME_SAFE" == "plot-jh-on-"* ]]; then
    set -o errexit
    set -o pipefail
    set -o nounset
    set -x

    cluster_type=${1:-}
    if [[ -z "$cluster_type" ]]; then
        echo "ERROR: a cluster_type argument must be provided."
        exit 1
    fi

    results_dir="$MATBENCH_RESULTS_DIR/$MATBENCH_EXPE_NAME"
    mkdir -p "$results_dir"

    _get_data_from_pr "$cluster_type" "$results_dir"

    generate_matbench::get_prometheus
    generate_matbench::get_matrix_benchmarking

    generate_matbench::generate_plots
fi
