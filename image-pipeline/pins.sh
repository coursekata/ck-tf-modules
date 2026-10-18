# shellcheck shell=bash disable=SC2034 # read by the scripts and workflows that source this file
# Tool pins for the image pipeline. The workflow hands both to
# docker/setup-buildx-action, and buildx does every registry operation, so nothing
# else is installed.

BUILDKIT_IMAGE="moby/buildkit:v0.33.1@sha256:cec9f139f45e93c5c69c60f8b07cfad9f43f4ef6b6a6cd917527fea5ff2e3dea"

BUILDX_VERSION="v0.38.0"
