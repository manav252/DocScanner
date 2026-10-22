import numpy as np
import pytest

from conftest import SPEC, load_fixture
from scanner_core import decode_image, encode_image, scan


def test_scan_auto_detect_round_trip():
    data = encode_image(load_fixture("tilted_paper"))
    res = scan(decode_image(data), filter="bw")
    assert res.found and res.image.ndim == 2
    h, w = res.image.shape
    assert 0.65 < w / h < 0.85  # letter page ~0.77


def test_scan_with_manual_corners_and_rotation():
    img = load_fixture("strong_perspective")
    res = scan(img, corners=np.float32(SPEC["cases"]["strong_perspective"]["corners"]), quarter_turns=1)
    assert res.image.shape[1] > res.image.shape[0]  # rotated to landscape


def test_decode_rejects_garbage():
    with pytest.raises(ValueError):
        decode_image(b"not an image")
