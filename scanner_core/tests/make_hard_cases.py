"""Hard detection cases: a seeded set of synthetic photos with known corners.

Twelve photos per case (1200x1600, JPEG), each with a different random page
placement, written to shared/test_fixtures/hard/ with hard_cases.json:

  hand_held     page tilted in the air, 1-2 fingers covering corners, motion blur
  plain_white   white page on a light table, no drop shadow
  cluttered     patterned cloth, other papers and objects around the page
  half_shadow   one side of the page in deep shadow
  handwritten   pen strokes all over the page, some running to its edges
  curved        book-like page: top and bottom edges bow
  aadhaar       fake Aadhaar-style card (made-up data), small in the frame
  pan           fake PAN-style card with a signature (made-up data)

All names, numbers and photos are invented; nothing is a real document.
The cards also record their text (for the OCR and card-type checks).

Run:  python tests/make_hard_cases.py
"""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

import make_fixtures as mf

OUT = Path(__file__).resolve().parents[2] / "shared" / "test_fixtures" / "hard"
FONTS = Path(__file__).resolve().parents[2] / "app" / "assets" / "fonts"
W, H = mf.W, mf.H
PER_CASE = 12


def font(size, bold=False, deva=False):
    name = "NotoSansDevanagari-Regular.ttf" if deva else ("NotoSans-Bold.ttf" if bold else "NotoSans-Regular.ttf")
    return ImageFont.truetype(str(FONTS / name), size)


def random_quad(rng, cx=(480, 720), cy=(650, 950), half_w=(300, 420), half_h=(400, 560), tilt=25, jitter=50):
    x, y = rng.uniform(*cx), rng.uniform(*cy)
    sw, sh = rng.uniform(*half_w), rng.uniform(*half_h)
    a = np.radians(rng.uniform(-tilt, tilt))
    base = np.float32([[-sw, -sh], [sw, -sh], [sw, sh], [-sw, sh]]) + rng.uniform(-jitter, jitter, (4, 2))
    rot = np.float32([[np.cos(a), -np.sin(a)], [np.sin(a), np.cos(a)]])
    return (base @ rot.T + [x, y]).clip([15, 15], [W - 15, H - 15])


def motion_blur(img, rng, length):
    k = np.zeros((length, length), np.float32)
    k[length // 2, :] = 1
    rot = cv2.getRotationMatrix2D((length / 2 - 0.5, length / 2 - 0.5), rng.uniform(0, 180), 1)
    k = cv2.warpAffine(k, rot, (length, length))
    return cv2.filter2D(img, -1, k / k.sum())


def add_finger(img, corner, inward, rng):
    """A skin-coloured finger lying over a corner, pointing into the page."""
    length, width = rng.uniform(170, 260), rng.uniform(60, 80)
    d = inward / np.linalg.norm(inward)
    d = d + rng.uniform(-0.35, 0.35, 2)
    d /= np.linalg.norm(d)
    tip = corner + d * rng.uniform(25, 60)  # the fingertip covers the corner
    base = tip - d * length
    n = np.float32([-d[1], d[0]])
    poly = np.int32([base + n * width / 2, tip + n * width / 2, tip - n * width / 2, base - n * width / 2])
    mask = np.zeros(img.shape[:2], np.uint8)
    cv2.fillPoly(mask, [poly], 255)
    cv2.circle(mask, tuple(np.int32(tip)), int(width / 2), 255, -1)
    shade = cv2.GaussianBlur(mask, (0, 0), 6).astype(np.float32)[..., None] / 255
    skin = np.float32([120, 150, 205]) * rng.uniform(0.8, 1.1)  # BGR
    img[:] = img * (1 - shade) + skin * shade


def bg_cloth(rng):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    p = rng.uniform(18, 40)
    checks = ((np.floor(xx / p) + np.floor(yy / p)) % 2)[..., None]
    a, b = rng.integers(40, 220, 3), rng.integers(40, 220, 3)
    img = a * checks + b * (1 - checks)
    stripes = (np.sin((xx + yy) / rng.uniform(3, 6)) > 0.6)[..., None] * 30
    return np.clip(img + stripes, 0, 255).astype(np.uint8)


def other_papers(img, rng, n=3):
    for _ in range(n):
        q = random_quad(rng, cx=(0, W), cy=(0, H), half_w=(120, 260), half_h=(150, 320), tilt=40, jitter=20)
        cv2.fillPoly(img, [np.int32(q)], tuple(int(v) for v in rng.integers(215, 250, 3)))


def handwriting(paper, rng):
    h, w = paper.shape[:2]
    ink = tuple(int(v) for v in rng.choice([(150, 60, 20), (40, 40, 40), (30, 30, 160)]))
    for _ in range(int(rng.integers(14, 22))):
        y = rng.uniform(80, h - 80)
        x = rng.uniform(40, w * 0.3)
        pts = []
        while x < rng.uniform(w * 0.6, w - 30):
            pts.append((x, y + rng.normal(0, 6)))
            x += rng.uniform(6, 14)
        cv2.polylines(paper, [np.int32(pts)], False, ink, int(rng.integers(2, 4)), cv2.LINE_AA)
    for _ in range(3):  # strokes that run off the page edge (margin notes, underlines)
        y = rng.uniform(100, h - 100)
        cv2.line(
            paper,
            (int(rng.uniform(w * 0.5, w * 0.8)), int(y)),
            (w - 1, int(y + rng.normal(0, 20))),
            ink,
            3,
            cv2.LINE_AA,
        )
    return paper


def curve_page(paper, rng):
    """Bow the top and bottom edges (as a page in an open book): returns the
    curved page and its mask, corners unchanged."""
    h, w = paper.shape[:2]
    bulge = rng.uniform(0.04, 0.08) * h
    pad = int(bulge) + 2
    canvas = np.full((h + 2 * pad, w, 3), 0, np.uint8)
    mask = np.zeros((h + 2 * pad, w), np.uint8)
    xs = np.arange(w, dtype=np.float32)
    off = bulge * np.sin(np.pi * xs / (w - 1))  # 0 at the corners
    map_x = np.tile(xs, (h + 2 * pad, 1))
    yy = np.arange(h + 2 * pad, dtype=np.float32)[:, None] - pad
    map_y = (yy + off[None, :]).astype(np.float32)  # rows move up in the middle: the page bows upward
    canvas = cv2.remap(paper, map_x, map_y, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
    mask = cv2.remap(np.full((h, w), 255, np.uint8), map_x, map_y, cv2.INTER_NEAREST, borderMode=cv2.BORDER_CONSTANT)
    return canvas, mask, pad


def place_masked(bg, img, mask, src, dst):
    M = cv2.getPerspectiveTransform(np.float32(src), np.float32(dst))
    warped = cv2.warpPerspective(img, M, (W, H), flags=cv2.INTER_AREA)
    m = cv2.warpPerspective(mask, M, (W, H))
    out = bg.astype(np.float32)
    sh = cv2.GaussianBlur(np.roll(m, (12, 10), (0, 1)), (0, 0), 14).astype(np.float32) / 255
    out *= (1 - 0.35 * sh)[..., None]
    m = cv2.GaussianBlur(m, (3, 3), 0).astype(np.float32)[..., None] / 255
    return out * (1 - m) + warped.astype(np.float32) * m


def card(kind, rng):
    """A fake ID card, 1012x638 px (85.6 x 54 mm at ~300 dpi). Returns (BGR, text fields)."""
    w, h = 1012, 638
    names = ["Asha Verma", "Rohan Mehta", "Priya Nair", "Kabir Singh", "Meera Iyer", "Arjun Rao"]
    name = str(rng.choice(names))
    dob = f"{int(rng.integers(1, 28)):02d}/{int(rng.integers(1, 12)):02d}/{int(rng.integers(1965, 2004))}"
    im = Image.new("RGB", (w, h), (248, 246, 240) if kind == "aadhaar" else (226, 236, 246))
    d = ImageDraw.Draw(im)
    photo = (40, 150, 260, 430)
    d.rectangle(photo, fill=(200, 200, 205))
    d.ellipse((105, 190, 195, 290), fill=(150, 130, 120))  # a plain silhouette, not a face
    d.rounded_rectangle((80, 300, 220, 430), 30, fill=(150, 130, 120))
    if kind == "aadhaar":
        number = " ".join(str(int(rng.integers(1000, 9999))) for _ in range(3))
        number = str(int(rng.integers(2, 9))) + number[1:]
        d.rectangle((0, 0, w, 110), fill=(250, 160, 60))
        d.text((300, 15), "भारत सरकार", font=font(34, deva=True), fill=(20, 20, 20))
        d.text((300, 58), "Government of India", font=font(32, bold=True), fill=(20, 20, 20))
        d.text((300, 160), name, font=font(40, bold=True), fill=(10, 10, 10))
        d.text((300, 230), f"DOB: {dob}", font=font(34), fill=(10, 10, 10))
        d.text((300, 290), str(rng.choice(["Female", "Male"])), font=font(34), fill=(10, 10, 10))
        d.text((240, 480), number, font=font(60, bold=True), fill=(10, 10, 10))
        d.rectangle((0, h - 70, w, h), fill=(200, 40, 40))
        d.text((300, h - 60), "आधार - आम आदमी का अधिकार", font=font(30, deva=True), fill=(255, 255, 255))
        fields = {"type": "aadhaar", "name": name, "dob": dob, "number": number}
    else:
        letters = "ABCDEFGHJKLMNPRSTUVWXYZ"
        number = (
            "".join(rng.choice(list(letters), 3))
            + "P"
            + name.split()[1][0]
            + f"{int(rng.integers(1000, 9999))}"
            + str(rng.choice(list(letters)))
        )
        father = str(rng.choice(["Suresh Kumar", "Anil Sharma", "Vijay Das"]))
        d.text((300, 20), "आयकर विभाग", font=font(30, deva=True), fill=(20, 20, 60))
        d.text((300, 60), "INCOME TAX DEPARTMENT", font=font(34, bold=True), fill=(20, 20, 60))
        d.text((640, 20), "भारत सरकार", font=font(30, deva=True), fill=(20, 20, 60))
        d.text((640, 60), "GOVT. OF INDIA", font=font(34, bold=True), fill=(20, 20, 60))
        d.text((300, 130), "Permanent Account Number Card", font=font(28), fill=(20, 20, 20))
        d.text((300, 175), number, font=font(52, bold=True), fill=(10, 10, 10))
        d.text((300, 265), name.upper(), font=font(36, bold=True), fill=(10, 10, 10))
        d.text((300, 330), father.upper(), font=font(32), fill=(10, 10, 10))
        d.text((300, 395), dob, font=font(32), fill=(10, 10, 10))
        # Signature under the photo: thin, fast pen strokes.
        xs = np.linspace(55, 245, 60)
        ys = 500 + 18 * np.sin(xs / 9) + rng.normal(0, 3, 60)
        d.line(list(zip(xs.tolist(), ys.tolist())), fill=(20, 20, 90), width=2)
        d.line([(70, 525), (230, 515)], fill=(20, 20, 90), width=2)
        d.text((60, 560), "Signature", font=font(22), fill=(60, 60, 60))
        fields = {"type": "pan", "name": name, "dob": dob, "number": number}
    return cv2.cvtColor(np.asarray(im), cv2.COLOR_RGB2BGR), fields


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    cases: dict[str, list] = {}

    def save(case, i, img, corners, extra=None):
        name = f"{case}_{i:02d}"
        cv2.imwrite(str(OUT / f"{name}.jpg"), img, [cv2.IMWRITE_JPEG_QUALITY, 70])
        cases.setdefault(case, []).append(
            {"file": f"{name}.jpg", "corners": np.round(corners, 1).tolist(), **(extra or {})}
        )

    for i in range(PER_CASE):
        rng = np.random.default_rng(7000 + i)
        paper = mf.make_paper(rng)
        ph, pw = paper.shape[:2]

        # Hand-held: in the air (perspective), fingers over 1-2 corners, a little shake.
        q = random_quad(rng, tilt=15, jitter=70)
        img = mf.place(mf.bg_wood(rng), paper, q, shadow=False)
        centre = q.mean(axis=0)
        for k in rng.choice(4, int(rng.integers(1, 3)), replace=False):
            add_finger(img, q[k], centre - q[k], rng)
        img = motion_blur(np.clip(img, 0, 255).astype(np.uint8), rng, int(rng.integers(3, 8))).astype(np.float32)
        save("hand_held", i, mf.finish(img, rng, blur=0.6), q)

        # Plain white page on a light table.
        q = random_quad(rng)
        white = np.full_like(paper, 250)
        if i % 2:
            white = mf.make_paper(rng, tint=(250, 250, 250))
        img = mf.place(mf.bg_light_table(rng), white, q, shadow=False)
        save("plain_white", i, mf.finish(img, rng, light=(1.0, 0.94), noise=3), q)

        # Cluttered: cloth or desk clutter, plus other papers around.
        q = random_quad(rng, half_w=(260, 360), half_h=(340, 480))
        bg = bg_cloth(rng) if i % 2 else mf.bg_cluttered(rng)
        other_papers(bg, rng)
        save("cluttered", i, mf.finish(mf.place(bg, paper, q), rng), q)

        # Half shadow: a soft-edged shadow over the left or right half of the scene.
        q = random_quad(rng)
        img = mf.place(mf.bg_wood(rng), paper, q)
        x = rng.uniform(0.35, 0.65) * W
        shadow = np.zeros((H, W), np.float32)
        if i % 2:
            shadow[:, : int(x)] = 1
        else:
            shadow[:, int(x) :] = 1
        shadow = cv2.GaussianBlur(shadow, (0, 0), rng.uniform(10, 40))
        img = img * (1 - rng.uniform(0.55, 0.7) * shadow)[..., None]
        save("half_shadow", i, mf.finish(img, rng), q)

        # Handwritten.
        q = random_quad(rng)
        hand = handwriting(np.full_like(paper, 246), rng)
        save("handwritten", i, mf.finish(mf.place(mf.bg_wood(rng), hand, q), rng), q)

        # Curved page.
        q = random_quad(rng, tilt=12, jitter=30)
        curved, mask, pad = curve_page(paper, rng)
        src_c = [[0, pad], [pw, pad], [pw, ph + pad], [0, ph + pad]]
        save("curved", i, mf.finish(place_masked(mf.bg_wood(rng), curved, mask, src_c, q), rng), q)

        # ID cards, small in the frame (card ~35-50 % of the photo width).
        for kind in ("aadhaar", "pan"):
            im, fields = card(kind, rng)
            ch, cw = im.shape[:2]
            s = rng.uniform(0.35, 0.5) * W / cw
            q = random_quad(
                rng,
                cx=(450, 750),
                cy=(600, 1000),
                half_w=(cw * s / 2,) * 2,
                half_h=(ch * s / 2,) * 2,
                tilt=20,
                jitter=12,
            )
            bg = mf.bg_wood(rng) if i % 2 else bg_cloth(rng)
            M = cv2.getPerspectiveTransform(np.float32([[0, 0], [cw, 0], [cw, ch], [0, ch]]), np.float32(q))
            warped = cv2.warpPerspective(im, M, (W, H), flags=cv2.INTER_AREA)
            m = cv2.warpPerspective(np.full((ch, cw), 255, np.uint8), M, (W, H))
            m = cv2.GaussianBlur(m, (3, 3), 0).astype(np.float32)[..., None] / 255
            img = bg.astype(np.float32) * (1 - m) + warped.astype(np.float32) * m
            save(kind, i, mf.finish(img, rng), q, {"fields": fields})

    (OUT / "hard_cases.json").write_text(
        json.dumps({"image_size": [W, H], "corner_order": "TL,TR,BR,BL", "cases": cases}, indent=1, ensure_ascii=False)
    )
    print(f"wrote {sum(len(v) for v in cases.values())} photos in {len(cases)} cases to {OUT}")


if __name__ == "__main__":
    main()
