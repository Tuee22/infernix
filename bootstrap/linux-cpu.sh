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
  build   Ensure host prerequisites and build the \`${COMPOSE_IMAGE}\` launcher image.
  up      Ensure host prerequisites, build the launcher image, and run \`cluster up\`.
  status  Show \`cluster status\` through the launcher image.
  test    Run \`infernix test all\` through the launcher image.
  down    Run \`cluster down\` while preserving durable repo-local state under ./.data/.
  purge   Destructive cleanup: tear down the cluster, remove repo-local state, and remove the local launcher image.

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
  docker compose build infernix
  docker compose build playwright
  docker compose run --rm infernix infernix internal materialize-substrate ${COMPOSE_SUBSTRATE} --demo-ui true
  docker compose run --rm infernix infernix cluster up
  docker compose run --rm infernix infernix cluster status
  docker compose run --rm infernix infernix test all
  docker compose run --rm infernix infernix cluster down

Teardown and cleanup:
  ${SCRIPT_LABEL} down
  ${SCRIPT_LABEL} purge
EOF
}

compose_env() {
  COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT}" \
    INFERNIX_COMPOSE_IMAGE="${COMPOSE_IMAGE}" \
    INFERNIX_COMPOSE_SUBSTRATE="${COMPOSE_SUBSTRATE}" \
    INFERNIX_COMPOSE_BASE_IMAGE="${COMPOSE_BASE_IMAGE}" \
    INFERNIX_HOST_REPO_ROOT="${BOOTSTRAP_REPO_ROOT}" \
    "$@"
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

image_present() {
  docker image inspect "${COMPOSE_IMAGE}" >/dev/null 2>&1
}

playwright_image_present() {
  docker image inspect infernix-playwright:local >/dev/null 2>&1
}

ensure_launcher_image() {
  ensure_host_prerequisites
  if ! image_present; then
    bootstrap::run compose_env docker compose build infernix
  fi
  if ! playwright_image_present; then
    bootstrap::run compose_env docker compose build playwright
  fi
}

substrate_staged() {
  [[ -f ./.build/outer-container/build/infernix-substrate.dhall ]]
}

ensure_substrate_staged() {
  if substrate_staged; then
    return 0
  fi
  bootstrap::run compose_env docker compose run --rm infernix \
    infernix internal materialize-substrate "${COMPOSE_SUBSTRATE}" --demo-ui true
}

run_infernix() {
  ensure_launcher_image
  ensure_substrate_staged
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
    docker image rm -f infernix-playwright:local || true
    return 0
  fi
  bootstrap::warn "Skipping Docker image removal because Docker is not currently usable from this shell."
}

command_doctor() {
  ensure_host_prerequisites
  bootstrap::info "Linux CPU host prerequisites are ready."
}

command_build() {
  ensure_launcher_image
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
  bootstrap::confirm_destructive "Purge Linux CPU launcher state, local image, and repo-local data?"
  best_effort_compose_down
  best_effort_remove_image
  bootstrap::run rm -rf ./.build ./.data
  bootstrap::info "Removed ./.build, ./.data, ${COMPOSE_IMAGE}, and infernix-playwright:local."
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
    *) bootstrap::die "Unsupported Linux CPU command: ${command}" ;;
  esac
  show_postamble
}

main "$@"
