import importlib.util
import json
import struct
import sys
import unittest
import zlib
from pathlib import Path

import numpy as np

module, image_path = map(Path, sys.argv[1:3])
sys.argv = sys.argv[:1]
spec = importlib.util.spec_from_file_location("hdr_grade", module)
hdr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hdr)


class WallpaperHdrTest(unittest.TestCase):
    def test_grade_protects_diffuse_and_person(self):
        grey = np.full((220, 424, 3), 0.5, dtype=np.float32)
        radiance, boost = hdr.grade(grey)
        self.assertEqual(float(boost.max()), 0.0)
        np.testing.assert_allclose(radiance, ((0.5 + 0.055) / 1.055) ** 2.4 * 203, rtol=1e-6)
        white, boost = hdr.grade(np.ones_like(grey))
        self.assertAlmostEqual(float(white[112, 231].max()), 203.0, places=3)
        self.assertEqual(float(boost[112, 231]), 0.0)
        self.assertGreater(float(white[47, 304].max()), 450)
        self.assertLessEqual(float(white.max()), 480.001)

    def test_pq_is_absolute_and_reversible(self):
        nits = np.array([0, 0.001, 1, 100, 203, 480, 10000], dtype=np.float64)
        np.testing.assert_allclose(hdr.pq_decode(hdr.pq_encode(nits)), nits, atol=1e-7)
        self.assertAlmostEqual(float(hdr.pq_encode(np.array(203))), 0.58069, places=4)

    def test_actual_png_pixels_and_metadata(self):
        data = image_path.read_bytes()
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        chunks = {}
        offset = 8
        compressed = []
        while offset < len(data):
            length = struct.unpack_from(">I", data, offset)[0]
            kind = data[offset + 4:offset + 8]
            payload = data[offset + 8:offset + 8 + length]
            crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
            self.assertEqual(zlib.crc32(kind + payload), crc)
            chunks[kind] = payload
            if kind == b"IDAT":
                compressed.append(payload)
            offset += length + 12
        width, height, depth, color, _, _, _ = struct.unpack(">IIBBBBB", chunks[b"IHDR"])
        self.assertEqual((width, height, depth, color), (4233, 2195, 16, 2))
        self.assertEqual(chunks[b"cICP"], bytes([9, 16, 0, 1]))
        self.assertNotIn(b"gAMA", chunks)
        self.assertNotIn(b"sRGB", chunks)
        rows = np.frombuffer(zlib.decompress(b"".join(compressed)), dtype=np.uint8).reshape(height, width * 6 + 1)
        self.assertTrue((rows[:, 0] == 1).all())
        decoded = rows[:, 1:].copy()
        for channel_byte in range(6):
            decoded[:, channel_byte::6] = np.cumsum(rows[:, channel_byte + 1::6], axis=1, dtype=np.uint32) % 256
        pq = decoded.reshape(height, width, 6).view(">u2").reshape(height, width, 3).astype(np.float64) / 65535
        rgb = hdr.pq_decode(pq)
        self.assertTrue(np.isfinite(rgb).all())
        self.assertLessEqual(float(rgb.max()), 480.1)
        self.assertGreater(float(rgb.max()), 470)
        luminance = rgb @ np.array([0.2627, 0.6780, 0.0593])
        cll, fall = struct.unpack(">2I", chunks[b"cLLI"])
        self.assertAlmostEqual(cll / 10000, float(luminance.max()), delta=0.1)
        self.assertAlmostEqual(fall / 10000, float(luminance.mean()), delta=0.01)
        report = json.loads(image_path.with_suffix(".json").read_text())
        self.assertLess(report["pixels_above_sdr_white_percent"], 5)
        self.assertGreater(report["pixels_above_sdr_white_percent"], 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
