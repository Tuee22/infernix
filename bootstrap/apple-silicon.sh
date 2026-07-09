#!/usr/bin/env bash
PATH=/usr/bin:/bin
export PATH
set -euo pipefail

BOOTSTRAP_BASH=/bin/bash
BOOTSTRAP_CURL=/usr/bin/curl
BOOTSTRAP_DIRNAME=/usr/bin/dirname
BOOTSTRAP_DSCL=/usr/bin/dscl
BOOTSTRAP_ENV=/usr/bin/env
BOOTSTRAP_ID=/usr/bin/id
BOOTSTRAP_SUDO=/usr/bin/sudo
BOOTSTRAP_UNAME=/usr/bin/uname

SCRIPT_DIR="$(cd -- "$("${BOOTSTRAP_DIRNAME}" -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/common.sh
source "${SCRIPT_DIR}/common.sh"

SCRIPT_LABEL="./bootstrap/apple-silicon.sh"
APPLE_GHC_VERSION="9.12.4"
APPLE_CABAL_VERSION="3.16.1.0"
APPLE_HOMEBREW_BIN=/opt/homebrew/bin
APPLE_BREW_BIN="${APPLE_HOMEBREW_BIN}/brew"
APPLE_GHCUP_BIN="${APPLE_HOMEBREW_BIN}/ghcup"
APPLE_GHC_BIN=""
APPLE_CABAL_BIN=""
APPLE_PROTOC_BIN=""

show_help() {
  cat <<EOF
${SCRIPT_LABEL} - idempotent Apple Silicon bootstrap for Infernix

Usage:
  ${SCRIPT_LABEL} help
  ${SCRIPT_LABEL} doctor
  ${SCRIPT_LABEL} build
  ${SCRIPT_LABEL} up
  ${SCRIPT_LABEL} run-daemon
  ${SCRIPT_LABEL} status
  ${SCRIPT_LABEL} test
  ${SCRIPT_LABEL} down
  ${SCRIPT_LABEL} purge

Commands:
  help        Show this help text.
  doctor      Ensure Homebrew, ghcup, GHC ${APPLE_GHC_VERSION}, Cabal ${APPLE_CABAL_VERSION}, and \`protoc\`;
              also reports whether Poetry has been bootstrapped yet.
  build       Ensure prerequisites and build both host binaries under ./.build/.
  up          Ensure prerequisites, build the host binary, reconcile \`./infernix.dhall\` /
              \`./infernix-host.dhall\` via \`infernix init --if-missing\`, and run \`cluster up\`.
  run-daemon  Run the on-host \`infernix service\` engine daemon in the foreground; required for
              inference on Apple Silicon after \`up\` and not spawned by \`up\` itself.
  status      Show \`cluster status\`.
  test        Run \`./.build/infernix test all\`.
  down        Run \`cluster down\` while preserving durable repo-local state under ./.data/.
  purge       Compatibility alias for \`down\`; preserves build output, data, images, and prerequisites.

This script is safe to re-run. It prefers the supported Apple Silicon path:
Homebrew + ghcup + direct host-native \`./.build/infernix\`, while reconciling build-time
Homebrew tools such as \`protoc\` before the first direct Cabal handoff.
EOF
}

show_postamble() {
  cat <<EOF

Available Apple Silicon commands:
  ${SCRIPT_LABEL} doctor
  ${SCRIPT_LABEL} build
  ${SCRIPT_LABEL} up
  ${SCRIPT_LABEL} run-daemon
  ${SCRIPT_LABEL} status
  ${SCRIPT_LABEL} test
  ${SCRIPT_LABEL} down
  ${SCRIPT_LABEL} purge

Direct reference commands:
  cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes
  ./.build/infernix init
  ./.build/infernix cluster up
  ./.build/infernix service
  ./.build/infernix cluster status
  ./.build/infernix test all
  ./.build/infernix cluster down

Teardown and cleanup:
  ${SCRIPT_LABEL} down
  ${SCRIPT_LABEL} purge
EOF
}

ensure_homebrew() {
  if [[ ! -x "${APPLE_BREW_BIN}" ]]; then
    bootstrap::info "Installing Homebrew into the supported /opt/homebrew prefix."
    "${BOOTSTRAP_BASH}" -c "$("${BOOTSTRAP_CURL}" -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ ! -x "${APPLE_BREW_BIN}" ]]; then
      bootstrap::pending "Homebrew installation is still pending. Finish any macOS or Command Line Tools prompts, then rerun ${SCRIPT_LABEL}."
    fi
  fi
}

ensure_brew_formula() {
  local formula="$1"
  if "${APPLE_BREW_BIN}" list --formula "${formula}" >/dev/null 2>&1; then
    return 0
  fi
  bootstrap::run "${APPLE_BREW_BIN}" install "${formula}"
}

ensure_ghcup_toolchain() {
  local home_dir
  local ghc_path
  local ghc_version_path
  local cabal_path
  local cabal_version_path

  ensure_brew_formula ghcup
  [[ -x "${APPLE_GHCUP_BIN}" ]] || bootstrap::die "Homebrew installed ghcup but ${APPLE_GHCUP_BIN} is missing."

  home_dir="$(bootstrap::effective_home)"
  ghc_path="${home_dir}/.ghcup/bin/ghc"
  ghc_version_path="${home_dir}/.ghcup/bin/ghc-${APPLE_GHC_VERSION}"
  cabal_path="${home_dir}/.ghcup/bin/cabal"
  cabal_version_path="${home_dir}/.ghcup/bin/cabal-${APPLE_CABAL_VERSION}"

  if [[ ! -x "${ghc_version_path}" ]]; then
    bootstrap::run "${BOOTSTRAP_ENV}" "HOME=${home_dir}" "${APPLE_GHCUP_BIN}" install ghc "${APPLE_GHC_VERSION}"
  fi
  bootstrap::run "${BOOTSTRAP_ENV}" "HOME=${home_dir}" "${APPLE_GHCUP_BIN}" set ghc "${APPLE_GHC_VERSION}"

  if [[ ! -x "${cabal_version_path}" ]]; then
    bootstrap::run "${BOOTSTRAP_ENV}" "HOME=${home_dir}" "${APPLE_GHCUP_BIN}" install cabal "${APPLE_CABAL_VERSION}"
  fi
  bootstrap::run "${BOOTSTRAP_ENV}" "HOME=${home_dir}" "${APPLE_GHCUP_BIN}" set cabal "${APPLE_CABAL_VERSION}"

  APPLE_GHC_BIN="$(bootstrap::require_command_version ghc "${ghc_path}" "${APPLE_GHC_VERSION}" --numeric-version)"
  APPLE_CABAL_BIN="$(bootstrap::require_command_version cabal "${cabal_path}" "${APPLE_CABAL_VERSION}" --numeric-version)"
}

ensure_protobuf_compiler() {
  local protobuf_prefix
  ensure_brew_formula protobuf
  protobuf_prefix="$("${APPLE_BREW_BIN}" --prefix protobuf)"
  APPLE_PROTOC_BIN="$(bootstrap::require_command protoc "${protobuf_prefix}/bin/protoc" "Protocol Buffers compiler" --version)"
}

# Phase 3 Sprint 3.11 follow-on (2026-05-29): the supported Apple
# host-native publication path falls back to `skopeo copy` when
# `docker push` hits the Docker 29.x containerd snapshotter
# "Unavailable" layers race. Reconcile the Homebrew-managed `skopeo`
# formula so the binary's fallback resolves through
# `HostConfig.toolPaths.skopeo` (defaulting to
# `/opt/homebrew/bin/skopeo`) without requiring operator setup.
ensure_skopeo() {
  ensure_brew_formula skopeo
}

# Diagnostic only: Poetry is not a generic platform prerequisite (see
# documents/development/python_policy.md). `infernix` bootstraps a
# user-local Poetry executable itself the first time an Apple adapter
# setup or validation path needs one, provided `./infernix-host.dhall`
# already exists (created by `infernix init`). This check only surfaces
# status from `doctor`/`build`/`up` so an unbootstrapped Poetry is visible
# early instead of only as a deeper `cluster up` failure.
check_poetry() {
  local home_dir
  local candidate
  home_dir="$(bootstrap::effective_home)"
  for candidate in "${home_dir}/.local/share/pypoetry/venv/bin/poetry" "${home_dir}/.local/bin/poetry"; do
    if [[ -x "${candidate}" ]]; then
      bootstrap::info "Poetry is available at ${candidate}."
      return 0
    fi
  done
  bootstrap::info "Poetry is not yet bootstrapped. infernix bootstraps it automatically the first time an Apple adapter setup path needs one, once ./infernix-host.dhall exists (run \`infernix init\` first if you have not already)."
}

ensure_build_prerequisites() {
  bootstrap::require_macos
  ensure_homebrew
  ensure_ghcup_toolchain
  ensure_protobuf_compiler
  ensure_skopeo
  check_poetry
}

# The hermetic PATH=/usr/bin:/bin set at the top of this script keeps the
# bootstrap itself from depending on the operator's inherited PATH. The direct
# Cabal build still needs a process PATH for Cabal/proto-lens setup tools, so
# provide a deterministic setup-local path rather than appending the inherited
# environment.
apple_launcher_path() {
  printf '%s\n' "$(bootstrap::effective_home)/.ghcup/bin:${APPLE_HOMEBREW_BIN}:/usr/bin:/bin"
}

run_launcher() {
  bootstrap::run "${BOOTSTRAP_ENV}" "PATH=$(apple_launcher_path)" ./.build/infernix "$@"
}

build_launcher() {
  local home_dir
  ensure_build_prerequisites
  home_dir="$(bootstrap::effective_home)"
  bootstrap::run "${BOOTSTRAP_ENV}" "HOME=${home_dir}" "PATH=$(apple_launcher_path)" "${APPLE_CABAL_BIN}" install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes
}

ensure_launcher_ready() {
  [[ -x ./.build/infernix ]] || build_launcher
}

command_doctor() {
  ensure_build_prerequisites
  bootstrap::info "Apple host prerequisites are ready."
}

command_build() {
  build_launcher
  bootstrap::info "Apple host launcher build is ready."
}

command_up() {
  build_launcher
  run_launcher init --if-missing
  run_launcher cluster up
}

command_run_daemon() {
  ensure_launcher_ready
  run_launcher service
}

command_status() {
  ensure_launcher_ready
  run_launcher cluster status
}

command_test() {
  build_launcher
  run_launcher test all
}

command_down() {
  ensure_launcher_ready
  run_launcher cluster down
}

command_purge() {
  command_down
  bootstrap::info "Preserved ./.build, ./.data, local images, host binaries, and installed prerequisites."
}

main() {
  local command="${1:-help}"
  bootstrap::cd_repo_root
  case "${command}" in
    help | -h | --help) show_help ;;
    doctor) command_doctor ;;
    build) command_build ;;
    up) command_up ;;
    run-daemon) command_run_daemon ;;
    status) command_status ;;
    test) command_test ;;
    down) command_down ;;
    purge) command_purge ;;
    *) bootstrap::die "Unsupported Apple Silicon command: ${command}" ;;
  esac
  show_postamble
}

main "$@"
