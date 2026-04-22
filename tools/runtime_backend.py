#!/usr/bin/env python3

from __future__ import annotations

import base64
import importlib.util
import io
import json
import mimetypes
import os
import pathlib
import shutil
import subprocess
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
ARTIFACT_BUNDLE_NAME = "bundle.json"


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


@dataclass(frozen=True)
class RuntimeArtifact:
    object_key: str
    local_object_path: pathlib.Path
    durable_source_uri: str
    bundle_metadata: dict[str, object]


@dataclass(frozen=True)
class SourceArtifactSelection:
    selection_mode: str
    authoritative_uri: str
    authoritative_kind: str
    selected_artifacts: list[dict[str, object]]


@dataclass(frozen=True)
class SourceArtifact:
    payload_object_key: str | None
    payload_local_path: pathlib.Path | None
    payload_uri: str
    manifest_object_key: str
    manifest_local_path: pathlib.Path
    manifest_uri: str
    acquisition_mode: str
    fetch_status: str
    resolved_url: str
    content_type: str
    error: str
    selection_mode: str
    authoritative_uri: str
    authoritative_kind: str
    selected_artifacts: list[dict[str, object]]


@dataclass
class WorkerHandle:
    artifact_bundle_path: pathlib.Path
    process: subprocess.Popen[str]


class RuntimeBackend:
    def __init__(
        self,
        *,
        paths: dict[str, pathlib.Path],
        runtime_mode: str,
        control_plane_context: str,
        daemon_location: str,
        publication_state: dict,
        allow_filesystem_fallback: bool = False,
    ) -> None:
        self.paths = paths
        self.runtime_mode = runtime_mode
        self.control_plane_context = control_plane_context
        self.daemon_location = daemon_location
        self.publication_state = publication_state
        self.allow_filesystem_fallback = allow_filesystem_fallback
        self.external_config = resolve_external_backend_config(publication_state, daemon_location)
        self.source_artifact_overrides = parse_source_artifact_overrides()
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
        self.backend_access_mode = "filesystem-fixture"
        self.worker_execution_mode = "process-isolated-engine-workers"
        self.worker_adapter_mode = worker_adapter_mode_from_environment()
        self.artifact_acquisition_mode = "engine-ready-artifact-manifests"
        self.worker_handles: dict[tuple[str, str, str], WorkerHandle] = {}
        if self.external_config is not None:
            self._initialize_external_backends(self.external_config)
        elif not self.allow_filesystem_fallback:
            raise RuntimeError(
                "service runtime requires a MinIO and Pulsar backend; "
                "filesystem-fixture mode must be enabled explicitly for local fixture ownership"
            )

    def close(self) -> None:
        for worker_handle in self.worker_handles.values():
            self._terminate_worker(worker_handle)
        self.worker_handles.clear()
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
            durable_source_uri = materialization.durable_source_uri if materialization is not None else ""
            bundle_metadata = self._load_bundle_metadata(durable_source_uri, local_cache_path)
            entries.append(
                {
                    "runtimeMode": cache_entry.runtime_mode or self.runtime_mode,
                    "modelId": cache_entry.model_id,
                    "selectedEngine": materialization.selected_engine if materialization is not None else "",
                    "durableSourceUri": durable_source_uri,
                    "cacheKey": cache_entry.cache_key,
                    "cachePath": str(local_cache_path),
                    "materialized": (local_cache_path / "materialized.txt").exists(),
                    "workerProfile": bundle_string(bundle_metadata, "workerProfile"),
                    "engineAdapterId": bundle_string(bundle_metadata, "engineAdapterId"),
                    "engineAdapterType": bundle_string(bundle_metadata, "engineAdapterType"),
                    "engineAdapterLocator": bundle_string(bundle_metadata, "engineAdapterLocator"),
                    "engineAdapterAvailability": bundle_string(bundle_metadata, "engineAdapterAvailability"),
                    "artifactAcquisitionMode": bundle_string(bundle_metadata, "artifactAcquisitionMode"),
                    "sourceArtifactUri": bundle_string(bundle_metadata, "sourceArtifactUri"),
                    "sourceArtifactManifestUri": bundle_string(bundle_metadata, "sourceArtifactManifestUri"),
                    "sourceArtifactFetchStatus": bundle_string(bundle_metadata, "sourceArtifactFetchStatus"),
                    "sourceArtifactContentType": bundle_string(bundle_metadata, "sourceArtifactContentType"),
                    "sourceArtifactSelectionMode": bundle_string(bundle_metadata, "sourceArtifactSelectionMode"),
                    "sourceArtifactAuthoritativeUri": bundle_string(bundle_metadata, "sourceArtifactAuthoritativeUri"),
                    "sourceArtifactAuthoritativeKind": bundle_string(bundle_metadata, "sourceArtifactAuthoritativeKind"),
                    "sourceArtifactSelectedArtifacts": bundle_list(bundle_metadata, "sourceArtifactSelectedArtifacts"),
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
        output_text = self._execute_worker(model, inbound_request.request_id, inbound_request.input_text)
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
        artifact = self._ensure_runtime_artifact(model)
        artifact_payload = self._load_runtime_object(artifact.object_key)
        if artifact_payload is None:
            raise RuntimeError(f"runtime artifact is missing after materialization: {artifact.object_key}")
        cache_bundle_path = cache_dir / "artifact-bundle.json"
        cache_bundle_path.write_bytes(artifact_payload)
        (cache_dir / "materialized.txt").write_text(
            f"materialized from {artifact.durable_source_uri} via {model['selectedEngine']}\n",
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
            durable_source_uri=artifact.durable_source_uri,
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
            "durableSourceUri": artifact.durable_source_uri,
            "cacheKey": "default",
            "cachePath": str(cache_dir),
            "materialized": True,
            "workerProfile": bundle_string(artifact.bundle_metadata, "workerProfile"),
            "engineAdapterId": bundle_string(artifact.bundle_metadata, "engineAdapterId"),
            "engineAdapterType": bundle_string(artifact.bundle_metadata, "engineAdapterType"),
            "engineAdapterLocator": bundle_string(artifact.bundle_metadata, "engineAdapterLocator"),
            "engineAdapterAvailability": bundle_string(artifact.bundle_metadata, "engineAdapterAvailability"),
            "artifactAcquisitionMode": bundle_string(artifact.bundle_metadata, "artifactAcquisitionMode"),
            "sourceArtifactUri": bundle_string(artifact.bundle_metadata, "sourceArtifactUri"),
            "sourceArtifactManifestUri": bundle_string(artifact.bundle_metadata, "sourceArtifactManifestUri"),
            "sourceArtifactFetchStatus": bundle_string(artifact.bundle_metadata, "sourceArtifactFetchStatus"),
            "sourceArtifactContentType": bundle_string(artifact.bundle_metadata, "sourceArtifactContentType"),
            "sourceArtifactSelectionMode": bundle_string(artifact.bundle_metadata, "sourceArtifactSelectionMode"),
            "sourceArtifactAuthoritativeUri": bundle_string(artifact.bundle_metadata, "sourceArtifactAuthoritativeUri"),
            "sourceArtifactAuthoritativeKind": bundle_string(artifact.bundle_metadata, "sourceArtifactAuthoritativeKind"),
            "sourceArtifactSelectedArtifacts": bundle_list(artifact.bundle_metadata, "sourceArtifactSelectedArtifacts"),
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
            payload = bridge_receive_message(
                self.external_config,
                REQUEST_TOPIC,
                f"infernix-service-{self.daemon_location}-requests",
                request_message.request_id,
            )
            received_request = inference_pb2.InferenceRequest()
            received_request.ParseFromString(payload)
            return received_request
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
            payload = bridge_receive_message(
                self.external_config,
                RESULT_TOPIC,
                f"infernix-service-{self.daemon_location}-results",
                result_message.request_id,
            )
            received_result = inference_pb2.InferenceResult()
            received_result.ParseFromString(payload)
            return received_result
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

    def _load_runtime_object(self, key: str, *, local_root: pathlib.Path | None = None) -> bytes | None:
        if self.edge_bridge_base_url is not None and self.runtime_bucket is not None:
            payload = bridge_get_object(self.external_config, self.runtime_bucket, key)
            if payload is not None:
                return payload
        if self.minio is not None and self.runtime_bucket is not None:
            try:
                response = self.minio.get_object(self.runtime_bucket, key)
                try:
                    return response.read()
                finally:
                    response.close()
                    response.release_conn()
            except S3Error as exc:
                if exc.code != "NoSuchKey":
                    raise
        local_path = (local_root or self.paths["object_store_root"]) / key
        if local_path.exists():
            return local_path.read_bytes()
        return None

    def _ensure_runtime_artifact(self, model: dict) -> RuntimeArtifact:
        object_key = f"artifacts/{self.runtime_mode}/{model['modelId']}/{ARTIFACT_BUNDLE_NAME}"
        local_object_path = self.paths["object_store_root"] / object_key
        source_artifact = self._ensure_source_artifact(model)
        bundle_metadata = build_artifact_bundle(
            model,
            self.runtime_mode,
            source_artifact=source_artifact,
        )
        payload = json.dumps(bundle_metadata, indent=2, sort_keys=True).encode("utf-8")
        current_payload = local_object_path.read_bytes() if local_object_path.exists() else None
        if current_payload != payload:
            self._store_runtime_object(object_key, payload)
        if self.runtime_bucket is not None:
            durable_source_uri = f"s3://{self.runtime_bucket}/{object_key}"
        else:
            durable_source_uri = local_object_path.resolve().as_uri()
        return RuntimeArtifact(
            object_key=object_key,
            local_object_path=local_object_path,
            durable_source_uri=durable_source_uri,
            bundle_metadata=bundle_metadata,
        )

    def _ensure_source_artifact(self, model: dict) -> SourceArtifact:
        source_url = source_artifact_url_for(self.source_artifact_overrides, model)
        prefix = f"source-artifacts/{self.runtime_mode}/{model['modelId']}"
        manifest_object_key = f"{prefix}/source.json"
        manifest_local_path = self.paths["object_store_root"] / manifest_object_key
        existing_source_artifact = load_existing_source_artifact(manifest_local_path)
        if existing_source_artifact is not None:
            return existing_source_artifact
        payload_object_key: str | None = None
        payload_local_path: pathlib.Path | None = None
        payload_uri = ""
        resolved_url = source_url
        content_type = ""
        error = ""
        payload_bytes: bytes | None = None

        local_source_path = local_source_artifact_path(source_url)
        if local_source_path is not None:
            acquisition_mode = "local-file-copy"
            resolved_url = local_source_path.resolve().as_uri()
            content_type = mimetypes.guess_type(local_source_path.name)[0] or "application/octet-stream"
            try:
                payload_bytes = local_source_path.read_bytes()
                fetch_status = "materialized"
            except OSError as exc:
                fetch_status = "unavailable"
                error = str(exc)
        else:
            try:
                (
                    acquisition_mode,
                    fetch_status,
                    resolved_url,
                    content_type,
                    error,
                    payload_bytes,
                ) = fetch_remote_source_artifact(source_url)
            except (urllib.error.URLError, OSError, ValueError, json.JSONDecodeError) as exc:
                acquisition_mode = "direct-upstream-fetch"
                fetch_status = "unavailable"
                error = str(exc)

        if payload_bytes is not None:
            payload_object_key = f"{prefix}/payload.bin"
            payload_local_path = self.paths["object_store_root"] / payload_object_key
            self._store_runtime_object(payload_object_key, payload_bytes)
            if self.runtime_bucket is not None:
                payload_uri = f"s3://{self.runtime_bucket}/{payload_object_key}"
            else:
                payload_uri = payload_local_path.resolve().as_uri()

        selection = select_engine_ready_source_artifacts(
            model=model,
            source_url=source_url,
            resolved_url=resolved_url,
            acquisition_mode=acquisition_mode,
            payload_uri=payload_uri,
            content_type=content_type,
            payload_bytes=payload_bytes,
        )

        if self.runtime_bucket is not None:
            manifest_uri = f"s3://{self.runtime_bucket}/{manifest_object_key}"
        else:
            manifest_uri = manifest_local_path.resolve().as_uri()

        manifest_payload = json.dumps(
            {
                "artifactKind": "infernix-source-artifact",
                "schemaVersion": 1,
                "runtimeMode": self.runtime_mode,
                "modelId": model["modelId"],
                "sourceDownloadUrl": model["downloadUrl"],
                "resolvedSourceUrl": resolved_url,
                "acquisitionMode": acquisition_mode,
                "fetchStatus": fetch_status,
                "contentType": content_type,
                "payloadObjectKey": payload_object_key or "",
                "payloadUri": payload_uri,
                "manifestObjectKey": manifest_object_key,
                "manifestUri": manifest_uri,
                "error": error,
                "selectionMode": selection.selection_mode,
                "authoritativeInputUri": selection.authoritative_uri,
                "authoritativeInputKind": selection.authoritative_kind,
                "selectedArtifacts": selection.selected_artifacts,
            },
            indent=2,
            sort_keys=True,
        ).encode("utf-8")
        self._store_runtime_object(manifest_object_key, manifest_payload)
        return SourceArtifact(
            payload_object_key=payload_object_key,
            payload_local_path=payload_local_path,
            payload_uri=payload_uri,
            manifest_object_key=manifest_object_key,
            manifest_local_path=manifest_local_path,
            manifest_uri=manifest_uri,
            acquisition_mode=acquisition_mode,
            fetch_status=fetch_status,
            resolved_url=resolved_url,
            content_type=content_type,
            error=error,
            selection_mode=selection.selection_mode,
            authoritative_uri=selection.authoritative_uri,
            authoritative_kind=selection.authoritative_kind,
            selected_artifacts=selection.selected_artifacts,
        )

    def _load_bundle_metadata(self, durable_source_uri: str, cache_dir: pathlib.Path) -> dict[str, object]:
        cache_bundle_path = cache_dir / "artifact-bundle.json"
        if cache_bundle_path.exists():
            try:
                return json.loads(cache_bundle_path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                return {}
        bundle_payload = self._load_runtime_object_for_uri(durable_source_uri)
        if bundle_payload is None:
            return {}
        try:
            payload = json.loads(bundle_payload.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return {}
        return payload if isinstance(payload, dict) else {}

    def _load_runtime_object_for_uri(self, durable_source_uri: str) -> bytes | None:
        if durable_source_uri.startswith("s3://"):
            parsed = urllib.parse.urlparse(durable_source_uri)
            bucket_name = parsed.netloc
            object_key = parsed.path.lstrip("/")
            if bucket_name != (self.runtime_bucket or bucket_name):
                return None
            return self._load_runtime_object(object_key)
        if durable_source_uri.startswith("file://"):
            local_path = pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(durable_source_uri).path))
            if local_path.exists():
                return local_path.read_bytes()
            return None
        local_path = pathlib.Path(durable_source_uri)
        if local_path.exists():
            return local_path.read_bytes()
        return None

    def _execute_worker(self, model: dict, request_id: str, input_text: str) -> str:
        payload = json.dumps(
            {
                "requestId": request_id,
                "requestModelId": model["modelId"],
                "runtimeMode": self.runtime_mode,
                "inputText": input_text,
            }
        )
        try:
            return self._execute_worker_once(model, request_id, payload)
        except (BrokenPipeError, OSError, RuntimeError, json.JSONDecodeError):
            self._restart_worker(model)
            return self._execute_worker_once(model, request_id, payload)

    def _execute_worker_once(self, model: dict, request_id: str, payload: str) -> str:
        worker_handle = self._ensure_worker(model)
        stdin = worker_handle.process.stdin
        stdout = worker_handle.process.stdout
        if stdin is None or stdout is None:
            raise RuntimeError("worker process did not expose stdio pipes")
        stdin.write(payload + "\n")
        stdin.flush()
        response_line = stdout.readline()
        if response_line == "":
            raise RuntimeError(f"worker exited before responding for {model['modelId']}")
        response = json.loads(response_line)
        if response.get("requestId") != request_id:
            raise RuntimeError(f"worker returned a mismatched request id for {model['modelId']}")
        error_message = response.get("error")
        if isinstance(error_message, str) and error_message:
            raise RuntimeError(error_message)
        output_text = response.get("outputText")
        if not isinstance(output_text, str):
            raise RuntimeError(f"worker returned an invalid payload for {model['modelId']}")
        return output_text

    def _ensure_worker(self, model: dict) -> WorkerHandle:
        key = (self.runtime_mode, model["modelId"], model["selectedEngine"])
        artifact_bundle_path = self.paths["model_cache_root"] / self.runtime_mode / model["modelId"] / "default" / "artifact-bundle.json"
        existing = self.worker_handles.get(key)
        if existing is not None and existing.process.poll() is None and existing.artifact_bundle_path == artifact_bundle_path:
            return existing
        if existing is not None:
            self._terminate_worker(existing)
        worker_script = pathlib.Path(__file__).resolve().parent / "runtime_worker.py"
        process = subprocess.Popen(
            [os.sys.executable, str(worker_script), "--artifact-bundle", str(artifact_bundle_path)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=None,
            text=True,
            bufsize=1,
        )
        worker_handle = WorkerHandle(artifact_bundle_path=artifact_bundle_path, process=process)
        self.worker_handles[key] = worker_handle
        return worker_handle

    def _restart_worker(self, model: dict) -> None:
        key = (self.runtime_mode, model["modelId"], model["selectedEngine"])
        existing = self.worker_handles.pop(key, None)
        if existing is not None:
            self._terminate_worker(existing)

    def _terminate_worker(self, worker_handle: WorkerHandle) -> None:
        if worker_handle.process.poll() is not None:
            return
        worker_handle.process.terminate()
        try:
            worker_handle.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            worker_handle.process.kill()
            worker_handle.process.wait(timeout=5)


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


def build_artifact_bundle(
    model: dict,
    runtime_mode: str,
    *,
    source_artifact: SourceArtifact | None = None,
) -> dict[str, object]:
    engine_adapter = engine_adapter_for(model["selectedEngine"], runtime_mode)
    source_artifact = source_artifact or SourceArtifact(
        payload_object_key=None,
        payload_local_path=None,
        payload_uri="",
        manifest_object_key="",
        manifest_local_path=pathlib.Path(),
        manifest_uri="",
        acquisition_mode="unknown",
        fetch_status="unfetched",
        resolved_url=model["downloadUrl"],
        content_type="",
        error="",
        selection_mode="unselected",
        authoritative_uri=model["downloadUrl"],
        authoritative_kind="upstream-reference",
        selected_artifacts=[],
    )
    return {
        "artifactKind": "infernix-runtime-bundle",
        "schemaVersion": 1,
        "runtimeMode": runtime_mode,
        "matrixRowId": model["matrixRowId"],
        "modelId": model["modelId"],
        "displayName": model["displayName"],
        "family": model["family"],
        "artifactType": model["artifactType"],
        "referenceModel": model["referenceModel"],
        "selectedEngine": model["selectedEngine"],
        "runtimeLane": model["runtimeLane"],
        "sourceDownloadUrl": model["downloadUrl"],
        "workerProfile": worker_profile_for(model),
        "engineAdapterId": engine_adapter["engineAdapterId"],
        "engineAdapterType": engine_adapter["engineAdapterType"],
        "engineAdapterLocator": engine_adapter["engineAdapterLocator"],
        "engineAdapterAvailable": engine_adapter["engineAdapterAvailable"],
        "engineAdapterAvailability": engine_adapter["engineAdapterAvailability"],
        "artifactAcquisitionMode": source_artifact.acquisition_mode,
        "engineWorkerMode": "engine-specific-runner",
        "sourceArtifactUri": source_artifact.payload_uri,
        "sourceArtifactManifestUri": source_artifact.manifest_uri,
        "sourceArtifactLocalPath": str(source_artifact.payload_local_path) if source_artifact.payload_local_path is not None else "",
        "sourceArtifactManifestPath": str(source_artifact.manifest_local_path),
        "sourceArtifactFetchStatus": source_artifact.fetch_status,
        "sourceArtifactResolvedUrl": source_artifact.resolved_url,
        "sourceArtifactContentType": source_artifact.content_type,
        "sourceArtifactError": source_artifact.error,
        "sourceArtifactSelectionMode": source_artifact.selection_mode,
        "sourceArtifactAuthoritativeUri": source_artifact.authoritative_uri,
        "sourceArtifactAuthoritativeKind": source_artifact.authoritative_kind,
        "sourceArtifactSelectedArtifacts": source_artifact.selected_artifacts,
    }


def worker_profile_for(model: dict) -> str:
    family = model["family"]
    if family == "llm":
        return "text-generation"
    if family == "speech":
        return "speech-transcription"
    if family == "audio":
        return "audio-processing"
    if family == "music":
        return "music-transcription"
    if family == "image":
        return "image-generation"
    if family == "video":
        return "video-generation"
    return "tool-execution"


def engine_adapter_for(selected_engine: str, runtime_mode: str) -> dict[str, object]:
    normalized = selected_engine.lower()
    if "llama.cpp" in normalized:
        return command_adapter("llama-cpp-cli", ["llama-cli", "main"])
    if "whisper.cpp" in normalized:
        return command_adapter("whisper-cpp-cli", ["whisper-cli", "main"])
    if "jvm" in normalized:
        return command_adapter("jvm-cli", ["java"])
    if "ctranslate2" in normalized:
        return module_adapter("ctranslate2-python", "ctranslate2")
    if "onnx runtime" in normalized:
        return module_adapter("onnxruntime-python", "onnxruntime")
    if "vllm" in normalized:
        return module_adapter("vllm-python", "vllm")
    if "mlx" in normalized:
        return module_adapter("mlx-python", "mlx")
    if "diffusers" in normalized or "comfyui" in normalized:
        return module_adapter("diffusers-python", "diffusers")
    if "tensorflow" in normalized:
        return module_adapter("tensorflow-python", "tensorflow")
    if "core ml" in normalized:
        return module_adapter("coreml-python", "coremltools")
    if "jax" in normalized:
        return module_adapter("jax-python", "jax")
    if "pytorch" in normalized or "transformers" in normalized:
        module_name = "torch" if runtime_mode == "linux-cuda" else "transformers"
        return module_adapter("pytorch-python", module_name)
    raise ValueError(f"unsupported selected engine mapping: {selected_engine}")


def command_adapter(adapter_id: str, command_names: list[str]) -> dict[str, object]:
    command_name = next((name for name in command_names if shutil.which(name) is not None), "")
    return {
        "engineAdapterId": adapter_id,
        "engineAdapterType": "external-command",
        "engineAdapterLocator": command_name or command_names[0],
        "engineAdapterAvailable": command_name != "",
        "engineAdapterAvailability": "command available" if command_name != "" else "command not installed",
    }


def module_adapter(adapter_id: str, module_name: str) -> dict[str, object]:
    available = importlib.util.find_spec(module_name) is not None
    return {
        "engineAdapterId": adapter_id,
        "engineAdapterType": "python-module",
        "engineAdapterLocator": module_name,
        "engineAdapterAvailable": available,
        "engineAdapterAvailability": "module importable" if available else "module not installed",
    }


def worker_adapter_mode_from_environment() -> str:
    for name, value in os.environ.items():
        if name.startswith("INFERNIX_ENGINE_COMMAND_") and value:
            return "engine-specific-command-prefixes"
    return "engine-specific-runner-defaults"


def select_engine_ready_source_artifacts(
    *,
    model: dict[str, object],
    source_url: str,
    resolved_url: str,
    acquisition_mode: str,
    payload_uri: str,
    content_type: str,
    payload_bytes: bytes | None,
) -> SourceArtifactSelection:
    if acquisition_mode == "huggingface-model-metadata":
        payload = decode_json_payload(payload_bytes)
        return select_huggingface_artifacts(model, payload, payload_uri, resolved_url)
    if acquisition_mode == "github-repository-metadata":
        payload = decode_json_payload(payload_bytes)
        return select_github_artifacts(model, payload, payload_uri, resolved_url)

    authoritative_uri = payload_uri or resolved_url or source_url
    authoritative_kind = "payload-object" if payload_uri else "upstream-reference"
    artifact_kind = artifact_kind_for_name(str(model.get("artifactType", "")), content_type)
    selected_artifacts = [
        artifact_entry(
            artifact_id="primary",
            artifact_kind=artifact_kind,
            uri=authoritative_uri,
            required=True,
        )
    ]
    return SourceArtifactSelection(
        selection_mode="engine-specific-direct-artifact",
        authoritative_uri=authoritative_uri,
        authoritative_kind=authoritative_kind,
        selected_artifacts=selected_artifacts,
    )


def decode_json_payload(payload_bytes: bytes | None) -> dict[str, object]:
    if not payload_bytes:
        return {}
    try:
        payload = json.loads(payload_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def load_existing_source_artifact(manifest_local_path: pathlib.Path) -> SourceArtifact | None:
    if not manifest_local_path.exists():
        return None
    try:
        payload = json.loads(manifest_local_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(payload, dict):
        return None
    if not isinstance(payload.get("selectionMode"), str) or not payload.get("selectionMode"):
        return None
    payload_object_key = payload.get("payloadObjectKey")
    if not isinstance(payload_object_key, str) or payload_object_key == "":
        payload_object_key = None
    payload_local_path = manifest_local_path.parent / "payload.bin" if payload_object_key is not None else None
    payload_uri = payload.get("payloadUri")
    manifest_uri = payload.get("manifestUri")
    return SourceArtifact(
        payload_object_key=payload_object_key,
        payload_local_path=payload_local_path if payload_local_path is not None and payload_local_path.exists() else None,
        payload_uri=payload_uri if isinstance(payload_uri, str) else "",
        manifest_object_key=str(payload.get("manifestObjectKey") or ""),
        manifest_local_path=manifest_local_path,
        manifest_uri=manifest_uri if isinstance(manifest_uri, str) and manifest_uri else manifest_local_path.resolve().as_uri(),
        acquisition_mode=str(payload.get("acquisitionMode") or "unknown"),
        fetch_status=str(payload.get("fetchStatus") or "unknown"),
        resolved_url=str(payload.get("resolvedSourceUrl") or payload.get("sourceDownloadUrl") or ""),
        content_type=str(payload.get("contentType") or ""),
        error=str(payload.get("error") or ""),
        selection_mode=str(payload.get("selectionMode") or "unselected"),
        authoritative_uri=str(payload.get("authoritativeInputUri") or payload.get("payloadUri") or payload.get("resolvedSourceUrl") or ""),
        authoritative_kind=str(payload.get("authoritativeInputKind") or "upstream-reference"),
        selected_artifacts=[entry for entry in payload.get("selectedArtifacts", []) if isinstance(entry, dict)],
    )


def select_huggingface_artifacts(
    model: dict[str, object],
    payload: dict[str, object],
    payload_uri: str,
    resolved_url: str,
) -> SourceArtifactSelection:
    model_id = payload.get("modelId")
    siblings = ((payload.get("metadata") or {}).get("siblings")) if isinstance(payload.get("metadata"), dict) else []
    sibling_names = [name for name in siblings if isinstance(name, str)]
    patterns = engine_artifact_patterns(str(model.get("selectedEngine", "")), str(model.get("artifactType", "")))
    selected_names = select_matching_names(sibling_names, patterns)
    if isinstance(model_id, str) and model_id and selected_names:
        selected_artifacts = [
            artifact_entry(
                artifact_id=name.replace("/", "_"),
                artifact_kind=artifact_kind_for_name(name, ""),
                uri=f"https://huggingface.co/{model_id}/resolve/main/{urllib.parse.quote(name, safe='/')}",
                required=index == 0,
            )
            for index, name in enumerate(selected_names)
        ]
    else:
        fallback_uri = resolved_url or str(payload.get("apiUrl") or model.get("downloadUrl") or "")
        selected_artifacts = [
            artifact_entry(
                artifact_id="repository",
                artifact_kind="provider-metadata",
                uri=fallback_uri,
                required=True,
            )
        ]
    authoritative_uri, authoritative_kind = authoritative_selection(
        selected_artifacts,
        fallback_uri=payload_uri or resolved_url or str(model.get("downloadUrl") or ""),
        fallback_kind="provider-metadata-manifest",
    )
    return SourceArtifactSelection(
        selection_mode="engine-specific-huggingface-selection",
        authoritative_uri=authoritative_uri,
        authoritative_kind=authoritative_kind,
        selected_artifacts=selected_artifacts,
    )


def select_github_artifacts(
    model: dict[str, object],
    payload: dict[str, object],
    payload_uri: str,
    resolved_url: str,
) -> SourceArtifactSelection:
    patterns = engine_artifact_patterns(str(model.get("selectedEngine", "")), str(model.get("artifactType", "")))
    selected_artifacts: list[dict[str, object]] = []
    releases = payload.get("releases")
    if isinstance(releases, list):
        for release in releases[:5]:
            if not isinstance(release, dict):
                continue
            assets = release.get("assets")
            if not isinstance(assets, list):
                continue
            asset_names = [asset.get("name") for asset in assets if isinstance(asset, dict)]
            selected_names = select_matching_names(
                [name for name in asset_names if isinstance(name, str)],
                patterns,
            )
            for name in selected_names:
                asset_payload = next(
                    (
                        asset
                        for asset in assets
                        if isinstance(asset, dict) and asset.get("name") == name
                    ),
                    None,
                )
                if not isinstance(asset_payload, dict):
                    continue
                download_url = asset_payload.get("browser_download_url")
                if isinstance(download_url, str) and download_url:
                    selected_artifacts.append(
                        artifact_entry(
                            artifact_id=name,
                            artifact_kind=artifact_kind_for_name(name, str(asset_payload.get("content_type") or "")),
                            uri=download_url,
                            required=not selected_artifacts,
                        )
                    )
            if selected_artifacts:
                break

    if not selected_artifacts:
        repository = str(payload.get("repository") or "")
        metadata = payload.get("metadata")
        html_url = metadata.get("html_url") if isinstance(metadata, dict) else ""
        fallback_uri = html_url if isinstance(html_url, str) and html_url else resolved_url or str(model.get("downloadUrl") or "")
        selected_artifacts.append(
            artifact_entry(
                artifact_id="repository",
                artifact_kind="repository-reference",
                uri=fallback_uri,
                required=True,
            )
        )
        if repository:
            selected_artifacts.append(
                artifact_entry(
                    artifact_id="source-archive",
                    artifact_kind="source-archive",
                    uri=f"https://github.com/{repository}/archive/refs/heads/{default_branch_for_payload(payload)}.tar.gz",
                    required=False,
                )
            )

    authoritative_uri, authoritative_kind = authoritative_selection(
        selected_artifacts,
        fallback_uri=payload_uri or resolved_url or str(model.get("downloadUrl") or ""),
        fallback_kind="provider-metadata-manifest",
    )
    return SourceArtifactSelection(
        selection_mode="engine-specific-github-selection",
        authoritative_uri=authoritative_uri,
        authoritative_kind=authoritative_kind,
        selected_artifacts=selected_artifacts,
    )


def default_branch_for_payload(payload: dict[str, object]) -> str:
    metadata = payload.get("metadata")
    if isinstance(metadata, dict):
        default_branch = metadata.get("default_branch")
        if isinstance(default_branch, str) and default_branch:
            return default_branch
    return "main"


def authoritative_selection(
    selected_artifacts: list[dict[str, object]],
    *,
    fallback_uri: str,
    fallback_kind: str,
) -> tuple[str, str]:
    required_artifact = next(
        (
            entry
            for entry in selected_artifacts
            if isinstance(entry.get("required"), bool) and entry["required"]
        ),
        None,
    )
    primary_artifact = required_artifact or next(iter(selected_artifacts), None)
    if isinstance(primary_artifact, dict):
        primary_uri = primary_artifact.get("uri")
        primary_kind = primary_artifact.get("artifactKind")
        if isinstance(primary_uri, str) and primary_uri:
            resolved_kind = primary_kind if isinstance(primary_kind, str) and primary_kind else fallback_kind
            return primary_uri, resolved_kind
    return fallback_uri, fallback_kind


def engine_artifact_patterns(selected_engine: str, artifact_type: str) -> list[str]:
    normalized_engine = selected_engine.lower()
    normalized_artifact_type = artifact_type.lower()
    if "llama.cpp" in normalized_engine or "gguf" in normalized_artifact_type:
        return [".gguf", "tokenizer.model", "tokenizer.json", "config.json"]
    if "whisper.cpp" in normalized_engine:
        return [".bin", ".ggml", ".gguf", "filters", "vocab", "tokenizer"]
    if "ctranslate2" in normalized_engine:
        return ["model.bin", "config.json", "tokenizer.json", "tokenizer.model", "vocabulary"]
    if "onnx runtime" in normalized_engine or "onnx" in normalized_artifact_type:
        return [".onnx", "config.json", "tokenizer.json", "tokenizer.model"]
    if "tensorflow" in normalized_engine:
        return ["saved_model.pb", ".pb", ".h5", "config.json"]
    if "core ml" in normalized_engine:
        return [".mlpackage", ".mlmodelc", ".mlmodel", "config.json"]
    if "jax" in normalized_engine:
        return [".npz", ".ckpt", ".msgpack", "checkpoint", ".gin", "config.json"]
    if "mlx" in normalized_engine:
        return [".safetensors", "tokenizer.model", "tokenizer.json", "config.json"]
    if "diffusers" in normalized_engine or "comfyui" in normalized_engine:
        return ["model_index.json", ".safetensors", "scheduler", "tokenizer", "vae", "unet", "text_encoder"]
    if "jvm" in normalized_engine:
        return [".jar", ".zip", ".tar.gz"]
    return [
        ".safetensors",
        ".bin",
        "config.json",
        "generation_config.json",
        "tokenizer.json",
        "tokenizer.model",
        "tokenizer_config.json",
        "preprocessor_config.json",
    ]


def select_matching_names(names: list[str], patterns: list[str]) -> list[str]:
    selected: list[str] = []
    normalized_names = list(dict.fromkeys(names))
    for pattern in patterns:
        normalized_pattern = pattern.lower()
        for name in normalized_names:
            normalized_name = name.lower()
            if normalized_pattern.startswith("."):
                matched = normalized_name.endswith(normalized_pattern)
            else:
                matched = normalized_pattern in normalized_name
            if matched and name not in selected:
                selected.append(name)
                if len(selected) >= 8:
                    return selected
    return selected


def artifact_entry(*, artifact_id: str, artifact_kind: str, uri: str, required: bool) -> dict[str, object]:
    return {
        "artifactId": artifact_id,
        "artifactKind": artifact_kind,
        "uri": uri,
        "required": required,
    }


def artifact_kind_for_name(name: str, content_type: str) -> str:
    normalized_name = name.lower()
    normalized_content_type = content_type.lower()
    if normalized_name.endswith(".gguf"):
        return "gguf-weights"
    if normalized_name.endswith(".safetensors"):
        return "safetensors-weights"
    if normalized_name.endswith(".onnx"):
        return "onnx-model"
    if normalized_name.endswith(".h5") or normalized_name.endswith(".pb"):
        return "tensorflow-model"
    if normalized_name.endswith(".mlmodel") or normalized_name.endswith(".mlpackage") or normalized_name.endswith(".mlmodelc"):
        return "coreml-model"
    if normalized_name.endswith(".jar"):
        return "jvm-application"
    if normalized_name.endswith(".json") or "json" in normalized_content_type:
        return "metadata"
    if normalized_name.endswith(".tar.gz") or normalized_name.endswith(".zip"):
        return "source-archive"
    return "runtime-artifact"


def fetch_remote_source_artifact(source_url: str) -> tuple[str, str, str, str, str, bytes | None]:
    if is_huggingface_model_url(source_url):
        return fetch_huggingface_source_artifact(source_url)
    if is_github_repository_url(source_url):
        return fetch_github_source_artifact(source_url)
    return fetch_http_source_artifact(source_url)


def remote_source_fetch_max_bytes() -> int:
    raw_value = os.environ.get("INFERNIX_REMOTE_SOURCE_FETCH_MAX_BYTES", "1048576")
    try:
        parsed = int(raw_value)
    except ValueError:
        return 1048576
    return max(parsed, 1024)


def local_source_artifact_path(source_url: str) -> pathlib.Path | None:
    parsed = urllib.parse.urlparse(source_url)
    if parsed.scheme == "file":
        return pathlib.Path(urllib.parse.unquote(parsed.path))
    if parsed.scheme == "" and pathlib.Path(source_url).exists():
        return pathlib.Path(source_url)
    return None


def parse_source_artifact_overrides() -> dict[str, str]:
    raw_value = os.environ.get("INFERNIX_SOURCE_ARTIFACT_OVERRIDES", "")
    if raw_value == "":
        return {}
    payload = json.loads(raw_value)
    if not isinstance(payload, dict):
        raise ValueError("INFERNIX_SOURCE_ARTIFACT_OVERRIDES must be a JSON object")
    overrides: dict[str, str] = {}
    for key, value in payload.items():
        if isinstance(key, str) and isinstance(value, str) and value != "":
            overrides[key] = value
    return overrides


def source_artifact_url_for(overrides: dict[str, str], model: dict[str, object]) -> str:
    model_id = model.get("modelId")
    if isinstance(model_id, str):
        override = overrides.get(model_id)
        if override is not None:
            return override
    source_url = model.get("downloadUrl")
    if not isinstance(source_url, str) or source_url == "":
        raise ValueError("model downloadUrl must be a non-empty string")
    return source_url


def is_huggingface_model_url(source_url: str) -> bool:
    parsed = urllib.parse.urlparse(source_url)
    return parsed.scheme in {"http", "https"} and parsed.netloc == "huggingface.co"


def is_github_repository_url(source_url: str) -> bool:
    parsed = urllib.parse.urlparse(source_url)
    return parsed.scheme in {"http", "https"} and parsed.netloc == "github.com"


def fetch_huggingface_source_artifact(source_url: str) -> tuple[str, str, str, str, str, bytes]:
    repo_id = parse_huggingface_repo_id(source_url)
    api_url = f"https://huggingface.co/api/models/{repo_id}"
    metadata = fetch_json_url(api_url)
    payload: dict[str, object] = {
        "provider": "huggingface",
        "modelId": repo_id,
        "apiUrl": api_url,
        "metadata": {
            "id": metadata.get("id"),
            "sha": metadata.get("sha"),
            "pipeline_tag": metadata.get("pipeline_tag"),
            "library_name": metadata.get("library_name"),
            "downloads": metadata.get("downloads"),
            "likes": metadata.get("likes"),
            "tags": metadata.get("tags", [])[:32] if isinstance(metadata.get("tags"), list) else [],
            "siblings": [
                sibling.get("rfilename")
                for sibling in metadata.get("siblings", [])[:128]
                if isinstance(sibling, dict) and isinstance(sibling.get("rfilename"), str)
            ],
        },
    }
    readme_text = fetch_optional_text(f"https://huggingface.co/{repo_id}/resolve/main/README.md", remote_source_fetch_max_bytes() // 2)
    if readme_text:
        payload["readme"] = readme_text
    return (
        "huggingface-model-metadata",
        "materialized",
        api_url,
        "application/json",
        "",
        json.dumps(payload, indent=2, sort_keys=True).encode("utf-8"),
    )


def fetch_github_source_artifact(source_url: str) -> tuple[str, str, str, str, str, bytes]:
    owner, repo = parse_github_repo(source_url)
    api_url = f"https://api.github.com/repos/{owner}/{repo}"
    metadata = fetch_json_url(api_url)
    releases_url = f"https://api.github.com/repos/{owner}/{repo}/releases?per_page=5"
    releases = fetch_json_array_url(releases_url)
    payload: dict[str, object] = {
        "provider": "github",
        "repository": f"{owner}/{repo}",
        "apiUrl": api_url,
        "metadata": {
            "full_name": metadata.get("full_name"),
            "default_branch": metadata.get("default_branch"),
            "description": metadata.get("description"),
            "stargazers_count": metadata.get("stargazers_count"),
            "forks_count": metadata.get("forks_count"),
            "open_issues_count": metadata.get("open_issues_count"),
            "html_url": metadata.get("html_url"),
        },
        "releases": [
            {
                "tag_name": release.get("tag_name"),
                "assets": [
                    {
                        "name": asset.get("name"),
                        "browser_download_url": asset.get("browser_download_url"),
                        "content_type": asset.get("content_type"),
                        "size": asset.get("size"),
                    }
                    for asset in release.get("assets", [])
                    if isinstance(asset, dict)
                ],
            }
            for release in releases
            if isinstance(release, dict)
        ],
    }
    default_branch = metadata.get("default_branch")
    if isinstance(default_branch, str) and default_branch:
        readme_url = f"https://raw.githubusercontent.com/{owner}/{repo}/{default_branch}/README.md"
        readme_text = fetch_optional_text(readme_url, remote_source_fetch_max_bytes() // 2)
        if readme_text:
            payload["readme"] = readme_text
    return (
        "github-repository-metadata",
        "materialized",
        api_url,
        "application/json",
        "",
        json.dumps(payload, indent=2, sort_keys=True).encode("utf-8"),
    )


def fetch_http_source_artifact(source_url: str) -> tuple[str, str, str, str, str, bytes]:
    request = urllib.request.Request(
        source_url,
        headers={"User-Agent": "infernix-runtime/0.1"},
        method="GET",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        resolved_url = response.geturl()
        content_type = response.headers.get_content_type() or "application/octet-stream"
        max_bytes = remote_source_fetch_max_bytes()
        payload = response.read(max_bytes + 1)
        fetch_status = "truncated" if len(payload) > max_bytes else "materialized"
        return (
            "direct-http-download",
            fetch_status,
            resolved_url,
            content_type,
            "",
            payload[:max_bytes],
        )


def parse_huggingface_repo_id(source_url: str) -> str:
    parsed = urllib.parse.urlparse(source_url)
    segments = [segment for segment in parsed.path.split("/") if segment]
    if len(segments) < 2:
        raise ValueError(f"unsupported Hugging Face model URL: {source_url}")
    return "/".join(segments[:2])


def parse_github_repo(source_url: str) -> tuple[str, str]:
    parsed = urllib.parse.urlparse(source_url)
    segments = [segment for segment in parsed.path.split("/") if segment]
    if len(segments) < 2:
        raise ValueError(f"unsupported GitHub repository URL: {source_url}")
    return segments[0], segments[1]


def fetch_json_url(url: str) -> dict[str, object]:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "infernix-runtime/0.1", "Accept": "application/json"},
        method="GET",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"expected JSON object from {url}")
    return payload


def fetch_json_array_url(url: str) -> list[object]:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "infernix-runtime/0.1", "Accept": "application/json"},
        method="GET",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if not isinstance(payload, list):
        raise ValueError(f"expected JSON array from {url}")
    return payload


def fetch_optional_text(url: str, max_bytes: int) -> str:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "infernix-runtime/0.1"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = response.read(max_bytes + 1)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return ""
        raise
    return payload[:max_bytes].decode("utf-8", errors="replace")


def bundle_string(payload: dict[str, object], field_name: str) -> str:
    value = payload.get(field_name)
    return value if isinstance(value, str) else ""


def bundle_list(payload: dict[str, object], field_name: str) -> list[dict[str, object]]:
    value = payload.get(field_name)
    if not isinstance(value, list):
        return []
    return [entry for entry in value if isinstance(entry, dict)]
