import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'crash_note.dart';

const _activeKey = 'docscanner.active', _trailKey = 'docscanner.trail';
var _next = 0;
var _listening = false;

web.Storage? get _store {
  try {
    return web.window.localStorage;
  } catch (_) {
    return null; // private mode / blocked storage: no notes
  }
}

Map<String, dynamic> _active() {
  try {
    return (jsonDecode(_store?.getItem(_activeKey) ?? '{}') as Map).cast<String, dynamic>();
  } catch (_) {
    return {};
  }
}

String _now() => DateTime.now().toIso8601String().substring(11, 19);

void _trail(String line) {
  final s = _store;
  if (s == null) return;
  final lines = (s.getItem(_trailKey) ?? '').split('\n').where((l) => l.isNotEmpty).toList()..add('${_now()} $line');
  s.setItem(_trailKey, lines.skip(lines.length > 25 ? lines.length - 25 : 0).join('\n'));
}

void _listen() {
  if (_listening) return;
  _listening = true;
  // Leaving the page normally (closing the tab, navigating) is not a crash.
  web.window.addEventListener('pagehide', ((web.Event _) => _store?.removeItem(_activeKey)).toJS);
}

/// Record that [step] starts; returns a token for [noteDone].
int noteStep(String step) {
  _listen();
  final id = ++_next;
  final a = _active()..['$id'] = step;
  _store?.setItem(_activeKey, jsonEncode(a));
  _trail(step);
  return id;
}

void noteDone(int token) {
  final a = _active()..remove('$token');
  if (a.isEmpty) {
    _store?.removeItem(_activeKey);
  } else {
    _store?.setItem(_activeKey, jsonEncode(a));
  }
}

/// A screen opened, an error happened: kept in the trail only.
void noteEvent(String event) {
  _listen();
  _trail(event);
}

/// The note left by a page that died during a step (once; then cleared).
CrashNote? takeCrashNote() {
  final s = _store;
  if (s == null) return null;
  final a = _active();
  final trail = s.getItem(_trailKey) ?? '';
  s.removeItem(_activeKey);
  s.removeItem(_trailKey);
  if (a.isEmpty) return null;
  final step = a.values.last as String;
  final nav = web.window.navigator, scr = web.window.screen;
  final details = [
    'Closed during: ${a.values.join(' + ')}',
    'Browser: ${nav.userAgent}',
    'Screen: ${scr.width}x${scr.height} @${web.window.devicePixelRatio}x',
    'Recent steps:',
    trail,
  ].join('\n');
  return CrashNote(step: step, details: details);
}
