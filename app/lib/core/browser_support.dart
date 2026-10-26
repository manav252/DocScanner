// Whether this browser can run the image processing (web only; phones always can).
export 'browser_support_stub.dart' if (dart.library.js_interop) 'browser_support_web.dart';
