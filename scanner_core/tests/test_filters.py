import cv2
import numpy as np
import pytest

from scanner_core import Filter, apply_filter, crop, rotate

@pytest.fixture
def shadowed_page():
    """White page with dark text, lit by a strong left-to-right gradient (shadow)."""
    page = np.full((800, 600, 3), 245, np.uint8)
    for y in range(80, 760, 40):
        cv2.putText(page, "the quick brown fox", (40, y), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (20, 20, 20), 2)
    cv2.rectangle(page, (400, 40), (560, 70), (40, 40, 200), -1)  # red stamp keeps its colour
    light = np.linspace(1.0, 0.45, 600, dtype=np.float32)[None, :, None]
    return (page * light).astype(np.uint8)

def text_mask(shape):
    m = np.zeros(shape[:2], np.uint8)
    for y in range(80, 760, 40):
        cv2.putText(m, "the quick brown fox", (40, y), cv2.FONT_HERSHEY_SIMPLEX, 0.9, 255, 2)
    return m > 0

def test_all_filters_keep_size(shadowed_page):
    for f in Filter:
        out = apply_filter(shadowed_page, f)
        assert out.shape[:2] == shadowed_page.shape[:2]
        assert out.dtype == np.uint8

def test_grayscale_is_single_channel(shadowed_page):
    assert apply_filter(shadowed_page, "grayscale").ndim == 2

def test_bw_is_binary_and_keeps_text(shadowed_page):
    out = apply_filter(shadowed_page, Filter.BW)
    assert set(np.unique(out)) <= {0, 255}
    text = text_mask(out.shape)
    bg = ~cv2.dilate(text.astype(np.uint8), np.ones((9, 9), np.uint8)).astype(bool)
    bg[30:80, 390:570] = False
    assert (out[bg] == 255).mean() > 0.98  # background white even in the shadow
    assert (out[text] == 0).mean() > 0.6   # most stroke pixels black

def test_magic_color_removes_shadow(shadowed_page):
    out = apply_filter(shadowed_page, Filter.MAGIC_COLOR)
    gray = cv2.cvtColor(out, cv2.COLOR_BGR2GRAY)
    text = text_mask(out.shape)
    bg = ~cv2.dilate(text.astype(np.uint8), np.ones((9, 9), np.uint8)).astype(bool)
    bg[30:80, 390:570] = False
    left, right = gray[:, :150][bg[:, :150]], gray[:, 450:][bg[:, 450:]]
    before = cv2.cvtColor(shadowed_page, cv2.COLOR_BGR2GRAY)[:, 450:][bg[:, 450:]]
    assert before.mean() < 150                  # input really is shadowed
    assert left.mean() > 235 and right.mean() > 235
    assert gray[text].mean() < 120              # ink stays dark
    b, g, r = out[50, 480].astype(int)
    assert r > g + 60 and r > b + 60            # colour preserved

def test_rotate():
    img = np.arange(6, dtype=np.uint8).reshape(2, 3)
    assert rotate(img, 1).shape == (3, 2)
    assert rotate(img, 1)[0, 0] == img[1, 0]   # clockwise
    np.testing.assert_array_equal(rotate(img, 4), img)
    np.testing.assert_array_equal(rotate(img, -1), rotate(img, 3))

def test_crop():
    img = np.zeros((100, 200, 3), np.uint8)
    assert crop(img, 0.25, 0.5, 0.5, 0.5).shape == (50, 100, 3)
    with pytest.raises(ValueError):
        crop(img, 0.8, 0, 0.5, 1)

def test_unknown_filter():
    with pytest.raises(ValueError):
        apply_filter(np.zeros((10, 10, 3), np.uint8), "sepia")
