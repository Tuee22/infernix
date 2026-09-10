ARG GO_IMAGE=golang:1.24
ARG BASE_IMAGE=ubuntu:24.04
FROM ${GO_IMAGE} AS nvkind-builder

ARG NVKIND_GO_INSTALL_TARGET=github.com/NVIDIA/nvkind/cmd/nvkind@8bce71ec58cf12b4003758eb4e49adac53cc40f2

RUN GOBIN=/go/bin go install ${NVKIND_GO_INSTALL_TARGET}

FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG RUNTIME_MODE=linux-cpu
ARG DEMO_UI=true
ARG GHC_VERSION=9.12.4
ARG CABAL_VERSION=3.16.1.0
ARG KIND_VERSION=v0.29.0
ARG KUBECTL_VERSION=v1.34.0
ARG HELM_VERSION=v3.18.6
ARG PROTOC_VERSION=34.1
ARG PROTOC_LINUX_AMD64_SHA256=af27ea66cd26938fe48587804ca7d4817457a08350021a1c6e23a27ccc8c6904
ARG PROTOC_LINUX_ARM64_SHA256=31c5e9e3c7bf013cf41fb97765ee255c140024a6b175b6cc9b64beddd7c23ba7
# Phase 8 follow-on (2026-07-04): default to the canonical Ubuntu archive.
# The mirrors.edge.kernel.org mirror served an inconsistent index (libssl-dev
# 3.0.13-0ubuntu3.9 vs libssl3t64 3.0.13-0ubuntu3.11), breaking the apt solve on
# the linux-cpu ubuntu:24.04 base. archive.ubuntu.com is index-consistent.
ARG UBUNTU_APT_MIRROR=http://archive.ubuntu.com/ubuntu/
ARG TARGETARCH

# Phase 1 Sprint 1.11 — the build-root env override was removed. The Haskell binary
# discovers its build root through 'discoverPaths' (cwd-walk + optional
# host-manifest lookup) instead of consuming a process-inherited env
# var. The supported in-image build root is the convention default
# @/workspace/.build@.
ENV DEBIAN_FRONTEND=noninteractive \
    BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
    BOOTSTRAP_HASKELL_INSTALL_NO_STACK=1 \
    BOOTSTRAP_HASKELL_GHC_VERSION=${GHC_VERSION} \
    BOOTSTRAP_HASKELL_CABAL_VERSION=${CABAL_VERSION} \
    POETRY_VIRTUALENVS_IN_PROJECT=true \
    POETRY_HOME=/opt/poetry \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    GHC_VERSION=${GHC_VERSION} \
    CABAL_VERSION=${CABAL_VERSION} \
    PATH=/opt/poetry/bin:/root/.local/bin:/root/.ghcup/bin:/root/.cabal/bin:${PATH}

RUN sed -i \
      -e "s#http://archive.ubuntu.com/ubuntu/#${UBUNTU_APT_MIRROR}#g" \
      -e "s#http://security.ubuntu.com/ubuntu/#${UBUNTU_APT_MIRROR}#g" \
      /etc/apt/sources.list.d/ubuntu.sources \
    && printf 'Acquire::ForceIPv4 "true";\nAcquire::Retries "5";\n' >/etc/apt/apt.conf.d/99infernix-network

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        docker-buildx \
        docker.io \
        docker-compose-v2 \
        git \
        gnupg \
        libatomic1 \
        libffi-dev \
        libgmp-dev \
        libncurses-dev \
        libssl-dev \
        libtinfo-dev \
        pkg-config \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        skopeo \
        tini \
        xz-utils \
        zlib1g-dev \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && ln -sf /usr/bin/python3 /usr/local/bin/python \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv --copies ${POETRY_HOME} \
    && cp -aL /usr/lib/python3.12/. ${POETRY_HOME}/lib/python3.12/ \
    && ${POETRY_HOME}/bin/python -m pip install --upgrade pip \
    && ${POETRY_HOME}/bin/pip install poetry \
    && ln -sfn ${POETRY_HOME}/bin/poetry /usr/local/bin/poetry \
    && poetry config keyring.enabled false

# Phase 1 Sprint 1.24 (2026-08-09): Haskell protobuf bindings are checked in,
# and ordinary builds never run a generator. The Linux image build retains one
# explicit drift-proof lane: fetch the pinned upstream compiler for the native
# image architecture, build the pinned Haskell plugin below, regenerate into a
# temporary tree, and compare every output byte after the full source copy.
RUN set -eu; \
    protoc_tmp="$(mktemp -d)"; \
    protoc_arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${protoc_arch}" in \
      amd64) protoc_asset_arch="x86_64"; protoc_sha256="${PROTOC_LINUX_AMD64_SHA256}" ;; \
      arm64) protoc_asset_arch="aarch_64"; protoc_sha256="${PROTOC_LINUX_ARM64_SHA256}" ;; \
      *) echo "unsupported protobuf generator architecture: ${protoc_arch}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o "${protoc_tmp}/protoc.zip" \
      "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-${protoc_asset_arch}.zip"; \
    python3 -c 'import hashlib, pathlib, sys; expected, archive = sys.argv[1:]; actual = hashlib.sha256(pathlib.Path(archive).read_bytes()).hexdigest(); raise SystemExit(0 if actual == expected else f"protoc archive SHA-256 mismatch: expected {expected}, got {actual}")' \
      "${protoc_sha256}" "${protoc_tmp}/protoc.zip"; \
    python3 -m zipfile -e "${protoc_tmp}/protoc.zip" "${protoc_tmp}/unpacked"; \
    mkdir -p /opt/infernix/proto-tools; \
    install "${protoc_tmp}/unpacked/bin/protoc" /opt/infernix/proto-tools/protoc; \
    test "$(/opt/infernix/proto-tools/protoc --version)" = "libprotoc ${PROTOC_VERSION}"; \
    rm -rf "${protoc_tmp}"

# Configure the authenticated upstream repository before GHCup's initial index
# update, so the clean image uses the same HTTPS origin as later Cabal work.
RUN mkdir -p /root/.cabal \
    && printf '%s\n' \
      'repository hackage.haskell.org' \
      '  url: https://hackage.haskell.org/' \
      '  secure: True' > /root/.cabal/config

RUN curl https://get-ghcup.haskell.org -sSf | sh \
    && ghcup install ghc ${GHC_VERSION} \
    && ghcup set ghc ${GHC_VERSION} \
    && ghcup set cabal ${CABAL_VERSION} \
    && mkdir -p /opt/ghc \
    && ln -sfn /root/.ghcup/ghc/${GHC_VERSION} /opt/ghc/${GHC_VERSION}

RUN set -eu; \
    tool_arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${tool_arch}" in \
      amd64|arm64) ;; \
      *) echo "unsupported linux substrate tool architecture: ${tool_arch}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${tool_arch}"; \
    chmod +x /usr/local/bin/kind; \
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${tool_arch}/kubectl"; \
    chmod +x /usr/local/bin/kubectl; \
    curl -fsSL -o /tmp/helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-${tool_arch}.tar.gz"; \
    tar -C /tmp -xzf /tmp/helm.tar.gz; \
    install "/tmp/linux-${tool_arch}/helm" /usr/local/bin/helm; \
    rm -rf /tmp/helm.tar.gz "/tmp/linux-${tool_arch}"

COPY --from=nvkind-builder /go/bin/nvkind /usr/local/bin/nvkind

# Phase 3 Sprint 3.11 (2026-05-29): the bitnami minio sub-chart is
# retired in favor of the hand-authored MinIO StatefulSet under
# `chart/templates/minio/`, so this pre-fetch stops pulling
# `minio-17.0.21.tgz` from charts.bitnami.com. The supported MinIO
# image inventory uses upstream multi-arch `minio/minio` + `minio/mc`
# + `busybox` (see chart/values.yaml.infernixMinio).
RUN set -eu; \
    mkdir -p /opt/infernix/chart/charts; \
    helm pull pg-operator --repo https://percona.github.io/percona-helm-charts --version 2.9.0 --destination /opt/infernix/chart/charts; \
    helm pull pg-db --repo https://percona.github.io/percona-helm-charts --version 2.9.0 --destination /opt/infernix/chart/charts; \
    helm pull pulsar --repo https://pulsar.apache.org/charts --version 4.5.0 --destination /opt/infernix/chart/charts; \
    helm pull oci://docker.io/envoyproxy/gateway-helm --version v1.7.2 --destination /opt/infernix/chart/charts

WORKDIR /workspace

COPY cabal.project infernix.cabal LICENSE README.md /workspace/
COPY proto /workspace/proto
COPY web/package.json /workspace/web/package.json
COPY web/scripts /workspace/web/scripts
COPY python/pyproject.toml /workspace/python/pyproject.toml

# Clean-image seed envelope: each Cabal invocation is one 4096 MiB compiler
# plus the live driver and one worker auxiliary at 1024 MiB each (6144 MiB
# total). Driver and compiler caps are carried on each invocation; the compiler
# heap/address flags and final jobs value override project/config files at the
# child boundary.
#
# The two steps that build third-party packages deliberately do NOT export
# GHCRTS. A `build-type: Custom` dependency compiles its own `Setup` program,
# cabal links that program without `-rtsopts`, and an un-`rtsopts` binary does
# not honour an inherited GHCRTS — it refuses to start
# ("Most RTS options are disabled"). Measured: `entropy-0.4.1.11`, required by
# `wai-websockets`, failed its configure step for exactly this reason. Dropping
# the export here gives up no bound that ever applied, because the cap was fatal
# rather than effective on those helpers; the driver cap (`cabal +RTS -M1024M`)
# and the compiler cap (`--ghc-options=+RTS -M4096M -xr12288M`) are both still
# passed on the command line, where they bind. This is why the plugin below is
# linked `-rtsopts=ignore -with-rtsopts=-M1024M`: that is the one binary this
# image later runs *with* GHCRTS set, so it must be built to admit it.
RUN mkdir -p /workspace/.build /workspace/tools/generated_proto \
    && cabal +RTS -M1024M -RTS update --verbose=2 \
    && cabal +RTS -M1024M -RTS \
         build all --only-dependencies \
         --jobs=1 \
         '--ghc-options=+RTS -M4096M -xr12288M -RTS' \
    && cabal +RTS -M1024M -RTS \
         install proto-lens-protoc-0.9.0.1 \
         --installdir=/opt/infernix/proto-tools \
         --install-method=copy \
         --overwrite-policy=always \
         --jobs=1 \
         '--ghc-options=+RTS -M4096M -xr12288M -RTS -rtsopts=ignore -with-rtsopts=-M1024M' \
    && test -x /opt/infernix/proto-tools/proto-lens-protoc \
    && npm --prefix web install --no-audit --no-fund \
    && python3 -m venv --copies /workspace/python/.venv \
    && cp -aL /usr/lib/python3.12/. /workspace/python/.venv/lib/python3.12/ \
    && poetry install --directory python --no-root

COPY . /workspace

RUN set -eu; \
    generated_root="$(mktemp -d)"; \
    GHCRTS=-M1024M /opt/infernix/proto-tools/protoc \
      --plugin=protoc-gen-haskell=/opt/infernix/proto-tools/proto-lens-protoc \
      --haskell_out="${generated_root}" \
      --proto_path=/workspace/proto \
      /workspace/proto/infernix/manifest/runtime_manifest.proto \
      /workspace/proto/infernix/runtime/inference.proto; \
    actual_generated="$(cd "${generated_root}" && find . ! -type d -print | LC_ALL=C sort)"; \
    expected_generated="$(printf '%s\n' \
      './Proto/Infernix/Manifest/RuntimeManifest.hs' \
      './Proto/Infernix/Manifest/RuntimeManifest_Fields.hs' \
      './Proto/Infernix/Runtime/Inference.hs' \
      './Proto/Infernix/Runtime/Inference_Fields.hs')"; \
    if [ "${actual_generated}" != "${expected_generated}" ]; then \
      printf '%s\n%s\n%s\n' \
        'generated Haskell protobuf inventory drift' \
        "expected:${expected_generated}" \
        "actual:${actual_generated}" >&2; \
      exit 1; \
    fi; \
    for generated_file in \
      Proto/Infernix/Manifest/RuntimeManifest.hs \
      Proto/Infernix/Manifest/RuntimeManifest_Fields.hs \
      Proto/Infernix/Runtime/Inference.hs \
      Proto/Infernix/Runtime/Inference_Fields.hs; do \
      if [ -L "${generated_root}/${generated_file}" ] || [ ! -f "${generated_root}/${generated_file}" ]; then \
        echo "generated Haskell protobuf output is not a regular non-symlink file: ${generated_file}" >&2; \
        exit 1; \
      fi; \
      if ! cmp -s "${generated_root}/${generated_file}" "/workspace/src/${generated_file}"; then \
        echo "generated Haskell protobuf byte drift: src/${generated_file}" >&2; \
        exit 1; \
      fi; \
    done; \
    rm -rf "${generated_root}"

RUN set -eu; \
    native_tmp="$(mktemp -d)"; \
    native_arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${native_arch}" in \
      amd64) native_asset_arch="x64"; temurin_arch="x64" ;; \
      arm64) native_asset_arch="arm64"; temurin_arch="aarch64" ;; \
      *) echo "unsupported native payload architecture: ${native_arch}" >&2; exit 1 ;; \
    esac; \
    mkdir -p \
      /opt/infernix/native-payloads/llama.cpp \
      /opt/infernix/native-payloads/whisper.cpp \
      /opt/infernix/native-payloads/basic-pitch \
      /opt/infernix/audiveris-jre; \
    curl -fsSL --retry 3 --retry-max-time 120 -o "${native_tmp}/llama.tar.gz" \
      "https://github.com/ggml-org/llama.cpp/releases/download/b9704/llama-b9704-bin-ubuntu-${native_asset_arch}.tar.gz"; \
    tar -xzf "${native_tmp}/llama.tar.gz" -C /opt/infernix/native-payloads/llama.cpp; \
    curl -fsSL --retry 3 --retry-max-time 120 -o "${native_tmp}/whisper.tar.gz" \
      "https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.0/whisper-bin-ubuntu-${native_asset_arch}.tar.gz"; \
    tar -xzf "${native_tmp}/whisper.tar.gz" -C /opt/infernix/native-payloads/whisper.cpp; \
    curl -fsSL --retry 3 --retry-max-time 120 -o /opt/infernix/native-payloads/basic-pitch/nmp.onnx \
      https://raw.githubusercontent.com/spotify/basic-pitch/main/basic_pitch/saved_models/icassp_2022/nmp.onnx; \
    curl -fsSL --retry 3 --retry-max-time 120 -o "${native_tmp}/audiveris.deb" \
      https://github.com/Audiveris/audiveris/releases/download/5.10.2/Audiveris-5.10.2-ubuntu24.04-x86_64.deb; \
    curl -fsSL --retry 3 --retry-max-time 120 -o "${native_tmp}/temurin-jre.tar.gz" \
      "https://api.adoptium.net/v3/binary/latest/25/ga/linux/${temurin_arch}/jre/hotspot/normal/eclipse"; \
    tar -xzf "${native_tmp}/temurin-jre.tar.gz" -C /opt/infernix/audiveris-jre --strip-components=1; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      libasound2t64 \
      libgomp1 \
      libx11-6 \
      libxext6 \
      libxi6 \
      libxrender1 \
      libxtst6; \
    dpkg-deb -x "${native_tmp}/audiveris.deb" /; \
    rm -rf /opt/audiveris/lib/runtime; \
    mkdir -p /opt/infernix/audiveris-javacpp-cache; \
    /opt/infernix/audiveris-jre/bin/java \
      -Dorg.bytedeco.javacpp.cachedir=/opt/infernix/audiveris-javacpp-cache \
      -Dorg.bytedeco.javacpp.canCreateSymbolicLink=false \
      -cp '/opt/audiveris/lib/app/*' Audiveris -version; \
    python3 -m venv --copies /opt/infernix/native-python; \
    /opt/infernix/native-python/bin/python -m pip install --upgrade pip; \
    /opt/infernix/native-python/bin/pip install --no-cache-dir -r /workspace/python/native-runners/requirements-linux.txt; \
    /opt/infernix/native-python/bin/pip uninstall -y hf_xet || true; \
    rm -rf "${native_tmp}" /var/lib/apt/lists/*

RUN mkdir -p /workspace/.build /opt/infernix /opt/infernix/dhall \
    && rm -rf /workspace/chart/charts \
    && ln -s /opt/infernix/chart/charts /workspace/chart/charts \
    && cd /workspace \
    && find . \
         \( -name .build -o -name .data -o -name .git -o -name .hpc -o -name .mypy_cache -o -name .parcel-cache -o -name .ruff_cache -o -name .spago -o -name .stack-work -o -name .venv -o -name __pycache__ -o -name dist-newstyle -o -name node_modules -o -path './chart/charts' -o -path './tools/generated_proto' -o -path './web/dist' -o -path './web/output' \) -prune \
         -o -type f \
         ! -name '*.aux' \
         ! -name '*.dyn_hi' \
         ! -name '*.dyn_o' \
         ! -name '*.eventlog' \
         ! -name '*.hi' \
         ! -name '*.hp' \
         ! -name '*.log' \
         ! -name '*.o' \
         ! -name '*.prof' \
         ! -name '*.tix' \
         ! -name '.DS_Store' \
         ! -name '.gitignore' \
         ! -name 'Chart.lock' \
         ! -name 'poetry.lock' \
         ! -name 'spago.lock' \
         -print \
       | sed 's#^\\./##' | LC_ALL=C sort > /opt/infernix/source-snapshot-files.txt

# Wave I: huggingface_hub installs `hf_xet`, whose Xet large-file transport
# routes weight downloads through HF's `xet-read-token` API, which the Hub
# rate-limits aggressively per source IP (HTTP 429) under a busy cohort run —
# while the regular `resolve` -> CDN HTTP path is not throttled. The coordinator's
# lazy model bootstrap (`adapters/model_bootstrap.py` `snapshot_download`) runs in
# this base venv, so removing `hf_xet` forces the un-throttled HTTP fallback. This
# is a dependency-level removal, not an env var, per the configuration doctrine.
# The two retained Cabal steps repeat the same closed 6144 MiB seed envelope;
# they are sequential and carry their driver/compiler caps on the invocation.
RUN mkdir -p /workspace/tools/generated_proto \
    && poetry install --directory python \
    && cp -aL /usr/lib/python3.12/. /workspace/python/.venv/lib/python3.12/ \
    && poetry --directory python run pip uninstall -y hf_xet \
    && poetry --directory python run python -m grpc_tools.protoc \
         -I /workspace/proto \
         --python_out /workspace/tools/generated_proto \
         /workspace/proto/infernix/manifest/runtime_manifest.proto \
         /workspace/proto/infernix/runtime/inference.proto \
    && cabal +RTS -M1024M -RTS \
         build all \
         --jobs=1 \
         '--ghc-options=+RTS -M4096M -xr12288M -RTS' \
    && cabal +RTS -M1024M -RTS \
         install \
         --installdir=/workspace/.build \
         --install-method=copy \
         --overwrite-policy=always \
         all:exes \
         --jobs=1 \
         '--ghc-options=+RTS -M4096M -xr12288M -RTS' \
    && install /workspace/.build/infernix /usr/local/bin/infernix \
    && /usr/local/bin/infernix internal linux-host-seed > /opt/infernix/dhall/ImageHostSeed.dhall \
    && cp /opt/infernix/dhall/ImageHostSeed.dhall /opt/infernix/dhall/InfernixHost.dhall \
    && /usr/local/bin/infernix internal image-build-identity > /opt/infernix/build-identity.json

# Phase 3 Sprint 3.10 — install Playwright's system dependencies before native
# artifact observation. The installer legitimately regenerates
# /etc/ld.so.cache; materializing afterward ensures cache-backed loader edges
# bind the final immutable image bytes rather than an intermediate layer.
RUN apt-get update \
    && npm --prefix web exec -- playwright install --with-deps chromium firefox webkit \
    && rm -rf /var/lib/apt/lists/*

# Keep artifact materialization in its own final filesystem-mutating layer: its
# fail-closed loader and provenance checks are intentionally stricter than
# compilation, and a failed observation must be diagnosable and retryable
# without rebuilding the binary.
# Only upstream download archives persist across failed materialization attempts.
# Environments and native artifact roots are rebuilt and verified in the image.
RUN --mount=type=cache,id=infernix-poetry-artifacts-${TARGETARCH},target=/root/.cache/pypoetry/artifacts,sharing=locked \
    infernix internal materialize-substrate ${RUNTIME_MODE} --demo-ui ${DEMO_UI} --empty-models \
    && infernix test init --runtime-mode ${RUNTIME_MODE} --demo-ui ${DEMO_UI} \
    && npm --prefix web run build \
    && poetry --directory python run check-code \
    && infernix internal materialize-linux-native-engines

# Phase 4 Sprint 4.17 — this is the slim control-plane / coordinator image: it
# carries the `infernix` binaries, the framework-free shared `python/` project
# (so the coordinator's `check-code` and adapter dispatch resolve), and the
# cluster toolbelt. The `linux-cpu` image additionally bakes the small CPU
# framework groups needed by its in-cluster engine pods. CUDA framework venvs
# still live only in per-engine images built from `docker/engine.Dockerfile`
# (CUDA-runtime base + this image's binary/python + one engine's `--with cuda`
# venv), so the GPU lane avoids the retired ~121 GB monolith.

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["infernix", "--help"]
