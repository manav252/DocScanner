// Crash notes (web): iPhone Safari can kill the page without any error the
// app could catch. Heavy steps are written to localStorage before they run
// and cleared after; a step still marked when the app starts again means the
// page died during it. A short trail of recent steps, screens and errors is
// kept with it, so the user can copy the details.
export 'crash_note_stub.dart' if (dart.library.js_interop) 'crash_note_web.dart';

class CrashNote {
  const CrashNote({required this.step, required this.details});

  /// What the app was doing when the page closed.
  final String step;

  /// Steps, screens and errors before it, and the device, for a bug report.
  final String details;
}
