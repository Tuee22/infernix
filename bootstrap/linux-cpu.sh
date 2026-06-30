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
BOOTSTRAP_INSTALL=/usr/bin/install
BOOTSTRAP_MKTEMP=/usr/bin/mktemp
BOOTSTRAP_RM=/usr/bin/rm
BOOTSTRAP_SUDO=/usr/bin/sudo
BOOTSTRAP_SYSTEMCTL=/usr/bin/systemctl
BOOTSTRAP_TR=/usr/bin/tr
BOOTSTRAP_GREP=/usr/bin/grep
BOOTSTRAP_USERMOD=/usr/sbin/usermod

SCRIPT_DIR="$(cd -- "$("${BOOTSTRAP_DIRNAME}" -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/common.sh
source "${SCRIPT_DIR}/common.sh"

SCRIPT_LABEL="./bootstrap/linux-cpu.sh"
COMPOSE_IMAGE="infernix-linux-cpu:local"
COMPOSE_SUBSTRATE="linux-cpu"
COMPOSE_BASE_IMAGE="ubuntu:24.04"
COMPOSE_PROJECT="infernix-linux-cpu"
COMPOSE_FILES=(--file compose.yaml)

# Apple Silicon hosts run this CPU lane through the operator's already-running
# native arm64 Docker daemon (the colima Linux VM). Docker schedules the
# launcher container on the VM's native linux/arm64 kernel — real Linux, not
# emulation. On macOS the Docker CLI lives under the Homebrew prefix instead of
# /usr/bin, and the apt/systemctl/usermod host-engine reconciliation does not
# apply, so the macOS branch only verifies the already-selected daemon and never
# installs an engine, creates or switches a Docker context, or provisions a VM.
BOOTSTRAP_HOST_OS="$("${BOOTSTRAP_UNAME}" -s)"
if [[ "${BOOTSTRAP_HOST_OS}" == "Darwin" ]]; then
  BOOTSTRAP_DOCKER=/opt/homebrew/bin/docker
fi

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
  docker compose --project-name ${COMPOSE_PROJECT} --file compose.yaml run --rm infernix infernix cluster up
  docker compose --project-name ${COMPOSE_PROJECT} --file compose.yaml run --rm infernix infernix cluster status
  docker compose --project-name ${COMPOSE_PROJECT} --file compose.yaml run --rm infernix infernix test all
  docker compose --project-name ${COMPOSE_PROJECT} --file compose.yaml run --rm infernix infernix cluster down

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

docker_ready() {
  "${BOOTSTRAP_DOCKER}" version >/dev/null 2>&1
}

docker_compose_ready() {
  "${BOOTSTRAP_DOCKER}" compose version >/dev/null 2>&1
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

  if [[ "${BOOTSTRAP_HOST_OS}" == "Darwin" ]]; then
    bootstrap::die "Docker is not reachable at ${BOOTSTRAP_DOCKER}. On Apple Silicon this lane runs through the operator's already-running native arm64 Docker daemon (the colima Linux VM); start it and rerun ${SCRIPT_LABEL}. This entrypoint does not install an engine, create or switch a Docker context, or provision a VM on macOS."
  fi

  bootstrap::require_linux
  bootstrap::require_ubuntu_24_04
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

ensure_host_prerequisites() {
  ensure_docker_engine
  ensure_docker_socket_access
}

run_infernix() {
  ensure_host_prerequisites
  compose_run "$@"
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
    *) bootstrap::die "Unsupported Linux CPU command: ${command}" ;;
  esac
  show_postamble
}

main "$@"
