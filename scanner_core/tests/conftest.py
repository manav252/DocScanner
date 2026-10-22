import json
from pathlib import Path

import cv2
import numpy as np
import pytest

FIXTURES = Path(__file__).resolve().parents[2] / "shared" / "test_fixtures"
SPEC = json.loads((FIXTURES / "expected_corners.json").read_text())


def load_fixture(name: str) -> np.ndarray:
    img = cv2.imread(str(FIXTURES / f"{name}.jpg"))
    assert img is not None, f"missing fixture {name}; run python tests/make_fixtures.py"
    return img


def max_corner_error(a, b) -> float:
    return float(np.linalg.norm(np.float32(a) - np.float32(b), axis=1).max())


@pytest.fixture(scope="session")
def spec():
    return SPEC
