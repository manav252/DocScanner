import cv2
import numpy as np

import make_fixtures as mf
from conftest import SPEC, load_fixture
from scanner_core import output_size, page_curves, warp_page, warp_perspective


def ncc(a, b):
    a = a.astype(np.float32) - a.mean()
    b = b.astype(np.float32) - b.mean()
    return float((a * b).sum() / np.sqrt((a * a).sum() * (b * b).sum()))


def test_warp_recovers_flat_page():
    rng = np.random.default_rng(7)
    paper = mf.make_paper(rng)
    corners = [[260, 230], [1010, 380], [900, 1420], [120, 1260]]
    scene = mf.place(mf.bg_wood(rng), paper, corners).astype(np.uint8)
    flat = warp_perspective(scene, np.float32(corners)[[2, 0, 3, 1]])  # order must not matter
    ref = cv2.resize(paper, (flat.shape[1], flat.shape[0]), interpolation=cv2.INTER_AREA)

    def g(im):
        return cv2.GaussianBlur(cv2.cvtColor(im, cv2.COLOR_BGR2GRAY), (5, 5), 0)

    assert ncc(g(flat), g(ref)) > 0.9


def test_output_size_axis_aligned():
    assert output_size(np.float32([[0, 0], [400, 0], [400, 300], [0, 300]])) == (400, 300)


def test_output_size_uses_longest_edges():
    w, h = output_size(np.float32([[380, 330], [820, 330], [1130, 1450], [70, 1450]]))
    assert w == 1060 and h > 1120


def test_max_side_caps_output():
    img = load_fixture("tilted_paper")
    out = warp_perspective(img, np.float32(SPEC["cases"]["tilted_paper"]["corners"]), max_side=500)
    assert max(out.shape[:2]) == 500


def _hard():
    import json
    from pathlib import Path

    d = Path(__file__).resolve().parents[2] / "shared" / "test_fixtures" / "hard"
    return d, json.loads((d / "hard_cases.json").read_text())["cases"]


def _rule_bend(img):
    """How much the red rule under the page title bends (% of page height)."""
    b, r = img[..., 0].astype(int), img[..., 2].astype(int)
    mask = (r - b > 50) & (r > 110)
    h, w = mask.shape
    ys = []
    for x in range(int(0.12 * w), int(0.88 * w), 4):
        col = np.nonzero(mask[int(0.05 * h) : int(0.3 * h), x])[0]
        if len(col):
            ys.append(np.median(col))
    return (max(ys) - min(ys)) / h * 100


def test_curved_pages_come_out_flat():
    """Book-like pages (top and bottom edges bow): the grid warp straightens
    the title rule that a single perspective warp leaves bent."""
    d, cases = _hard()
    for it in cases["curved"]:
        img, c = cv2.imread(str(d / it["file"])), np.float32(it["corners"])
        assert page_curves(img, c) is not None, it["file"]
        before, after = _rule_bend(warp_perspective(img, c)), _rule_bend(warp_page(img, c))
        assert before > 2.5 and after < 1.0, f"{it['file']}: bend {before:.2f}% -> {after:.2f}%"


def test_flat_pages_keep_the_plain_perspective_warp():
    d, cases = _hard()
    for name in ("hand_held", "plain_white", "half_shadow", "handwritten", "cluttered", "pan"):
        for it in cases[name]:
            assert page_curves(cv2.imread(str(d / it["file"])), np.float32(it["corners"])) is None, it["file"]
    for name, case in SPEC["cases"].items():
        if case["found"]:
            assert page_curves(load_fixture(name), np.float32(case["corners"])) is None, name
