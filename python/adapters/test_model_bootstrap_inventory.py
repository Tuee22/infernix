"""Producer inventory controls for staged model artifacts."""

from __future__ import annotations

import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from botocore.exceptions import ClientError

from adapters import model_bootstrap


class RecordingStore:
    def __init__(self) -> None:
        self.objects: dict[str, bytes] = {}

    def upload_file(self, source: str, _bucket: str, key: str) -> None:
        self.objects[key] = Path(source).read_bytes()

    def put_object(self, **kwargs: Any) -> None:
        if kwargs.get("IfNoneMatch") == "*" and kwargs["Key"] in self.objects:
            raise ValueError("conditional write conflict")
        self.objects[kwargs["Key"]] = kwargs["Body"]

    def head_object(self, **kwargs: Any) -> dict[str, Any]:
        if kwargs["Key"] not in self.objects:
            raise ClientError(
                {"Error": {"Code": "404"}, "ResponseMetadata": {"HTTPStatusCode": 404}},
                "HeadObject",
            )
        return {"ContentLength": len(self.objects[kwargs["Key"]])}

    def get_paginator(self, _operation: str) -> Any:
        return self

    def paginate(self, **kwargs: Any) -> list[dict[str, Any]]:
        return [
            {
                "Contents": [
                    {"Key": key}
                    for key in sorted(self.objects)
                    if key.startswith(kwargs["Prefix"])
                ]
            }
        ]

    def get_object(self, **kwargs: Any) -> dict[str, Any]:
        body = self.objects[kwargs["Key"]]
        return {"Body": io.BytesIO(body), "ContentLength": len(body)}


class ArtifactInventoryTests(unittest.TestCase):
    def test_retained_inventory_is_published_only_after_matching_upstream(self) -> None:
        def download(_url: str, destination: Path) -> None:
            destination.write_bytes(b"upstream")

        store = RecordingStore()
        store.objects = {"model/.ready": b"old sentinel", "model/payload": b"upstream"}
        with patch.object(
            model_bootstrap, "_download_single_payload", side_effect=download
        ):
            model_bootstrap._ensure_retained_artifact_inventory(
                store, "models", "model", "https://example.invalid/model"
            )
        inventory = json.loads(
            store.objects["model/" + model_bootstrap.ARTIFACT_INVENTORY_NAME]
        )
        self.assertEqual(
            inventory["files"][0]["sha256"], hashlib.sha256(b"upstream").hexdigest()
        )
        self.assertEqual(store.objects["model/.ready"], b"old sentinel")
        self.assertEqual(store.objects["model/payload"], b"upstream")

    def test_retained_mismatch_preserves_objects_and_publishes_no_inventory(
        self,
    ) -> None:
        def download(_url: str, destination: Path) -> None:
            destination.write_bytes(b"upstream")

        for payload in (b"different", b"upstreaM"):
            store = RecordingStore()
            original = {"model/.ready": b"old sentinel", "model/payload": payload}
            store.objects = dict(original)
            with (
                self.subTest(payload=payload),
                patch.object(
                    model_bootstrap, "_download_single_payload", side_effect=download
                ),
            ):
                with self.assertRaises(ValueError):
                    model_bootstrap._ensure_retained_artifact_inventory(
                        store, "models", "model", "https://example.invalid/model"
                    )
            self.assertEqual(store.objects, original)

    def test_retained_inventory_probe_failure_does_not_trigger_download(self) -> None:
        class Unavailable(RecordingStore):
            def head_object(self, **_kwargs: Any) -> dict[str, Any]:
                raise ClientError(
                    {
                        "Error": {"Code": "403"},
                        "ResponseMetadata": {"HTTPStatusCode": 403},
                    },
                    "HeadObject",
                )

        with patch.object(model_bootstrap, "_download_single_payload") as download:
            with self.assertRaises(ClientError):
                model_bootstrap._ensure_retained_artifact_inventory(
                    Unavailable(), "models", "model", "https://example.invalid/model"
                )
            download.assert_not_called()

    def test_retained_snapshot_requires_matching_index_and_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "weights").write_bytes(b"model")
            files = [("weights", root / "weights")]
            store = RecordingStore()
            store.objects = {
                "model/.ready": b"ready",
                "model/weights": b"model",
                "model/" + model_bootstrap.NATIVE_SNAPSHOT_INDEX_NAME: b"wrong\n",
            }
            with self.assertRaises(ValueError):
                model_bootstrap._verify_retained_artifacts(
                    store, "models", "model", files, require_index=True
                )
            store.objects["model/" + model_bootstrap.NATIVE_SNAPSHOT_INDEX_NAME] = (
                b"weights\n"
            )
            model_bootstrap._verify_retained_artifacts(
                store, "models", "model", files, require_index=True
            )
            store.objects["model/extra"] = b"unlisted"
            with self.assertRaises(ValueError):
                model_bootstrap._verify_retained_artifacts(
                    store, "models", "model", files, require_index=True
                )

    def test_snapshot_inventory_identifies_uploaded_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "nested").mkdir()
            (root / "nested" / "weights").write_bytes(b"weights")
            (root / "config").write_bytes(b"config")
            store = RecordingStore()
            model_bootstrap._upload_directory(store, "models", "model", root)
            inventory = json.loads(
                store.objects["model/" + model_bootstrap.ARTIFACT_INVENTORY_NAME]
            )
            self.assertEqual(inventory["version"], 1)
            self.assertEqual(
                [entry["path"] for entry in inventory["files"]],
                ["config", "nested/weights"],
            )
            for entry in inventory["files"]:
                payload = store.objects["model/" + entry["path"]]
                self.assertEqual(entry["size"], len(payload))
                self.assertEqual(entry["sha256"], hashlib.sha256(payload).hexdigest())

    def test_reserved_inventory_name_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "000-payload").write_bytes(b"must not be uploaded")
            (root / model_bootstrap.ARTIFACT_INVENTORY_NAME).write_bytes(b"conflict")
            store = RecordingStore()
            with self.assertRaises(ValueError):
                model_bootstrap._upload_directory(store, "models", "model", root)
            self.assertNotIn(
                "model/" + model_bootstrap.ARTIFACT_INVENTORY_NAME, store.objects
            )
            self.assertEqual(store.objects, {})

    def test_snapshot_symlink_refuses_before_any_upload(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "000-payload").write_bytes(b"must not be uploaded")
            (root / "linked").symlink_to(root / "000-payload")
            store = RecordingStore()
            with self.assertRaises(ValueError):
                model_bootstrap._upload_directory(store, "models", "model", root)
            self.assertEqual(store.objects, {})

    def test_snapshot_inventory_bound_refuses_before_any_upload(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "weights").write_bytes(b"model")
            store = RecordingStore()
            with patch.object(model_bootstrap, "SNAPSHOT_INVENTORY_LIMIT", 64):
                with self.assertRaises(ValueError):
                    model_bootstrap._upload_directory(store, "models", "model", root)
            self.assertEqual(store.objects, {})


if __name__ == "__main__":
    unittest.main()
