#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/common.sh
source "${SCRIPT_DIR}/common.sh"

SCRIPT_LABEL="./bootstrap/linux-cpu.sh"
COMPOSE_IMAGE="infernix-linux-cpu:local"
COMPOSE_SUBSTRATE="linux-cpu"
COMPOSE_BASE_IMAGE="ubuntu:24.04"
COMPOSE_PROJECT="infernix-linux-cpu"

show_help() {
  cat <<EOF
${SCRIPT_LABEL} - idempotent Ubuntu 24.04 CPU bootstrap for Infernix

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
  doctor  Ensure Docker Engine, the Compose plugin, and user access to the Docker socket.
  build   Ensure host prerequisites and build or enter the \`${COMPOSE_IMAGE}\` launcher image.
  up      Ensure host prerequisites, enter the launcher image, and run \`cluster up\`.
  status  Show \`cluster status\` through the launcher image.
  test    Run \`infernix test all\` through the launcher image.
  down    Run \`cluster down\` while preserving durable repo-local state under ./.data/.
  purge   Compatibility alias for \`down\`; preserves repo-local state, images, and prerequisites.

This script is safe to re-run. It targets the supported Ubuntu 24.04 CPU path.
EOF
}

show_postamble() {
  cat <<EOF

Available Linux CPU commands:
  ${SCRIPT_LABEL} doctor
  ${SCRIPT_LABEL} build
  ${SCRIPT_LABEL} up
  ${SCRIPT_LABEL} status
  ${SCRIPT_LABEL} test
  ${SCRIPT_LABEL} down
  ${SCRIPT_LABEL} purge

Direct reference commands:
  docker compose run --rm infernix infernix cluster up
  docker compose run --rm infernix infernix cluster status
  docker compose run --rm infernix infernix test all
  docker compose run --rm infernix infernix cluster down

Teardown and cleanup:
  ${SCRIPT_LABEL} down
  ${SCRIPT_LABEL} purge
EOF
}

# Phase 1 Sprint 1.11 — compose.yaml has no build: block, no
# environment: block, and no substrate-selection env var. The script
# sets exactly @INFERNIX_COMPOSE_IMAGE@ (compose's image-name selector)
# and @INFERNIX_HOST_REPO_ROOT@ (Sprint 2.10 territory, still consumed
# by @Cluster.hs@ for host-side kind config path resolution).
compose_env() {
  COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT}" \
    INFERNIX_COMPOSE_IMAGE="${COMPOSE_IMAGE}" \
    INFERNIX_HOST_REPO_ROOT="${BOOTSTRAP_REPO_ROOT}" \
    "$@"
}

# Phase 1 Sprint 1.11 — explicit @docker build@ replaces the previous
# compose.yaml @build: args:@ block (forbidden by the
# configuration-doctrine standards). Build args feed the Dockerfile;
# the resulting image is referenced from compose.yaml by name only.
build_launcher_image() {
  bootstrap::run docker build \
    --file docker/linux-substrate.Dockerfile \
    --tag "${COMPOSE_IMAGE}" \
    --build-arg "RUNTIME_MODE=${COMPOSE_SUBSTRATE}" \
    --build-arg "BASE_IMAGE=${COMPOSE_BASE_IMAGE}" \
    --build-arg "DEMO_UI=true" \
    .
}

docker_ready() {
  docker version >/dev/null 2>&1
}

docker_compose_ready() {
  docker compose version >/dev/null 2>&1
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

  bootstrap::require_linux
  bootstrap::require_ubuntu_24_04
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

ensure_host_prerequisites() {
  ensure_docker_engine
  ensure_docker_socket_access
}

run_infernix() {
  ensure_host_prerequisites
  bootstrap::run compose_env docker compose run --rm infernix infernix "$@"
}

command_doctor() {
  ensure_host_prerequisites
  bootstrap::info "Linux CPU host prerequisites are ready."
}

command_build() {
  ensure_host_prerequisites
  build_launcher_image
  run_infernix --help
  bootstrap::info "Linux CPU launcher image is ready."
}

command_up() {
  run_infernix cluster up
}

command_status() {
  run_infernix cluster status
}

command_test() {
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
  # Phase 1 Sprint 1.11 — @--yes@ replaces the @INFERNIX_BOOTSTRAP_YES@
  # env-var sense for destructive-confirmation gates.
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
    *) bootstrap::die "Unsupported Linux CPU command: ${command}" ;;
  esac
  show_postamble
}

main "$@"
