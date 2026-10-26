import time

import cv2
import numpy as np
import pytest

import make_fixtures as mf
from conftest import SPEC, load_fixture, max_corner_error
from scanner_core import detect_document, full_bounds, order_corners

W, H = SPEC["image_size"]
TOLERANCE = 0.01 * np.hypot(W, H)  # 1% of the diagonal (20 px on a 1200x1600 photo)


@pytest.mark.parametrize("name", list(SPEC["cases"]))
def test_fixture(name):
    case = SPEC["cases"][name]
    det = detect_document(load_fixture(name))
    assert det.found == case["found"], case["note"]
    if case["found"]:
        err = max_corner_error(det.corners, case["corners"])
        assert err < TOLERANCE, f"{name}: corner error {err:.1f}px"
    else:
        np.testing.assert_allclose(det.corners, full_bounds(W, H))


@pytest.mark.parametrize("seed", range(40))
def test_random_placements(seed):
    """Random rotation/perspective/scale on random backgrounds."""
    rng = np.random.default_rng(1000 + seed)
    paper = mf.make_paper(rng)
    cx, cy = rng.uniform(450, 750), rng.uniform(600, 1000)
    sw, sh = rng.uniform(280, 430), rng.uniform(380, 560)
    ang = np.radians(rng.uniform(-30, 30))
    base = np.float32([[-sw, -sh], [sw, -sh], [sw, sh], [-sw, sh]])
    base += rng.uniform(-50, 50, (4, 2))  # perspective jitter
    R = np.float32([[np.cos(ang), -np.sin(ang)], [np.sin(ang), np.cos(ang)]])
    corners = (base @ R.T + [cx, cy]).clip([10, 10], [W - 10, H - 10]).tolist()
    bg = [mf.bg_wood, mf.bg_cluttered, mf.bg_light_table][seed % 3](rng)
    img = mf.finish(mf.place(bg, paper, corners, shadow=seed % 3 != 2), rng)
    det = detect_document(img)
    assert det.found
    assert max_corner_error(det.corners, order_corners(np.float32(corners))) < TOLERANCE


def test_blank_and_tiny_images_fall_back_to_bounds():
    for img in (np.zeros((40, 60, 3), np.uint8), np.full((720, 1280, 3), 128, np.uint8)):
        det = detect_document(img)
        assert not det.found
        np.testing.assert_allclose(det.corners, full_bounds(img.shape[1], img.shape[0]))


def test_accepts_grayscale():
    det = detect_document(cv2.cvtColor(load_fixture("tilted_paper"), cv2.COLOR_BGR2GRAY))
    assert det.found


def test_empty_image_raises():
    with pytest.raises(ValueError):
        detect_document(np.zeros((0, 0, 3), np.uint8))


@pytest.mark.parametrize("deg", [0, 10, 30, 44, -20, -44])
def test_order_corners_rotated(deg):
    rect = np.float32([[100, 100], [300, 100], [300, 400], [100, 400]])
    c = rect.mean(axis=0)
    a = np.radians(deg)
    R = np.float32([[np.cos(a), -np.sin(a)], [np.sin(a), np.cos(a)]])
    rot = (rect - c) @ R.T + c
    for perm in ([0, 1, 2, 3], [2, 0, 3, 1], [3, 2, 1, 0]):
        np.testing.assert_allclose(order_corners(rot[perm]), rot, atol=1e-4)


def test_order_corners_keystone():
    q = np.float32([[380, 330], [820, 330], [1130, 1450], [70, 1450]])
    np.testing.assert_allclose(order_corners(q[[1, 3, 0, 2]]), q)


def test_speed_on_hd_frame():
    """Live preview budget: well under 66 ms (15 fps) per 1280x720 frame."""
    frame = cv2.resize(load_fixture("cluttered_background"), (720, 1280))
    detect_document(frame)
    t = time.perf_counter()
    for _ in range(20):
        detect_document(frame)
    ms = (time.perf_counter() - t) / 20 * 1000
    print(f"detect_document 1280x720: {ms:.1f} ms")
    assert ms < 30


def test_params_match_shared_json():
    """detector_params.json is the contract the Dart and JS ports are checked against."""
    import json
    from pathlib import Path

    from scanner_core import detect as D

    p = json.loads((Path(__file__).resolve().parents[2] / "shared" / "detector_params.json").read_text())
    assert (D.MAX_DIM, D.MIN_AREA_RATIO, D.MIN_FILL_RATIO, D.MAX_EDGE_DEVIATION, D.MIN_ANGLE, D.MAX_ANGLE) == (
        p["max_dim"],
        p["min_area_ratio"],
        p["min_fill_ratio"],
        p["max_edge_deviation"],
        p["min_angle"],
        p["max_angle"],
    )
    assert list(D.APPROX_EPSILONS) == p["approx_epsilons"]
    assert (D.MAX_BOW, D.CURVED_BOW, D.MIN_SUPPORT, D.MIN_LINE_SUPPORT, D.STEP_OFFSET, D.STEP_MIN) == (
        p["max_bow"],
        p["curved_bow"],
        p["min_support"],
        p["min_line_support"],
        p["step_offset"],
        p["step_min"],
    )
    assert (D.LINE_COUNT, D.CONFIDENT_SCORE, D.HOUGH_THRESHOLD, D.HOUGH_MIN_LENGTH, D.HOUGH_MAX_GAP) == (
        p["line_count"],
        p["confident_score"],
        p["hough_threshold"],
        p["hough_min_length"],
        p["hough_max_gap"],
    )
