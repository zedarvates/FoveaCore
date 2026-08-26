import math
import unittest

import numpy as np

import neural_residual_experiment as compression
import rigid_motion_benchmark as motion


class RigidMotionBenchmarkTests(unittest.TestCase):
    def test_rigid_transform_moves_positions_rotations_and_scales_together(self) -> None:
        positions = np.asarray([[1.0, 0.0, 0.0]], dtype=np.float32)
        rotations = np.asarray([[1.0, 0.0, 0.0, 0.0]], dtype=np.float32)
        scales = np.ones((1, 3), dtype=np.float32)
        half = math.sqrt(0.5)
        object_rotation = np.asarray([half, 0.0, half, 0.0], dtype=np.float32)

        transformed = motion.apply_rigid_transform(
            positions,
            rotations,
            scales,
            translation=np.asarray([1.0, 2.0, 3.0], dtype=np.float32),
            rotation=object_rotation,
            uniform_scale=2.0,
        )

        np.testing.assert_allclose(transformed["position"], [[1.0, 2.0, 1.0]], atol=1e-6)
        np.testing.assert_allclose(transformed["rotation"], [object_rotation], atol=1e-6)
        np.testing.assert_allclose(transformed["scale"], [[2.0, 2.0, 2.0]], atol=1e-6)

    def test_motion_loop_decodes_latent_once_and_closes_without_drift(self) -> None:
        artifact = compression.serialize_quantized_artifact(
            latent_codes=np.asarray([[0], [1]], dtype=np.int8),
            first_weight_codes=np.asarray([[1]], dtype=np.int8),
            first_weight_scales=np.asarray([1.0], dtype=np.float32),
            first_bias=np.asarray([0.0], dtype=np.float16),
            second_weight_codes=np.zeros((6, 1), dtype=np.int8),
            second_weight_scales=np.ones(6, dtype=np.float32),
            second_bias=np.zeros(6, dtype=np.float16),
            latent_bits=8,
        )
        positions = np.asarray([[0.0, 0.0, 0.0], [1.0, 0.0, 0.0]], dtype=np.float32)

        report = motion.run_rigid_motion_benchmark(artifact, positions, frames=9, warmup=1)

        self.assertEqual(report["latent_decode_count"], 1)
        self.assertEqual(report["frames"], 9)
        self.assertEqual(report["splats"], 2)
        self.assertEqual(report["per_frame_transform_bytes"], 32)
        self.assertEqual(report["per_frame_latent_bytes"], 0)
        self.assertLess(report["loop_closure_position_rmse"], 1e-6)
        self.assertLess(report["loop_closure_rotation_degrees"], 1e-4)
        self.assertLess(report["loop_closure_scale_rmse"], 1e-6)
        self.assertTrue(report["all_finite"])
        self.assertGreater(report["motion_frame_median_ms"], 0.0)


if __name__ == "__main__":
    unittest.main()
