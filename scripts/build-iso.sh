#!/usr/bin/env bash
# Builds one automated-installation ISO per node using proxmox-auto-install-assistant
# running inside a container (e.g. an image built from proxmox_auto_install_assistant_container).
#
# Environment (set by isos.tf):
#   CONTAINER_ENGINE   docker | podman          (default: docker)
#   CONTAINER_PLATFORM optional --platform value (e.g. linux/amd64)
#   CONTAINER_IMAGE    assistant image, must contain proxmox-auto-install-assistant + xorriso
#   BUILD_DIR          absolute path of the working directory, mounted at /work
#   NODE               node name (informational)
#   ANSWER_FILE        absolute path of the answer.toml to embed
#   HOOK_FILE          absolute path of the first-boot hook (optional)
#   BASE_ISO           absolute path of the base PVE ISO
#   ISO_URL            download URL for the base ISO if it is missing
#   OUTPUT_FILE        absolute path of the generated ISO
set -euo pipefail

ENGINE="${CONTAINER_ENGINE:-docker}"
PLATFORM="${CONTAINER_PLATFORM:-}"
IMAGE="${CONTAINER_IMAGE:?CONTAINER_IMAGE must be set}"
BUILD_DIR="${BUILD_DIR:?BUILD_DIR must be set}"
ANSWER_FILE="${ANSWER_FILE:?ANSWER_FILE must be set}"
HOOK_FILE="${HOOK_FILE:-}"
BASE_ISO="${BASE_ISO:?BASE_ISO must be set}"
ISO_URL="${ISO_URL:-}"
OUTPUT_FILE="${OUTPUT_FILE:?OUTPUT_FILE must be set}"
NODE="${NODE:-node}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

# 1. Fetch the base ISO if it is not present yet.
if [ ! -f "$BASE_ISO" ]; then
    if [ -z "$ISO_URL" ]; then
        echo "ERROR: base ISO '$BASE_ISO' not found and ISO_URL is not set" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$BASE_ISO")"
    echo "downloading base ISO from $ISO_URL"
    curl -fL --retry 3 --progress-bar -o "$BASE_ISO" "$ISO_URL"
fi

# Paths inside the container (BUILD_DIR is mounted at /work).
to_work_path() {
    printf '/work/%s' "${1#"$BUILD_DIR"/}"
}

WORK_ANSWER=$(to_work_path "$ANSWER_FILE")
WORK_BASE=$(to_work_path "$BASE_ISO")
WORK_OUTPUT=$(to_work_path "$OUTPUT_FILE")

PLATFORM_FLAG=()
if [ -n "$PLATFORM" ]; then
    PLATFORM_FLAG=(--platform "$PLATFORM")
fi

run() {
    $ENGINE run --rm "${PLATFORM_FLAG[@]}" -v "$BUILD_DIR:/work" "$IMAGE" "$@"
}

# 2. Validate the answer file before wasting time on ISO generation.
echo "[$NODE] validating answer file"
run proxmox-auto-install-assistant validate-answer "$WORK_ANSWER"

# 3. Prepare the ISO.
ARGS=(
    prepare-iso
    "$WORK_BASE"
    --fetch-from iso
    --answer-file "$WORK_ANSWER"
    --output "$WORK_OUTPUT"
)
if [ -n "$HOOK_FILE" ]; then
    ARGS+=(--on-first-boot "$(to_work_path "$HOOK_FILE")")
fi

echo "[$NODE] preparing ISO: proxmox-auto-install-assistant ${ARGS[*]}"
run "${ARGS[@]}"

echo "[$NODE] ISO ready: $OUTPUT_FILE"
