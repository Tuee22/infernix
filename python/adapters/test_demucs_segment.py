"""Execution-window checks for the Demucs source-separation adapter."""

from __future__ import annotations

import unittest
from types import SimpleNamespace

from adapters.pytorch_python import _demucs_inference_options


class DemucsSegmentTests(unittest.TestCase):
    def test_cpu_bounds_padding_and_overlapping_windows(self) -> None:
        model = SimpleNamespace(segment=7.8)
        options = _demucs_inference_options(model, "cpu")
        self.assertEqual(options, {"device": "cpu", "segment": 2.0})
        self.assertEqual(model.segment, 2.0)

    def test_cpu_preserves_a_smaller_model_segment(self) -> None:
        model = SimpleNamespace(segment=1.5)
        self.assertEqual(_demucs_inference_options(model, "cpu")["segment"], 1.5)
        self.assertEqual(model.segment, 1.5)

    def test_accelerator_preserves_the_model_segment(self) -> None:
        model = SimpleNamespace(segment=7.8)
        self.assertEqual(_demucs_inference_options(model, "mps"), {"device": "mps"})
        self.assertEqual(model.segment, 7.8)


if __name__ == "__main__":
    unittest.main()
