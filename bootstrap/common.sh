#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_DIRNAME="${BOOTSTRAP_DIRNAME:-/usr/bin/dirname}"
BOOTSTRAP_DSCL="${BOOTSTRAP_DSCL:-/usr/bin/dscl}"
BOOTSTRAP_GETENT="${BOOTSTRAP_GETENT:-/usr/bin/getent}"
BOOTSTRAP_ID="${BOOTSTRAP_ID:-/usr/bin/id}"
BOOTSTRAP_SUDO="${BOOTSTRAP_SUDO:-/usr/bin/sudo}"
BOOTSTRAP_UNAME="${BOOTSTRAP_UNAME:-/usr/bin/uname}"

# Phase 1 Sprint 1.11 — destructive-confirmation gate is set explicitly
# from the bootstrap entrypoint's CLI parsing (typically the @--yes@
# flag), not by consulting the operator's inherited environment. See
# @bootstrap::confirm_destructive@ below.
BOOTSTRAP_SCRIPT_DIR="$(cd -- "$("${BOOTSTRAP_DIRNAME}" -- "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_REPO_ROOT="$(cd -- "${BOOTSTRAP_SCRIPT_DIR}/.." && pwd)"
BOOTSTRAP_PENDING_EXIT_CODE=20
BOOTSTRAP_ASSUME_YES=0
BOOTSTRAP_EFFECTIVE_USER=""
BOOTSTRAP_EFFECTIVE_HOME=""

bootstrap::repo_root() {
  printf '%s\n' "${BOOTSTRAP_REPO_ROOT}"
}

bootstrap::cd_repo_root() {
  cd -- "${BOOTSTRAP_REPO_ROOT}"
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
  [[ "$("${BOOTSTRAP_UNAME}" -s)" == "Darwin" ]] || bootstrap::die "This bootstrap entrypoint only supports macOS."
}

bootstrap::require_linux() {
  [[ "$("${BOOTSTRAP_UNAME}" -s)" == "Linux" ]] || bootstrap::die "This bootstrap entrypoint only supports Linux."
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
  if [[ "$("${BOOTSTRAP_ID}" -u)" -eq 0 ]]; then
    return 0
  fi
  bootstrap::run "${BOOTSTRAP_SUDO}" -v
}

bootstrap::load_effective_user() {
  local uid
  local passwd_entry
  local os_name
  local home_line

  [[ -n "${BOOTSTRAP_EFFECTIVE_USER}" ]] && return 0
  os_name="$("${BOOTSTRAP_UNAME}" -s)"
  case "${os_name}" in
    Darwin)
      BOOTSTRAP_EFFECTIVE_USER="$("${BOOTSTRAP_ID}" -un)"
      home_line="$("${BOOTSTRAP_DSCL}" . -read "/Users/${BOOTSTRAP_EFFECTIVE_USER}" NFSHomeDirectory 2>/dev/null || true)"
      BOOTSTRAP_EFFECTIVE_HOME="${home_line#NFSHomeDirectory: }"
      [[ -n "${BOOTSTRAP_EFFECTIVE_HOME}" && "${BOOTSTRAP_EFFECTIVE_HOME}" != "${home_line}" ]] \
        || bootstrap::die "Unable to resolve current user's home directory through dscl."
      ;;
    *)
      uid="$("${BOOTSTRAP_ID}" -u)"
      passwd_entry="$("${BOOTSTRAP_GETENT}" passwd "${uid}" 2>/dev/null || true)"
      [[ -n "${passwd_entry}" ]] || bootstrap::die "Unable to resolve current user from /etc/passwd."
      BOOTSTRAP_EFFECTIVE_USER="${passwd_entry%%:*}"
      passwd_entry="${passwd_entry#*:}"
      passwd_entry="${passwd_entry#*:}"
      passwd_entry="${passwd_entry#*:}"
      passwd_entry="${passwd_entry#*:}"
      BOOTSTRAP_EFFECTIVE_HOME="${passwd_entry%%:*}"
      ;;
  esac
}

bootstrap::effective_user() {
  bootstrap::load_effective_user
  printf '%s\n' "${BOOTSTRAP_EFFECTIVE_USER}"
}

bootstrap::effective_home() {
  bootstrap::load_effective_user
  printf '%s\n' "${BOOTSTRAP_EFFECTIVE_HOME}"
}

bootstrap::require_command() {
  local command_name="$1"
  local expected_path="$2"
  local description="$3"
  shift 3
  local verify_args=("$@")

  [[ -x "${expected_path}" ]] || bootstrap::die "${description} is expected at ${expected_path} after bootstrap setup."
  if [[ "${#verify_args[@]}" -gt 0 ]]; then
    "${expected_path}" "${verify_args[@]}" >/dev/null 2>&1 \
      || bootstrap::die "${description} at ${expected_path} failed verification via \`${command_name} ${verify_args[*]}\`."
  fi
  printf '%s\n' "${expected_path}"
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
  if [[ "${BOOTSTRAP_ASSUME_YES}" -eq 1 ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    bootstrap::die "Destructive cleanup requires confirmation. Re-run with --yes."
  fi
  printf '%s [y/N] ' "${prompt}"
  read -r reply
  case "${reply}" in
    y | Y | yes | YES) return 0 ;;
    *) bootstrap::die "Cancelled." ;;
  esac
}

# Phase 1 Sprint 1.11 — pop a leading @--yes@ from a script's argv and
# flip the destructive-confirmation gate. Bootstrap entrypoints call
# this once during argv parsing.
bootstrap::parse_yes_flag() {
  if [[ "${1:-}" == "--yes" ]]; then
    BOOTSTRAP_ASSUME_YES=1
    return 1
  fi
  return 0
}
