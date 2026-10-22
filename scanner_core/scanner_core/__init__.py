"""Reference OpenCV document-scanning pipeline shared by the backend and tests."""
from .detect import Detection, detect_document, full_bounds, order_corners
from .filters import Filter, apply_filter, crop, rotate
from .pipeline import ScanResult, decode_image, encode_image, scan
from .smoothing import CornerSmoother, StabilityTracker
from .warp import output_size, warp_perspective

__all__ = ["Detection", "detect_document", "full_bounds", "order_corners", "Filter", "apply_filter", "crop",
           "rotate", "ScanResult", "decode_image", "encode_image", "scan", "CornerSmoother", "StabilityTracker",
           "output_size", "warp_perspective"]
