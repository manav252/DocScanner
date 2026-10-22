import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Trigger a browser download of [bytes] as [name].
void downloadBytes(String name, Uint8List bytes, String mimeType) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body!.append(a);
  a.click();
  a.remove();
  // Give the browser time to start the download before revoking.
  Future<void>.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
