"""Frame-to-frame corner smoothing and steadiness tracking for the live preview.

The camera UI feeds every detection result into a ``CornerSmoother`` (removes
jitter, briefly holds the last outline when a frame misses) and a
``StabilityTracker`` (decides when the page has been steady long enough to
auto-capture). Both work in normalised [0, 1] coordinates so they are
independent of the analysis resolution.
"""
from __future__ import annotations

from collections import deque

import numpy as np


class CornerSmoother:
    def __init__(self, alpha: float = 0.4, jump_threshold: float = 0.08, hold_frames: int = 4):
        """
        alpha: EMA weight of the newest frame (higher = more responsive, more jitter).
        jump_threshold: if any corner moves more than this (fraction of the frame diagonal)
            the page was moved, so snap to the new position instead of easing.
        hold_frames: keep showing the last outline for this many missed frames.
        """
        self.alpha, self.jump, self.hold = alpha, jump_threshold, hold_frames
        self._state: np.ndarray | None = None
        self._missed = 0

    def reset(self) -> None:
        self._state, self._missed = None, 0

    def update(self, corners: np.ndarray | None) -> np.ndarray | None:
        """corners: (4, 2) normalised, or None when nothing was detected this frame."""
        if corners is None:
            self._missed += 1
            if self._missed > self.hold:
                self._state = None
            return None if self._state is None else self._state.copy()
        c = np.asarray(corners, np.float32).reshape(4, 2)
        self._missed = 0
        if self._state is None or np.linalg.norm(c - self._state, axis=1).max() > self.jump * np.sqrt(2):
            self._state = c.copy()
        else:
            self._state = self.alpha * c + (1 - self.alpha) * self._state
        return self._state.copy()


class StabilityTracker:
    def __init__(self, window: int = 12, tolerance: float = 0.012):
        """Steady when the last ``window`` detections all lie within ``tolerance``
        (fraction of the frame diagonal) of their mean. At 15 fps, 12 frames ~ 0.8 s."""
        self.window, self.tol = window, tolerance
        self._buf: deque[np.ndarray] = deque(maxlen=window)

    def reset(self) -> None:
        self._buf.clear()

    def update(self, corners: np.ndarray | None) -> bool:
        if corners is None:
            self._buf.clear()
            return False
        self._buf.append(np.asarray(corners, np.float32).reshape(4, 2))
        return self.is_steady

    @property
    def progress(self) -> float:
        """0..1, for drawing a 'hold still' ring in the UI."""
        return len(self._buf) / self.window if self._buf and self._spread() <= self.tol * np.sqrt(2) else 0.0

    def _spread(self) -> float:
        a = np.stack(self._buf)
        return float(np.linalg.norm(a - a.mean(axis=0), axis=2).max())

    @property
    def is_steady(self) -> bool:
        return len(self._buf) == self.window and self._spread() <= self.tol * np.sqrt(2)
