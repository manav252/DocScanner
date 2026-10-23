// Free hosting (Render) puts the backend to sleep after ~15 minutes without
// traffic; the first request then takes up to a minute. The app pings /health
// in the background when it opens, and sign-in/sync wait here (showing
// "Waking up the server…") instead of failing. Nothing else needs the server.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_settings.dart';

enum ServerState {
  /// Not checked yet.
  unknown,

  /// Did not answer the first time; retrying (cold start).
  waking,

  /// Answered /health.
  up,

  /// No answer within [ServerWaker.maxWait] (offline, wrong address, server down).
  unreachable,
}

class ServerWaker extends Notifier<ServerState> {
  /// How long a cold start may take before we give up.
  static Duration maxWait = const Duration(seconds: 90);
  static Duration retryEvery = const Duration(seconds: 4);

  Future<bool>? _waking;

  @override
  ServerState build() {
    ref.watch(appSettingsProvider.select((s) => s.serverUrl)); // new address: check again
    _waking = null;
    return ServerState.unknown;
  }

  /// Make sure the server is awake. Returns false if it did not answer in time.
  /// Concurrent callers share one attempt.
  Future<bool> wake() {
    if (state == ServerState.up) return Future.value(true);
    return _waking ??= _wake().whenComplete(() {
      _waking = null;
    });
  }

  /// The server stopped answering (e.g. it went back to sleep): check again next time.
  void lost() {
    if (state == ServerState.up) state = ServerState.unknown;
  }

  Future<bool> _wake() async {
    final api = ref.read(apiClientProvider);
    final deadline = DateTime.now().add(maxWait);
    var first = true;
    while (ref.mounted) {
      if (await api.health()) {
        if (ref.mounted) state = ServerState.up;
        return true;
      }
      if (!ref.mounted) return false;
      if (DateTime.now().isAfter(deadline)) {
        state = ServerState.unreachable;
        return false;
      }
      if (first) {
        state = ServerState.waking;
        first = false;
      }
      await Future<void>.delayed(retryEvery);
    }
    return false;
  }
}

final serverWakerProvider = NotifierProvider<ServerWaker, ServerState>(ServerWaker.new);

/// Pinged once when the app opens, so a sleeping server is usually awake by the
/// time someone signs in or syncs.
final serverWarmupProvider = FutureProvider<bool>((ref) => ref.read(serverWakerProvider.notifier).wake());
