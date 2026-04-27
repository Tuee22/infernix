FROM infernix-linux-base:local

ENV INFERNIX_BUILD_ROOT=/opt/build/infernix \
    INFERNIX_CABAL_BUILDDIR=/opt/build/infernix/cabal \
    INFERNIX_RUNTIME_MODE=linux-cpu \
    PATH=/opt/build/infernix:/workspace/.build:/root/.local/bin:/root/.ghcup/bin:/root/.cabal/bin:${PATH}

COPY . /workspace

RUN mkdir -p /opt/build/infernix /workspace/tools/generated_proto \
    && cabal update \
    && npm --prefix web ci \
    && npx --prefix web playwright install --with-deps chromium firefox webkit \
    && poetry install --directory python/linux-cpu \
    && poetry --directory python/linux-cpu run python -m grpc_tools.protoc \
         -I /workspace/proto \
         --python_out /workspace/tools/generated_proto \
         /workspace/proto/infernix/api/inference_service.proto \
         /workspace/proto/infernix/manifest/runtime_manifest.proto \
         /workspace/proto/infernix/runtime/inference.proto \
    && cabal --builddir=/opt/build/infernix/cabal install \
         --installdir=/usr/local/bin \
         --install-method=copy \
         --overwrite-policy=always \
         exe:infernix \
         exe:infernix-demo \
    && npm --prefix web run build \
    && poetry --directory python/linux-cpu run check-code

CMD ["infernix", "--help"]
