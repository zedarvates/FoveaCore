#!/usr/bin/env python3
"""Deterministic tests for the neural offset-field resource baker."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

import bake_offset_field


class BakeOffsetFieldTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)

    def _save(self, data: np.ndarray) -> Path:
        source = self.root / "field.npy"
        np.save(source, data)
        return source

    def test_bakes_current_resource_contract_in_x_fastest_order(self) -> None:
        field = np.empty((2, 2, 2, 3), dtype=np.float32)
        for x in range(2):
            for y in range(2):
                for z in range(2):
                    field[x, y, z] = (x, y, z)

        destination = self.root / "nested" / "field.tres"
        self.assertTrue(
            bake_offset_field.bake(
                self._save(field), destination, resolution=2, bounds=(-1, -2, -3, 4, 5, 6)
            )
        )

        resource = destination.read_text(encoding="utf-8")
        self.assertIn(bake_offset_field.SCRIPT_PATH, resource)
        self.assertIn("grid_dims = Vector3i(2, 2, 2)", resource)
        self.assertIn("bounds_min = Vector3(-1, -2, -3)", resource)
        self.assertIn("bounds_max = Vector3(4, 5, 6)", resource)
        self.assertIn("frame_count = 1", resource)
        self.assertIn(
            "offsets = PackedVector3Array("
            "0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0, "
            "0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1)",
            resource,
        )

    def test_rejects_shape_that_disagrees_with_resolution(self) -> None:
        source = self._save(np.zeros((2, 2, 1, 3), dtype=np.float32))
        with self.assertRaisesRegex(ValueError, "expected shape"):
            bake_offset_field.bake(source, self.root / "field.tres", resolution=2)

    def test_rejects_non_finite_offsets(self) -> None:
        field = np.zeros((1, 1, 1, 3), dtype=np.float32)
        field[0, 0, 0, 1] = np.nan
        with self.assertRaisesRegex(ValueError, "finite"):
            bake_offset_field.bake(self._save(field), self.root / "field.tres", resolution=1)

    def test_rejects_inverted_bounds(self) -> None:
        source = self._save(np.zeros((1, 1, 1, 3), dtype=np.float32))
        with self.assertRaisesRegex(ValueError, "maximum"):
            bake_offset_field.bake(
                source,
                self.root / "field.tres",
                resolution=1,
                bounds=(0, 0, 0, 0, 1, 1),
            )


if __name__ == "__main__":
    unittest.main()
