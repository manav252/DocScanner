import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Scanning and importing decode and encode images in a worker with
/// OffscreenCanvas, which Safari only has from iOS 16.4.
bool get canProcessImages => globalContext.has('OffscreenCanvas');
