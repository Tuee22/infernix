#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/common.sh
source "${SCRIPT_DIR}/common.sh"

SCRIPT_LABEL="./bootstrap/linux-gpu.sh"
COMPOSE_IMAGE="infernix-linux-gpu:local"
COMPOSE_SUBSTRATE="linux-gpu"
COMPOSE_BASE_IMAGE="nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04"
NVIDIA_PROBE_IMAGE="nvidia/cuda:12.4.1-base-ubuntu22.04"

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
  build   Ensure host prerequisites and build the \`${COMPOSE_IMAGE}\` launcher image.
  up      Ensure host prerequisites, build the launcher image, and run \`cluster up\`.
  status  Show \`cluster status\` through the launcher image.
  test    Run \`infernix test all\` through the launcher image.
  down    Run \`cluster down\` while preserving durable repo-local state under ./.data/.
  purge   Destructive cleanup: tear down the cluster, remove repo-local state, and remove the local launcher image.

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
  INFERNIX_COMPOSE_IMAGE=${COMPOSE_IMAGE} INFERNIX_COMPOSE_SUBSTRATE=${COMPOSE_SUBSTRATE} INFERNIX_COMPOSE_BASE_IMAGE=${COMPOSE_BASE_IMAGE} docker compose build infernix
  INFERNIX_COMPOSE_IMAGE=${COMPOSE_IMAGE} INFERNIX_COMPOSE_SUBSTRATE=${COMPOSE_SUBSTRATE} INFERNIX_COMPOSE_BASE_IMAGE=${COMPOSE_BASE_IMAGE} docker compose run --rm infernix infernix cluster up
  INFERNIX_COMPOSE_IMAGE=${COMPOSE_IMAGE} INFERNIX_COMPOSE_SUBSTRATE=${COMPOSE_SUBSTRATE} INFERNIX_COMPOSE_BASE_IMAGE=${COMPOSE_BASE_IMAGE} docker compose run --rm infernix infernix cluster status
  INFERNIX_COMPOSE_IMAGE=${COMPOSE_IMAGE} INFERNIX_COMPOSE_SUBSTRATE=${COMPOSE_SUBSTRATE} INFERNIX_COMPOSE_BASE_IMAGE=${COMPOSE_BASE_IMAGE} docker compose run --rm infernix infernix test all
  INFERNIX_COMPOSE_IMAGE=${COMPOSE_IMAGE} INFERNIX_COMPOSE_SUBSTRATE=${COMPOSE_SUBSTRATE} INFERNIX_COMPOSE_BASE_IMAGE=${COMPOSE_BASE_IMAGE} docker compose run --rm infernix infernix cluster down

Teardown and cleanup:
  ${SCRIPT_LABEL} down
  ${SCRIPT_LABEL} purge
EOF
}

compose_env() {
  INFERNIX_COMPOSE_IMAGE="${COMPOSE_IMAGE}" \
    INFERNIX_COMPOSE_SUBSTRATE="${COMPOSE_SUBSTRATE}" \
    INFERNIX_COMPOSE_BASE_IMAGE="${COMPOSE_BASE_IMAGE}" \
    "$@"
}

ensure_platform_shape() {
  bootstrap::require_linux
  bootstrap::require_ubuntu_24_04
  [[ "$(dpkg --print-architecture)" == "amd64" ]] || bootstrap::die "The supported linux-gpu host shape is Ubuntu 24.04 amd64."
}

docker_ready() {
  docker version >/dev/null 2>&1
}

docker_compose_ready() {
  docker compose version >/dev/null 2>&1
}

docker_gpu_runtime_ready() {
  docker run --rm --gpus all "${NVIDIA_PROBE_IMAGE}" nvidia-smi -L >/dev/null 2>&1
}

docker_gpu_volume_mount_ready() {
  docker run --rm --gpus all -v /dev/null:/var/run/nvidia-container-devices/all "${NVIDIA_PROBE_IMAGE}" nvidia-smi -L >/dev/null 2>&1
}

ensure_docker_service_running() {
  if docker_ready; then
    return 0
  fi
  if bootstrap::have systemctl; then
    bootstrap::ensure_sudo_session
    bootstrap::run sudo systemctl enable --now docker
  fi
}

write_docker_sources_file() {
  local temp_file
  temp_file="$(mktemp)"
  cat >"${temp_file}" <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${BOOTSTRAP_OS_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  if ! sudo cmp -s "${temp_file}" /etc/apt/sources.list.d/docker.sources 2>/dev/null; then
    bootstrap::run sudo cp "${temp_file}" /etc/apt/sources.list.d/docker.sources
  fi
  rm -f "${temp_file}"
}

ensure_docker_engine() {
  if docker_ready && docker_compose_ready; then
    return 0
  fi

  ensure_platform_shape
  bootstrap::ensure_sudo_session

  bootstrap::run sudo apt-get update
  bootstrap::run sudo apt-get install -y ca-certificates curl gnupg
  bootstrap::run sudo install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    bootstrap::run sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    bootstrap::run sudo chmod a+r /etc/apt/keyrings/docker.asc
  fi
  write_docker_sources_file
  bootstrap::run sudo apt-get update
  bootstrap::run sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  ensure_docker_service_running
}

ensure_docker_socket_access() {
  ensure_docker_service_running
  if docker_ready && docker_compose_ready; then
    return 0
  fi

  if sudo docker version >/dev/null 2>&1; then
    if ! id -nG "${USER}" | tr ' ' '\n' | grep -qx docker; then
      bootstrap::run sudo usermod -aG docker "${USER}"
    fi
    bootstrap::pending "Docker is installed, but this shell does not yet have Docker socket access. Open a new shell, then rerun ${SCRIPT_LABEL}."
  fi

  bootstrap::die "Docker is installed but not usable from this shell. Check the Docker daemon and socket permissions, then rerun ${SCRIPT_LABEL}."
}

driver_packages_present() {
  dpkg -l 'nvidia-driver*' 2>/dev/null | grep -q '^ii'
}

ensure_nvidia_driver() {
  if bootstrap::have nvidia-smi && nvidia-smi -L >/dev/null 2>&1; then
    return 0
  fi

  ensure_platform_shape
  bootstrap::ensure_sudo_session
  bootstrap::run sudo apt-get update
  bootstrap::run sudo apt-get install -y ubuntu-drivers-common

  if driver_packages_present; then
    bootstrap::pending "NVIDIA driver packages appear installed, but nvidia-smi is still not ready. Reboot the host, then rerun ${SCRIPT_LABEL}."
  fi

  bootstrap::run sudo ubuntu-drivers install --gpgpu
  bootstrap::pending "Installed the recommended Ubuntu NVIDIA compute driver. Reboot the host, then rerun ${SCRIPT_LABEL}."
}

write_nvidia_toolkit_list() {
  local temp_file
  temp_file="$(mktemp)"
  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' >"${temp_file}"
  if ! sudo cmp -s "${temp_file}" /etc/apt/sources.list.d/nvidia-container-toolkit.list 2>/dev/null; then
    bootstrap::run sudo cp "${temp_file}" /etc/apt/sources.list.d/nvidia-container-toolkit.list
  fi
  rm -f "${temp_file}"
}

ensure_nvidia_container_toolkit() {
  if docker_gpu_runtime_ready && docker_gpu_volume_mount_ready; then
    return 0
  fi

  ensure_docker_engine
  ensure_docker_socket_access
  ensure_nvidia_driver
  bootstrap::ensure_sudo_session

  bootstrap::run sudo apt-get update
  bootstrap::run sudo apt-get install -y ca-certificates curl gnupg
  bootstrap::run sudo install -m 0755 -d /usr/share/keyrings
  if [[ ! -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg ]]; then
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
      | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  fi
  write_nvidia_toolkit_list
  bootstrap::run sudo apt-get update
  bootstrap::run sudo apt-get install -y nvidia-container-toolkit
  if ! sudo nvidia-ctk runtime configure --runtime=docker --set-as-default --cdi.enabled; then
    bootstrap::run sudo nvidia-ctk runtime configure --runtime=docker
  fi
  bootstrap::run sudo nvidia-ctk config --set accept-nvidia-visible-devices-as-volume-mounts=true --in-place
  bootstrap::run sudo systemctl restart docker

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

image_present() {
  docker image inspect "${COMPOSE_IMAGE}" >/dev/null 2>&1
}

ensure_launcher_image() {
  ensure_host_prerequisites
  if image_present; then
    return 0
  fi
  bootstrap::run compose_env docker compose build infernix
}

run_infernix() {
  ensure_launcher_image
  bootstrap::run compose_env docker compose run --rm infernix infernix "$@"
}

best_effort_compose_down() {
  if docker_ready && docker_compose_ready; then
    compose_env docker compose down -v --remove-orphans || true
    return 0
  fi
  bootstrap::warn "Skipping docker compose down because Docker is not currently usable from this shell."
}

best_effort_remove_image() {
  if docker_ready; then
    docker image rm -f "${COMPOSE_IMAGE}" || true
    return 0
  fi
  bootstrap::warn "Skipping Docker image removal because Docker is not currently usable from this shell."
}

command_doctor() {
  ensure_gpu_runtime_prerequisites
  bootstrap::info "Linux GPU host prerequisites are ready."
}

command_build() {
  ensure_launcher_image
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
  bootstrap::confirm_destructive "Purge Linux GPU launcher state, local image, and repo-local data?"
  best_effort_compose_down
  best_effort_remove_image
  bootstrap::run rm -rf ./.build ./.data
  bootstrap::info "Removed ./.build, ./.data, and ${COMPOSE_IMAGE}."
}

main() {
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
