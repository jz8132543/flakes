"""Generate wallpaper variants without reconstructing lost source detail."""

import argparse
import io
import json
import struct
import zlib
from pathlib import Path

import numpy as np
from PIL import Image, ImageCms

WHITE = 203.0
PEAK = 480.0
SRGB_TO_2020 = np.array(
    [[0.6274039, 0.3292830, 0.0433131],
     [0.0690973, 0.9195404, 0.0113623],
     [0.0163914, 0.0880133, 0.8955953]],
    dtype=np.float32,
)


def pq_encode(nits):
    power = np.power(np.maximum(nits, 0) / 10000.0, 2610 / 16384)
    return np.power((3424 / 4096 + 2413 / 128 * power)
                    / (1 + 2392 / 128 * power), 2523 / 32)


def pq_decode(code):
    power = np.power(code, 32 / 2523)
    return 10000 * np.power(np.maximum(power - 3424 / 4096, 0)
                            / (2413 / 128 - 2392 / 128 * power), 16384 / 2610)


def srgb_to_linear(rgb):
    return np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)


def grade(rgb):
    linear = srgb_to_linear(rgb)
    height, width = linear.shape[:2]
    y, x = np.ogrid[:height, :width]
    x = (x + 0.5) / width
    y = (y + 0.5) / height
    mask = np.zeros((height, width), dtype=np.float32)
    # Hand-selected lanterns, stage lamps, string lights and audience glow sticks.
    # The broad white costume and skin are deliberately outside these regions.
    lights = [
        (0.246, 0.055, 0.025, 0.055), (0.820, 0.032, 0.022, 0.050),
        (0.352, 0.182, 0.055, 0.110), (0.731, 0.098, 0.055, 0.100),
        (0.306, 0.305, 0.055, 0.045), (0.718, 0.211, 0.030, 0.038),
        (0.150, 0.410, 0.035, 0.033), (0.880, 0.534, 0.020, 0.060),
        (0.255, 0.763, 0.027, 0.035), (0.314, 0.731, 0.018, 0.025),
        (0.770, 0.737, 0.026, 0.030), (0.779, 0.790, 0.024, 0.026),
        (0.037, 0.977, 0.080, 0.065), (0.205, 0.913, 0.075, 0.052),
        (0.760, 0.985, 0.072, 0.065), (0.850, 0.942, 0.075, 0.110),
        (0.969, 0.855, 0.055, 0.140),
    ]
    for cx, cy, sx, sy in lights:
        distance = ((x - cx) / sx) ** 2 + ((y - cy) / sy) ** 2
        np.maximum(mask, np.exp(-distance / 2), out=mask)
    person = ((x - 0.545) / 0.105) ** 2 + ((y - 0.51) / 0.49) ** 2
    feather = np.clip((person - 0.8) / 0.5, 0, 1)
    mask *= feather * feather * (3 - 2 * feather)
    # Smooth shoulder: diffuse tones remain unchanged; only near-white light cores expand.
    maximum = linear.max(axis=2)
    shoulder = np.clip((maximum - 0.60) / 0.40, 0, 1)
    shoulder = shoulder * shoulder * (3 - 2 * shoulder)
    boost = (PEAK - WHITE) * shoulder * mask
    radiance = linear * (WHITE + boost / np.maximum(maximum, 1e-6))[..., None]
    result = radiance @ SRGB_TO_2020.T
    return result.astype(np.float32), boost


def write_png(path, radiance, mastering_peak=PEAK):
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))

    height, width = radiance.shape[:2]
    pixels = np.rint(pq_encode(radiance) * 65535).astype(">u2")
    rows = pixels.view(np.uint8).reshape(height, width * 6)
    # PNG Sub filtering is lossless and keeps the high-bit-depth master compact.
    filtered = rows.copy()
    filtered[:, 6:] = rows[:, 6:] - rows[:, :-6]
    scanlines = np.zeros((height, width * 6 + 1), dtype=np.uint8)
    scanlines[:, 0] = 1
    scanlines[:, 1:] = filtered
    luminance = radiance @ np.array([0.2627, 0.6780, 0.0593], dtype=np.float32)
    cll, fall = float(luminance.max()), float(luminance.mean())
    with path.open("wb") as output:
        output.write(b"\x89PNG\r\n\x1a\n")
        output.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 16, 2, 0, 0, 0)))
        output.write(chunk(b"cICP", bytes([9, 16, 0, 1])))
        if mastering_peak is not None:
            output.write(chunk(b"mDCV", struct.pack(">8H2I", 35400, 14600, 8500, 39850,
                                                  6550, 2300, 15635, 16450,
                                                  round(mastering_peak * 10000), 0)))
        output.write(chunk(b"cLLI", struct.pack(">2I", round(cll * 10000), round(fall * 10000))))
        output.write(chunk(b"IDAT", zlib.compress(scanlines.tobytes(), 6)))
        output.write(chunk(b"IEND", b""))
    decoded = pq_decode(pixels.astype(np.float64) / 65535)
    assert np.isfinite(decoded).all()
    assert decoded.max() <= (mastering_peak if mastering_peak is not None else WHITE) + 0.1
    assert np.max(np.abs(decoded - radiance)) < 0.1
    return cll, fall


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preserve-sdr", action="store_true", help="map SDR white to 203 nits without boosting highlights")
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    source, destination = args.source, args.destination
    with Image.open(source) as image:
        width, height = image.size
        icc = image.info.get("icc_profile")
        if icc:
            image = ImageCms.profileToProfile(image, ImageCms.ImageCmsProfile(io.BytesIO(icc)),
                                             ImageCms.createProfile("sRGB"), outputMode="RGB")
        rgb = np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0
    if args.preserve_sdr:
        # Clip only floating-point overshoot at white; the matrix maps sRGB inside BT.2020.
        radiance = np.minimum((srgb_to_linear(rgb) * WHITE) @ SRGB_TO_2020.T, WHITE)
        mastering_peak = None
        method = "SDR colorimetry preserved in BT.2020 PQ; no highlight expansion"
    else:
        radiance, boost = grade(rgb)
        mastering_peak = PEAK
        method = "Image-specific local inverse tone mapping; no AI reconstruction"
    cll, fall = write_png(destination, radiance, mastering_peak)
    if not args.preserve_sdr:
        assert boost.max() > 200, "The selected light sources must extend beyond SDR white"
    report = {
        "source": source.name, "width": width, "height": height,
        "bit_depth": 16, "primaries": "BT.2020", "transfer": "ST 2084 PQ",
        "reference_white_nits": WHITE, "mastering_peak_nits": mastering_peak,
        "max_rgb_nits": float(radiance.max()), "max_cll_nits": cll, "max_fall_nits": fall,
        "pixels_above_sdr_white_percent": float((radiance.max(axis=2) > WHITE).mean() * 100),
        "method": method,
    }
    destination.with_suffix(".json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
