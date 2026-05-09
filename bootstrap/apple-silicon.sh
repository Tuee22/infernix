#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/common.sh
source "${SCRIPT_DIR}/common.sh"

SCRIPT_LABEL="./bootstrap/apple-silicon.sh"
APPLE_GHC_VERSION="9.14.1"
APPLE_CABAL_VERSION="3.16.1.0"
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
  ${SCRIPT_LABEL} status
  ${SCRIPT_LABEL} test
  ${SCRIPT_LABEL} down
  ${SCRIPT_LABEL} purge

Commands:
  help    Show this help text.
  doctor  Ensure Homebrew, ghcup, GHC ${APPLE_GHC_VERSION}, Cabal ${APPLE_CABAL_VERSION}, and `protoc`.
  build   Ensure prerequisites, build both binaries, and stage the Apple substrate file.
  up      Ensure prerequisites, build, stage the substrate file, and run \`cluster up\`.
  status  Show \`cluster status\`.
  test    Run \`./.build/infernix test all\`.
  down    Run \`cluster down\` while preserving durable repo-local state under ./.data/.
  purge   Destructive cleanup: tear down the cluster and remove ./.build/ and ./.data/.

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
  ${SCRIPT_LABEL} status
  ${SCRIPT_LABEL} test
  ${SCRIPT_LABEL} down
  ${SCRIPT_LABEL} purge

Direct reference commands:
  cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes
  ./.build/infernix internal materialize-substrate apple-silicon
  ./.build/infernix cluster up
  ./.build/infernix cluster status
  docker compose build playwright
  ./.build/infernix test all
  ./.build/infernix cluster down

Teardown and cleanup:
  ${SCRIPT_LABEL} down
  ${SCRIPT_LABEL} purge
EOF
}

ensure_homebrew() {
  local brew_bin
  if bootstrap::have brew; then
    brew_bin="$(command -v brew)"
  elif [[ -x /opt/homebrew/bin/brew ]]; then
    brew_bin="/opt/homebrew/bin/brew"
  else
    bootstrap::info "Installing Homebrew into the supported /opt/homebrew prefix."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
      brew_bin="/opt/homebrew/bin/brew"
    else
      bootstrap::pending "Homebrew installation is still pending. Finish any macOS or Command Line Tools prompts, then rerun ${SCRIPT_LABEL}."
    fi
  fi
  # shellcheck disable=SC2046
  eval "$("${brew_bin}" shellenv)"
}

ensure_brew_formula() {
  local formula="$1"
  if brew list --formula "${formula}" >/dev/null 2>&1; then
    return 0
  fi
  bootstrap::run brew install "${formula}"
}

ensure_ghcup_toolchain() {
  ensure_brew_formula ghcup
  bootstrap::prepend_path "${HOME}/.ghcup/bin"
  bootstrap::prepend_path "${HOME}/.cabal/bin"

  if [[ ! -x "${HOME}/.ghcup/bin/ghc-${APPLE_GHC_VERSION}" ]]; then
    bootstrap::run ghcup install ghc "${APPLE_GHC_VERSION}"
  fi
  bootstrap::run ghcup set ghc "${APPLE_GHC_VERSION}"

  if [[ ! -x "${HOME}/.ghcup/bin/cabal-${APPLE_CABAL_VERSION}" ]]; then
    bootstrap::run ghcup install cabal "${APPLE_CABAL_VERSION}"
  fi
  bootstrap::run ghcup set cabal "${APPLE_CABAL_VERSION}"

  APPLE_GHC_BIN="$(bootstrap::require_command_version ghc "${HOME}/.ghcup/bin/ghc" "${APPLE_GHC_VERSION}" --numeric-version)"
  APPLE_CABAL_BIN="$(bootstrap::require_command_version cabal "${HOME}/.ghcup/bin/cabal" "${APPLE_CABAL_VERSION}" --numeric-version)"
}

ensure_protobuf_compiler() {
  local protobuf_prefix
  ensure_brew_formula protobuf
  protobuf_prefix="$(brew --prefix protobuf)"
  APPLE_PROTOC_BIN="$(bootstrap::require_command protoc "${protobuf_prefix}/bin/protoc" "Protocol Buffers compiler" --version)"
}

ensure_build_prerequisites() {
  bootstrap::require_macos
  ensure_homebrew
  ensure_ghcup_toolchain
  ensure_protobuf_compiler
}

build_launcher() {
  ensure_build_prerequisites
  bootstrap::run "${APPLE_CABAL_BIN}" install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes
  bootstrap::run ./.build/infernix internal materialize-substrate apple-silicon
}

ensure_launcher_ready() {
  [[ -x ./.build/infernix ]] || build_launcher
  bootstrap::run ./.build/infernix internal materialize-substrate apple-silicon
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
  bootstrap::run ./.build/infernix cluster up
}

command_status() {
  ensure_launcher_ready
  bootstrap::run ./.build/infernix cluster status
}

command_test() {
  build_launcher
  bootstrap::run docker compose build playwright
  bootstrap::run ./.build/infernix test all
}

command_down() {
  ensure_launcher_ready
  bootstrap::run ./.build/infernix cluster down
}

command_purge() {
  bootstrap::confirm_destructive "Purge Apple build output and durable repo-local state?"
  if [[ -x ./.build/infernix ]]; then
    ./.build/infernix cluster down || true
  fi
  bootstrap::run rm -rf ./.build ./.data
  bootstrap::info "Removed ./.build and ./.data."
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
    *) bootstrap::die "Unsupported Apple Silicon command: ${command}" ;;
  esac
  show_postamble
}

main "$@"
