"""Phone-test scenes: synthetic versions of the six scenes that failed on a real
phone (Oct 2026). Eight seeded photos per scene (1200x1600, JPEG), written to
shared/test_fixtures/scenes/ with scene_cases.json:

  card_on_white   small ID card on a white sheet that runs off the frame
  card_flash      ID card ~60 % of the frame width on white paper, flash glare
  card_close      ID card very close and blurry, corners near the frame edges
  blank_on_cloth  blank white page on checked cloth (must not return the frame)
  blank_shadow    blank page with a half shadow across it
  notebook        ruled, handwritten page of an open notebook: soft spine side,
                  shadow on top, bottom running off the frame
  card_on_pattern ID card, flash on, on a busy block-printed cloth (blue stepped
                  diamonds and orange vines on cream) whose edges merge with the card's

"corners" is the page (or card) outline, TL,TR,BR,BL; corners outside the
photo are clamped to it (what the detector should return). All card data is
invented. Real photos of the same scenes go in tests/fixtures/real/ (not in git).

Run:  python tests/make_scene_cases.py
"""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np

import make_fixtures as mf
import make_hard_cases as hc

OUT = Path(__file__).resolve().parents[2] / "shared" / "test_fixtures" / "scenes"
W, H = mf.W, mf.H
PER_CASE = 8


def quad(rng, cx, cy, half_w, half_h, tilt, jitter=0.0):
    """A rotated rectangle (with optional corner jitter), not clipped to the frame."""
    a = np.radians(rng.uniform(-tilt, tilt))
    base = np.float32([[-half_w, -half_h], [half_w, -half_h], [half_w, half_h], [-half_w, half_h]])
    base += rng.uniform(-jitter, jitter, (4, 2)).astype(np.float32)
    rot = np.float32([[np.cos(a), -np.sin(a)], [np.sin(a), np.cos(a)]])
    return base @ rot.T + np.float32([cx, cy])


def put(bg, img, q):
    """Warp [img] onto [bg] at quad [q] (no drop shadow)."""
    h, w = img.shape[:2]
    M = cv2.getPerspectiveTransform(np.float32([[0, 0], [w, 0], [w, h], [0, h]]), np.float32(q))
    warped = cv2.warpPerspective(img, M, (W, H), flags=cv2.INTER_AREA)
    m = cv2.warpPerspective(np.full((h, w), 255, np.uint8), M, (W, H))
    m = cv2.GaussianBlur(m, (3, 3), 0).astype(np.float32)[..., None] / 255
    return bg.astype(np.float32) * (1 - m) + warped.astype(np.float32) * m


def white_sheet(rng, w=900, h=1200, level=None):
    v = level if level is not None else rng.uniform(238, 250)
    img = np.full((h, w, 3), v, np.float32)
    img += cv2.GaussianBlur(rng.normal(0, 3, (h, w)).astype(np.float32), (0, 0), 1.5)[..., None]
    return np.clip(img, 0, 255).astype(np.uint8)


def glare(img, rng, centre, radius, strength):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    g = np.exp(-((xx - centre[0]) ** 2 + (yy - centre[1]) ** 2) / (2 * radius**2))
    return img + strength * g[..., None]


def flash_falloff(img):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    r = np.hypot((xx - W / 2) / W, (yy - H / 2) / H)
    return img * (1.05 - 0.55 * r**2)[..., None]


def notebook_page(rng, w=820, h=1150):
    """Ruled page with a margin and handwriting."""
    page = np.full((h, w, 3), (236, 240, 238), np.uint8)
    for y in range(110, h - 30, 34):
        cv2.line(page, (0, y), (w, y), (205, 175, 150), 2, cv2.LINE_AA)  # light blue rules (BGR)
    cv2.line(page, (95, 0), (95, h), (150, 150, 230), 2, cv2.LINE_AA)  # red margin
    return hc.handwriting(page, rng)


def light_checks(rng):
    """Checked cloth in white and a pale colour (gingham)."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    p = rng.uniform(14, 30)
    a = ((np.floor(xx / p) % 2) + (np.floor(yy / p) % 2))[..., None] / 2  # 0, 0.5, 1
    white = np.float32([235, 236, 238])
    colour = rng.integers(120, 210, 3).astype(np.float32)
    img = white * (1 - a) + colour * a
    return np.clip(img + rng.normal(0, 4, img.shape), 0, 255).astype(np.uint8)


def block_print(rng):
    """Cream cloth with blue stepped (pixelated) diamonds and thin orange vines."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    p = rng.uniform(150, 220)  # diamond period
    step = p / rng.uniform(7, 10)  # stair steps along the diamond's edges
    qx, qy = np.floor(xx / step) * step, np.floor(yy / step) * step
    d = np.abs(((qx + qy) % p) - p / 2) + np.abs(((qx - qy) % p) - p / 2)
    diamonds = (d < p * 0.42).astype(np.float32)[..., None]
    cream = np.float32([175, 205, 225]) + rng.uniform(-10, 10, 3)
    blue = np.float32([120, 70, 40]) + rng.uniform(-15, 15, 3)
    img = cream * (1 - diamonds) + blue * diamonds
    vines = (np.abs(np.sin(xx / rng.uniform(17, 25) + 3 * np.sin(yy / rng.uniform(30, 45)))) < 0.08)[..., None]
    img = np.where(vines, np.float32([60, 120, 200]), img)
    return np.clip(img + rng.normal(0, 5, img.shape), 0, 255).astype(np.uint8)


def clamp(q):
    return np.clip(q, [0, 0], [W - 1, H - 1])


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    cases: dict[str, list] = {}

    def save(case, i, img, corners, extra=None):
        name = f"{case}_{i:02d}"
        cv2.imwrite(str(OUT / f"{name}.jpg"), img, [cv2.IMWRITE_JPEG_QUALITY, 80])
        cases.setdefault(case, []).append(
            {"file": f"{name}.jpg", "corners": np.round(clamp(corners), 1).tolist(), **(extra or {})}
        )

    for i in range(PER_CASE):
        rng = np.random.default_rng(9100 + i)
        kind = "aadhaar" if i % 2 == 0 else "pan"

        # 1. Small card on a white sheet that runs off the frame.
        sheet = quad(rng, W / 2 + rng.uniform(-150, 150), H / 2 + rng.uniform(-150, 150), 720, 900, 8)
        img = put(mf.bg_wood(rng), white_sheet(rng), sheet)
        card, _ = hc.card(kind, rng)
        s = rng.uniform(0.25, 0.35) * W / card.shape[1]
        q = quad(rng, rng.uniform(450, 750), rng.uniform(650, 950), card.shape[1] * s / 2, card.shape[0] * s / 2, 20, 6)
        img = put(img, card, q)
        save("card_on_white", i, mf.finish(img, rng, light=(1.0, 0.9)), q)

        # 2. Card ~60 % of the frame width on white paper, flash on: glare on the card.
        bg = white_sheet(rng, W, H)
        card, _ = hc.card(kind, rng)
        s = rng.uniform(0.55, 0.65) * W / card.shape[1]
        q = quad(rng, rng.uniform(560, 640), rng.uniform(700, 900), card.shape[1] * s / 2, card.shape[0] * s / 2, 10, 8)
        img = flash_falloff(put(bg, card, q))
        c = q.mean(axis=0) + rng.uniform(-120, 120, 2)
        img = glare(img, rng, c, rng.uniform(60, 110), rng.uniform(120, 200))
        save("card_flash", i, mf.finish(img, rng, light=(1.0, 0.95), noise=3), q)

        # 3. Card very close and blurry, corners at the frame edges.
        bg = mf.bg_wood(rng) if i % 2 else hc.bg_cloth(rng)
        card, _ = hc.card(kind, rng)
        s = rng.uniform(0.9, 0.98) * W / card.shape[1]
        q = quad(rng, W / 2 + rng.uniform(-20, 20), H / 2 + rng.uniform(-80, 80), card.shape[1] * s / 2, card.shape[0] * s / 2, 4, 10)
        img = cv2.GaussianBlur(np.clip(put(bg, card, q), 0, 255).astype(np.uint8), (0, 0), rng.uniform(2.5, 4)).astype(np.float32)
        save("card_close", i, mf.finish(img, rng), q)

        # 4. Blank white page, large in the frame, on light checked cloth.
        q = hc.random_quad(rng, cx=(560, 640), cy=(760, 840), half_w=(420, 520), half_h=(560, 700), tilt=8, jitter=30)
        img = mf.place(light_checks(rng), white_sheet(rng, 850, 1100), q, shadow=False)
        save("blank_on_cloth", i, mf.finish(img, rng), q)

        # 5. Blank page, half in shadow.
        q = hc.random_quad(rng)
        bg = hc.bg_cloth(rng) if i % 2 else mf.bg_wood(rng)
        img = mf.place(bg, white_sheet(rng, 850, 1100), q)
        x = rng.uniform(0.35, 0.65) * W
        shadow = np.zeros((H, W), np.float32)
        if i % 2:
            shadow[:, : int(x)] = 1
        else:
            shadow[:, int(x) :] = 1
        shadow = cv2.GaussianBlur(shadow, (0, 0), rng.uniform(10, 40))
        img = img * (1 - rng.uniform(0.55, 0.7) * shadow)[..., None]
        save("blank_shadow", i, mf.finish(img, rng), q)

        # 6. Open notebook: the right-hand page is the target. Its left side is
        # the spine (a soft fold shadow, no sharp edge), the bottom runs off the
        # frame, a shadow lies across the top.
        right = notebook_page(rng)
        left = notebook_page(rng)
        ph, pw = right.shape[:2]
        spine_x = rng.uniform(80, 200)
        top = rng.uniform(90, 200)
        page_w = rng.uniform(820, 960)
        page_h = (H - top) + rng.uniform(40, 120)  # bottom beyond the frame
        a = np.radians(rng.uniform(-4, 4))
        rot = np.float32([[np.cos(a), -np.sin(a)], [np.sin(a), np.cos(a)]])
        origin = np.float32([spine_x, top])
        q = np.float32([[0, 0], [page_w, 0], [page_w, page_h], [0, page_h]]) @ rot.T + origin
        lq = np.float32([[-page_w, 0], [0, 0], [0, page_h], [-page_w, page_h]]) @ rot.T + origin
        cover = np.float32([[-page_w - 25, -18], [page_w + 22, -18], [page_w + 22, page_h + 20], [-page_w - 25, page_h + 20]]) @ rot.T + origin
        bg = mf.bg_wood(rng).astype(np.float32)
        cv2.fillPoly(bg, [np.int32(cover)], (60, 50, 45))  # dark cover around the pages
        img = put(put(bg, left, lq), right, q)
        # Fold shadow along the spine, fading into both pages.
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        d = (xx - origin[0]) * np.cos(a) + (yy - origin[1]) * np.sin(a)
        img = img * (1 - 0.45 * np.exp(-((d / rng.uniform(25, 45)) ** 2)))[..., None]
        shadow = ((xx - 0) * 0 + yy < top + rng.uniform(120, 260)).astype(np.float32)
        shadow = cv2.GaussianBlur(shadow, (0, 0), 30)
        img = img * (1 - rng.uniform(0.3, 0.5) * shadow)[..., None]
        save("notebook", i, mf.finish(img, rng), q)

    for i in range(PER_CASE):
        # 7. Card on block-printed cloth, flash on (a separate loop: the scenes
        # above keep their random draws).
        rng = np.random.default_rng(9300 + i)
        kind = "aadhaar" if i % 2 == 0 else "pan"
        card, _ = hc.card(kind, rng)
        s = rng.uniform(0.75, 0.9) * W / card.shape[1]
        q = quad(rng, W / 2 + rng.uniform(-40, 40), H / 2 + rng.uniform(-150, 250), card.shape[1] * s / 2, card.shape[0] * s / 2, 4, 4)
        img = flash_falloff(put(block_print(rng), card, q))
        c = q.mean(axis=0) + rng.uniform(-150, 150, 2)
        img = glare(img, rng, c, rng.uniform(80, 140), rng.uniform(60, 120))
        save("card_on_pattern", i, mf.finish(img, rng, light=(1.0, 0.95), noise=3), q)

    (OUT / "scene_cases.json").write_text(
        json.dumps({"image_size": [W, H], "corner_order": "TL,TR,BR,BL", "cases": cases}, indent=1, ensure_ascii=False)
    )
    print(f"wrote {sum(len(v) for v in cases.values())} photos in {len(cases)} cases to {OUT}")


if __name__ == "__main__":
    main()
