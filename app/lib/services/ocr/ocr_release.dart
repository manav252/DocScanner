// Free the OCR engine's memory when it is idle. On the web, Tesseract's
// workers hold ~200 MB, which with the camera and image processing could get
// an iPhone's Safari tab killed. Phones (ML Kit) have nothing to release.
export 'ocr_release_stub.dart' if (dart.library.js_interop) 'ocr_release_web.dart';
