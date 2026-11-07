#!/bin/bash

./ollama-model-test.sh phi3:mini "Explain Kubernetes architecture."
./ollama-model-test.sh qwen:0.5b "Explain Kubernetes architecture."
./ollama-model-test.sh deepseek-coder:1.3b "Explain Kubernetes architecture."
./ollama-model-test.sh deepseek-r1:1.5b "Explain Kubernetes architecture."
