ARG BASE_IMAGE=mcr.microsoft.com/playwright:v1.57.0-noble
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NPM_CONFIG_UPDATE_NOTIFIER=false

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY web/package.json /workspace/web/
RUN npm --prefix /workspace/web install --no-audit --no-fund

COPY web/playwright /workspace/web/playwright
COPY web/test /workspace/web/test

ENTRYPOINT ["npm", "--prefix", "web", "exec", "--"]
CMD ["playwright", "test", "./playwright/inference.spec.js", "--reporter=list", "--timeout=30000"]
