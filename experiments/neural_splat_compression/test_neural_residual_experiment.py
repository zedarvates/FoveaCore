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


if __name__ == "__main__":
    unittest.main()
