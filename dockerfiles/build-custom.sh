#!/bin/bash

# Build script that adds subscription nag removal to the base image

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building custom PBS Docker image with subscription nag removal...${NC}"

# Get the latest tag from upstream
TAG=${TAG:-latest}
REGISTRY=${REGISTRY:-ayufan/proxmox-backup-server}
CUSTOM_TAG=${CUSTOM_TAG:-custom}

echo -e "${YELLOW}Using base image: ${REGISTRY}:${TAG}${NC}"

# First, ensure we have the base image
echo -e "${GREEN}Pulling base image...${NC}"
docker pull ${REGISTRY}:${TAG}

# Build our custom overlay
echo -e "${GREEN}Building custom overlay...${NC}"
docker build \
  --build-arg BASE_IMAGE=${REGISTRY}:${TAG} \
  -t ${REGISTRY}:${CUSTOM_TAG} \
  -f dockerfiles/Dockerfile.custom \
  .

echo -e "${GREEN}Custom image built successfully: ${REGISTRY}:${CUSTOM_TAG}${NC}"
echo -e "${YELLOW}To use it, update your docker-compose.yml to use tag: ${CUSTOM_TAG}${NC}"