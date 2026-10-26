// Web-only file picker options, behind a conditional import (the web plugin
// cannot be imported in the phone build).
export 'picker_options_stub.dart' if (dart.library.js_interop) 'picker_options_web.dart';
