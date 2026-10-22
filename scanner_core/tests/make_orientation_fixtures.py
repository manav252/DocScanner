"""Photos that exercise orientation and size handling in the crop editor.

Writes shared/test_fixtures/orientation/:
  portrait.jpg        1200x1600 upright
  landscape.jpg       1600x1200 upright (page rotated 90 degrees in the scene)
  exif_rotated.jpg    stored as 1600x1200 pixels + EXIF Orientation=6, i.e. a phone photo
                      that must be shown (and processed) as 1200x1600 portrait
  large.jpg           4800x6400 upright (very large photo)
and orientation.json with each file's upright size and the page corners in upright pixels.

Usage: python tests/make_orientation_fixtures.py   (needs Pillow: pip install pillow)
"""
import json
from pathlib import Path

from PIL import Image

FIX = Path(__file__).resolve().parents[2] / "shared" / "test_fixtures"
OUT = FIX / "orientation"
OUT.mkdir(exist_ok=True)
spec = json.loads((FIX / "expected_corners.json").read_text())
src = Image.open(FIX / "tilted_paper.jpg").convert("RGB")  # 1200x1600
corners = spec["cases"]["tilted_paper"]["corners"]
W, H = src.size
cases = {}

src.save(OUT / "portrait.jpg", quality=92)
cases["portrait.jpg"] = {"size": [W, H], "corners": corners}

# Rotate the scene 90 degrees clockwise: (x, y) -> (H - 1 - y, x)
land = src.transpose(Image.Transpose.ROTATE_270)
land.save(OUT / "landscape.jpg", quality=92)
cases["landscape.jpg"] = {"size": [H, W], "corners": [[H - 1 - y, x] for x, y in corners]}

# Phone-style: pixels stored sideways (rotated 90 CCW), EXIF says "rotate 90 CW to display".
stored = src.transpose(Image.Transpose.ROTATE_90)  # 1600x1200
exif = Image.Exif()
exif[0x0112] = 6
stored.save(OUT / "exif_rotated.jpg", quality=92, exif=exif)
cases["exif_rotated.jpg"] = {"size": [W, H], "corners": corners, "stored_size": list(stored.size), "exif_orientation": 6}

big = src.resize((W * 4, H * 4), Image.Resampling.LANCZOS)
big.save(OUT / "large.jpg", quality=85)
cases["large.jpg"] = {"size": [W * 4, H * 4], "corners": [[x * 4, y * 4] for x, y in corners]}

(OUT / "orientation.json").write_text(json.dumps(cases, indent=2))
print("wrote", sorted(cases))
