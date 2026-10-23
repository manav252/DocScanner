// Runs sync in the background: after sign-in, shortly after local changes,
// periodically, and on demand. Exposes a status for the UI.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_settings.dart';
import '../../core/providers.dart';
import '../../services/api/api_client.dart';
import 'sync_service.dart';

enum SyncPhase { signedOut, idle, syncing, offline, error }

class SyncStatus {
  const SyncStatus(this.phase, {this.lastSynced, this.message, this.conflicts = const []});
  final SyncPhase phase;
  final DateTime? lastSynced;
  final String? message;

  /// Documents edited on two devices in the last sync (newer edit kept).
  final List<String> conflicts;

  SyncStatus copyWith(SyncPhase phase, {DateTime? lastSynced, String? message, List<String>? conflicts}) => SyncStatus(
    phase,
    lastSynced: lastSynced ?? this.lastSynced,
    message: message,
    conflicts: conflicts ?? this.conflicts,
  );
}

class SyncController extends Notifier<SyncStatus> {
  static const period = Duration(minutes: 2);
  static const debounce = Duration(seconds: 3);

  Timer? _timer, _debounce;
  StreamSubscription<String>? _changes;
  bool _running = false, _again = false, _applying = false;

  @override
  SyncStatus build() {
    final session = ref.watch(sessionProvider);
    ref.watch(appSettingsProvider.select((s) => s.serverUrl));
    ref.onDispose(_stop);
    if (session == null) return const SyncStatus(SyncPhase.signedOut);
    _timer = Timer.periodic(period, (_) => syncNow());
    _changes = ref.read(documentRepositoryProvider).changes.listen((_) {
      if (_applying) return; // changes made by sync itself
      _debounce?.cancel();
      _debounce = Timer(debounce, syncNow);
    });
    Future.microtask(syncNow);
    return const SyncStatus(SyncPhase.idle);
  }

  void _stop() {
    _timer?.cancel();
    _debounce?.cancel();
    _changes?.cancel();
  }

  /// Sync now (coalesces concurrent requests).
  Future<void> syncNow() async {
    if (ref.read(sessionProvider) == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        state = state.copyWith(SyncPhase.syncing);
        final service = SyncService(
          api: ref.read(apiClientProvider),
          repo: ref.read(documentRepositoryProvider),
          store: ref.read(keyValueStoreProvider),
        );
        try {
          _applying = true;
          final report = await service.sync();
          if (!ref.mounted) return;
          state = state.copyWith(SyncPhase.idle, lastSynced: DateTime.now(), conflicts: report.conflictTitles);
        } on OfflineException {
          if (ref.mounted) state = state.copyWith(SyncPhase.offline, message: 'Server not reachable; will retry');
        } on ApiException catch (e) {
          if (!ref.mounted) return;
          state = e.isUnauthorized
              ? const SyncStatus(SyncPhase.signedOut)
              : state.copyWith(SyncPhase.error, message: e.message);
        } catch (e) {
          if (ref.mounted) state = state.copyWith(SyncPhase.error, message: '$e');
        } finally {
          _applying = false;
        }
      } while (_again && ref.mounted);
    } finally {
      _running = false;
    }
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);
