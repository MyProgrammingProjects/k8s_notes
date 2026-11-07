#!/bin/bash

set -Eeuo pipefail

# Configuration
API="http://localhost:11434/api/generate"

MODEL="${1:-qwen:0.5b}"
PROMPT="${2:-Explain why Kubernetes is useful for ML workloads.}"

TEST_ID="$(date +%s)-${MODEL//[:\/]/_}-$$"

RESULTS_DIR="results"
MONITOR_SCRIPT="./ollama-monitor-k8s.sh"

INFERENCE_LOG="$RESULTS_DIR/inference.csv"
RESOURCE_LOG="$RESULTS_DIR/resources-${TEST_ID}.csv"

MONITOR_PID=""
RESPONSE=$(mktemp)

mkdir -p "$RESULTS_DIR"

# Cleanup background process and temporary files
cleanup() {
    local exit_code=$?

    if [[ -n "$MONITOR_PID" ]]; then
        echo ""
        echo "Stopping Kubernetes monitoring (PID: $MONITOR_PID)"

        kill "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
    fi

    rm -f "$RESPONSE"

    echo "Test finished with exit code: $exit_code"

    exit "$exit_code"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Validate dependencies
for cmd in curl jq kubectl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $cmd"
        exit 1
    fi
done

if [[ ! -x "$MONITOR_SCRIPT" ]]; then
    echo "ERROR: Monitoring script not found or not executable."
    exit 1
fi

# Initialize inference CSV
if [[ ! -f "$INFERENCE_LOG" ]]; then
    echo "test_id,start,end,model,curl_seconds,load_seconds,prompt_eval_seconds,prompt_tokens,prompt_tokens_per_second,generation_seconds,output_tokens,output_tokens_per_second" \
        > "$INFERENCE_LOG"
fi

# Initialize resource CSV
echo "test_id,timestamp,pod,container,cpu,memory" \
    > "$RESOURCE_LOG"

echo "======================================"
echo "Ollama inference experiment"
echo "======================================"
echo "Test ID : $TEST_ID"
echo "Model   : $MODEL"
echo "Prompt  : $PROMPT"
echo ""

# Start Kubernetes monitoring
"$MONITOR_SCRIPT" "$RESOURCE_LOG" "$TEST_ID" &

MONITOR_PID=$!

echo "Kubernetes monitoring started (PID: $MONITOR_PID)"

# Allow monitoring to start before inference
sleep 2

# Record request start
START=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

echo ""
echo "Sending request to Ollama..."

# Execute API request and measure client-side time
CURL_TIME=$(
    curl -sS --fail \
        -o "$RESPONSE" \
        -w '%{time_total}' \
        "$API" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg model "$MODEL" \
            --arg prompt "$PROMPT" \
            '{
                model: $model,
                prompt: $prompt,
                stream: false,
                options: {
                    temperature: 0,
                    seed: 42,
                    num_predict: 128
                }
            }')"
)

END=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

# Validate Ollama response
if ! jq -e '.model and (.eval_count != null)' \
    "$RESPONSE" >/dev/null; then
    echo "ERROR: Invalid Ollama response."
    cat "$RESPONSE"
    exit 1
fi

echo ""
echo "======================================"
echo "Generated response"
echo "======================================"

jq -r '.response' "$RESPONSE"

# Extract and calculate inference metrics
jq -r \
    --arg id "$TEST_ID" \
    --arg start "$START" \
    --arg end "$END" \
    --arg curl "$CURL_TIME" \
    '[
        $id,
        $start,
        $end,
        .model,
        ($curl | tonumber),
        (.load_duration / 1e9),
        (.prompt_eval_duration / 1e9),
        .prompt_eval_count,
        (if .prompt_eval_duration > 0 then
            (.prompt_eval_count / .prompt_eval_duration * 1e9)
         else 0 end),
        (.eval_duration / 1e9),
        .eval_count,
        (if .eval_duration > 0 then
            (.eval_count / .eval_duration * 1e9)
         else 0 end)
    ] | @csv' "$RESPONSE" >> "$INFERENCE_LOG"

echo ""
echo "======================================"
echo "Inference metrics"
echo "======================================"

jq '{
    model,
    total_duration_seconds: (.total_duration / 1e9),
    load_duration_seconds: (.load_duration / 1e9),
    prompt_tokens: .prompt_eval_count,
    prompt_eval_seconds: (.prompt_eval_duration / 1e9),
    output_tokens: .eval_count,
    generation_seconds: (.eval_duration / 1e9),
    output_tokens_per_second:
        (if .eval_duration > 0 then
            (.eval_count / .eval_duration * 1e9)
         else 0 end)
}' "$RESPONSE"

echo ""
echo "======================================"
echo "Results"
echo "======================================"
echo "Inference CSV : $INFERENCE_LOG"
echo "Resources CSV : $RESOURCE_LOG"
echo "Test ID       : $TEST_ID"
