#!/usr/bin/env bash
PATH=/usr/bin:/bin
export PATH
set -euo pipefail

BOOTSTRAP_DIRNAME=/usr/bin/dirname
BOOTSTRAP_APT_GET=/usr/bin/apt-get
BOOTSTRAP_CHMOD=/usr/bin/chmod
BOOTSTRAP_CMP=/usr/bin/cmp
BOOTSTRAP_CP=/usr/bin/cp
BOOTSTRAP_CURL=/usr/bin/curl
BOOTSTRAP_DOCKER=/usr/bin/docker
BOOTSTRAP_DPKG=/usr/bin/dpkg
BOOTSTRAP_ENV=/usr/bin/env
BOOTSTRAP_GPG=/usr/bin/gpg
BOOTSTRAP_GREP=/usr/bin/grep
BOOTSTRAP_INSTALL=/usr/bin/install
BOOTSTRAP_MKTEMP=/usr/bin/mktemp
BOOTSTRAP_NVIDIA_CTK=/usr/bin/nvidia-ctk
BOOTSTRAP_NVIDIA_SMI=/usr/bin/nvidia-smi
BOOTSTRAP_RM=/usr/bin/rm
BOOTSTRAP_SED=/usr/bin/sed
BOOTSTRAP_SUDO=/usr/bin/sudo
BOOTSTRAP_SYSTEMCTL=/usr/bin/systemctl
BOOTSTRAP_TR=/usr/bin/tr
BOOTSTRAP_UBUNTU_DRIVERS=/usr/bin/ubuntu-drivers
BOOTSTRAP_USERMOD=/usr/sbin/usermod

SCRIPT_DIR="$(cd -- "$("${BOOTSTRAP_DIRNAME}" -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/common.sh
source "${SCRIPT_DIR}/common.sh"

SCRIPT_LABEL="./bootstrap/linux-gpu.sh"
COMPOSE_IMAGE="infernix-linux-gpu:local"
COMPOSE_SUBSTRATE="linux-gpu"
# Pinned to CUDA 12.8 to match the supported NVIDIA driver branch (570.x,
# `nvidia-smi` reports CUDA 12.8). A CUDA 13.x runtime needs driver >= 580,
# so the cuDNN runtime base and the engine's cu128 PyTorch/vLLM wheels are
# aligned on 12.8; bump both together only when the host driver moves to 580+.
COMPOSE_BASE_IMAGE="nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04"
NVIDIA_PROBE_IMAGE="nvidia/cuda:12.8.1-base-ubuntu24.04"
COMPOSE_PROJECT="infernix-linux-gpu"
COMPOSE_FILES=(--file compose.yaml)

show_help() {
  cat <<EOF
${SCRIPT_LABEL} - idempotent Ubuntu 24.04 NVIDIA bootstrap for Infernix

Usage:
  ${SCRIPT_LABEL} help
  ${SCRIPT_LABEL} doctor
  ${SCRIPT_LABEL} build
  ${SCRIPT_LABEL} up
  ${SCRIPT_LABEL} status
  ${SCRIPT_LABEL} test
  ${SCRIPT_LABEL} down
  ${SCRIPT_LABEL} purge

Commands:
  help    Show this help text.
  doctor  Ensure Docker, the NVIDIA driver, the NVIDIA Container Toolkit, and Docker GPU access.
  build   Ensure host prerequisites and build or enter the \`${COMPOSE_IMAGE}\` launcher image.
  up      Ensure host prerequisites, enter the launcher image, and run \`cluster up\`.
  status  Show \`cluster status\` through the launcher image.
  test    Run \`infernix test all\` through the launcher image.
  down    Run \`cluster down\` while preserving durable repo-local state under ./.data/.
  purge   Compatibility alias for \`down\`; preserves repo-local state, images, and prerequisites.

If the NVIDIA driver is missing, this script installs the recommended Ubuntu compute driver,
then stops and instructs you to reboot and run it again.
EOF
}

show_postamble() {
  cat <<EOF

Available Linux GPU commands:
  ${SCRIPT_LABEL} doctor
  ${SCRIPT_LABEL} build
  ${SCRIPT_LABEL} up
  ${SCRIPT_LABEL} status
  ${SCRIPT_LABEL} test
  ${SCRIPT_LABEL} down
  ${SCRIPT_LABEL} purge

Direct reference commands:
  docker build -f docker/Dockerfile --provenance=false -t ${COMPOSE_IMAGE} --build-arg RUNTIME_MODE=${COMPOSE_SUBSTRATE} --build-arg BASE_IMAGE=${COMPOSE_BASE_IMAGE} --build-arg DEMO_UI=true .
  LAUNCHER_IMAGE=${COMPOSE_IMAGE} docker compose --project-name ${COMPOSE_PROJECT} --file compose.yaml run --rm infernix infernix cluster up
  LAUNCHER_IMAGE=${COMPOSE_IMAGE} docker compose --project-name ${COMPOSE_PROJECT} --file compose.yaml run --rm infernix infernix cluster status
  LAUNCHER_IMAGE=${COMPOSE_IMAGE} docker compose --project-name ${COMPOSE_PROJECT} --file compose.yaml run --rm infernix infernix test all
  LAUNCHER_IMAGE=${COMPOSE_IMAGE} docker compose --project-name ${COMPOSE_PROJECT} --file compose.yaml run --rm infernix infernix cluster down

Teardown and cleanup:
  ${SCRIPT_LABEL} down
  ${SCRIPT_LABEL} purge
EOF
}

# Phase 1 Sprint 1.11 — compose.yaml has no build: block, no
# environment: block, and no substrate-selection env var. The script
# selects the project and compose files with explicit CLI arguments.
compose_run() {
  bootstrap::run "${BOOTSTRAP_ENV}" "LAUNCHER_IMAGE=${COMPOSE_IMAGE}" "${BOOTSTRAP_DOCKER}" compose --project-name "${COMPOSE_PROJECT}" "${COMPOSE_FILES[@]}" run --rm infernix infernix "$@"
}

# Phase 1 Sprint 1.11 — explicit @docker build@ replaces the previous
# compose.yaml @build: args:@ block (forbidden by the
# configuration-doctrine standards). Build args feed the Dockerfile;
# the resulting image is referenced from compose.yaml by name only.
# BuildKit provenance is disabled so Harbor publication sees a plain
# single-platform image rather than an OCI index with attestation metadata.
build_launcher_image() {
  bootstrap::run "${BOOTSTRAP_DOCKER}" build \
    --file docker/Dockerfile \
    --provenance=false \
    --tag "${COMPOSE_IMAGE}" \
    --build-arg "RUNTIME_MODE=${COMPOSE_SUBSTRATE}" \
    --build-arg "BASE_IMAGE=${COMPOSE_BASE_IMAGE}" \
    --build-arg "DEMO_UI=true" \
    .
}

ensure_platform_shape() {
  bootstrap::require_linux
  bootstrap::require_ubuntu_24_04
  [[ "$("${BOOTSTRAP_DPKG}" --print-architecture)" == "amd64" ]] || bootstrap::die "The supported linux-gpu host shape is Ubuntu 24.04 amd64."
}

docker_ready() {
  "${BOOTSTRAP_DOCKER}" version >/dev/null 2>&1
}

docker_compose_ready() {
  "${BOOTSTRAP_DOCKER}" compose version >/dev/null 2>&1
}

docker_gpu_runtime_ready() {
  "${BOOTSTRAP_DOCKER}" run --rm --gpus all "${NVIDIA_PROBE_IMAGE}" "${BOOTSTRAP_NVIDIA_SMI}" -L >/dev/null 2>&1
}

docker_gpu_volume_mount_ready() {
  "${BOOTSTRAP_DOCKER}" run --rm --gpus all -v /dev/null:/var/run/nvidia-container-devices/all "${NVIDIA_PROBE_IMAGE}" "${BOOTSTRAP_NVIDIA_SMI}" -L >/dev/null 2>&1
}

ensure_docker_service_running() {
  if docker_ready; then
    return 0
  fi
  if [[ -x "${BOOTSTRAP_SYSTEMCTL}" ]]; then
    bootstrap::ensure_sudo_session
    bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_SYSTEMCTL}" enable --now docker
  fi
}

write_docker_sources_file() {
  local temp_file
  temp_file="$("${BOOTSTRAP_MKTEMP}")"
  {
    printf '%s\n' "Types: deb"
    printf '%s\n' "URIs: https://download.docker.com/linux/ubuntu"
    printf '%s\n' "Suites: ${BOOTSTRAP_OS_CODENAME}"
    printf '%s\n' "Components: stable"
    printf '%s\n' "Architectures: $("${BOOTSTRAP_DPKG}" --print-architecture)"
    printf '%s\n' "Signed-By: /etc/apt/keyrings/docker.asc"
  } >"${temp_file}"
  if ! "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_CMP}" -s "${temp_file}" /etc/apt/sources.list.d/docker.sources 2>/dev/null; then
    bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_CP}" "${temp_file}" /etc/apt/sources.list.d/docker.sources
  fi
  "${BOOTSTRAP_RM}" -f "${temp_file}"
}

ensure_docker_engine() {
  if docker_ready && docker_compose_ready; then
    return 0
  fi

  ensure_platform_shape
  bootstrap::ensure_sudo_session

  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_APT_GET}" update
  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_APT_GET}" install -y ca-certificates curl gnupg
  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_INSTALL}" -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_CURL}" -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_CHMOD}" a+r /etc/apt/keyrings/docker.asc
  fi
  write_docker_sources_file
  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_APT_GET}" update
  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_APT_GET}" install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  ensure_docker_service_running
}

ensure_docker_socket_access() {
  ensure_docker_service_running
  if docker_ready && docker_compose_ready; then
    return 0
  fi

  if "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_DOCKER}" version >/dev/null 2>&1; then
    local effective_user
    effective_user="$(bootstrap::effective_user)"
    if ! "${BOOTSTRAP_ID}" -nG "${effective_user}" | "${BOOTSTRAP_TR}" ' ' '\n' | "${BOOTSTRAP_GREP}" -qx docker; then
      bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_USERMOD}" -aG docker "${effective_user}"
    fi
    bootstrap::pending "Docker is installed, but this shell does not yet have Docker socket access. Open a new shell, then rerun ${SCRIPT_LABEL}."
  fi

  bootstrap::die "Docker is installed but not usable from this shell. Check the Docker daemon and socket permissions, then rerun ${SCRIPT_LABEL}."
}

driver_packages_present() {
  "${BOOTSTRAP_DPKG}" -l 'nvidia-driver*' 2>/dev/null | "${BOOTSTRAP_GREP}" -q '^ii'
}

ensure_nvidia_driver() {
  if [[ -x "${BOOTSTRAP_NVIDIA_SMI}" ]] && "${BOOTSTRAP_NVIDIA_SMI}" -L >/dev/null 2>&1; then
    return 0
  fi

  ensure_platform_shape
  bootstrap::ensure_sudo_session
  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_APT_GET}" update
  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_APT_GET}" install -y ubuntu-drivers-common

  if driver_packages_present; then
    bootstrap::pending "NVIDIA driver packages appear installed, but nvidia-smi is still not ready. Reboot the host, then rerun ${SCRIPT_LABEL}."
  fi

  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_UBUNTU_DRIVERS}" install --gpgpu
  bootstrap::pending "Installed the recommended Ubuntu NVIDIA compute driver. Reboot the host, then rerun ${SCRIPT_LABEL}."
}

write_nvidia_toolkit_list() {
  local temp_file
  temp_file="$("${BOOTSTRAP_MKTEMP}")"
  "${BOOTSTRAP_CURL}" -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | "${BOOTSTRAP_SED}" 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' >"${temp_file}"
  if ! "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_CMP}" -s "${temp_file}" /etc/apt/sources.list.d/nvidia-container-toolkit.list 2>/dev/null; then
    bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_CP}" "${temp_file}" /etc/apt/sources.list.d/nvidia-container-toolkit.list
  fi
  "${BOOTSTRAP_RM}" -f "${temp_file}"
}

ensure_nvidia_container_toolkit() {
  if docker_gpu_runtime_ready && docker_gpu_volume_mount_ready; then
    return 0
  fi

  ensure_docker_engine
  ensure_docker_socket_access
  ensure_nvidia_driver
  bootstrap::ensure_sudo_session

  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_APT_GET}" update
  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_APT_GET}" install -y ca-certificates curl gnupg
  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_INSTALL}" -m 0755 -d /usr/share/keyrings
  if [[ ! -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg ]]; then
    "${BOOTSTRAP_CURL}" -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
      | "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_GPG}" --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  fi
  write_nvidia_toolkit_list
  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_APT_GET}" update
  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_APT_GET}" install -y nvidia-container-toolkit
  if ! "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_NVIDIA_CTK}" runtime configure --runtime=docker --set-as-default --cdi.enabled; then
    bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_NVIDIA_CTK}" runtime configure --runtime=docker
  fi
  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_NVIDIA_CTK}" config --set accept-nvidia-visible-devices-as-volume-mounts=true --in-place
  bootstrap::run "${BOOTSTRAP_SUDO}" "${BOOTSTRAP_SYSTEMCTL}" restart docker

  if ! docker_gpu_runtime_ready || ! docker_gpu_volume_mount_ready; then
    bootstrap::die "Docker GPU probes are still failing after NVIDIA Container Toolkit configuration. Verify \`nvidia-smi -L\` and rerun ${SCRIPT_LABEL} doctor."
  fi
}

ensure_host_prerequisites() {
  ensure_platform_shape
  ensure_docker_engine
  ensure_docker_socket_access
}

ensure_gpu_runtime_prerequisites() {
  ensure_host_prerequisites
  ensure_nvidia_driver
  ensure_nvidia_container_toolkit
}

run_infernix() {
  ensure_host_prerequisites
  compose_run "$@"
}

command_doctor() {
  ensure_gpu_runtime_prerequisites
  bootstrap::info "Linux GPU host prerequisites are ready."
}

command_build() {
  ensure_gpu_runtime_prerequisites
  build_launcher_image
  run_infernix --help
  bootstrap::info "Linux GPU launcher image is ready."
}

command_up() {
  ensure_gpu_runtime_prerequisites
  run_infernix cluster up
}

command_status() {
  run_infernix cluster status
}

command_test() {
  ensure_gpu_runtime_prerequisites
  run_infernix test all
}

command_down() {
  run_infernix cluster down
}

command_purge() {
  command_down
  bootstrap::info "Preserved ./.build, ./.data, local images, and installed prerequisites."
}

main() {
  # Phase 1 Sprint 1.11 — @--yes@ owns destructive-confirmation gates.
  if ! bootstrap::parse_yes_flag "${1:-}"; then
    shift
  fi
  local command="${1:-help}"
  bootstrap::cd_repo_root
  case "${command}" in
    help | -h | --help) show_help ;;
    doctor) command_doctor ;;
    build) command_build ;;
    up) command_up ;;
    status) command_status ;;
    test) command_test ;;
    down) command_down ;;
    purge) command_purge ;;
    *) bootstrap::die "Unsupported Linux GPU command: ${command}" ;;
  esac
  show_postamble
}

main "$@"
