"""Generate synthetic but realistic test photos of documents with known corners.

Each fixture is a "phone photo" (1200x1600) of a paper page placed with a
known perspective on a background, with lighting gradients, shadows, noise,
blur and JPEG compression. The ground-truth corners are written to
shared/test_fixtures/expected_corners.json and are reused by the Python,
Dart (native) and web test suites.

Run:  python tests/make_fixtures.py
"""
from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np

OUT = Path(__file__).resolve().parents[2] / "shared" / "test_fixtures"
W, H = 1200, 1600
WORDS = ("invoice total amount date payment account scanner document page "
         "receipt order shipping customer number reference tax summary").split()


def make_paper(rng: np.random.Generator, w=850, h=1100, tint=(245, 246, 248)) -> np.ndarray:
    paper = np.full((h, w, 3), tint, np.uint8)
    cv2.putText(paper, "QUARTERLY REPORT", (70, 120), cv2.FONT_HERSHEY_DUPLEX, 1.6, (40, 40, 40), 3, cv2.LINE_AA)
    cv2.rectangle(paper, (70, 150), (w - 70, 156), (60, 60, 160), -1)
    y = 220
    while y < h - 260:
        x = 70
        while True:
            word = str(rng.choice(WORDS))
            (tw, _), _ = cv2.getTextSize(word, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
            if x + tw > w - 70:
                break
            cv2.putText(paper, word, (x, y), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (30, 30, 30), 2, cv2.LINE_AA)
            x += tw + 14
        y += 42
    # a small table
    for r in range(5):
        cv2.line(paper, (70, h - 230 + r * 40), (w - 70, h - 230 + r * 40), (90, 90, 90), 1)
    for c in range(4):
        x = 70 + c * (w - 140) // 3
        cv2.line(paper, (x, h - 230), (x, h - 70), (90, 90, 90), 1)
    return paper


def bg_wood(rng):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    grain = np.sin(yy / 9.0 + 3 * np.sin(xx / 140.0)) * 0.5 + 0.5
    noise = cv2.GaussianBlur(rng.normal(0, 1, (H, W)).astype(np.float32), (0, 0), 3)
    v = 0.55 + 0.25 * grain + 0.08 * noise
    base = np.array([40, 75, 120], np.float32)  # BGR brown
    return np.clip(base[None, None, :] * v[..., None] * 1.4, 0, 255).astype(np.uint8)


def bg_light_table(rng):
    img = np.full((H, W, 3), (222, 226, 228), np.float32)
    img += cv2.GaussianBlur(rng.normal(0, 4, (H, W, 1)).astype(np.float32), (0, 0), 2)[..., None]
    return np.clip(img, 0, 255).astype(np.uint8)


def bg_cluttered(rng):
    img = np.full((H, W, 3), (95, 90, 80), np.uint8)
    for _ in range(45):
        color = tuple(int(c) for c in rng.integers(0, 255, 3))
        kind = rng.integers(0, 4)
        x, y = int(rng.integers(0, W)), int(rng.integers(0, H))
        if kind == 0:
            cv2.rectangle(img, (x, y), (x + int(rng.integers(30, 220)), y + int(rng.integers(30, 160))), color, -1)
        elif kind == 1:
            cv2.circle(img, (x, y), int(rng.integers(15, 90)), color, -1)
        elif kind == 2:
            cv2.line(img, (x, y), (int(rng.integers(0, W)), int(rng.integers(0, H))), color, int(rng.integers(2, 10)))
        else:
            cv2.putText(img, str(rng.choice(WORDS)), (x, y), cv2.FONT_HERSHEY_SIMPLEX, 1.5, color, 3)
    return img


def place(bg, paper, corners, shadow=True, rng=None):
    h, w = paper.shape[:2]
    src = np.float32([[0, 0], [w, 0], [w, h], [0, h]])
    dst = np.float32(corners)
    M = cv2.getPerspectiveTransform(src, dst)
    warped = cv2.warpPerspective(paper, M, (W, H), flags=cv2.INTER_AREA)
    mask = cv2.warpPerspective(np.full((h, w), 255, np.uint8), M, (W, H))
    out = bg.astype(np.float32)
    if shadow:  # soft drop shadow under the page
        sh = cv2.GaussianBlur(np.roll(mask, (12, 10), (0, 1)), (0, 0), 14).astype(np.float32) / 255
        out *= (1 - 0.35 * sh)[..., None]
    m = cv2.GaussianBlur(mask, (3, 3), 0).astype(np.float32)[..., None] / 255
    return out * (1 - m) + warped.astype(np.float32) * m


def finish(img, rng, light=(1.0, 0.8), noise=4.0, blur=1.0, shadow_band=None):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    a, b = light
    grad = a - (a - b) * (0.6 * xx / W + 0.4 * yy / H)
    img = img * grad[..., None]
    if shadow_band is not None:  # hard-ish shadow (e.g. a phone/hand) across the scene
        (x0, y0), (x1, y1), depth = shadow_band
        band = np.zeros((H, W), np.uint8)
        cv2.fillPoly(band, [np.int32([[x0, y0], [x1, y1], [W, H], [W, y1]])], 255)
        band = cv2.GaussianBlur(band, (0, 0), 25).astype(np.float32) / 255
        img = img * (1 - depth * band)[..., None]
    img = img + rng.normal(0, noise, img.shape)
    img = np.clip(img, 0, 255).astype(np.uint8)
    if blur:
        img = cv2.GaussianBlur(img, (0, 0), blur)
    ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 85])
    return cv2.imdecode(buf, cv2.IMREAD_COLOR)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(42)
    paper = make_paper(rng)
    cases = {}

    def save(name, img, corners, note):
        cv2.imwrite(str(OUT / f"{name}.jpg"), img)
        cases[name] = {"found": corners is not None, "corners": corners, "note": note}

    c = [[260, 230], [1010, 380], [900, 1420], [120, 1260]]
    save("tilted_paper", finish(place(bg_wood(rng), paper, c), rng), c,
         "Page rotated ~12 deg with mild perspective on a wooden desk")

    c = [[170, 200], [1040, 170], [1080, 1430], [140, 1460]]
    save("low_contrast", finish(place(bg_light_table(rng), make_paper(rng, tint=(238, 240, 240)), c, shadow=False),
                                rng, light=(1.0, 0.92), noise=3), c,
         "Off-white page on a near-white table, no drop shadow")

    c = [[330, 290], [960, 340], [920, 1250], [280, 1200]]
    img = place(bg_cluttered(rng), paper, c)
    cv2.line(img, (700, 1380), (1000, 1100), (30, 30, 160), 16, cv2.LINE_AA)  # a pen lying across the bottom edge
    save("cluttered_background", finish(img, rng), c,
         "Page on a busy desk with many coloured shapes and a pen crossing its bottom edge")

    c = [[380, 330], [820, 330], [1130, 1450], [70, 1450]]
    save("strong_perspective", finish(place(bg_wood(rng), paper, c), rng), c,
         "Phone held at a steep angle: strong keystone")

    c = [[150, 180], [1060, 230], [1030, 1400], [170, 1430]]
    save("shadow_across", finish(place(bg_wood(rng), paper, c), rng,
                                 shadow_band=((0, 700), (700, 1000), 0.55)), c,
         "A diagonal shadow (from a hand/phone) falls across the page")

    receipt = make_paper(rng, w=420, h=1200, tint=(250, 250, 247))
    c = [[480, 160], [800, 210], [700, 1480], [380, 1430]]
    save("narrow_receipt", finish(place(bg_wood(rng), receipt, c), rng), c, "Long narrow receipt")

    c = [[25, 30], [1175, 20], [1180, 1575], [20, 1580]]
    save("fills_frame", finish(place(bg_wood(rng), paper, c, shadow=False), rng), c,
         "Page nearly fills the frame, corners close to the image border")

    save("no_document", finish(bg_cluttered(rng).astype(np.float32), rng), None,
         "Cluttered desk without any page: must fall back to full image bounds")

    (OUT / "expected_corners.json").write_text(json.dumps(
        {"image_size": [W, H], "corner_order": "TL,TR,BR,BL", "cases": cases}, indent=2))
    print(f"wrote {len(cases)} fixtures to {OUT}")


if __name__ == "__main__":
    main()
