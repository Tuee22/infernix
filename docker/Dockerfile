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
ARG UBUNTU_APT_MIRROR=http://mirrors.edge.kernel.org/ubuntu/
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
        protobuf-compiler \
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

RUN python3 -m venv ${POETRY_HOME} \
    && ${POETRY_HOME}/bin/python -m pip install --upgrade pip \
    && ${POETRY_HOME}/bin/pip install poetry \
    && ln -sfn ${POETRY_HOME}/bin/poetry /usr/local/bin/poetry \
    && poetry config keyring.enabled false

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
    helm pull harbor --repo https://helm.goharbor.io --version 1.18.3 --destination /opt/infernix/chart/charts; \
    helm pull pg-operator --repo https://percona.github.io/percona-helm-charts --version 2.9.0 --destination /opt/infernix/chart/charts; \
    helm pull pg-db --repo https://percona.github.io/percona-helm-charts --version 2.9.0 --destination /opt/infernix/chart/charts; \
    helm pull pulsar --repo https://pulsar.apache.org/charts --version 4.5.0 --destination /opt/infernix/chart/charts; \
    helm pull oci://docker.io/envoyproxy/gateway-helm --version v1.7.2 --destination /opt/infernix/chart/charts

WORKDIR /workspace

COPY cabal.project infernix.cabal LICENSE README.md Setup.hs /workspace/
COPY proto /workspace/proto
COPY web/package.json /workspace/web/package.json
COPY web/scripts /workspace/web/scripts
COPY python/pyproject.toml /workspace/python/pyproject.toml

RUN mkdir -p /workspace/.build /workspace/tools/generated_proto \
    && cabal update \
    && cabal build all --only-dependencies \
    && npm --prefix web install --no-audit --no-fund \
    && poetry install --directory python --no-root

COPY . /workspace

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
    curl -fsSL -o "${native_tmp}/llama.tar.gz" \
      "https://github.com/ggml-org/llama.cpp/releases/download/b9704/llama-b9704-bin-ubuntu-${native_asset_arch}.tar.gz"; \
    tar -xzf "${native_tmp}/llama.tar.gz" -C /opt/infernix/native-payloads/llama.cpp; \
    curl -fsSL -o "${native_tmp}/whisper.tar.gz" \
      "https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.0/whisper-bin-ubuntu-${native_asset_arch}.tar.gz"; \
    tar -xzf "${native_tmp}/whisper.tar.gz" -C /opt/infernix/native-payloads/whisper.cpp; \
    curl -fsSL -o /opt/infernix/native-payloads/basic-pitch/nmp.onnx \
      https://raw.githubusercontent.com/spotify/basic-pitch/main/basic_pitch/saved_models/icassp_2022/nmp.onnx; \
    curl -fsSL -o "${native_tmp}/audiveris.deb" \
      https://github.com/Audiveris/audiveris/releases/download/5.10.2/Audiveris-5.10.2-ubuntu24.04-x86_64.deb; \
    curl -fsSL -o "${native_tmp}/temurin-jre.tar.gz" \
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
    python3 -m venv /opt/infernix/native-python; \
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

# Phase 1 Sprint 1.11 — bake the supported Linux outer-container host
# manifest into the image at the canonical mount path. The Haskell
# binary's `discoverPaths` reads this file via `tryLoadHostManifest`
# at startup so it can resolve `buildRoot = /workspace/.build/outer-container/build`
# (the supported outer-container path) instead of falling back to
# `/workspace/.build` (the host-native fallback default that
# mis-classifies the container as `HostNative`). Operators override
# per-host by editing this file before the binary needs it.
RUN printf '%s\n' \
    '{ hostExecutionContext = < AppleHostNative | LinuxOuterContainer >.LinuxOuterContainer' \
    ", hostArchitecture = \"${TARGETARCH:-$(dpkg --print-architecture)}\"" \
    ', toolPaths =' \
    '    { docker = "/usr/bin/docker"' \
    '    , kubectl = "/usr/local/bin/kubectl"' \
    '    , helm = "/usr/local/bin/helm"' \
    '    , kind = "/usr/local/bin/kind"' \
    '    , cabal = "/root/.ghcup/bin/cabal"' \
    '    , ghc = "/root/.ghcup/bin/ghc"' \
    '    , ghcup = ""' \
    '    , ormolu = "/workspace/.build/haskell-style-tools/bin/ormolu"' \
    '    , hlint = "/workspace/.build/haskell-style-tools/bin/hlint"' \
    '    , npm = "/usr/bin/npm"' \
    '    , node = "/usr/bin/node"' \
    '    , python3 = "/usr/bin/python3"' \
    '    , poetry = "/opt/poetry/bin/poetry"' \
    '    , protoc = "/usr/bin/protoc"' \
    '    , git = "/usr/bin/git"' \
    '    , tar = "/usr/bin/tar"' \
    '    , curl = "/usr/bin/curl"' \
    '    , aptGet = "/usr/bin/apt-get"' \
    '    , brew = ""' \
    '    , sudo = "/usr/bin/sudo"' \
    '    , systemctl = "/usr/bin/systemctl"' \
    '    , mkdir = "/usr/bin/mkdir"' \
    '    , chmod = "/usr/bin/chmod"' \
    '    , ln = "/usr/bin/ln"' \
    '    , install = "/usr/bin/install"' \
    '    , id = "/usr/bin/id"' \
    '    , getent = "/usr/bin/getent"' \
    '    , cut = "/usr/bin/cut"' \
    '    , dirname = "/usr/bin/dirname"' \
    '    , bash = "/usr/bin/bash"' \
    '    , crictl = "/usr/local/bin/crictl"' \
    '    , chown = "/usr/bin/chown"' \
    '    , nvidiaSmi = "/usr/bin/nvidia-smi"' \
    '    , nvkind = "/usr/local/bin/nvkind"' \
    '    , skopeo = "/usr/bin/skopeo"' \
    '    , hostname = "/usr/bin/hostname"' \
    '    }' \
    ', filesystem =' \
    '    { repoRoot = "/workspace"' \
    '    , buildRoot = "/workspace/.build/outer-container/build"' \
    '    , dataRoot = "/workspace/.data"' \
    '    , runtimeRoot = "/workspace/.data/runtime"' \
    '    , kubeconfigPath = "/workspace/.data/runtime/infernix.kubeconfig"' \
    '    , secretsRoot = "/workspace/.data/runtime/secrets"' \
    '    , homeDirectory = "/root"' \
    '    , kindRoot = "/workspace/.data/runtime/kind"' \
    '    }' \
    ', playwrightHost = "127.0.0.1"' \
    ', controlPlaneContext = "outer-container"' \
    '}' \
    > /opt/infernix/dhall/InfernixHost.dhall

# Wave I: huggingface_hub installs `hf_xet`, whose Xet large-file transport
# routes weight downloads through HF's `xet-read-token` API, which the Hub
# rate-limits aggressively per source IP (HTTP 429) under a busy cohort run —
# while the regular `resolve` -> CDN HTTP path is not throttled. The coordinator's
# lazy model bootstrap (`adapters/model_bootstrap.py` `snapshot_download`) runs in
# this base venv, so removing `hf_xet` forces the un-throttled HTTP fallback. This
# is a dependency-level removal, not an env var, per the configuration doctrine.
RUN mkdir -p /workspace/tools/generated_proto \
    && poetry install --directory python \
    && poetry --directory python run pip uninstall -y hf_xet \
    && poetry --directory python run python -m grpc_tools.protoc \
         -I /workspace/proto \
         --python_out /workspace/tools/generated_proto \
         /workspace/proto/infernix/manifest/runtime_manifest.proto \
         /workspace/proto/infernix/runtime/inference.proto \
    && cabal build all \
    && cabal install \
         --installdir=/usr/local/bin \
         --install-method=copy \
         --overwrite-policy=always \
         exe:infernix \
    && infernix internal materialize-substrate ${RUNTIME_MODE} --demo-ui ${DEMO_UI} \
    && infernix internal materialize-linux-native-engines \
    && if [ "${RUNTIME_MODE}" = "linux-cpu" ]; then \
         poetry install --directory python/engines/transformers --with linux-cpu --no-interaction; \
         printf '%s\n' \
           'runtimeMode=linux-cpu' \
           'adapterId=transformers-python' \
           'groups=linux-cpu' \
           > python/engines/transformers/.venv/.infernix-framework-groups-linux-cpu-linux-cpu; \
         poetry install --directory python/engines/pytorch --with linux-cpu --no-interaction; \
         printf '%s\n' \
           'runtimeMode=linux-cpu' \
           'adapterId=pytorch-python' \
           'groups=linux-cpu' \
           > python/engines/pytorch/.venv/.infernix-framework-groups-linux-cpu-linux-cpu; \
       fi \
    && npm --prefix web run build \
    && poetry --directory python run check-code

# Phase 4 Sprint 4.17 — this is the slim control-plane / coordinator image: it
# carries the `infernix` binaries, the framework-free shared `python/` project
# (so the coordinator's `check-code` and adapter dispatch resolve), and the
# cluster toolbelt. The `linux-cpu` image additionally bakes the small CPU
# framework groups needed by its in-cluster engine pods. CUDA framework venvs
# still live only in per-engine images built from `docker/engine.Dockerfile`
# (CUDA-runtime base + this image's binary/python + one engine's `--with cuda`
# venv), so the GPU lane avoids the retired ~121 GB monolith.

# Phase 3 Sprint 3.10 — Playwright system dependencies + browser
# install live in the launcher image. The previous dedicated
# @infernix-playwright:local@ container is retired; @infernix test e2e@
# now invokes @npm --prefix web exec -- playwright test ...@ inside
# this launcher container, on the same private Docker @kind@ network as
# the running cluster.
RUN apt-get update \
    && npm --prefix web exec -- playwright install --with-deps chromium firefox webkit \
    && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["infernix", "--help"]
