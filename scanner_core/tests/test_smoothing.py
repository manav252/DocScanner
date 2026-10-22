import numpy as np

from scanner_core import CornerSmoother, StabilityTracker

BASE = np.float32([[0.2, 0.1], [0.8, 0.12], [0.85, 0.9], [0.15, 0.88]])


def test_smoother_reduces_jitter():
    rng = np.random.default_rng(0)
    s = CornerSmoother()
    raw, out = [], []
    for _ in range(200):
        c = BASE + rng.normal(0, 0.004, BASE.shape)
        raw.append(c)
        out.append(s.update(c))
    raw, out = np.stack(raw[20:]), np.stack(out[20:])
    assert out.std(axis=0).mean() < 0.6 * raw.std(axis=0).mean()


def test_smoother_snaps_on_big_move():
    s = CornerSmoother()
    s.update(BASE)
    moved = BASE + 0.2
    np.testing.assert_allclose(s.update(moved), moved)


def test_smoother_holds_then_drops():
    s = CornerSmoother(hold_frames=3)
    s.update(BASE)
    for _ in range(3):
        np.testing.assert_allclose(s.update(None), BASE)
    assert s.update(None) is None


def test_stability_steady_after_window():
    t = StabilityTracker(window=5)
    results = [t.update(BASE + 0.001 * i % 2) for i in range(5)]
    assert results == [False] * 4 + [True]
    assert t.progress == 1.0


def test_stability_not_steady_while_moving():
    t = StabilityTracker(window=5)
    assert not any(t.update(BASE + 0.02 * i) for i in range(10))


def test_stability_resets_on_miss():
    t = StabilityTracker(window=3)
    for _ in range(3):
        t.update(BASE)
    assert t.is_steady
    t.update(None)
    assert not t.is_steady and t.progress == 0
