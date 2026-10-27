import 'crash_note.dart';

/// Phones and tests: nothing to record (a crash there has its own reports).
int noteStep(String step) => 0;
void noteDone(int token) {}
void noteEvent(String event) {}
CrashNote? takeCrashNote() => null;
