#!/bin/bash

INPUT_ACR_NAME=$1
TARGET_ACR_NAME=$2
IMAGE_NAME=$3
USER_ID=$4
MI_CLIENT_ID=$5

IMAGE_SOURCE="$INPUT_ACR_NAME.azurecr.io/$IMAGE_NAME"
IMAGE_TARGET="$TARGET_ACR_NAME.azurecr.io/$IMAGE_NAME"

# Log in to the Azure Container Registry
echo "Logging in to Azure"
az login --identity --username $USER_ID || { echo "Error: Failed to log in to Azure."; exit 1; }
echo "Logging in to input ACR: $INPUT_ACR_NAME"
az acr login --name "$INPUT_ACR_NAME" || { echo "Error: Failed to log in to source ACR $INPUT_ACR_NAME."; exit 1; }

# Pull the image from the ACR
echo "Pulling image: $IMAGE_SOURCE"
if ! docker pull "$IMAGE_SOURCE"; then
    echo "Error: Image $IMAGE_NAME not found in source ACR $ACR_NAME."
    exit 1
fi

# Scanning the image
echo "Scanning image: $IMAGE_NAME using CoMET"
SCAN_TOOL="mcr.microsoft.com/tvm-containers/shavsa/comet:v1-linux-amd64"
if ! docker pull "$SCAN_TOOL"; then
    echo "Error: Failed to pull the CoMET scanning tool."
    exit 1
fi

docker run -v $(pwd)/result:/result -v //var/run/docker.sock:/var/run/docker.sock -v scanutility:/internal mcr.microsoft.com/tvm-containers/shavsa/comet:v1-linux-amd64 scan --force-manifest-download --managed-identity-authentication --scan-result-path /result --user-assigned-mi $MI_CLIENT_ID "$IMAGE_SOURCE" || {
    echo "Error: Scanning failed. Check the CoMET tool logs for details."
    exit 1
}

# Check the scan result
if [[ ! -f "$JSON_FILE" ]]; then
    echo "Error: Scan result file $JSON_FILE not found."
    exit 1
fi

# Check the vulnerabilities array in the JSON file
VULNERABILITIES_COUNT=$(jq '.vulnerabilities | length' "$JSON_FILE")
if [[ "$VULNERABILITIES_COUNT" -gt 0 ]]; then
    echo "Vulnerabilities detected ($VULNERABILITIES_COUNT). Image will not be pushed to the target ACR."
    exit 1
fi

# Log in to the target ACR
echo "Logging in to target ACR: $TARGET_ACR_NAME"
az acr login --name "$TARGET_ACR_NAME" || { echo "Error: Failed to log in to target ACR $TARGET_ACR_NAME."; exit 1; }

# Tag and push the image to the target ACR
echo "Tagging image as $IMAGE_TARGET..."
docker tag $IMAGE_SOURCE $IMAGE_TARGET || { echo "Error: Failed to tag the Docker image."; exit 1; }

echo "Pushing image to $IMAGE_TARGET..."
if ! docker push "$IMAGE_TARGET"; then
    echo "Error: Failed to push the image to the target ACR."
    exit 1
fi

echo "Image successfully pushed to $TARGET_ACR_NAME."
exit 0
