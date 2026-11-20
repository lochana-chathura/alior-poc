#!/usr/bin/env bash
# Builds podacralior.azurecr.io/wso2am:4.7.0.23-pg1 in ACR from Dockerfile.u23 and the updated pack.
# Usage: bash platform/control-plane/image/build-u23.sh /path/to/wso2am-4.7.0.23.zip
# The zip only goes to the private registry, never to Git.
set -euo pipefail
cd "$(dirname "$0")/../../.."; source infra/azure/env.sh
ZIP=${1:?path to wso2am-4.7.0.23.zip}
CTX=$(mktemp -d); trap 'rm -rf "$CTX"' EXIT
cp platform/control-plane/image/Dockerfile.u23 "$CTX/Dockerfile"
cp "$ZIP" "$CTX/wso2am-4.7.0.23.zip"
az acr build -r "$ACR" -t wso2am:4.7.0.23-pg1 --platform linux/amd64 "$CTX"
