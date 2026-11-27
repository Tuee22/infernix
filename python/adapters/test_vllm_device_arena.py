"""The vLLM arena leaves room within the grant for device residue."""

from __future__ import annotations

import unittest
from typing import cast
from unittest.mock import Mock, patch

from adapters.common import AdapterContext
from adapters.vllm_python import _device_arena_fraction


class DeviceArenaTests(unittest.TestCase):
    def test_arena_tracks_grant_and_observed_device(self) -> None:
        context = Mock(spec=AdapterContext)
        context.require_device_mib.return_value = 12288
        with patch(
            "adapters.vllm_python._observed_device_envelope_mib", return_value=24576
        ):
            self.assertEqual(
                _device_arena_fraction(cast(AdapterContext, context)), 11264 / 24576
            )

    def test_grant_must_cover_residue_reserve(self) -> None:
        context = Mock(spec=AdapterContext)
        context.require_device_mib.return_value = 1024
        with patch(
            "adapters.vllm_python._observed_device_envelope_mib", return_value=24576
        ):
            with self.assertRaisesRegex(RuntimeError, "residue reserve"):
                _device_arena_fraction(cast(AdapterContext, context))


if __name__ == "__main__":
    unittest.main()
