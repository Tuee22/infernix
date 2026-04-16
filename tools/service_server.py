#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import unquote, urlparse


CATALOG = [
    {
        "modelId": "echo-text",
        "displayName": "Echo Text",
        "family": "text",
        "description": "Returns the input unchanged.",
        "requestShape": [{"name": "inputText", "label": "Input Text", "fieldType": "text"}],
    },
    {
        "modelId": "uppercase-text",
        "displayName": "Uppercase Text",
        "family": "text",
        "description": "Transforms input to uppercase.",
        "requestShape": [{"name": "inputText", "label": "Input Text", "fieldType": "text"}],
    },
    {
        "modelId": "word-count",
        "displayName": "Word Count",
        "family": "analysis",
        "description": "Returns the number of words in the input.",
        "requestShape": [{"name": "inputText", "label": "Input Text", "fieldType": "text"}],
    },
]


def model_lookup(model_id: str) -> dict | None:
    return next((model for model in CATALOG if model["modelId"] == model_id), None)


class InfernixHandler(BaseHTTPRequestHandler):
    server_version = "InfernixHTTP/0.1"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)

        if path == "/healthz":
            self.respond_json(HTTPStatus.OK, {"status": "ok"})
            return

        if path == "/api/models":
            self.respond_json(HTTPStatus.OK, CATALOG)
            return

        if path.startswith("/api/models/"):
            model_id = path.removeprefix("/api/models/")
            model = model_lookup(model_id)
            if model is None:
                self.respond_json(HTTPStatus.NOT_FOUND, {"errorCode": "unknown_model", "message": "Model not found."})
            else:
                self.respond_json(HTTPStatus.OK, model)
            return

        if path.startswith("/api/inference/"):
            request_id = path.removeprefix("/api/inference/")
            result_path = self.paths["results_root"] / f"{request_id}.json"
            if not result_path.exists():
                self.respond_json(
                    HTTPStatus.NOT_FOUND,
                    {"errorCode": "unknown_request", "message": "Result not found."},
                )
            else:
                self.respond_json(HTTPStatus.OK, json.loads(result_path.read_text()))
            return

        if path.startswith("/objects/"):
            object_path = self.paths["object_store_root"] / path.removeprefix("/objects/")
            if object_path.exists():
                self.respond_file(object_path, "text/plain; charset=utf-8")
            else:
                self.respond_json(HTTPStatus.NOT_FOUND, {"errorCode": "not_found", "message": "Object not found."})
            return

        if path in {"/harbor", "/minio/console", "/pulsar/admin"}:
            self.respond_html(
                HTTPStatus.OK,
                f"<html><body><h1>{path}</h1><p>Compatibility portal surface.</p></body></html>",
            )
            return

        if path in {"/minio/s3", "/pulsar/ws"}:
            self.respond_json(HTTPStatus.OK, {"path": path, "status": "ready"})
            return

        self.serve_static(path)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        if path != "/api/inference":
            self.respond_json(HTTPStatus.NOT_FOUND, {"errorCode": "not_found", "message": "Path not found."})
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length)
        try:
            payload = json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError as exc:
            self.respond_json(HTTPStatus.BAD_REQUEST, {"errorCode": "invalid_json", "message": str(exc)})
            return

        model_id = payload.get("requestModelId") or payload.get("modelId")
        input_text = payload.get("inputText", "")
        if not isinstance(model_id, str) or not isinstance(input_text, str):
            self.respond_json(
                HTTPStatus.BAD_REQUEST,
                {"errorCode": "invalid_request", "message": "The request payload is malformed."},
            )
            return

        model = model_lookup(model_id)
        if model is None:
            self.respond_json(
                HTTPStatus.BAD_REQUEST,
                {"errorCode": "unknown_model", "message": "The requested model is not registered."},
            )
            return

        if not input_text.strip():
            self.respond_json(
                HTTPStatus.BAD_REQUEST,
                {"errorCode": "invalid_request", "message": "The request input must not be blank."},
            )
            return

        request_id = f"req-{int(time.time() * 1000)}"
        cache_root = self.paths["model_cache_root"] / model_id / "default"
        cache_root.mkdir(parents=True, exist_ok=True)
        (cache_root / "materialized.txt").write_text("materialized\n")

        output_text = run_model(model_id, input_text)
        payload_json: dict[str, str | None]
        if len(output_text) > 80:
            object_rel_path = pathlib.Path("results") / f"{request_id}.txt"
            object_path = self.paths["object_store_root"] / object_rel_path
            object_path.parent.mkdir(parents=True, exist_ok=True)
            object_path.write_text(output_text)
            payload_json = {"inlineOutput": None, "objectRef": str(object_rel_path).replace(os.sep, "/")}
        else:
            payload_json = {"inlineOutput": output_text, "objectRef": None}

        result = {
            "requestId": request_id,
            "resultModelId": model_id,
            "status": "completed",
            "payload": payload_json,
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        result_path = self.paths["results_root"] / f"{request_id}.json"
        result_path.parent.mkdir(parents=True, exist_ok=True)
        result_path.write_text(json.dumps(result))
        self.respond_json(HTTPStatus.CREATED, result)

    def serve_static(self, path: str) -> None:
        dist_root = self.paths["web_dist_root"]
        relative_path = path.lstrip("/") or "index.html"
        target = (dist_root / relative_path).resolve()
        try:
            target.relative_to(dist_root.resolve())
        except ValueError:
            self.respond_json(HTTPStatus.NOT_FOUND, {"errorCode": "not_found", "message": "Path not found."})
            return

        if target.is_dir():
            target = target / "index.html"
        if not target.exists():
            if path == "/":
                target = dist_root / "index.html"
            else:
                self.respond_json(HTTPStatus.NOT_FOUND, {"errorCode": "not_found", "message": "Path not found."})
                return

        self.respond_file(target, guess_content_type(target))

    def respond_json(self, status: HTTPStatus, payload: object) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def respond_html(self, status: HTTPStatus, html: str) -> None:
        body = html.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def respond_file(self, path: pathlib.Path, content_type: str) -> None:
        body = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        return

    @property
    def paths(self) -> dict[str, pathlib.Path]:
        return self.server.paths  # type: ignore[attr-defined]


class InfernixHTTPServer(HTTPServer):
    def server_bind(self) -> None:
        self.socket.bind(self.server_address)
        self.server_address = self.socket.getsockname()
        self.server_name = "127.0.0.1"
        self.server_port = self.server_address[1]


def run_model(model_id: str, input_text: str) -> str:
    if model_id == "uppercase-text":
        return input_text.upper()
    if model_id == "word-count":
        return str(len(input_text.split()))
    return input_text


def guess_content_type(path: pathlib.Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".html":
        return "text/html; charset=utf-8"
    if suffix == ".js":
        return "text/javascript; charset=utf-8"
    if suffix == ".css":
        return "text/css; charset=utf-8"
    if suffix == ".json":
        return "application/json; charset=utf-8"
    return "application/octet-stream"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--port", type=int, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = pathlib.Path(args.repo_root).resolve()
    paths = {
        "results_root": repo_root / ".data" / "runtime" / "results",
        "object_store_root": repo_root / ".data" / "object-store",
        "model_cache_root": repo_root / ".data" / "runtime" / "model-cache",
        "web_dist_root": repo_root / "web" / "dist",
    }
    for path in paths.values():
        path.mkdir(parents=True, exist_ok=True)

    server = InfernixHTTPServer(("127.0.0.1", args.port), InfernixHandler)
    server.paths = paths  # type: ignore[attr-defined]
    print(f"infernix service listening on {args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
