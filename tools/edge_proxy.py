#!/usr/bin/env python3

from __future__ import annotations

import http.client
import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse


HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}


def parse_upstream(value: str) -> tuple[str, int]:
    host, _, port_text = value.partition(":")
    return host, int(port_text or "80")


def select_upstream(path: str) -> tuple[str, int]:
    if path == "/api" or path.startswith("/api/") or path.startswith("/objects/") or path == "/healthz":
        return parse_upstream(os.environ["INFERNIX_SERVICE_UPSTREAM"])
    if path.startswith("/harbor"):
        return parse_upstream(os.environ["INFERNIX_HARBOR_UPSTREAM"])
    if path.startswith("/minio/"):
        return parse_upstream(os.environ["INFERNIX_MINIO_UPSTREAM"])
    if path.startswith("/pulsar/"):
        return parse_upstream(os.environ["INFERNIX_PULSAR_UPSTREAM"])
    return parse_upstream(os.environ["INFERNIX_WEB_UPSTREAM"])


class EdgeProxyHandler(BaseHTTPRequestHandler):
    server_version = "InfernixEdge/0.1"

    def do_GET(self) -> None:
        self.forward()

    def do_HEAD(self) -> None:
        self.forward()

    def do_POST(self) -> None:
        self.forward()

    def do_PUT(self) -> None:
        self.forward()

    def forward(self) -> None:
        parsed = urlparse(self.path)
        upstream_host, upstream_port = select_upstream(parsed.path)
        body = b""
        content_length = self.headers.get("Content-Length")
        if content_length is not None:
            body = self.rfile.read(int(content_length))
        headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in HOP_BY_HOP_HEADERS
        }
        headers["Host"] = upstream_host
        connection = http.client.HTTPConnection(upstream_host, upstream_port, timeout=300)
        try:
            connection.request(self.command, self.path, body=body, headers=headers)
            response = connection.getresponse()
            payload = response.read()
        except OSError as exc:
            message = f"upstream request failed: {exc}".encode("utf-8")
            self.send_response(HTTPStatus.BAD_GATEWAY)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(message)))
            self.end_headers()
            self.wfile.write(message)
            return
        finally:
            connection.close()

        self.send_response(response.status, response.reason)
        for header, value in response.getheaders():
            if header.lower() in HOP_BY_HOP_HEADERS:
                continue
            if header.lower() == "content-length":
                continue
            self.send_header(header, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format: str, *args: object) -> None:
        return


def main() -> int:
    bind_host = os.environ.get("INFERNIX_BIND_HOST", "0.0.0.0")
    port = int(os.environ.get("INFERNIX_PORT", "8080"))
    server = ThreadingHTTPServer((bind_host, port), EdgeProxyHandler)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
