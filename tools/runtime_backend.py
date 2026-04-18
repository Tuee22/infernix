#!/usr/bin/env python3

from __future__ import annotations

import base64
import io
import json
import os
import pathlib
import shutil
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Iterable

import pulsar
from google.protobuf.descriptor import Descriptor, FieldDescriptor
from minio import Minio
from minio.error import S3Error

_GENERATED_PROTO_ROOT = pathlib.Path(__file__).resolve().parent / "generated_proto"
if str(_GENERATED_PROTO_ROOT) not in os.sys.path:
    os.sys.path.insert(0, str(_GENERATED_PROTO_ROOT))

from infernix.manifest import runtime_manifest_pb2
from infernix.runtime import inference_pb2


REQUEST_TOPIC = "infernix-inference-requests"
RESULT_TOPIC = "infernix-inference-results"
COORDINATION_TOPIC = "infernix-runtime-manifests"


@dataclass(frozen=True)
class ExternalBackendConfig:
    minio_endpoint: str
    minio_access_key: str
    minio_secret_key: str
    runtime_bucket: str
    results_bucket: str
    pulsar_admin_url: str
    pulsar_service_url: str
    pulsar_tenant: str
    pulsar_namespace: str
    edge_bridge_base_url: str | None = None


class RuntimeBackend:
    def __init__(
        self,
        *,
        paths: dict[str, pathlib.Path],
        runtime_mode: str,
        control_plane_context: str,
        daemon_location: str,
        publication_state: dict,
    ) -> None:
        self.paths = paths
        self.runtime_mode = runtime_mode
        self.control_plane_context = control_plane_context
        self.daemon_location = daemon_location
        self.publication_state = publication_state
        self.external_config = resolve_external_backend_config(publication_state, daemon_location)
        self.minio: Minio | None = None
        self.runtime_bucket: str | None = None
        self.results_bucket: str | None = None
        self.edge_bridge_base_url: str | None = None
        self.pulsar_client: pulsar.Client | None = None
        self.request_producer: pulsar.Producer | None = None
        self.result_producer: pulsar.Producer | None = None
        self.coordination_producer: pulsar.Producer | None = None
        self.request_consumer: pulsar.Consumer | None = None
        self.result_consumer: pulsar.Consumer | None = None
        self.backend_access_mode = "filesystem-fallback"
        if self.external_config is not None:
            self._initialize_external_backends(self.external_config)

    def close(self) -> None:
        if self.request_consumer is not None:
            self.request_consumer.close()
        if self.result_consumer is not None:
            self.result_consumer.close()
        if self.request_producer is not None:
            self.request_producer.close()
        if self.result_producer is not None:
            self.result_producer.close()
        if self.coordination_producer is not None:
            self.coordination_producer.close()
        if self.pulsar_client is not None:
            self.pulsar_client.close()

    def list_cache_entries(self) -> list[dict]:
        manifests = list(self._list_manifest_messages())
        entries: list[dict] = []
        for manifest in manifests:
            if not manifest.cache_entries:
                continue
            cache_entry = manifest.cache_entries[0]
            materialization = manifest.materializations[0] if manifest.materializations else None
            local_cache_path = self.paths["model_cache_root"] / self.runtime_mode / cache_entry.model_id / cache_entry.cache_key
            entries.append(
                {
                    "runtimeMode": cache_entry.runtime_mode or self.runtime_mode,
                    "modelId": cache_entry.model_id,
                    "selectedEngine": materialization.selected_engine if materialization is not None else "",
                    "durableSourceUri": materialization.durable_source_uri if materialization is not None else "",
                    "cacheKey": cache_entry.cache_key,
                    "cachePath": str(local_cache_path),
                    "materialized": (local_cache_path / "materialized.txt").exists(),
                }
            )
        return entries

    def evict_cache(self, model_id: str | None) -> list[dict]:
        entries = self.list_cache_entries()
        targets = [entry for entry in entries if model_id is None or entry["modelId"] == model_id]
        for entry in targets:
            cache_root = pathlib.Path(entry["cachePath"])
            if cache_root.exists():
                shutil.rmtree(cache_root, ignore_errors=True)
        return targets

    def rebuild_cache(self, catalog: list[dict], model_id: str | None) -> list[dict]:
        catalog_by_id = {model["modelId"]: model for model in catalog}
        entries = self.list_cache_entries()
        targets = [entry for entry in entries if model_id is None or entry["modelId"] == model_id]
        rebuilt: list[dict] = []
        for entry in targets:
            model = catalog_by_id.get(entry["modelId"])
            if model is None:
                continue
            rebuilt.append(self.materialize_cache(model))
        return rebuilt

    def submit_inference(self, model: dict, input_text: str) -> dict:
        request_id = f"req-{int(time.time() * 1000)}"
        request_message = inference_pb2.InferenceRequest(
            request_id=request_id,
            request_model_id=model["modelId"],
            input_text=input_text,
            runtime_mode=self.runtime_mode,
        )
        inbound_request = self._publish_and_receive_request(request_message)
        self.materialize_cache(model)
        output_text = run_model(model, inbound_request.input_text)
        payload = inference_pb2.ResultPayload()
        object_ref: str | None = None
        if len(output_text) > 80:
            object_ref = f"results/{request_id}.txt"
            payload.object_ref = object_ref
            self._store_large_output(object_ref, output_text)
        else:
            payload.inline_output = output_text
        result_message = inference_pb2.InferenceResult(
            request_id=request_id,
            result_model_id=model["modelId"],
            matrix_row_id=model["matrixRowId"],
            runtime_mode=self.runtime_mode,
            selected_engine=model["selectedEngine"],
            status="completed",
            payload=payload,
            created_at=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        )
        self._store_result_message(result_message)
        stored_result = self._publish_and_receive_result(result_message)
        if stored_result is None:
            stored_result = result_message
        return inference_result_to_json(stored_result)

    def load_result(self, request_id: str) -> dict | None:
        raw_payload = self._load_result_bytes(request_id)
        if raw_payload is None:
            return None
        message = inference_pb2.InferenceResult()
        message.ParseFromString(raw_payload)
        return inference_result_to_json(message)

    def load_object(self, object_ref: str) -> bytes | None:
        if self.edge_bridge_base_url is not None and self.results_bucket is not None:
            payload = bridge_get_object(self.external_config, self.results_bucket, object_ref)
            if payload is not None:
                return payload
        if self.minio is not None and self.results_bucket is not None:
            try:
                response = self.minio.get_object(self.results_bucket, object_ref)
                try:
                    return response.read()
                finally:
                    response.close()
                    response.release_conn()
            except S3Error as exc:
                if exc.code != "NoSuchKey":
                    raise
        object_path = self.paths["object_store_root"] / object_ref
        if object_path.exists():
            return object_path.read_bytes()
        return None

    def materialize_cache(self, model: dict) -> dict:
        cache_dir = self.paths["model_cache_root"] / self.runtime_mode / model["modelId"] / "default"
        cache_dir.mkdir(parents=True, exist_ok=True)
        (cache_dir / "materialized.txt").write_text(
            f"materialized from {model['downloadUrl']} via {model['selectedEngine']}\n",
            encoding="utf-8",
        )
        manifest = runtime_manifest_pb2.RuntimeManifest(
            manifest_id=f"{self.runtime_mode}:{model['modelId']}:default",
            runtime_mode=self.runtime_mode,
            durable_results_prefix=f"s3://{self.results_bucket or 'infernix-results'}/results/{self.runtime_mode}",
        )
        manifest.materializations.add(
            runtime_mode=self.runtime_mode,
            model_id=model["modelId"],
            selected_engine=model["selectedEngine"],
            durable_source_uri=model["downloadUrl"],
            materialized_cache_path=str(cache_dir),
        )
        manifest.cache_entries.add(
            runtime_mode=self.runtime_mode,
            model_id=model["modelId"],
            cache_key="default",
            cache_path=str(cache_dir),
            materialized=True,
        )
        manifest_bytes = manifest.SerializeToString()
        manifest_key = f"manifests/{self.runtime_mode}/{model['modelId']}/default.pb"
        self._store_runtime_object(manifest_key, manifest_bytes)
        if self.coordination_producer is not None:
            self.coordination_producer.send(
                manifest_bytes,
                properties={
                    "runtimeMode": self.runtime_mode,
                    "modelId": model["modelId"],
                    "manifestId": manifest.manifest_id,
                },
            )
        return {
            "runtimeMode": self.runtime_mode,
            "modelId": model["modelId"],
            "selectedEngine": model["selectedEngine"],
            "durableSourceUri": model["downloadUrl"],
            "cacheKey": "default",
            "cachePath": str(cache_dir),
            "materialized": True,
        }

    def _initialize_external_backends(self, config: ExternalBackendConfig) -> None:
        self.edge_bridge_base_url = config.edge_bridge_base_url
        self.runtime_bucket = config.runtime_bucket
        self.results_bucket = config.results_bucket
        if self.edge_bridge_base_url is not None:
            self.backend_access_mode = "edge-route-bridge"
            ensure_bridge_bucket(config, config.runtime_bucket)
            ensure_bridge_bucket(config, config.results_bucket)
            ensure_pulsar_schema(
                config,
                REQUEST_TOPIC,
                descriptor_to_schema_payload(inference_pb2.InferenceRequest.DESCRIPTOR),
            )
            ensure_pulsar_schema(
                config,
                RESULT_TOPIC,
                descriptor_to_schema_payload(inference_pb2.InferenceResult.DESCRIPTOR),
            )
            ensure_pulsar_schema(
                config,
                COORDINATION_TOPIC,
                descriptor_to_schema_payload(runtime_manifest_pb2.RuntimeManifest.DESCRIPTOR),
            )
            return
        minio_endpoint, minio_secure = parse_minio_endpoint(config.minio_endpoint)
        self.minio = Minio(
            minio_endpoint,
            access_key=config.minio_access_key,
            secret_key=config.minio_secret_key,
            secure=minio_secure,
        )
        self.backend_access_mode = "cluster-local"
        ensure_bucket(self.minio, config.runtime_bucket)
        ensure_bucket(self.minio, config.results_bucket)
        ensure_pulsar_schema(
            config,
            REQUEST_TOPIC,
            descriptor_to_schema_payload(inference_pb2.InferenceRequest.DESCRIPTOR),
        )
        ensure_pulsar_schema(
            config,
            RESULT_TOPIC,
            descriptor_to_schema_payload(inference_pb2.InferenceResult.DESCRIPTOR),
        )
        ensure_pulsar_schema(
            config,
            COORDINATION_TOPIC,
            descriptor_to_schema_payload(runtime_manifest_pb2.RuntimeManifest.DESCRIPTOR),
        )
        self.pulsar_client = pulsar.Client(config.pulsar_service_url)
        self.request_producer = self.pulsar_client.create_producer(topic_name(config, REQUEST_TOPIC))
        self.result_producer = self.pulsar_client.create_producer(topic_name(config, RESULT_TOPIC))
        self.coordination_producer = self.pulsar_client.create_producer(topic_name(config, COORDINATION_TOPIC))
        request_subscription = f"infernix-service-{self.daemon_location}-requests"
        result_subscription = f"infernix-service-{self.daemon_location}-results"
        self.request_consumer = self.pulsar_client.subscribe(
            topic_name(config, REQUEST_TOPIC),
            request_subscription,
            consumer_type=pulsar.ConsumerType.Exclusive,
        )
        self.result_consumer = self.pulsar_client.subscribe(
            topic_name(config, RESULT_TOPIC),
            result_subscription,
            consumer_type=pulsar.ConsumerType.Exclusive,
        )

    def _list_manifest_messages(self) -> Iterable[runtime_manifest_pb2.RuntimeManifest]:
        if self.edge_bridge_base_url is not None and self.runtime_bucket is not None:
            prefix = f"manifests/{self.runtime_mode}/"
            for object_name in bridge_list_objects(self.external_config, self.runtime_bucket, prefix):
                payload = bridge_get_object(self.external_config, self.runtime_bucket, object_name)
                if payload is None:
                    continue
                manifest = runtime_manifest_pb2.RuntimeManifest()
                manifest.ParseFromString(payload)
                yield manifest
            return
        if self.minio is not None and self.runtime_bucket is not None:
            prefix = f"manifests/{self.runtime_mode}/"
            for item in self.minio.list_objects(self.runtime_bucket, prefix=prefix, recursive=True):
                response = self.minio.get_object(self.runtime_bucket, item.object_name)
                try:
                    payload = response.read()
                finally:
                    response.close()
                    response.release_conn()
                manifest = runtime_manifest_pb2.RuntimeManifest()
                manifest.ParseFromString(payload)
                yield manifest
            return

        manifest_root = self.paths["object_store_root"] / "manifests" / self.runtime_mode
        if not manifest_root.exists():
            return
        for manifest_path in sorted(manifest_root.glob("*/default.pb")):
            manifest = runtime_manifest_pb2.RuntimeManifest()
            manifest.ParseFromString(manifest_path.read_bytes())
            yield manifest

    def _publish_and_receive_request(
        self, request_message: inference_pb2.InferenceRequest
    ) -> inference_pb2.InferenceRequest:
        if self.edge_bridge_base_url is not None and self.external_config is not None:
            bridge_publish_message(
                self.external_config,
                REQUEST_TOPIC,
                request_message.SerializeToString(),
                {
                    "requestId": request_message.request_id,
                    "runtimeMode": request_message.runtime_mode,
                    "modelId": request_message.request_model_id,
                },
            )
            return request_message
        if self.request_producer is None or self.request_consumer is None:
            return request_message
        self.request_producer.send(
            request_message.SerializeToString(),
            properties={
                "requestId": request_message.request_id,
                "runtimeMode": request_message.runtime_mode,
                "modelId": request_message.request_model_id,
            },
        )
        return self._receive_request_message(request_message.request_id)

    def _publish_and_receive_result(
        self, result_message: inference_pb2.InferenceResult
    ) -> inference_pb2.InferenceResult | None:
        if self.edge_bridge_base_url is not None and self.external_config is not None:
            bridge_publish_message(
                self.external_config,
                RESULT_TOPIC,
                result_message.SerializeToString(),
                {
                    "requestId": result_message.request_id,
                    "runtimeMode": result_message.runtime_mode,
                    "modelId": result_message.result_model_id,
                },
            )
            return result_message
        if self.result_producer is None or self.result_consumer is None:
            return None
        self.result_producer.send(
            result_message.SerializeToString(),
            properties={
                "requestId": result_message.request_id,
                "runtimeMode": result_message.runtime_mode,
                "modelId": result_message.result_model_id,
            },
        )
        return self._receive_result_message(result_message.request_id)

    def _receive_request_message(self, request_id: str) -> inference_pb2.InferenceRequest:
        assert self.request_consumer is not None
        deadline = time.time() + 15
        while time.time() < deadline:
            try:
                message = self.request_consumer.receive(timeout_millis=3000)
            except pulsar.Timeout:
                continue
            request_message = inference_pb2.InferenceRequest()
            request_message.ParseFromString(message.data())
            self.request_consumer.acknowledge(message)
            if request_message.request_id == request_id:
                return request_message
        raise TimeoutError(f"timed out waiting for request topic delivery for {request_id}")

    def _receive_result_message(self, request_id: str) -> inference_pb2.InferenceResult:
        assert self.result_consumer is not None
        deadline = time.time() + 15
        while time.time() < deadline:
            try:
                message = self.result_consumer.receive(timeout_millis=3000)
            except pulsar.Timeout:
                continue
            result_message = inference_pb2.InferenceResult()
            result_message.ParseFromString(message.data())
            self.result_consumer.acknowledge(message)
            if result_message.request_id == request_id:
                return result_message
        raise TimeoutError(f"timed out waiting for result topic delivery for {request_id}")

    def _store_result_message(self, result_message: inference_pb2.InferenceResult) -> None:
        result_key = f"results/{result_message.request_id}.pb"
        self._store_runtime_object(result_key, result_message.SerializeToString())
        local_path = self.paths["results_root"] / f"{result_message.request_id}.pb"
        local_path.parent.mkdir(parents=True, exist_ok=True)
        local_path.write_bytes(result_message.SerializeToString())

    def _load_result_bytes(self, request_id: str) -> bytes | None:
        result_key = f"results/{request_id}.pb"
        if self.edge_bridge_base_url is not None and self.runtime_bucket is not None:
            payload = bridge_get_object(self.external_config, self.runtime_bucket, result_key)
            if payload is not None:
                return payload
        if self.minio is not None and self.runtime_bucket is not None:
            try:
                response = self.minio.get_object(self.runtime_bucket, result_key)
                try:
                    return response.read()
                finally:
                    response.close()
                    response.release_conn()
            except S3Error as exc:
                if exc.code != "NoSuchKey":
                    raise
        local_path = self.paths["results_root"] / f"{request_id}.pb"
        if local_path.exists():
            return local_path.read_bytes()
        return None

    def _store_large_output(self, object_ref: str, output_text: str) -> None:
        payload = output_text.encode("utf-8")
        if self.edge_bridge_base_url is not None and self.results_bucket is not None:
            bridge_put_object(
                self.external_config,
                self.results_bucket,
                object_ref,
                payload,
                "text/plain; charset=utf-8",
            )
        if self.minio is not None and self.results_bucket is not None:
            self.minio.put_object(
                self.results_bucket,
                object_ref,
                io.BytesIO(payload),
                len(payload),
                content_type="text/plain; charset=utf-8",
            )
        object_path = self.paths["object_store_root"] / object_ref
        object_path.parent.mkdir(parents=True, exist_ok=True)
        object_path.write_text(output_text, encoding="utf-8")

    def _store_runtime_object(self, key: str, payload: bytes) -> None:
        if self.edge_bridge_base_url is not None and self.runtime_bucket is not None:
            bridge_put_object(
                self.external_config,
                self.runtime_bucket,
                key,
                payload,
                "application/octet-stream",
            )
        if self.minio is not None and self.runtime_bucket is not None:
            self.minio.put_object(
                self.runtime_bucket,
                key,
                io.BytesIO(payload),
                len(payload),
                content_type="application/octet-stream",
            )
        local_path = self.paths["object_store_root"] / key
        local_path.parent.mkdir(parents=True, exist_ok=True)
        local_path.write_bytes(payload)


def resolve_external_backend_config(publication_state: dict, daemon_location: str) -> ExternalBackendConfig | None:
    cluster_present = publication_state.get("clusterPresent")
    has_explicit_env = any(
        os.environ.get(name)
        for name in (
            "INFERNIX_MINIO_ENDPOINT",
            "INFERNIX_PULSAR_ADMIN_URL",
            "INFERNIX_PULSAR_SERVICE_URL",
        )
    )
    if not cluster_present and not has_explicit_env:
        return None
    if daemon_location == "cluster-pod":
        default_minio_endpoint = "http://infernix-minio.platform.svc.cluster.local:9000"
        default_pulsar_admin_url = "http://infernix-infernix-pulsar-proxy.platform.svc.cluster.local/admin/v2"
        default_pulsar_service_url = "pulsar://infernix-infernix-pulsar-proxy.platform.svc.cluster.local:6650"
        default_edge_bridge_base_url = None
    else:
        edge_port = publication_state.get("edgePort")
        default_edge_bridge_base_url = (
            f"http://127.0.0.1:{edge_port}"
            if isinstance(edge_port, int) and edge_port > 0
            else None
        )
        default_minio_endpoint = (
            f"{default_edge_bridge_base_url}/minio/s3"
            if default_edge_bridge_base_url is not None
            else "http://127.0.0.1:30011"
        )
        default_pulsar_admin_url = (
            f"{default_edge_bridge_base_url}/pulsar/admin"
            if default_edge_bridge_base_url is not None
            else "http://127.0.0.1:30080/admin/v2"
        )
        default_pulsar_service_url = (
            f"{default_edge_bridge_base_url}/pulsar/ws"
            if default_edge_bridge_base_url is not None
            else "pulsar://127.0.0.1:30650"
        )
    return ExternalBackendConfig(
        minio_endpoint=os.environ.get("INFERNIX_MINIO_ENDPOINT", default_minio_endpoint),
        minio_access_key=os.environ.get("INFERNIX_MINIO_ACCESS_KEY", "minioadmin"),
        minio_secret_key=os.environ.get("INFERNIX_MINIO_SECRET_KEY", "minioadmin123"),
        runtime_bucket=os.environ.get("INFERNIX_MINIO_RUNTIME_BUCKET", "infernix-runtime"),
        results_bucket=os.environ.get("INFERNIX_MINIO_RESULTS_BUCKET", "infernix-results"),
        pulsar_admin_url=os.environ.get("INFERNIX_PULSAR_ADMIN_URL", default_pulsar_admin_url),
        pulsar_service_url=os.environ.get("INFERNIX_PULSAR_SERVICE_URL", default_pulsar_service_url),
        pulsar_tenant=os.environ.get("INFERNIX_PULSAR_TENANT", "public"),
        pulsar_namespace=os.environ.get("INFERNIX_PULSAR_NAMESPACE", "default"),
        edge_bridge_base_url=os.environ.get("INFERNIX_EDGE_BRIDGE_BASE_URL", default_edge_bridge_base_url),
    )


def ensure_bucket(client: Minio, bucket_name: str) -> None:
    if not client.bucket_exists(bucket_name):
        client.make_bucket(bucket_name)


def ensure_bridge_bucket(config: ExternalBackendConfig, bucket_name: str) -> None:
    bridge_request(
        config,
        "PUT",
        f"/minio/s3/_infernix/bridge/buckets/{urllib.parse.quote(bucket_name, safe='')}",
        expected_statuses={200},
    )


def ensure_pulsar_schema(config: ExternalBackendConfig, topic: str, schema_payload: dict[str, object]) -> None:
    url = schema_url(config, topic)
    current_payload = fetch_pulsar_schema(url)
    if current_payload is not None and current_payload.get("type") == schema_payload["type"] and current_payload.get("data") == schema_payload["schema"]:
        return
    publish_pulsar_schema(url, schema_payload)


def bridge_request(
    config: ExternalBackendConfig | None,
    method: str,
    path: str,
    *,
    payload: bytes | None = None,
    headers: dict[str, str] | None = None,
    expected_statuses: set[int] | None = None,
) -> tuple[int, bytes]:
    if config is None or config.edge_bridge_base_url is None:
        raise RuntimeError("edge bridge is not configured")
    request = urllib.request.Request(
        config.edge_bridge_base_url.rstrip("/") + path,
        data=payload,
        headers=headers or {},
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read()
            if expected_statuses is not None and response.status not in expected_statuses:
                raise RuntimeError(f"unexpected edge-bridge status {response.status} for {path}")
            return response.status, body
    except urllib.error.HTTPError as exc:
        body = exc.read()
        if expected_statuses is not None and exc.code in expected_statuses:
            return exc.code, body
        raise RuntimeError(f"edge bridge request failed: {method} {path} -> {exc.code} {body.decode('utf-8', errors='replace')}")


def bridge_put_object(
    config: ExternalBackendConfig | None,
    bucket_name: str,
    object_name: str,
    payload: bytes,
    content_type: str,
) -> None:
    bridge_request(
        config,
        "PUT",
        f"/minio/s3/_infernix/bridge/objects/{urllib.parse.quote(bucket_name, safe='')}/{urllib.parse.quote(object_name, safe='/')}",
        payload=payload,
        headers={"Content-Type": content_type},
        expected_statuses={200},
    )


def bridge_get_object(config: ExternalBackendConfig | None, bucket_name: str, object_name: str) -> bytes | None:
    status, body = bridge_request(
        config,
        "GET",
        f"/minio/s3/_infernix/bridge/objects/{urllib.parse.quote(bucket_name, safe='')}/{urllib.parse.quote(object_name, safe='/')}",
        expected_statuses={200, 404},
    )
    return body if status == 200 else None


def bridge_list_objects(config: ExternalBackendConfig | None, bucket_name: str, prefix: str) -> list[str]:
    _, body = bridge_request(
        config,
        "GET",
        f"/minio/s3/_infernix/bridge/buckets/{urllib.parse.quote(bucket_name, safe='')}?prefix={urllib.parse.quote(prefix, safe='/')}",
        expected_statuses={200},
    )
    payload = json.loads(body.decode("utf-8"))
    return [item for item in payload.get("objects", []) if isinstance(item, str)]


def bridge_publish_message(
    config: ExternalBackendConfig | None,
    topic: str,
    payload: bytes,
    properties: dict[str, str],
) -> None:
    bridge_request(
        config,
        "POST",
        f"/pulsar/ws/_infernix/bridge/topics/{urllib.parse.quote(topic, safe='')}/publish",
        payload=json.dumps(
            {
                "payloadBase64": base64_bytes(payload),
                "properties": properties,
            }
        ).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        expected_statuses={200},
    )


def bridge_receive_message(
    config: ExternalBackendConfig | None,
    topic: str,
    subscription: str,
    request_id: str,
) -> bytes:
    _, body = bridge_request(
        config,
        "POST",
        f"/pulsar/ws/_infernix/bridge/topics/{urllib.parse.quote(topic, safe='')}/receive",
        payload=json.dumps(
            {
                "subscription": subscription,
                "timeoutMs": 15000,
                "requestId": request_id,
            }
        ).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        expected_statuses={200},
    )
    payload = json.loads(body.decode("utf-8"))
    return base64_to_bytes(payload["payloadBase64"])


def base64_bytes(payload: bytes) -> str:
    return base64.b64encode(payload).decode("ascii")


def base64_to_bytes(payload: str) -> bytes:
    return base64.b64decode(payload.encode("ascii"))


def fetch_pulsar_schema(url: str, *, attempts: int = 12) -> dict[str, object] | None:
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        request = urllib.request.Request(url, method="GET")
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return None
            if exc.code in {502, 503, 504} and attempt < attempts:
                last_error = exc
                time.sleep(attempt)
                continue
            raise
        except (urllib.error.URLError, OSError) as exc:
            if attempt < attempts:
                last_error = exc
                time.sleep(attempt)
                continue
            raise
    if last_error is not None:
        raise last_error
    return None


def publish_pulsar_schema(url: str, schema_payload: dict[str, object], *, attempts: int = 12) -> None:
    payload_bytes = json.dumps(schema_payload).encode("utf-8")
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        upload_request = urllib.request.Request(
            url,
            data=payload_bytes,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(upload_request, timeout=10):
                return
        except urllib.error.HTTPError as exc:
            if exc.code == 409:
                current_payload = fetch_pulsar_schema(url, attempts=1)
                if current_payload is not None and current_payload.get("type") == schema_payload["type"] and current_payload.get("data") == schema_payload["schema"]:
                    return
            if exc.code in {502, 503, 504} and attempt < attempts:
                last_error = exc
                time.sleep(attempt)
                continue
            raise
        except (urllib.error.URLError, OSError) as exc:
            if attempt < attempts:
                last_error = exc
                time.sleep(attempt)
                continue
            raise
    if last_error is not None:
        raise last_error


def topic_name(config: ExternalBackendConfig, topic: str) -> str:
    return f"persistent://{config.pulsar_tenant}/{config.pulsar_namespace}/{topic}"


def schema_url(config: ExternalBackendConfig, topic: str) -> str:
    base_url = config.pulsar_admin_url.rstrip("/")
    return f"{base_url}/schemas/{config.pulsar_tenant}/{config.pulsar_namespace}/{topic}/schema"


def parse_minio_endpoint(endpoint: str) -> tuple[str, bool]:
    parsed = urllib.parse.urlparse(endpoint if "://" in endpoint else f"http://{endpoint}")
    host = parsed.netloc or parsed.path
    if parsed.path not in {"", "/"} and parsed.netloc:
        raise ValueError(f"MinIO endpoint must not contain a path prefix: {endpoint}")
    return host, parsed.scheme == "https"


def descriptor_to_schema_payload(descriptor: Descriptor) -> dict[str, object]:
    return {
        "type": "PROTOBUF",
        "schema": json.dumps(descriptor_to_avro_record(descriptor), separators=(",", ":")),
        "properties": {},
    }


def descriptor_to_avro_record(descriptor: Descriptor) -> dict[str, object]:
    fields: list[dict[str, object]] = []
    for field in descriptor.fields:
        avro_type = field_to_avro_type(field)
        entry: dict[str, object] = {"name": field.name, "type": avro_type}
        if isinstance(avro_type, list):
            entry["default"] = None
        fields.append(entry)
    return {
        "type": "record",
        "name": descriptor.name,
        "namespace": descriptor.file.package,
        "fields": fields,
    }


def field_to_avro_type(field: FieldDescriptor) -> object:
    base_type: object
    if field.type == FieldDescriptor.TYPE_STRING:
        base_type = "string"
    elif field.type == FieldDescriptor.TYPE_BOOL:
        base_type = "boolean"
    elif field.type in {FieldDescriptor.TYPE_INT32, FieldDescriptor.TYPE_SINT32, FieldDescriptor.TYPE_FIXED32}:
        base_type = "int"
    elif field.type in {FieldDescriptor.TYPE_INT64, FieldDescriptor.TYPE_SINT64, FieldDescriptor.TYPE_FIXED64}:
        base_type = "long"
    elif field.type == FieldDescriptor.TYPE_MESSAGE:
        base_type = descriptor_to_avro_record(field.message_type)
    else:
        base_type = "string"
    if field.is_repeated:
        return {"type": "array", "items": base_type}
    if field.containing_oneof is not None:
        return ["null", base_type]
    return base_type


def inference_result_to_json(message: inference_pb2.InferenceResult) -> dict:
    payload = {"inlineOutput": None, "objectRef": None}
    output_field = message.payload.WhichOneof("output")
    if output_field == "inline_output":
        payload["inlineOutput"] = message.payload.inline_output
    elif output_field == "object_ref":
        payload["objectRef"] = message.payload.object_ref
    return {
        "requestId": message.request_id,
        "resultModelId": message.result_model_id,
        "matrixRowId": message.matrix_row_id,
        "runtimeMode": message.runtime_mode,
        "selectedEngine": message.selected_engine,
        "status": message.status,
        "payload": payload,
        "createdAt": message.created_at,
    }


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
