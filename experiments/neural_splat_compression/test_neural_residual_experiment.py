import math
import struct
import tempfile
import unittest
from pathlib import Path

import numpy as np

import neural_residual_experiment as experiment


class NeuralResidualExperimentTests(unittest.TestCase):
    def test_binary_ply_parser_maps_3dgs_fields(self) -> None:
        header = """ply
format binary_little_endian 1.0
element vertex 1
property float x
property float y
property float z
property float f_dc_0
property float f_dc_1
property float f_dc_2
property float opacity
property float scale_0
property float scale_1
property float scale_2
property float rot_0
property float rot_1
property float rot_2
property float rot_3
end_header
""".encode("ascii")
        values = (
            1.0,
            2.0,
            3.0,
            0.0,
            1.0,
            -1.0,
            0.0,
            math.log(2.0),
            0.0,
            math.log(0.5),
            1.0,
            0.0,
            0.0,
            0.0,
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "one.ply"
            path.write_bytes(header + struct.pack("<14f", *values))
            data = experiment.load_3dgs_ply(path)

        np.testing.assert_allclose(data["position"], [[1.0, 2.0, 3.0]])
        np.testing.assert_allclose(data["scale"], [[2.0, 1.0, 0.5]], rtol=1e-6)
        np.testing.assert_allclose(data["rotation"], [[1.0, 0.0, 0.0, 0.0]])
        np.testing.assert_allclose(
            data["color"],
            [[0.5, 0.78209, 0.21791]],
            rtol=1e-6,
        )
        np.testing.assert_allclose(data["opacity"], [0.5])

    def test_rotation_vector_round_trip_handles_quaternion_sign(self) -> None:
        half = math.sqrt(0.5)
        quaternions = np.array(
            [[half, 0.0, half, 0.0], [-half, 0.0, -half, 0.0]],
            dtype=np.float32,
        )
        vectors = experiment.quaternion_to_rotation_vector(quaternions)
        self.assertEqual(vectors.shape, (2, 3))
        reconstructed = experiment.rotation_vector_to_quaternion(vectors)
        self.assertEqual(reconstructed.shape, (2, 4))
        dots = np.abs(np.sum(quaternions * reconstructed, axis=1))
        np.testing.assert_allclose(dots, [1.0, 1.0], atol=1e-6)

    def test_storage_estimate_counts_latents_and_decoder(self) -> None:
        estimate = experiment.estimate_storage_bytes(
            splat_count=8000,
            latent_dim=2,
            hidden_dim=32,
            latent_bits=8,
        )
        self.assertEqual(estimate["fixed_bytes"], 96072)
        self.assertEqual(estimate["latent_bytes"], 16000)
        self.assertEqual(estimate["decoder_bytes"], 662)
        self.assertEqual(estimate["total_bytes"], 112734)

    def test_quality_gate_rejects_any_regressed_attribute(self) -> None:
        passing = {
            "rotation_mean_degrees": 10.0,
            "scale_rmse": 0.029,
            "color_rmse": 0.037,
        }
        self.assertTrue(experiment.meets_quality_gate(passing))
        failing = dict(passing, rotation_mean_degrees=10.5)
        self.assertFalse(experiment.meets_quality_gate(failing))

    def test_feature_weights_target_rotation_without_reweighting_other_groups(self) -> None:
        weights = experiment.build_feature_weights({"rotation_weight": 4.0})
        np.testing.assert_allclose(weights, [1.0, 1.0, 1.0, 4.0, 4.0, 4.0, 1.0, 1.0, 1.0])

    def test_covariance_only_storage_counts_preserved_palette(self) -> None:
        estimate = experiment.estimate_storage_bytes(
            splat_count=8000,
            latent_dim=6,
            hidden_dim=96,
            latent_bits=8,
            output_dim=6,
            preserve_color_palette=True,
        )
        self.assertEqual(estimate["fixed_bytes"], 96072)
        self.assertEqual(estimate["preserved_color_bytes"], 11072)
        self.assertEqual(estimate["latent_bytes"], 48000)
        self.assertEqual(estimate["decoder_bytes"], 1828)
        self.assertEqual(estimate["total_bytes"], 156972)

    def test_covariance_only_features_exclude_rgb(self) -> None:
        data = {
            "scale": np.ones((2, 3), dtype=np.float32),
            "rotation": np.asarray(
                [[1.0, 0.0, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]],
                dtype=np.float32,
            ),
            "color": np.asarray([[1.0, 0.2, 0.3], [0.1, 0.8, 0.4]], dtype=np.float32),
        }
        features = experiment.build_features(data, "covariance_only")
        self.assertEqual(features.shape, (2, 6))
        np.testing.assert_allclose(features, np.zeros((2, 6)), atol=1e-7)

    def test_covariance_only_metrics_preserve_measured_palette_error(self) -> None:
        data = {
            "scale": np.ones((1, 3), dtype=np.float32),
            "rotation": np.asarray([[1.0, 0.0, 0.0, 0.0]], dtype=np.float32),
            "color": np.asarray([[0.9, 0.1, 0.5]], dtype=np.float32),
        }
        decoded = np.zeros((1, 6), dtype=np.float32)
        metrics = experiment.quality_metrics(data, decoded, preserve_color_palette=True)
        self.assertAlmostEqual(metrics["rotation_mean_degrees"], 0.0)
        self.assertAlmostEqual(metrics["scale_rmse"], 0.0)
        self.assertAlmostEqual(
            metrics["color_rmse"],
            experiment.QUALITY_LIMITS["color_rmse"],
        )

    def test_binary_artifact_round_trip_decodes_without_model(self) -> None:
        artifact = experiment.serialize_quantized_artifact(
            latent_codes=np.asarray([[1], [2]], dtype=np.int8),
            first_weight_codes=np.asarray([[2]], dtype=np.int8),
            first_weight_scales=np.asarray([0.5], dtype=np.float32),
            first_bias=np.asarray([0.0], dtype=np.float16),
            second_weight_codes=np.asarray([[4]], dtype=np.int8),
            second_weight_scales=np.asarray([0.25], dtype=np.float32),
            second_bias=np.asarray([0.0], dtype=np.float16),
            latent_bits=8,
        )
        self.assertEqual(len(artifact), 80)
        decoded = experiment.decode_quantized_artifact(artifact)
        np.testing.assert_allclose(decoded[:, 0], np.tanh([1.0, 2.0]), atol=1e-6)

    def test_binary_artifact_rejects_corrupt_magic(self) -> None:
        artifact = bytearray(
            experiment.serialize_quantized_artifact(
                latent_codes=np.asarray([[0]], dtype=np.int8),
                first_weight_codes=np.asarray([[1]], dtype=np.int8),
                first_weight_scales=np.asarray([1.0], dtype=np.float32),
                first_bias=np.asarray([0.0], dtype=np.float16),
                second_weight_codes=np.asarray([[1]], dtype=np.int8),
                second_weight_scales=np.asarray([1.0], dtype=np.float32),
                second_bias=np.asarray([0.0], dtype=np.float16),
                latent_bits=8,
            )
        )
        artifact[0:4] = b"NOPE"
        with self.assertRaisesRegex(ValueError, "magic"):
            experiment.decode_quantized_artifact(bytes(artifact))

    def test_decode_benchmark_reports_real_repeated_decodes(self) -> None:
        artifact = experiment.serialize_quantized_artifact(
            latent_codes=np.asarray([[1], [2]], dtype=np.int8),
            first_weight_codes=np.asarray([[2]], dtype=np.int8),
            first_weight_scales=np.asarray([0.5], dtype=np.float32),
            first_bias=np.asarray([0.0], dtype=np.float16),
            second_weight_codes=np.asarray([[4]], dtype=np.int8),
            second_weight_scales=np.asarray([0.25], dtype=np.float32),
            second_bias=np.asarray([0.0], dtype=np.float16),
            latent_bits=8,
        )
        report = experiment.benchmark_decode(artifact, warmup=1, repeats=5)
        self.assertEqual(report["decode_repeats"], 5)
        self.assertEqual(report["decoded_splats"], 2)
        self.assertEqual(report["decoded_dimensions"], 1)
        self.assertGreater(report["decode_median_ms"], 0.0)
        self.assertGreaterEqual(report["decode_p95_ms"], report["decode_median_ms"])


if __name__ == "__main__":
    unittest.main()
