#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_REPO_ROOT="$(cd -- "${BOOTSTRAP_SCRIPT_DIR}/.." && pwd)"
BOOTSTRAP_PENDING_EXIT_CODE=20

bootstrap::repo_root() {
  printf '%s\n' "${BOOTSTRAP_REPO_ROOT}"
}

bootstrap::cd_repo_root() {
  cd -- "${BOOTSTRAP_REPO_ROOT}"
}

bootstrap::have() {
  command -v "$1" >/dev/null 2>&1
}

bootstrap::info() {
  printf '[info] %s\n' "$*"
}

bootstrap::warn() {
  printf '[warn] %s\n' "$*" >&2
}

bootstrap::die() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

bootstrap::pending() {
  printf '[next] %s\n' "$*" >&2
  exit "${BOOTSTRAP_PENDING_EXIT_CODE}"
}

bootstrap::run() {
  bootstrap::info "+ $*"
  "$@"
}

bootstrap::require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || bootstrap::die "This bootstrap entrypoint only supports macOS."
}

bootstrap::require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || bootstrap::die "This bootstrap entrypoint only supports Linux."
}

bootstrap::load_os_release() {
  [[ -r /etc/os-release ]] || bootstrap::die "Missing /etc/os-release; unsupported Linux host."
  # shellcheck disable=SC1091
  . /etc/os-release
  BOOTSTRAP_OS_ID="${ID:-}"
  BOOTSTRAP_OS_VERSION_ID="${VERSION_ID:-}"
  BOOTSTRAP_OS_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
}

bootstrap::require_ubuntu_24_04() {
  bootstrap::load_os_release
  [[ "${BOOTSTRAP_OS_ID}" == "ubuntu" ]] || bootstrap::die "Supported Linux bootstrap host: Ubuntu 24.04."
  [[ "${BOOTSTRAP_OS_VERSION_ID}" == "24.04" ]] || bootstrap::die "Supported Linux bootstrap host: Ubuntu 24.04."
}

bootstrap::ensure_sudo_session() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  fi
  bootstrap::run sudo -v
}

bootstrap::prepend_path() {
  local entry="$1"
  [[ -n "${entry}" ]] || return 0
  case ":${PATH}:" in
    *":${entry}:"*) ;;
    *) export PATH="${entry}:${PATH}" ;;
  esac
  bootstrap::refresh_command_cache
}

bootstrap::refresh_command_cache() {
  hash -r 2>/dev/null || true
}

bootstrap::resolve_command() {
  command -v "$1" 2>/dev/null || return 1
}

bootstrap::require_command() {
  local command_name="$1"
  local expected_path="$2"
  local description="$3"
  shift 3
  local verify_args=("$@")
  local resolved

  bootstrap::prepend_path "$(dirname "${expected_path}")"
  [[ -x "${expected_path}" ]] || bootstrap::die "${description} is expected at ${expected_path} after bootstrap setup."
  resolved="$(bootstrap::resolve_command "${command_name}")" \
    || bootstrap::die "${description} is not visible on PATH after bootstrap setup. PATH=${PATH}"
  if [[ "${#verify_args[@]}" -gt 0 ]]; then
    "${resolved}" "${verify_args[@]}" >/dev/null 2>&1 \
      || bootstrap::die "${description} at ${resolved} failed verification via \`${command_name} ${verify_args[*]}\`."
  fi
  printf '%s\n' "${resolved}"
}

bootstrap::require_command_version() {
  local command_name="$1"
  local expected_path="$2"
  local expected_version="$3"
  shift 3
  local version_args=("$@")
  local resolved
  local actual_version

  resolved="$(bootstrap::require_command "${command_name}" "${expected_path}" "${command_name}" "${version_args[@]}")"
  actual_version="$("${resolved}" "${version_args[@]}")" \
    || bootstrap::die "Failed to read ${command_name} version from ${resolved}."
  [[ "${actual_version}" == "${expected_version}" ]] \
    || bootstrap::die "Expected ${command_name} ${expected_version}, got ${actual_version} from ${resolved}."
  printf '%s\n' "${resolved}"
}

bootstrap::confirm_destructive() {
  local prompt="$1"
  if [[ "${INFERNIX_BOOTSTRAP_YES:-0}" == "1" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    bootstrap::die "Destructive cleanup requires confirmation. Re-run with INFERNIX_BOOTSTRAP_YES=1."
  fi
  printf '%s [y/N] ' "${prompt}"
  read -r reply
  case "${reply}" in
    y | Y | yes | YES) return 0 ;;
    *) bootstrap::die "Cancelled." ;;
  esac
}
