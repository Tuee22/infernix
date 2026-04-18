#!/usr/bin/env python3

from __future__ import annotations

import base64
import io
import json
import os
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urljoin, urlparse
import urllib.error
import urllib.request

import pulsar
from minio import Minio
from minio.error import S3Error


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


def parse_minio_endpoint(endpoint: str) -> tuple[str, bool]:
    parsed = urlparse(endpoint if "://" in endpoint else f"http://{endpoint}")
    host = parsed.netloc or parsed.path
    if parsed.path not in {"", "/"} and parsed.netloc:
        raise ValueError(f"MinIO endpoint must not contain a path prefix: {endpoint}")
    return host, parsed.scheme == "https"


def harbor_basic_auth_header() -> str:
    raw = f"{os.environ.get('INFERNIX_HARBOR_ADMIN_USER', 'admin')}:{os.environ.get('INFERNIX_HARBOR_ADMIN_PASSWORD', '')}"
    return "Basic " + base64.b64encode(raw.encode("utf-8")).decode("ascii")


def load_json(url: str, headers: dict[str, str] | None = None) -> tuple[int, object]:
    request = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            payload = response.read().decode("utf-8", errors="replace").strip()
            if not payload:
                return response.status, {}
            try:
                return response.status, json.loads(payload)
            except json.JSONDecodeError:
                return response.status, {"raw": payload}
    except urllib.error.HTTPError as exc:
        payload = exc.read().decode("utf-8", errors="replace").strip()
        return exc.code, {"error": payload or exc.reason}
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return 0, {"error": str(exc)}


def probe_url(url: str, headers: dict[str, str] | None = None) -> tuple[int, str]:
    request = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, response.reason
    except urllib.error.HTTPError as exc:
        return exc.code, exc.reason
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return 0, str(exc)


def escape_html(value: object) -> str:
    return (
        str(value)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def harbor_dashboard() -> str:
    api_url = os.environ["INFERNIX_HARBOR_API_URL"].rstrip("/")
    headers = {"Authorization": harbor_basic_auth_header()}
    health_status, health_payload = load_json(f"{api_url}/api/v2.0/health", headers=headers)
    projects_status, projects_payload = load_json(f"{api_url}/api/v2.0/projects?page_size=10", headers=headers)
    projects = projects_payload if isinstance(projects_payload, list) else []
    project_names = ", ".join(sorted(project.get("name", "?") for project in projects if isinstance(project, dict))) or "none"
    return render_dashboard(
        "Harbor",
        [
            ("API", api_url),
            ("Health status", health_status),
            ("Projects status", projects_status),
            ("Projects", project_names),
        ],
        health_payload,
    )


def minio_dashboard() -> str:
    s3_endpoint = os.environ["INFERNIX_MINIO_S3_ENDPOINT"].rstrip("/")
    console_endpoint = os.environ["INFERNIX_MINIO_CONSOLE_ENDPOINT"].rstrip("/")
    s3_status, s3_detail = probe_url(s3_endpoint)
    console_status, console_detail = probe_url(console_endpoint)
    return render_dashboard(
        "MinIO",
        [
            ("S3 endpoint", s3_endpoint),
            ("S3 probe", f"{s3_status} {s3_detail}"),
            ("Console endpoint", console_endpoint),
            ("Console probe", f"{console_status} {console_detail}"),
        ],
        {
            "s3Endpoint": s3_endpoint,
            "consoleEndpoint": console_endpoint,
            "s3Status": s3_status,
            "consoleStatus": console_status,
        },
    )


def pulsar_dashboard() -> str:
    admin_url = os.environ["INFERNIX_PULSAR_ADMIN_URL"].rstrip("/")
    http_base_url = os.environ["INFERNIX_PULSAR_HTTP_BASE_URL"].rstrip("/")
    clusters_status, clusters_payload = load_json(f"{admin_url}/clusters")
    brokers_status, brokers_payload = load_json(f"{admin_url}/brokers/health")
    return render_dashboard(
        "Pulsar",
        [
            ("Admin URL", admin_url),
            ("HTTP base URL", http_base_url),
            ("Clusters status", clusters_status),
            ("Brokers health", brokers_status),
        ],
        {
            "clusters": clusters_payload,
            "brokersHealth": brokers_payload,
        },
    )


def render_dashboard(title: str, details: list[tuple[str, object]], payload: object) -> str:
    detail_rows = "".join(
        f"<tr><th>{escape_html(label)}</th><td>{escape_html(value)}</td></tr>"
        for label, value in details
    )
    pretty_payload = escape_html(json.dumps(payload, indent=2, sort_keys=True))
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        f"<title>{escape_html(title)} Gateway</title>"
        "<style>"
        "body{font-family:ui-monospace,Menlo,monospace;margin:2rem;background:#f6f2ea;color:#1d1a16;}"
        "table{border-collapse:collapse;margin:1rem 0;width:100%;max-width:64rem;}"
        "th,td{border:1px solid #cbbda9;padding:.6rem .8rem;text-align:left;vertical-align:top;}"
        "pre{background:#efe5d6;padding:1rem;overflow:auto;max-width:64rem;}"
        "h1{margin:0 0 1rem 0;}p{max-width:52rem;line-height:1.45;}"
        "</style></head><body>"
        f"<h1>{escape_html(title)} Gateway</h1>"
        "<p>Cluster-resident routed portal backed by the live platform service rather than a placeholder page.</p>"
        f"<table>{detail_rows}</table>"
        "<h2>Backend Payload</h2>"
        f"<pre>{pretty_payload}</pre>"
        "</body></html>"
    )


def rewrite_target(base_url: str, request_path: str, prefix: str) -> str:
    stripped = request_path.removeprefix(prefix)
    if not stripped.startswith("/"):
        stripped = "/" + stripped
    return urljoin(base_url.rstrip("/") + "/", stripped.lstrip("/"))


def topic_name(tenant: str, namespace: str, topic: str) -> str:
    return f"persistent://{tenant}/{namespace}/{topic}"


class MinioBridge:
    def __init__(self, endpoint: str, access_key: str, secret_key: str) -> None:
        host, secure = parse_minio_endpoint(endpoint)
        self.client = Minio(host, access_key=access_key, secret_key=secret_key, secure=secure)

    def ensure_bucket(self, bucket_name: str) -> None:
        if not self.client.bucket_exists(bucket_name):
            self.client.make_bucket(bucket_name)

    def list_objects(self, bucket_name: str, prefix: str) -> list[str]:
        return [item.object_name for item in self.client.list_objects(bucket_name, prefix=prefix, recursive=True)]

    def stat_object(self, bucket_name: str, object_name: str) -> bool:
        try:
            self.client.stat_object(bucket_name, object_name)
            return True
        except S3Error as exc:
            if exc.code == "NoSuchKey":
                return False
            raise

    def get_object(self, bucket_name: str, object_name: str) -> bytes | None:
        try:
            response = self.client.get_object(bucket_name, object_name)
        except S3Error as exc:
            if exc.code == "NoSuchKey":
                return None
            raise
        try:
            return response.read()
        finally:
            response.close()
            response.release_conn()

    def put_object(self, bucket_name: str, object_name: str, payload: bytes, content_type: str) -> None:
        self.ensure_bucket(bucket_name)
        self.client.put_object(
            bucket_name,
            object_name,
            io.BytesIO(payload),
            len(payload),
            content_type=content_type,
        )


class PulsarBridge:
    def __init__(self, service_url: str, tenant: str, namespace: str) -> None:
        self.client = pulsar.Client(service_url)
        self.tenant = tenant
        self.namespace = namespace
        self._lock = threading.Lock()
        self._producers: dict[str, pulsar.Producer] = {}
        self._consumers: dict[tuple[str, str], pulsar.Consumer] = {}

    def close(self) -> None:
        for consumer in self._consumers.values():
            consumer.close()
        for producer in self._producers.values():
            producer.close()
        self.client.close()

    def publish(self, topic: str, payload: bytes, properties: dict[str, str]) -> None:
        producer = self._producer_for(topic)
        producer.send(payload, properties=properties)

    def receive(
        self,
        topic: str,
        subscription: str,
        timeout_ms: int,
        expected_request_id: str | None,
    ) -> tuple[bytes, dict[str, str]] | None:
        consumer = self._consumer_for(topic, subscription)
        deadline = threading.Event()
        remaining_timeout = timeout_ms
        while remaining_timeout > 0:
            wait_timeout = min(3000, remaining_timeout)
            try:
                message = consumer.receive(timeout_millis=wait_timeout)
            except pulsar.Timeout:
                remaining_timeout -= wait_timeout
                continue
            properties = dict(message.properties())
            payload = message.data()
            consumer.acknowledge(message)
            if expected_request_id is None or properties.get("requestId") == expected_request_id:
                return payload, properties
            remaining_timeout -= wait_timeout
            if deadline.is_set():
                break
        return None

    def _producer_for(self, topic: str) -> pulsar.Producer:
        with self._lock:
            producer = self._producers.get(topic)
            if producer is None:
                producer = self.client.create_producer(topic_name(self.tenant, self.namespace, topic))
                self._producers[topic] = producer
            return producer

    def _consumer_for(self, topic: str, subscription: str) -> pulsar.Consumer:
        key = (topic, subscription)
        with self._lock:
            consumer = self._consumers.get(key)
            if consumer is None:
                consumer = self.client.subscribe(
                    topic_name(self.tenant, self.namespace, topic),
                    subscription,
                    consumer_type=pulsar.ConsumerType.Exclusive,
                    initial_position=pulsar.InitialPosition.Earliest,
                )
                self._consumers[key] = consumer
            return consumer


class PortalHandler(BaseHTTPRequestHandler):
    server_version = "InfernixPortal/0.2"

    def do_GET(self) -> None:
        self.handle_request()

    def do_HEAD(self) -> None:
        self.handle_request()

    def do_POST(self) -> None:
        self.handle_request()

    def do_PUT(self) -> None:
        self.handle_request()

    def handle_request(self) -> None:
        surface = self.server.surface  # type: ignore[attr-defined]
        path = unquote(urlparse(self.path).path)
        if surface == "harbor":
            self.handle_harbor(path)
            return
        if surface == "minio":
            self.handle_minio(path)
            return
        if surface == "pulsar":
            self.handle_pulsar(path)
            return
        self.respond_json(HTTPStatus.NOT_FOUND, {"error": "unknown_surface"})

    def handle_harbor(self, path: str) -> None:
        if path.startswith("/harbor/api/"):
            self.proxy_request(
                rewrite_target(os.environ["INFERNIX_HARBOR_API_URL"], path, "/harbor"),
                headers={"Authorization": harbor_basic_auth_header()},
            )
            return
        self.respond_html(harbor_dashboard())

    def handle_minio(self, path: str) -> None:
        if path.startswith("/minio/s3/_infernix/bridge/"):
            self.handle_minio_bridge(path)
            return
        if path == "/minio/s3":
            s3_endpoint = os.environ["INFERNIX_MINIO_S3_ENDPOINT"].rstrip("/")
            self.respond_json(
                HTTPStatus.OK,
                {
                    "path": "/minio/s3",
                    "status": "ready",
                    "surface": "minio",
                    "targetUrl": s3_endpoint,
                },
            )
            return
        if path.startswith("/minio/s3/"):
            self.proxy_request(rewrite_target(os.environ["INFERNIX_MINIO_S3_ENDPOINT"], path, "/minio/s3"))
            return
        self.respond_html(minio_dashboard())

    def handle_pulsar(self, path: str) -> None:
        if path.startswith("/pulsar/ws/_infernix/bridge/"):
            self.handle_pulsar_bridge(path)
            return
        if path.startswith("/pulsar/admin/"):
            self.proxy_request(rewrite_target(os.environ["INFERNIX_PULSAR_ADMIN_URL"], path, "/pulsar/admin"))
            return
        if path == "/pulsar/ws":
            admin_url = os.environ["INFERNIX_PULSAR_ADMIN_URL"].rstrip("/")
            brokers_status, brokers_payload = load_json(f"{admin_url}/brokers/health")
            self.respond_json(
                HTTPStatus.OK,
                {
                    "path": "/pulsar/ws",
                    "status": "ready" if brokers_status in {200, 204} else "degraded",
                    "surface": "pulsar",
                    "brokersHealth": brokers_payload,
                },
            )
            return
        self.respond_html(pulsar_dashboard())

    def handle_minio_bridge(self, path: str) -> None:
        bridge = self.server.minio_bridge  # type: ignore[attr-defined]
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        if path.startswith("/minio/s3/_infernix/bridge/buckets/"):
            bucket_name = path.removeprefix("/minio/s3/_infernix/bridge/buckets/")
            if not bucket_name:
                self.respond_json(HTTPStatus.BAD_REQUEST, {"error": "missing_bucket"})
                return
            if self.command in {"POST", "PUT"}:
                bridge.ensure_bucket(bucket_name)
                self.respond_json(HTTPStatus.OK, {"bucket": bucket_name, "status": "ready"})
                return
            if self.command == "GET":
                prefix = query.get("prefix", [""])[0]
                self.respond_json(
                    HTTPStatus.OK,
                    {"bucket": bucket_name, "prefix": prefix, "objects": bridge.list_objects(bucket_name, prefix)},
                )
                return
            self.respond_json(HTTPStatus.METHOD_NOT_ALLOWED, {"error": "unsupported_method"})
            return
        if path.startswith("/minio/s3/_infernix/bridge/objects/"):
            relative = path.removeprefix("/minio/s3/_infernix/bridge/objects/")
            bucket_name, _, object_name = relative.partition("/")
            if not bucket_name or not object_name:
                self.respond_json(HTTPStatus.BAD_REQUEST, {"error": "missing_object_target"})
                return
            if self.command == "HEAD":
                exists = bridge.stat_object(bucket_name, object_name)
                self.send_response(HTTPStatus.OK if exists else HTTPStatus.NOT_FOUND)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if self.command == "GET":
                payload = bridge.get_object(bucket_name, object_name)
                if payload is None:
                    self.respond_json(HTTPStatus.NOT_FOUND, {"error": "object_not_found"})
                else:
                    self.respond_bytes(HTTPStatus.OK, payload, "application/octet-stream")
                return
            if self.command in {"POST", "PUT"}:
                payload = self.read_body()
                bridge.put_object(
                    bucket_name,
                    object_name,
                    payload,
                    self.headers.get("Content-Type", "application/octet-stream"),
                )
                self.respond_json(HTTPStatus.OK, {"bucket": bucket_name, "object": object_name, "status": "stored"})
                return
            self.respond_json(HTTPStatus.METHOD_NOT_ALLOWED, {"error": "unsupported_method"})
            return
        self.respond_json(HTTPStatus.NOT_FOUND, {"error": "unknown_bridge_path"})

    def handle_pulsar_bridge(self, path: str) -> None:
        bridge = self.server.pulsar_bridge  # type: ignore[attr-defined]
        if bridge is None:
            self.respond_json(HTTPStatus.BAD_GATEWAY, {"error": "pulsar_bridge_unavailable"})
            return
        if not path.startswith("/pulsar/ws/_infernix/bridge/topics/"):
            self.respond_json(HTTPStatus.NOT_FOUND, {"error": "unknown_bridge_path"})
            return
        relative = path.removeprefix("/pulsar/ws/_infernix/bridge/topics/")
        topic, _, action = relative.partition("/")
        if not topic or action not in {"publish", "receive"}:
            self.respond_json(HTTPStatus.BAD_REQUEST, {"error": "invalid_bridge_request"})
            return
        if self.command != "POST":
            self.respond_json(HTTPStatus.METHOD_NOT_ALLOWED, {"error": "unsupported_method"})
            return
        payload = self.read_json_body()
        if payload is None:
            return
        if action == "publish":
            raw_payload = payload.get("payloadBase64")
            properties = payload.get("properties", {})
            if not isinstance(raw_payload, str) or not isinstance(properties, dict):
                self.respond_json(HTTPStatus.BAD_REQUEST, {"error": "invalid_publish_payload"})
                return
            bridge.publish(
                topic,
                base64.b64decode(raw_payload.encode("ascii")),
                {str(key): str(value) for key, value in properties.items()},
            )
            self.respond_json(HTTPStatus.OK, {"topic": topic, "status": "published"})
            return
        subscription = payload.get("subscription")
        timeout_ms = payload.get("timeoutMs", 15000)
        expected_request_id = payload.get("requestId")
        if not isinstance(subscription, str) or not isinstance(timeout_ms, int):
            self.respond_json(HTTPStatus.BAD_REQUEST, {"error": "invalid_receive_payload"})
            return
        message = bridge.receive(topic, subscription, timeout_ms, expected_request_id if isinstance(expected_request_id, str) else None)
        if message is None:
            self.respond_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": "receive_timeout", "topic": topic})
            return
        message_payload, properties = message
        self.respond_json(
            HTTPStatus.OK,
            {
                "topic": topic,
                "payloadBase64": base64.b64encode(message_payload).decode("ascii"),
                "properties": properties,
            },
        )

    def read_body(self) -> bytes:
        content_length = self.headers.get("Content-Length")
        if content_length is None:
            return b""
        return self.rfile.read(int(content_length))

    def read_json_body(self) -> dict | None:
        try:
            payload = json.loads(self.read_body().decode("utf-8") or "{}")
        except json.JSONDecodeError as exc:
            self.respond_json(HTTPStatus.BAD_REQUEST, {"error": "invalid_json", "detail": str(exc)})
            return None
        if not isinstance(payload, dict):
            self.respond_json(HTTPStatus.BAD_REQUEST, {"error": "invalid_json_payload"})
            return None
        return payload

    def proxy_request(self, target_url: str, headers: dict[str, str] | None = None) -> None:
        body = self.read_body()
        forwarded_headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in HOP_BY_HOP_HEADERS and key.lower() != "host"
        }
        for key, value in (headers or {}).items():
            forwarded_headers[key] = value
        request = urllib.request.Request(
            target_url,
            data=body if self.command not in {"GET", "HEAD"} else None,
            headers=forwarded_headers,
            method=self.command,
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = response.read()
                self.send_response(response.status)
                for header, value in response.getheaders():
                    if header.lower() in HOP_BY_HOP_HEADERS or header.lower() == "content-length":
                        continue
                    self.send_header(header, value)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(payload)
        except urllib.error.HTTPError as exc:
            payload = exc.read()
            self.send_response(exc.code)
            for header, value in exc.headers.items():
                if header.lower() in HOP_BY_HOP_HEADERS or header.lower() == "content-length":
                    continue
                self.send_header(header, value)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(payload)
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            self.respond_json(HTTPStatus.BAD_GATEWAY, {"error": str(exc), "targetUrl": target_url})

    def log_message(self, format: str, *args: object) -> None:
        return

    def respond_html(self, html: str) -> None:
        body = html.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def respond_json(self, status: HTTPStatus, payload: object) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def respond_bytes(self, status: HTTPStatus, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)


def main() -> int:
    bind_host = os.environ.get("INFERNIX_BIND_HOST", "0.0.0.0")
    port = int(os.environ.get("INFERNIX_PORT", "8080"))
    surface = os.environ.get("INFERNIX_PORTAL_SURFACE", "harbor")
    server = ThreadingHTTPServer((bind_host, port), PortalHandler)
    server.surface = surface  # type: ignore[attr-defined]
    server.minio_bridge = None  # type: ignore[attr-defined]
    server.pulsar_bridge = None  # type: ignore[attr-defined]
    if surface == "minio":
        server.minio_bridge = MinioBridge(  # type: ignore[attr-defined]
            os.environ["INFERNIX_MINIO_S3_ENDPOINT"],
            os.environ["INFERNIX_MINIO_ACCESS_KEY"],
            os.environ["INFERNIX_MINIO_SECRET_KEY"],
        )
    if surface == "pulsar":
        server.pulsar_bridge = PulsarBridge(  # type: ignore[attr-defined]
            os.environ["INFERNIX_PULSAR_SERVICE_URL"],
            os.environ.get("INFERNIX_PULSAR_TENANT", "public"),
            os.environ.get("INFERNIX_PULSAR_NAMESPACE", "default"),
        )
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
