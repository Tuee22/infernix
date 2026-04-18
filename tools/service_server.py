#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import pathlib
import shutil
import sys
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import unquote, urlparse
import urllib.error
import urllib.request

from demo_config import load_demo_config
from runtime_backend import RuntimeBackend


def load_catalog(paths: dict[str, pathlib.Path]) -> list[dict]:
    payload = load_demo_config(paths["demo_config_path"])
    return payload["models"]


def load_full_demo_config(paths: dict[str, pathlib.Path]) -> dict:
    return load_demo_config(paths["demo_config_path"])


def load_publication_state(publication_state_path: pathlib.Path) -> dict:
    if not publication_state_path.exists():
        return {"routes": []}
    payload = json.loads(publication_state_path.read_text())
    if not isinstance(payload, dict):
        raise ValueError("publication state must be a JSON object")
    routes = payload.get("routes")
    if not isinstance(routes, list):
        payload["routes"] = []
    return payload


def probe_route(base_url: str, route_prefix: str) -> tuple[str, str]:
    try:
        with urllib.request.urlopen(f"{base_url.rstrip('/')}{route_prefix}", timeout=5) as response:
            return "ready", f"http {response.status}"
    except urllib.error.HTTPError as exc:
        return "degraded", f"http {exc.code}"
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return "unreachable", str(exc)


def enrich_publication_state(
    publication: dict,
    route_probe_base_url: str | None,
    daemon_location: str,
) -> dict:
    payload = dict(publication)
    upstreams = payload.get("upstreams")
    if not isinstance(upstreams, list):
        return payload

    enriched_upstreams: list[dict] = []
    for upstream in upstreams:
        if not isinstance(upstream, dict):
            continue
        updated = dict(upstream)
        upstream_id = updated.get("id")
        route_prefix = updated.get("routePrefix")
        if upstream_id == "service":
            updated["healthStatus"] = "ready"
            updated["healthDetail"] = daemon_location
        elif route_probe_base_url and isinstance(route_prefix, str):
            health_status, health_detail = probe_route(route_probe_base_url, route_prefix)
            updated["healthStatus"] = health_status
            updated["healthDetail"] = health_detail
        else:
            updated["healthStatus"] = updated.get("healthStatus", "unprobed")
            updated["healthDetail"] = "route probe unavailable"
        enriched_upstreams.append(updated)

    payload["upstreams"] = enriched_upstreams
    return payload


def cache_root(paths: dict[str, pathlib.Path], runtime_mode: str, model_id: str) -> pathlib.Path:
    return paths["model_cache_root"] / runtime_mode / model_id / "default"


def cache_manifest_path(paths: dict[str, pathlib.Path], runtime_mode: str, model_id: str) -> pathlib.Path:
    return paths["object_store_root"] / "manifests" / runtime_mode / model_id / "default.json"


def materialize_cache(paths: dict[str, pathlib.Path], runtime_mode: str, model: dict) -> dict:
    model_id = model["modelId"]
    cache_dir = cache_root(paths, runtime_mode, model_id)
    cache_dir.mkdir(parents=True, exist_ok=True)
    (cache_dir / "materialized.txt").write_text(
        f"materialized from {model['downloadUrl']} via {model['selectedEngine']}\n"
    )
    manifest = {
        "runtimeMode": runtime_mode,
        "modelId": model_id,
        "selectedEngine": model["selectedEngine"],
        "durableSourceUri": model["downloadUrl"],
        "cacheKey": "default",
    }
    manifest_path = cache_manifest_path(paths, runtime_mode, model_id)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest))
    return manifest


def load_cache_entries(paths: dict[str, pathlib.Path], runtime_mode: str) -> list[dict]:
    manifest_root = paths["object_store_root"] / "manifests" / runtime_mode
    if not manifest_root.exists():
        return []
    entries: list[dict] = []
    for model_dir in sorted(path for path in manifest_root.iterdir() if path.is_dir()):
        manifest_path = model_dir / "default.json"
        if not manifest_path.exists():
            continue
        payload = json.loads(manifest_path.read_text())
        payload["cachePath"] = str(cache_root(paths, runtime_mode, payload["modelId"]))
        payload["materialized"] = (cache_root(paths, runtime_mode, payload["modelId"]) / "materialized.txt").exists()
        entries.append(payload)
    return entries


def evict_cache(paths: dict[str, pathlib.Path], runtime_mode: str, model_id: str | None) -> list[dict]:
    entries = load_cache_entries(paths, runtime_mode)
    targets = [entry for entry in entries if model_id is None or entry["modelId"] == model_id]
    for entry in targets:
        shutil.rmtree(cache_root(paths, runtime_mode, entry["modelId"]), ignore_errors=True)
    return targets


def rebuild_cache(paths: dict[str, pathlib.Path], runtime_mode: str, catalog: list[dict], model_id: str | None) -> list[dict]:
    catalog_by_id = {model["modelId"]: model for model in catalog}
    entries = load_cache_entries(paths, runtime_mode)
    targets = [entry for entry in entries if model_id is None or entry["modelId"] == model_id]
    rebuilt: list[dict] = []
    for entry in targets:
        model = catalog_by_id.get(entry["modelId"])
        if model is None:
            continue
        rebuilt.append(materialize_cache(paths, runtime_mode, model))
    return rebuilt


def model_lookup(model_id: str, catalog: list[dict]) -> dict | None:
    return next((model for model in catalog if model["modelId"] == model_id), None)


def resolve_data_root(repo_root: pathlib.Path) -> pathlib.Path:
    data_root = os.environ.get("INFERNIX_DATA_ROOT")
    if data_root is None:
        return repo_root / ".data"
    candidate = pathlib.Path(data_root)
    if candidate.is_absolute():
        return candidate
    return repo_root / candidate


class InfernixHandler(BaseHTTPRequestHandler):
    server_version = "InfernixHTTP/0.2"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        normalized_path = path[:-1] if path != "/" and path.endswith("/") else path
        catalog = load_catalog(self.paths)

        if normalized_path == "/healthz":
            self.respond_json(
                HTTPStatus.OK,
                {
                    "status": "ok",
                    "runtimeMode": self.runtime_mode,
                    "controlPlaneContext": self.control_plane_context,
                    "daemonLocation": self.daemon_location,
                    "catalogSource": self.catalog_source,
                    "durableBackendAccessMode": self.runtime_backend.backend_access_mode,
                    "demoConfigPath": str(self.paths["demo_config_path"]),
                    "mountedDemoConfigPath": str(self.paths["mounted_demo_config_path"]),
                },
            )
            return

        if normalized_path == "/api/publication":
            publication = load_publication_state(self.paths["publication_state_path"])
            publication = enrich_publication_state(publication, self.route_probe_base_url, self.daemon_location)
            publication.update(
                {
                    "runtimeMode": self.runtime_mode,
                    "controlPlaneContext": self.control_plane_context,
                    "daemonLocation": self.daemon_location,
                    "catalogSource": self.catalog_source,
                    "durableBackendAccessMode": self.runtime_backend.backend_access_mode,
                    "demoConfigPath": str(self.paths["demo_config_path"]),
                    "mountedDemoConfigPath": str(self.paths["mounted_demo_config_path"]),
                }
            )
            self.respond_json(HTTPStatus.OK, publication)
            return

        if normalized_path == "/api/models":
            self.respond_json(HTTPStatus.OK, catalog)
            return

        if normalized_path == "/api/demo-config":
            self.respond_json(HTTPStatus.OK, load_full_demo_config(self.paths))
            return

        if normalized_path == "/api/cache":
            self.respond_json(
                HTTPStatus.OK,
                {
                    "runtimeMode": self.runtime_mode,
                    "entries": self.runtime_backend.list_cache_entries(),
                },
            )
            return

        if path.startswith("/api/models/"):
            model_id = path.removeprefix("/api/models/")
            model = model_lookup(model_id, catalog)
            if model is None:
                self.respond_json(HTTPStatus.NOT_FOUND, {"errorCode": "unknown_model", "message": "Model not found."})
            else:
                self.respond_json(HTTPStatus.OK, model)
            return

        if path.startswith("/api/inference/"):
            request_id = path.removeprefix("/api/inference/")
            result = self.runtime_backend.load_result(request_id)
            if result is None:
                self.respond_json(
                    HTTPStatus.NOT_FOUND,
                    {"errorCode": "unknown_request", "message": "Result not found."},
                )
            else:
                self.respond_json(HTTPStatus.OK, result)
            return

        if path.startswith("/objects/"):
            object_body = self.runtime_backend.load_object(path.removeprefix("/objects/"))
            if object_body is not None:
                self.respond_bytes(HTTPStatus.OK, object_body, "text/plain; charset=utf-8")
            else:
                self.respond_json(HTTPStatus.NOT_FOUND, {"errorCode": "not_found", "message": "Object not found."})
            return

        if normalized_path in {"/harbor", "/minio/console", "/pulsar/admin"}:
            self.respond_html(
                HTTPStatus.OK,
                (
                    "<html><body><h1>"
                    f"{normalized_path}"
                    "</h1><p>Compatibility portal surface.</p>"
                    f"<p>Runtime mode: {self.runtime_mode}</p></body></html>"
                ),
            )
            return

        if normalized_path in {"/minio/s3", "/pulsar/ws"}:
            self.respond_json(
                HTTPStatus.OK,
                {"path": normalized_path, "status": "ready", "runtimeMode": self.runtime_mode},
            )
            return

        self.serve_static(path)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        if path != "/api/inference":
            if path in {"/api/cache/evict", "/api/cache/rebuild"}:
                content_length = int(self.headers.get("Content-Length", "0"))
                raw_body = self.rfile.read(content_length) if content_length > 0 else b"{}"
                try:
                    payload = json.loads(raw_body.decode("utf-8")) if raw_body else {}
                except json.JSONDecodeError as exc:
                    self.respond_json(HTTPStatus.BAD_REQUEST, {"errorCode": "invalid_json", "message": str(exc)})
                    return
                if payload is None:
                    payload = {}
                if not isinstance(payload, dict):
                    self.respond_json(
                        HTTPStatus.BAD_REQUEST,
                        {"errorCode": "invalid_request", "message": "The request payload must be a JSON object."},
                    )
                    return
                model_id = payload.get("modelId")
                if model_id is not None and not isinstance(model_id, str):
                    self.respond_json(
                        HTTPStatus.BAD_REQUEST,
                        {"errorCode": "invalid_request", "message": "modelId must be a string when provided."},
                    )
                    return
                catalog = load_catalog(self.paths)
                if path == "/api/cache/evict":
                    evicted = self.runtime_backend.evict_cache(model_id)
                    self.respond_json(
                        HTTPStatus.OK,
                        {
                            "runtimeMode": self.runtime_mode,
                            "evictedCount": len(evicted),
                            "entries": self.runtime_backend.list_cache_entries(),
                        },
                    )
                    return
                rebuilt = self.runtime_backend.rebuild_cache(catalog, model_id)
                self.respond_json(
                    HTTPStatus.OK,
                    {
                        "runtimeMode": self.runtime_mode,
                        "rebuiltCount": len(rebuilt),
                        "entries": self.runtime_backend.list_cache_entries(),
                    },
                )
                return
            self.respond_json(HTTPStatus.NOT_FOUND, {"errorCode": "not_found", "message": "Path not found."})
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length)
        try:
            payload = json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError as exc:
            self.respond_json(HTTPStatus.BAD_REQUEST, {"errorCode": "invalid_json", "message": str(exc)})
            return

        catalog = load_catalog(self.paths)
        model_id = payload.get("requestModelId") or payload.get("modelId")
        input_text = payload.get("inputText", "")
        if not isinstance(model_id, str) or not isinstance(input_text, str):
            self.respond_json(
                HTTPStatus.BAD_REQUEST,
                {"errorCode": "invalid_request", "message": "The request payload is malformed."},
            )
            return

        model = model_lookup(model_id, catalog)
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

        result = self.runtime_backend.submit_inference(model, input_text)
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

    def respond_bytes(self, status: HTTPStatus, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def respond_file(self, path: pathlib.Path, content_type: str) -> None:
        body = path.read_bytes()
        self.respond_bytes(HTTPStatus.OK, body, content_type)

    def log_message(self, format: str, *args: object) -> None:
        return

    @property
    def paths(self) -> dict[str, pathlib.Path]:
        return self.server.paths  # type: ignore[attr-defined]

    @property
    def runtime_mode(self) -> str:
        return self.server.runtime_mode  # type: ignore[attr-defined]

    @property
    def control_plane_context(self) -> str:
        return self.server.control_plane_context  # type: ignore[attr-defined]

    @property
    def daemon_location(self) -> str:
        return self.server.daemon_location  # type: ignore[attr-defined]

    @property
    def catalog_source(self) -> str:
        return self.server.catalog_source  # type: ignore[attr-defined]

    @property
    def route_probe_base_url(self) -> str | None:
        return self.server.route_probe_base_url  # type: ignore[attr-defined]

    @property
    def runtime_backend(self) -> RuntimeBackend:
        return self.server.runtime_backend  # type: ignore[attr-defined]


class InfernixHTTPServer(HTTPServer):
    def server_bind(self) -> None:
        self.socket.bind(self.server_address)
        self.server_address = self.socket.getsockname()
        self.server_name = self.server_address[0]
        self.server_port = self.server_address[1]


def run_model(model: dict, input_text: str) -> str:
    family = model["family"]
    engine = model["selectedEngine"]
    if family == "llm":
        return f"{engine} generated: {input_text}"
    if family == "speech":
        return f"Transcript via {engine}: {input_text}"
    if family in {"audio", "music"}:
        return f"Audio workflow via {engine}: {input_text}"
    if family == "image":
        return f"Image prompt accepted by {engine}: {input_text}"
    if family == "video":
        return f"Video prompt accepted by {engine}: {input_text}"
    return f"Tool workflow via {engine}: {input_text}"


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
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--runtime-mode", required=True)
    parser.add_argument("--control-plane-context", required=True)
    parser.add_argument("--daemon-location", required=True)
    parser.add_argument("--catalog-source", required=True)
    parser.add_argument("--demo-config", required=True)
    parser.add_argument("--mounted-demo-config", required=True)
    parser.add_argument("--publication-state", required=True)
    parser.add_argument("--route-probe-base-url")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = pathlib.Path(args.repo_root).resolve()
    data_root = resolve_data_root(repo_root)
    demo_config_path = pathlib.Path(args.demo_config).resolve()
    mounted_demo_config_path = pathlib.Path(args.mounted_demo_config)
    publication_state_path = pathlib.Path(args.publication_state).resolve()

    try:
        demo_config = load_demo_config(demo_config_path)
    except (FileNotFoundError, ValueError, json.JSONDecodeError) as exc:
        print(f"infernix service error: {exc}", file=sys.stderr)
        return 1
    if demo_config["runtimeMode"] != args.runtime_mode:
        print(
            (
                "infernix service error: "
                f"demo config runtime mode {demo_config['runtimeMode']} does not match requested runtime mode {args.runtime_mode}"
            ),
            file=sys.stderr,
        )
        return 1

    publication_state = load_publication_state(publication_state_path)
    paths = {
        "data_root": data_root,
        "results_root": data_root / "runtime" / "results",
        "object_store_root": data_root / "object-store",
        "model_cache_root": data_root / "runtime" / "model-cache",
        "web_dist_root": repo_root / "web" / "dist",
        "demo_config_path": demo_config_path,
        "mounted_demo_config_path": mounted_demo_config_path,
        "publication_state_path": publication_state_path,
    }
    for key, path in paths.items():
        if key in {"demo_config_path", "mounted_demo_config_path", "publication_state_path"}:
            continue
        path.mkdir(parents=True, exist_ok=True)

    runtime_backend = RuntimeBackend(
        paths=paths,
        runtime_mode=args.runtime_mode,
        control_plane_context=args.control_plane_context,
        daemon_location=args.daemon_location,
        publication_state=publication_state,
    )
    server = InfernixHTTPServer((args.host, args.port), InfernixHandler)
    server.paths = paths  # type: ignore[attr-defined]
    server.runtime_backend = runtime_backend  # type: ignore[attr-defined]
    server.runtime_mode = args.runtime_mode  # type: ignore[attr-defined]
    server.control_plane_context = args.control_plane_context  # type: ignore[attr-defined]
    server.daemon_location = args.daemon_location  # type: ignore[attr-defined]
    server.catalog_source = args.catalog_source  # type: ignore[attr-defined]
    server.route_probe_base_url = args.route_probe_base_url  # type: ignore[attr-defined]
    print(
        (
            f"infernix service listening on {args.port} "
            f"(runtime mode {args.runtime_mode}, control plane {args.control_plane_context}, "
            f"daemon {args.daemon_location}, demo config {demo_config_path})"
        ),
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        runtime_backend.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
