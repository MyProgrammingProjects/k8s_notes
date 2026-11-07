#!/bin/bash

set -euo pipefail

NAMESPACE="ollama"

POD=$(kubectl get pods -n "$NAMESPACE" \
    -l app=ollama \
    -o jsonpath='{.items[0].metadata.name}')

OUTPUT="${1:-continuous-resources.csv}"
TEST_ID="${2:-manual}"

while true; do
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

    kubectl top pod "$POD" \
        -n "$NAMESPACE" \
        --containers --no-headers |
    while read -r pod container cpu memory; do
        echo "$TEST_ID,$timestamp,$pod,$container,$cpu,$memory"
    done >> "$OUTPUT"

    sleep 1
done
