"""Behavioral controls for engine cache eviction leases."""

from __future__ import annotations

import fcntl
import hashlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from adapters import model_cache


class CacheEvictionLeaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="infernix-cache-lease-")
        self.root = Path(self.temp.name)
        model_cache.configure(
            model_cache.ModelCacheConfig(cache_root=self.root, quota_bytes=50)
        )
        for name in ("victim-model", "current-model"):
            entry = self.root / name
            entry.mkdir()
            (entry / ".ready").write_text("ready", encoding="utf-8")
            (entry / "payload").write_bytes(b"x" * 32)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_warm_inventory_rejects_same_length_corruption(self) -> None:
        entry = self.root / "current-model"
        inventory = {
            "version": 1,
            "files": [
                {
                    "path": "payload",
                    "size": 32,
                    "sha256": hashlib.sha256(b"x" * 32).hexdigest(),
                }
            ],
        }
        (entry / model_cache.ARTIFACT_INVENTORY_NAME).write_text(
            json.dumps(inventory), encoding="utf-8"
        )
        model_cache._verify_artifact_inventory(entry)
        (entry / "unlisted.bin").write_bytes(b"extra")
        with self.assertRaises(model_cache.ModelCacheNotPopulated):
            model_cache._verify_artifact_inventory(entry)
        (entry / "unlisted.bin").unlink()
        (entry / "unlisted-directory").mkdir()
        with self.assertRaises(model_cache.ModelCacheNotPopulated):
            model_cache._verify_artifact_inventory(entry)
        (entry / "unlisted-directory").rmdir()
        (entry / "payload").write_bytes(b"y" * 32)
        with self.assertRaises(model_cache.ModelCacheNotPopulated):
            model_cache.get_model_path("current-model")
        (entry / ".ready").write_text(
            model_cache.INVENTORY_READY_MARKER, encoding="utf-8"
        )
        (entry / model_cache.ARTIFACT_INVENTORY_NAME).unlink()
        with self.assertRaises(model_cache.ModelCacheNotPopulated):
            model_cache.get_model_path("current-model")

    def test_warm_legacy_cache_reconciles_only_matching_durable_identity(self) -> None:
        entry = self.root / "current-model"
        inventory_path = entry / model_cache.ARTIFACT_INVENTORY_NAME
        manifest = json.dumps(
            {
                "version": 1,
                "files": [
                    {
                        "path": "payload",
                        "size": 32,
                        "sha256": hashlib.sha256(b"x" * 32).hexdigest(),
                    }
                ],
            }
        ).encode()

        class Store:
            def get_object(self, **_kwargs: Any) -> dict[str, Any]:
                return {"Body": io.BytesIO(manifest), "ContentLength": len(manifest)}

        model_cache.configure(
            model_cache.ModelCacheConfig(
                cache_root=self.root,
                quota_bytes=4096,
                minio_endpoint="http://fixture",
                minio_access_key="fixture",
                minio_secret_key="fixture",
            )
        )
        with patch("boto3.client", return_value=Store()):
            (entry / "payload").write_bytes(b"y" * 32)
            with self.assertRaises(model_cache.ModelCacheNotPopulated):
                model_cache.get_model_path("current-model")
            self.assertFalse(inventory_path.exists())
            self.assertEqual((entry / "payload").read_bytes(), b"y" * 32)
            (entry / "payload").write_bytes(b"x" * 32)
            self.assertEqual(model_cache.get_model_path("current-model"), entry)
            self.assertEqual(inventory_path.read_bytes(), manifest)

    def test_warm_legacy_inventory_failure_preserves_cache(self) -> None:
        from botocore.exceptions import ClientError

        entry = self.root / "current-model"
        model_cache.configure(
            model_cache.ModelCacheConfig(
                cache_root=self.root,
                quota_bytes=4096,
                minio_endpoint="http://fixture",
                minio_access_key="fixture",
                minio_secret_key="fixture",
            )
        )

        class Store:
            def __init__(self, status: int) -> None:
                self.status = status

            def get_object(self, **_kwargs: Any) -> dict[str, Any]:
                raise ClientError(
                    {
                        "Error": {"Code": str(self.status)},
                        "ResponseMetadata": {"HTTPStatusCode": self.status},
                    },
                    "GetObject",
                )

        for status, error in (
            (404, model_cache.ModelCacheNotPopulated),
            (403, ClientError),
        ):
            with (
                self.subTest(status=status),
                patch("boto3.client", return_value=Store(status)),
            ):
                with self.assertRaises(error):
                    model_cache.get_model_path("current-model")
                self.assertFalse((entry / model_cache.ARTIFACT_INVENTORY_NAME).exists())
                self.assertEqual((entry / "payload").read_bytes(), b"x" * 32)

    def test_inventory_rejects_traversal_and_duplicate_paths(self) -> None:
        entry = self.root / "current-model"
        item = {"path": "../outside", "size": 1, "sha256": "0" * 64}
        inventory_path = entry / model_cache.ARTIFACT_INVENTORY_NAME
        valid = {
            "path": "payload",
            "size": 32,
            "sha256": hashlib.sha256(b"x" * 32).hexdigest(),
        }
        for items in ([item], [valid, valid]):
            inventory_path.write_text(
                json.dumps({"version": 1, "files": items}), encoding="utf-8"
            )
            with self.assertRaises(model_cache.ModelCacheNotPopulated):
                model_cache._verify_artifact_inventory(entry)

    def test_remote_inventory_refuses_unsafe_paths_before_download(self) -> None:
        prefix = "current-model/"
        for relatives in (
            ["../outside"],
            ["/absolute"],
            ["nested//file"],
            ["payload", "payload"],
            ["nested", "nested/file"],
            ["payload.tmp"],
        ):
            with (
                self.subTest(relatives=relatives),
                self.assertRaises(model_cache.ModelCacheNotPopulated),
            ):
                model_cache._validate_download_inventory(
                    [prefix + name for name in relatives], relatives, prefix
                )
        model_cache._validate_download_inventory(
            [prefix + ".ready", prefix + "nested/weights"],
            [".ready", "nested/weights"],
            prefix,
        )

    def test_remote_listing_stops_at_its_bound_and_rejects_invalid_keys(self) -> None:
        class Store:
            def __init__(self, pages: list[dict[str, Any]]) -> None:
                self.pages = pages

            def get_paginator(self, _operation: str) -> Any:
                return self

            def paginate(self, **_kwargs: Any) -> list[dict[str, Any]]:
                return self.pages

        with patch.object(model_cache, "MODEL_OBJECT_COUNT_LIMIT", 2):
            self.assertEqual(
                model_cache._list_minio_objects(
                    Store([{"Contents": [{"Key": "a"}, {"Key": "b"}]}]),
                    "bucket",
                    "prefix",
                ),
                ["a", "b"],
            )
            with self.assertRaises(model_cache.ModelCacheNotPopulated):
                model_cache._list_minio_objects(
                    Store(
                        [
                            {"Contents": [{"Key": "a"}, {"Key": "b"}]},
                            {"Contents": [{"Key": "c"}]},
                        ]
                    ),
                    "bucket",
                    "prefix",
                )
        with self.assertRaises(model_cache.ModelCacheNotPopulated):
            model_cache._list_minio_objects(
                Store([{"Contents": [{"Key": None}]}]), "bucket", "prefix"
            )

    def test_download_refuses_symlink_parent_and_preserves_prior_on_failure(
        self,
    ) -> None:
        class Store:
            def __init__(self, fail: bool) -> None:
                self.fail = fail

            def get_object(self, **_kwargs: Any) -> dict[str, Any]:
                class Body(io.BytesIO):
                    def read(self, size: int | None = -1) -> bytes:
                        if self_fail:
                            raise OSError("interrupted")
                        return super().read(-1 if size is None else size)

                self_fail = self.fail
                return {"Body": Body(b"new"), "ContentLength": 3}

        model_dir = self.root / "current-model"
        outside = self.root / "outside"
        outside.mkdir()
        (model_dir / "linked").symlink_to(outside, target_is_directory=True)
        root_fd = os.open(model_dir, os.O_RDONLY | os.O_DIRECTORY)
        try:
            with self.assertRaises(OSError):
                model_cache._download_minio_object(
                    Store(False), "models", "key", root_fd, "linked/file", 10
                )
            self.assertFalse((outside / "file").exists())
            with self.assertRaises(OSError):
                model_cache._download_minio_object(
                    Store(True), "models", "key", root_fd, "payload", 10
                )
            self.assertEqual((model_dir / "payload").read_bytes(), b"x" * 32)
            self.assertFalse(list(model_dir.glob(".infernix-download-*")))
            model_cache._download_minio_object(
                Store(False), "models", "key", root_fd, "nested/payload", 10
            )
            self.assertEqual((model_dir / "nested" / "payload").read_bytes(), b"new")
            with self.assertRaises(model_cache.ModelCacheQuotaExceeded):
                model_cache._download_minio_object(
                    Store(False), "models", "key", root_fd, "payload", 2
                )
            self.assertEqual((model_dir / "payload").read_bytes(), b"x" * 32)
        finally:
            os.close(root_fd)

    def test_inventory_verification_and_ready_publication_reject_symlink_tricks(
        self,
    ) -> None:
        entry = self.root / "current-model"
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "weights").write_bytes(b"weight")
        (entry / "linked").symlink_to(outside, target_is_directory=True)
        inventory = {
            "version": 1,
            "files": [
                {
                    "path": "linked/weights",
                    "size": 6,
                    "sha256": hashlib.sha256(b"weight").hexdigest(),
                }
            ],
        }
        (entry / model_cache.ARTIFACT_INVENTORY_NAME).write_text(
            json.dumps(inventory), encoding="utf-8"
        )
        with self.assertRaises(model_cache.ModelCacheNotPopulated):
            model_cache._verify_artifact_inventory(entry)
        (entry / ".ready").unlink()
        protected = outside / "protected"
        protected.write_text("unchanged", encoding="utf-8")
        (entry / ".ready").symlink_to(protected)
        root_fd = os.open(entry, os.O_RDONLY | os.O_DIRECTORY)
        try:
            model_cache._publish_cache_ready(
                root_fd, model_cache.INVENTORY_READY_MARKER
            )
        finally:
            os.close(root_fd)
        self.assertEqual(protected.read_text(encoding="utf-8"), "unchanged")
        self.assertFalse((entry / ".ready").is_symlink())

    def test_download_refuses_mismatched_extents(self) -> None:
        class Store:
            def __init__(self, declared: int) -> None:
                self.declared = declared

            def get_object(self, **_kwargs: Any) -> dict[str, Any]:
                return {"Body": io.BytesIO(b"abc"), "ContentLength": self.declared}

        entry = self.root / "current-model"
        root_fd = os.open(entry, os.O_RDONLY | os.O_DIRECTORY)
        try:
            for declared in (2, 4):
                with (
                    self.subTest(declared=declared),
                    self.assertRaises(model_cache.ModelCacheNotPopulated),
                ):
                    model_cache._download_minio_object(
                        Store(declared), "models", "key", root_fd, "payload", 10
                    )
                self.assertEqual((entry / "payload").read_bytes(), b"x" * 32)
                self.assertFalse(list(entry.glob(".infernix-download-*")))
        finally:
            os.close(root_fd)

    def test_inventory_backed_hydration_requires_complete_matching_objects(
        self,
    ) -> None:
        content = b"model-weight-bytes"
        manifest = json.dumps(
            {
                "version": 1,
                "files": [
                    {
                        "path": "nested/weights",
                        "size": len(content),
                        "sha256": hashlib.sha256(content).hexdigest(),
                    }
                ],
            }
        ).encode()

        class Store:
            def __init__(self, objects: dict[str, bytes]) -> None:
                self.objects = objects

            def get_paginator(self, _operation: str) -> Any:
                return self

            def paginate(self, **_kwargs: Any) -> list[dict[str, Any]]:
                return [
                    {
                        "Contents": [
                            {"Key": key, "Size": len(self.objects[key])}
                            for key in sorted(self.objects)
                        ]
                    }
                ]

            def get_object(self, **kwargs: Any) -> dict[str, Any]:
                data = self.objects[kwargs["Key"]]
                return {"Body": io.BytesIO(data), "ContentLength": len(data)}

        prefix = "candidate-model/"
        base = {
            prefix + ".ready": b"ready",
            prefix + model_cache.ARTIFACT_INVENTORY_NAME: manifest,
            prefix + "nested/weights": content,
        }
        model_cache.configure(
            model_cache.ModelCacheConfig(
                cache_root=self.root,
                quota_bytes=4096,
                minio_endpoint="http://fixture",
                minio_access_key="fixture",
                minio_secret_key="fixture",
            )
        )
        for name, objects, expected_success in (
            ("valid", base, True),
            (
                "missing-inventory",
                {
                    key: value
                    for key, value in base.items()
                    if not key.endswith(model_cache.ARTIFACT_INVENTORY_NAME)
                },
                False,
            ),
            (
                "corrupt",
                {**base, prefix + "nested/weights": b"X" * len(content)},
                False,
            ),
            ("unlisted", {**base, prefix + "extra": b"unlisted"}, False),
        ):
            destination = self.root / name
            with (
                self.subTest(name=name),
                patch("boto3.client", return_value=Store(objects)),
            ):
                if expected_success:
                    model_cache._populate_from_minio("candidate-model", destination)
                    self.assertEqual(
                        (destination / "nested/weights").read_bytes(), content
                    )
                    self.assertEqual(
                        (destination / ".ready").read_text(),
                        model_cache.INVENTORY_READY_MARKER,
                    )
                else:
                    with self.assertRaises(model_cache.ModelCacheNotPopulated):
                        model_cache._populate_from_minio("candidate-model", destination)
                    self.assertFalse((destination / ".ready").exists())
                    if name == "missing-inventory":
                        self.assertFalse(destination.exists())

    def test_active_victim_survives_and_idle_victim_can_be_evicted(self) -> None:
        locks = self.root / ".infernix-model-locks"
        locks.mkdir(parents=True)
        descriptor = os.open(
            locks / "victim-model.held", os.O_WRONLY | os.O_CREAT, 0o600
        )
        try:
            fcntl.flock(descriptor, fcntl.LOCK_SH | fcntl.LOCK_NB)
            with self.assertRaises(model_cache.ModelCacheQuotaExceeded):
                model_cache._enforce_lru_quota(self.root, "current-model")
            self.assertTrue((self.root / "victim-model" / "payload").is_file())
            self.assertTrue((self.root / "current-model" / "payload").is_file())
        finally:
            os.close(descriptor)

        model_cache._enforce_lru_quota(self.root, "current-model")
        self.assertFalse((self.root / "victim-model").exists())
        self.assertTrue((self.root / "current-model" / "payload").is_file())

    def test_reservation_larger_than_the_quota_is_refused_before_any_eviction(
        self,
    ) -> None:
        with self.assertRaises(model_cache.ModelCacheQuotaExceeded):
            model_cache._enforce_lru_quota(self.root, "new-model", reserve_bytes=51)
        self.assertTrue((self.root / "victim-model" / "payload").is_file())
        self.assertTrue((self.root / "current-model" / "payload").is_file())

    def test_reservation_evicts_idle_models_to_fit_the_declared_size(self) -> None:
        # The current model is charged its declared size, not its partial files:
        # 40 reserved + 37 held by the victim exceeds the 50-byte quota, so the
        # idle victim goes and the reserving model's own files are untouched.
        model_cache._enforce_lru_quota(self.root, "current-model", reserve_bytes=40)
        self.assertFalse((self.root / "victim-model").exists())
        self.assertTrue((self.root / "current-model" / "payload").is_file())

    def test_hydration_refuses_an_oversize_generation_before_writing(self) -> None:
        class Store:
            def get_paginator(self, _operation: str) -> Any:
                return self

            def paginate(self, **_kwargs: Any) -> list[dict[str, Any]]:
                return [
                    {
                        "Contents": [
                            {"Key": "big-model/.ready", "Size": 5},
                            {
                                "Key": "big-model/"
                                + model_cache.ARTIFACT_INVENTORY_NAME,
                                "Size": 10,
                            },
                            {"Key": "big-model/weights", "Size": 1000},
                        ]
                    }
                ]

            def get_object(self, **_kwargs: Any) -> dict[str, Any]:
                raise AssertionError(
                    "no object may be requested before the reservation"
                )

        model_cache.configure(
            model_cache.ModelCacheConfig(
                cache_root=self.root,
                quota_bytes=50,
                minio_endpoint="http://fixture",
                minio_access_key="fixture",
                minio_secret_key="fixture",
            )
        )
        destination = self.root / "big-model"
        with patch("boto3.client", return_value=Store()):
            with self.assertRaises(model_cache.ModelCacheQuotaExceeded):
                model_cache._populate_from_minio("big-model", destination)
        self.assertFalse(destination.exists())
        self.assertTrue((self.root / "victim-model" / "payload").is_file())

    def test_listing_without_a_declared_size_is_refused_for_reservation(self) -> None:
        class Store:
            def get_paginator(self, _operation: str) -> Any:
                return self

            def paginate(self, **_kwargs: Any) -> list[dict[str, Any]]:
                return [{"Contents": [{"Key": "a"}]}]

        with self.assertRaises(model_cache.ModelCacheNotPopulated):
            model_cache._list_minio_object_entries(Store(), "bucket", "prefix")

    def test_unknown_directory_is_not_an_eviction_victim(self) -> None:
        (self.root / "victim-model" / ".ready").unlink()
        with self.assertRaises(model_cache.ModelCacheQuotaExceeded):
            model_cache._enforce_lru_quota(self.root, "current-model")
        self.assertTrue((self.root / "victim-model" / "payload").is_file())

    def test_population_lease_refuses_concurrent_writer_and_symlink(self) -> None:
        with model_cache._population_lease(self.root, "current-model"):
            with self.assertRaises(model_cache.ModelCacheNotPopulated):
                model_cache.get_model_path("current-model")
        locks = self.root / ".infernix-population-locks"
        lock_path = locks / "current-model.held"
        lock_path.unlink()
        protected = self.root / "protected-population-lock"
        protected.write_bytes(b"unchanged")
        lock_path.symlink_to(protected)
        with self.assertRaises(OSError):
            model_cache.get_model_path("current-model")
        self.assertEqual(protected.read_bytes(), b"unchanged")

    def test_verified_warm_cache_remains_readable_while_population_lease_is_held(
        self,
    ) -> None:
        entry = self.root / "current-model"
        (entry / model_cache.ARTIFACT_INVENTORY_NAME).write_text(
            json.dumps(
                {
                    "version": 1,
                    "files": [
                        {
                            "path": "payload",
                            "size": 32,
                            "sha256": hashlib.sha256(b"x" * 32).hexdigest(),
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        model_cache.configure(
            model_cache.ModelCacheConfig(cache_root=self.root, quota_bytes=4096)
        )
        with model_cache._population_lease(self.root, "current-model"):
            self.assertEqual(model_cache.get_model_path("current-model"), entry)

    def test_substituted_lock_is_refused_before_eviction(self) -> None:
        locks = self.root / ".infernix-model-locks"
        locks.mkdir()
        protected = self.root / "protected-file"
        protected.write_text("protected", encoding="utf-8")
        (locks / "victim-model.held").symlink_to(protected)
        with self.assertRaises(OSError):
            model_cache._enforce_lru_quota(self.root, "current-model")
        self.assertEqual(protected.read_text(encoding="utf-8"), "protected")
        self.assertTrue((self.root / "victim-model" / "payload").is_file())

    def test_invalid_model_identifiers_refuse_before_cache_access(self) -> None:
        for name in ("../escape", "/absolute", "two//parts", "Uppercase", "a..b"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                model_cache.get_model_path(name)


if __name__ == "__main__":
    unittest.main()


class GenerationReplacementTests(unittest.TestCase):
    """Hydration replaces a whole generation or leaves the prior one intact."""

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="infernix-generation-")
        self.root = Path(self.temp.name)
        self.content = b"new-generation-weights"
        manifest = json.dumps(
            {
                "version": 1,
                "files": [
                    {
                        "path": "weights",
                        "size": len(self.content),
                        "sha256": hashlib.sha256(self.content).hexdigest(),
                    }
                ],
            }
        ).encode()
        self.objects = {
            "swap-model/.ready": b"ready",
            "swap-model/" + model_cache.ARTIFACT_INVENTORY_NAME: manifest,
            "swap-model/weights": self.content,
        }
        model_cache.configure(
            model_cache.ModelCacheConfig(
                cache_root=self.root,
                quota_bytes=1 << 20,
                minio_endpoint="http://fixture",
                minio_access_key="fixture",
                minio_secret_key="fixture",
            )
        )
        self.destination = self.root / "swap-model"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _store(self, fail_on: str | None = None) -> Any:
        objects = self.objects

        class Store:
            def get_paginator(self, _operation: str) -> Any:
                return self

            def paginate(self, **_kwargs: Any) -> list[dict[str, Any]]:
                return [
                    {
                        "Contents": [
                            {"Key": key, "Size": len(objects[key])}
                            for key in sorted(objects)
                        ]
                    }
                ]

            def get_object(self, **kwargs: Any) -> dict[str, Any]:
                if fail_on is not None and kwargs["Key"].endswith(fail_on):
                    raise RuntimeError("injected transfer failure")
                data = objects[kwargs["Key"]]
                return {"Body": io.BytesIO(data), "ContentLength": len(data)}

        return Store()

    def _residue(self) -> list[str]:
        candidates = self.root / model_cache.CANDIDATE_ROOT_NAME
        return sorted(entry.name for entry in candidates.iterdir())

    def test_replacement_publishes_only_the_new_generation(self) -> None:
        self.destination.mkdir()
        (self.destination / "stale-file").write_bytes(b"old generation")
        with patch("boto3.client", return_value=self._store()):
            model_cache._populate_from_minio("swap-model", self.destination)
        self.assertEqual((self.destination / "weights").read_bytes(), self.content)
        self.assertFalse((self.destination / "stale-file").exists())
        self.assertTrue((self.destination / ".ready").is_file())
        self.assertEqual(self._residue(), [])

    def test_failed_transfer_preserves_the_prior_generation_without_residue(
        self,
    ) -> None:
        self.destination.mkdir()
        (self.destination / "weights").write_bytes(b"prior generation")
        (self.destination / ".ready").write_text("ready", encoding="utf-8")
        with patch("boto3.client", return_value=self._store(fail_on="weights")):
            with self.assertRaises(RuntimeError):
                model_cache._populate_from_minio("swap-model", self.destination)
        self.assertEqual(
            (self.destination / "weights").read_bytes(), b"prior generation"
        )
        self.assertEqual(self._residue(), [])

    def test_interrupted_swap_is_reconciled_under_the_model_name(self) -> None:
        candidates = self.root / model_cache.CANDIDATE_ROOT_NAME
        candidates.mkdir()
        previous = candidates / "swap-model.previous.aaaa"
        previous.mkdir()
        (previous / "weights").write_bytes(b"restored")
        abandoned = candidates / "swap-model.candidate.bbbb"
        abandoned.mkdir()
        (abandoned / "weights").write_bytes(b"never published")
        other = candidates / "swap-model-other.candidate.cccc"
        other.mkdir()
        model_cache._reconcile_interrupted_generations(self.root, "swap-model")
        self.assertEqual((self.destination / "weights").read_bytes(), b"restored")
        self.assertEqual(self._residue(), ["swap-model-other.candidate.cccc"])
        # With the model directory present, a leftover previous generation is
        # removed rather than restored over it.
        again = candidates / "swap-model.previous.dddd"
        again.mkdir()
        model_cache._reconcile_interrupted_generations(self.root, "swap-model")
        self.assertEqual((self.destination / "weights").read_bytes(), b"restored")
        self.assertEqual(self._residue(), ["swap-model-other.candidate.cccc"])
