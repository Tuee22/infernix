# Phase 4 Sprint 4.17 — per-engine engine image.
#
# Splits the Sprint 4.16 monolith: instead of baking every framework venv into
# one ~121 GB image, each framework engine gets its own image carrying only its
# CUDA framework venv. An engine pod then pulls only its own framework through
# the Harbor/Kind flow.
#
# The image reuses the slim control-plane image as the source of the built
# `infernix` binary, the framework-free `python/` project, the generated proto
# stubs, and the staged host manifest; it adds a CUDA runtime base + exactly one
# engine's `--with cuda` venv.
#
# Build: docker build -f docker/engine.Dockerfile \
#   --build-arg ENGINE=vllm \
#   --build-arg CONTROL_PLANE_IMAGE=infernix-linux-gpu:local \
#   --build-arg BASE_IMAGE=nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04 \
#   -t infernix-engine-vllm-linux-gpu:local .
ARG CONTROL_PLANE_IMAGE=infernix-linux-gpu:local
ARG BASE_IMAGE=nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04

FROM ${CONTROL_PLANE_IMAGE} AS source

FROM ${BASE_IMAGE}

ARG ENGINE=vllm

ENV DEBIAN_FRONTEND=noninteractive \
    POETRY_HOME=/opt/poetry \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH=/opt/poetry/bin:/usr/local/bin:${PATH}

# Runtime system deps shared by the framework engines: python, poetry's
# bootstrap interpreter, tini for signal handling, and the audio/video/codec
# libraries the artifact families load (ffmpeg for diffusers video + imageio,
# libsndfile for torchaudio/soundfile, libgomp for torch/onnx threading).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        ffmpeg \
        git \
        libgomp1 \
        libsndfile1 \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        tini \
    && ln -sf /usr/bin/python3 /usr/local/bin/python \
    && python3 -m venv ${POETRY_HOME} \
    && ${POETRY_HOME}/bin/python -m pip install --upgrade pip \
    && ${POETRY_HOME}/bin/pip install poetry \
    && ln -sfn ${POETRY_HOME}/bin/poetry /usr/local/bin/poetry \
    && rm -rf /var/lib/apt/lists/*

# The built binary, the framework-free python project (path dependency for the
# per-engine venv), the generated proto stubs, the staged substrate/host
# manifest, and the chart cache — all from the slim control-plane image.
COPY --from=source /usr/local/bin/infernix /usr/local/bin/infernix
COPY --from=source /usr/local/bin/infernix-demo /usr/local/bin/infernix-demo
COPY --from=source /workspace /workspace
COPY --from=source /opt/infernix /opt/infernix

WORKDIR /workspace

# Drop build-only artifacts the engine role never uses (Haskell build tree,
# web bundle + node_modules), keeping the per-engine image lean — the engine
# pod runs `infernix service --role engine` against the framework-free python
# project + the per-engine venv only.
RUN rm -rf dist-newstyle web/node_modules web/dist web/output web/.spago

# Install only this engine's CUDA framework venv (in-project venv at
# python/engines/<engine>/.venv, path-depending on the shared framework-free
# adapters package). The runtime worker execs this venv's python with
# `-m adapters.<module>` (Sprint 4.16).
RUN poetry install --directory python/engines/${ENGINE} --with cuda --no-interaction

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["infernix", "service", "--role", "engine"]
