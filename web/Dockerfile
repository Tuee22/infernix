FROM node:22-bookworm-slim

WORKDIR /srv/web

COPY web/package.json web/package-lock.json ./

RUN npm ci

RUN npm install -g http-server \
    && npm cache clean --force

RUN npx playwright install-deps chromium firefox webkit

RUN npx playwright install chromium

RUN npx playwright install firefox

RUN npx playwright install webkit

COPY web/playwright.config.js ./playwright.config.js
COPY web/playwright ./playwright
COPY web/test ./test
COPY web/dist ./dist

EXPOSE 8080

CMD ["http-server", "/srv/web/dist", "-p", "8080", "-c-1"]
