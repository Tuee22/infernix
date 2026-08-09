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
APPLE_COLIMA_BIN="${APPLE_HOMEBREW_BIN}/colima"
APPLE_GHCUP_BIN="${APPLE_HOMEBREW_BIN}/ghcup"
APPLE_JQ_BIN="${APPLE_HOMEBREW_BIN}/jq"
APPLE_SYSCTL_BIN=/usr/sbin/sysctl
APPLE_GHC_BIN=""
APPLE_CABAL_BIN=""
APPLE_STAGE0_MINIMUM_EFFECTIVE_MIB=12288
APPLE_STAGE0_MAXIMUM_SHELL_INTEGER=9223372036854775807

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
  doctor      Ensure Homebrew, ghcup, GHC ${APPLE_GHC_VERSION}, and Cabal ${APPLE_CABAL_VERSION};
              also reports whether Poetry has been bootstrapped yet.
  build       Ensure prerequisites and build the host binary under ./.build/.
  up          Ensure prerequisites, build the host binary, reconcile \`./infernix.dhall\` /
              \`./infernix-host.dhall\` via \`infernix init --if-missing\`, and run \`cluster up\`.
  run-daemon  Run the on-host \`infernix service\` engine daemon in the foreground; required for
              inference on Apple Silicon after \`up\` and not spawned by \`up\` itself.
  status      Show \`cluster status\`.
  test        Build the launcher, reconcile missing Apple operator/host config while preserving an
              existing config, reconcile the Apple test config, then run \`./.build/infernix test all\`
              without operator \`cluster up\`; a clean workspace needs no separate config step.
  down        Run \`cluster down\` while preserving durable repo-local state under ./.data/.
  purge       Compatibility alias for \`down\`; preserves build output, data, images, and prerequisites.

This script is safe to re-run. It prefers the supported Apple Silicon path:
Homebrew + ghcup + direct host-native \`./.build/infernix\`. Haskell protobuf
bindings are checked in and verified without a build-time compiler on Darwin.
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

Operator/demo reference commands (use this script's \`build\` command for every governed Cabal rebuild):
  ${SCRIPT_LABEL} build
  ./.build/infernix init
  ./.build/infernix cluster up
  ./.build/infernix service
  ./.build/infernix cluster status
  ./.build/infernix cluster down

Harness validation (requires no live OperatorOwned cluster; it owns its cluster lifecycle):
  ./.build/infernix init --runtime-mode apple-silicon --demo-ui true --if-missing
  ./.build/infernix test init --runtime-mode apple-silicon --demo-ui true
  ./.build/infernix test all
This sequence works from a clean workspace, preserves an existing operator config, and does not run
operator \`cluster up\`.

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
  ensure_brew_formula jq
  ensure_skopeo
  check_poetry
}

# The hermetic PATH=/usr/bin:/bin set at the top of this script keeps the
# bootstrap itself from depending on the operator's inherited PATH. The direct
# Cabal build still needs a process PATH for the ghcup toolchain, so provide a
# deterministic launcher-local path rather than appending the inherited environment.
apple_launcher_path() {
  printf '%s\n' "$(bootstrap::effective_home)/.ghcup/bin:${APPLE_HOMEBREW_BIN}:/usr/bin:/bin"
}

# Bash arithmetic is signed and silently wraps an out-of-range decimal. Check
# the canonical unsigned decimal text before allowing it into an arithmetic
# expansion so malformed host observations fail closed instead of inflating the
# effective-memory result.
stage0_decimal_fits_shell_integer() {
  local decimal_value="$1"
  local maximum_value="${APPLE_STAGE0_MAXIMUM_SHELL_INTEGER}"

  [[ "${decimal_value}" == "0" || "${decimal_value}" =~ ^[1-9][0-9]*$ ]] || return 1
  ((${#decimal_value} < ${#maximum_value})) && return 0
  ((${#decimal_value} > ${#maximum_value})) && return 1
  [[ "${decimal_value}" < "${maximum_value}" || "${decimal_value}" == "${maximum_value}" ]]
}

run_launcher() {
  bootstrap::run "${BOOTSTRAP_ENV}" "PATH=$(apple_launcher_path)" ./.build/infernix "$@"
}

# A clean clone has no binary with which to run the canonical typed host-memory
# observation. This deliberately narrow seed preflight does not mint a second
# plan: it only proves that the fixed 6144 MiB seed envelope remains within the
# doctrine's 50% toolchain share. This fixed admitted seed applies to every
# stage-0/rebuild handoff. Commands that subsequently run `infernix init`
# supersede the committed project settings with the canonical live observation;
# the standalone `build` command intentionally performs only the seed-bound
# build and does not claim that initialization occurred.
require_stage0_build_memory() {
  local physical_bytes
  local physical_mib
  local colima_profiles
  local pledged_bytes
  local pledged_mib
  local effective_mib

  [[ -x "${APPLE_SYSCTL_BIN}" ]] || bootstrap::die "Stage-0 build-memory observation requires ${APPLE_SYSCTL_BIN}."
  [[ -x "${APPLE_COLIMA_BIN}" ]] || bootstrap::die "Stage-0 build-memory observation requires ${APPLE_COLIMA_BIN}; an unavailable Colima observation is not evidence of a zero pledge."
  [[ -x "${APPLE_JQ_BIN}" ]] || bootstrap::die "Stage-0 build-memory observation requires ${APPLE_JQ_BIN}."

  physical_bytes="$(${APPLE_SYSCTL_BIN} -n hw.memsize)"
  [[ "${physical_bytes}" =~ ^[1-9][0-9]*$ ]] || bootstrap::die "Stage-0 build-memory observation could not parse a positive hw.memsize byte count."
  stage0_decimal_fits_shell_integer "${physical_bytes}" || bootstrap::die "Stage-0 build-memory observation produced a hw.memsize value outside the supported shell-integer range."
  physical_mib=$((physical_bytes / 1048576))
  ((physical_mib > 0)) || bootstrap::die "Stage-0 build-memory observation rounded physical memory to zero MiB."

  colima_profiles="$("${BOOTSTRAP_ENV}" "PATH=$(apple_launcher_path)" "${APPLE_COLIMA_BIN}" list --json)" || bootstrap::die "Stage-0 build-memory observation could not run '${APPLE_COLIMA_BIN} list --json' with its fixed Homebrew tool path."
  pledged_bytes="$(
    printf '%s\n' "${colima_profiles}" |
      "${APPLE_JQ_BIN}" -s -e -r '
        if length == 0 then
          error("no Colima profiles were reported")
        else
          map(
            if ((.name | type) == "string" and (.name | gsub("[[:space:]]"; "") | length) > 0)
               and ((.status | type) == "string" and (.status | gsub("[[:space:]]"; "") | length) > 0)
               and ((.memory | type) == "number" and .memory >= 0 and (.memory | floor) == .memory)
            then .
            else error("malformed Colima profile")
            end
          )
          | map(select(.status != "Stopped") | .memory)
          | (add // 0)
        end
      '
  )" || bootstrap::die "Stage-0 build-memory observation could not parse the Colima profile inventory."
  [[ "${pledged_bytes}" =~ ^[0-9]+$ ]] || bootstrap::die "Stage-0 build-memory observation produced an invalid Colima pledge."
  stage0_decimal_fits_shell_integer "${pledged_bytes}" || bootstrap::die "Stage-0 build-memory observation produced a Colima pledge outside the supported shell-integer range."
  pledged_mib=$((pledged_bytes / 1048576))
  if ((pledged_bytes % 1048576 != 0)); then
    pledged_mib=$((pledged_mib + 1))
  fi
  ((pledged_mib < physical_mib)) || bootstrap::die "Stage-0 build-memory observation found an active Colima pledge that leaves no host memory."
  effective_mib=$((physical_mib - pledged_mib))
  ((effective_mib >= APPLE_STAGE0_MINIMUM_EFFECTIVE_MIB)) ||
    bootstrap::die "Stage-0 build requires at least ${APPLE_STAGE0_MINIMUM_EFFECTIVE_MIB} MiB effective memory so its 6144 MiB envelope stays within the 50% toolchain share; observed ${effective_mib} MiB after the active Colima pledge."
  bootstrap::info "Stage-0 build-memory preflight: ${physical_mib} MiB physical - ${pledged_mib} MiB active Colima pledge = ${effective_mib} MiB effective; using 1 compiler x 4096 MiB plus 2 control claims x 1024 MiB (6144 MiB total)."
}

build_launcher() {
  local home_dir
  ensure_build_prerequisites
  require_stage0_build_memory
  home_dir="$(bootstrap::effective_home)"
  bootstrap::run \
    "${BOOTSTRAP_ENV}" \
    "HOME=${home_dir}" \
    "PATH=$(apple_launcher_path)" \
    "GHCRTS=-M1024M" \
    "${APPLE_CABAL_BIN}" \
    +RTS -M1024M -RTS \
    install \
    --installdir=./.build \
    --install-method=copy \
    --overwrite-policy=always \
    all:exes \
    --jobs=1 \
    '--ghc-options=+RTS -M4096M -xr12288M -RTS'
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
  run_launcher init --runtime-mode apple-silicon --demo-ui true --if-missing
  run_launcher test init --runtime-mode apple-silicon --demo-ui true
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
