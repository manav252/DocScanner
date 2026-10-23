import cv2
import numpy as np

import make_fixtures as mf
from conftest import SPEC, load_fixture
from scanner_core import output_size, warp_perspective


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
