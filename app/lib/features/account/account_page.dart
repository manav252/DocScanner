// Sign in / create an account, see sync status, server options.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_settings.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../data/sync/sync_service.dart';
import '../library/library_controller.dart';
import '../../data/sync/sync_controller.dart';
import '../../services/api/api_client.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.backupSync)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: session == null ? const _SignInForm() : _SignedIn(session: session),
          ),
        ],
      ),
    );
  }
}

class _SignedIn extends ConsumerWidget {
  const _SignedIn({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final settings = ref.watch(appSettingsProvider);
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(session.email),
        subtitle: Text(settings.serverUrl),
      ),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            SyncIcon(status: status),
            const SizedBox(width: 12),
            Expanded(child: Text(describeSync(context, status), key: const ValueKey('sync-status'))),
            TextButton.icon(
              onPressed: status.phase == SyncPhase.syncing ? null : () => ref.read(syncControllerProvider.notifier).syncNow(),
              icon: const Icon(Icons.sync),
              label: Text(context.l10n.syncNow),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.l10n.processOnServer),
        subtitle: Text(context.l10n.processOnServerHint),
        value: settings.processOnServer,
        onChanged: (v) => ref.read(appSettingsProvider.notifier).update(settings.copyWith(processOnServer: v)),
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        icon: const Icon(Icons.logout),
        label: Text(context.l10n.signOut),
        onPressed: () async {
          final l = context.l10n;
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(l.signOutTitle),
              content: Text(l.signOutBody),
              actions: [
                TextButton.icon(onPressed: () => Navigator.of(c).pop(false), icon: const Icon(Icons.close), label: Text(l.cancel)),
                FilledButton.icon(onPressed: () => Navigator.of(c).pop(true), icon: const Icon(Icons.logout), label: Text(l.signOut)),
              ],
            ),
          );
          if (ok == true) await ref.read(sessionProvider.notifier).set(null);
        },
      ),
      const SizedBox(height: 12),
      Text(context.l10n.signedInNote, style: theme.textTheme.bodySmall),
    ]);
  }
}

String describeSync(BuildContext context, SyncStatus s) {
  final l = context.l10n;
  String synced(DateTime? t) {
    if (t == null) return l.syncNever;
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return l.syncJustNow;
    if (d.inMinutes < 60) return l.syncMinutesAgo(d.inMinutes);
    return l.syncHoursAgo(d.inHours);
  }

  return switch (s.phase) {
    SyncPhase.signedOut => l.syncNotSignedIn,
    SyncPhase.syncing => l.syncSyncing,
    SyncPhase.idle => synced(s.lastSynced),
    SyncPhase.offline => l.syncOffline,
    SyncPhase.error => l.syncProblem(s.message ?? '?'),
  };
}

class SyncIcon extends StatelessWidget {
  const SyncIcon({super.key, required this.status});
  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status.phase) {
      SyncPhase.signedOut => Icon(Icons.cloud_off_outlined, color: scheme.outline),
      SyncPhase.syncing => const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
      SyncPhase.idle => Icon(Icons.cloud_done_outlined, color: scheme.primary),
      SyncPhase.offline => const Icon(Icons.cloud_off, color: Colors.orange),
      SyncPhase.error => Icon(Icons.sync_problem, color: scheme.error),
    };
  }
}

class _SignInForm extends ConsumerStatefulWidget {
  const _SignInForm();

  @override
  ConsumerState<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends ConsumerState<_SignInForm> {
  final _form = GlobalKey<FormState>();
  late final _server = TextEditingController(text: ref.read(appSettingsProvider).serverUrl);
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _create = false, _busy = false, _obscure = true;
  String? _error;
  bool? _serverOk;

  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _saveServer() async {
    final url = _server.text.trim();
    final s = ref.read(appSettingsProvider);
    if (url != s.serverUrl) await ref.read(appSettingsProvider.notifier).update(s.copyWith(serverUrl: url));
  }

  Future<void> _testServer() async {
    await _saveServer();
    setState(() => _serverOk = null);
    final ok = await ref.read(apiClientProvider).health();
    if (mounted) setState(() => _serverOk = ok);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await _saveServer();
    final api = ref.read(apiClientProvider);
    try {
      if (_create) {
        await api.register(_email.text, _password.text);
      } else {
        await api.login(_email.text, _password.text);
      }
      // onSessionChanged stored the session; sync starts automatically for
      // documents marked for backup. Ask before uploading what is already here.
      await SyncService(
        api: api,
        repo: ref.read(documentRepositoryProvider),
        store: ref.read(keyValueStoreProvider),
      ).prepareForAccount(api.session!.userId);
      final actions = ref.read(libraryActionsProvider);
      final local = await actions.localOnly();
      if (local.isNotEmpty && mounted) {
        final l = context.l10n;
        final upload = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(l.uploadExistingTitle),
            content: Text(l.uploadExistingBody(local.length)),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.of(c).pop(false),
                icon: const Icon(Icons.phone_android),
                label: Text(l.notNow),
              ),
              FilledButton.icon(
                key: const ValueKey('upload-existing'),
                onPressed: () => Navigator.of(c).pop(true),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(l.uploadNow),
              ),
            ],
          ),
        );
        if (upload == true) await actions.backUp(local);
      }
      ref.read(syncControllerProvider.notifier).syncNow();
    } on OfflineException {
      if (mounted) _error = context.l10n.errOffline(_server.text.trim());
    } on ApiException catch (e) {
      if (mounted) {
        final l = context.l10n;
        _error = switch (e.status) {
          401 => l.errWrongPassword,
          409 => l.errAccountExists,
          422 => l.errInvalidInput,
          _ => e.message,
        };
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(header: true, child: Text(l.backUpYourScans, style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(height: 8),
        Text(l.backUpIntro),
        const SizedBox(height: 20),
        TextFormField(
          key: const ValueKey('server-url'),
          controller: _server,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(labelText: l.server, border: const OutlineInputBorder()),
          validator: (v) {
            final u = Uri.tryParse(v?.trim() ?? '');
            return u == null || !(u.isScheme('http') || u.isScheme('https')) || u.host.isEmpty ? l.serverHint : null;
          },
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            key: const ValueKey('test-connection'),
            onPressed: _testServer,
            icon: const Icon(Icons.wifi_tethering),
            label: Text(l.testConnection),
          ),
          if (_serverOk != null)
            Semantics(
              liveRegion: true,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_serverOk! ? Icons.check_circle : Icons.error_outline,
                    color: _serverOk! ? Colors.green.shade800 : scheme.error),
                const SizedBox(width: 6),
                Flexible(child: Text(_serverOk! ? l.serverReachable : l.serverUnreachable)),
              ]),
            ),
        ]),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(l.signIn)),
            ButtonSegment(value: true, label: Text(l.createAccount)),
          ],
          selected: {_create},
          onSelectionChanged: (s) => setState(() => _create = s.first),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(labelText: l.email, border: const OutlineInputBorder()),
          validator: (v) => (v ?? '').contains('@') ? null : l.enterEmail,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('password'),
          controller: _password,
          obscureText: _obscure,
          autofillHints: [_create ? AutofillHints.newPassword : AutofillHints.password],
          decoration: InputDecoration(
            labelText: l.password,
            helperText: _create ? l.passwordRule : null,
            border: const OutlineInputBorder(),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                key: const ValueKey('toggle-password'),
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                label: Text(_obscure ? l.showPassword : l.hidePassword,
                    semanticsLabel: _obscure ? l.showPasswordLabel : l.hidePasswordLabel),
              ),
            ),
          ),
          validator: (v) => (v ?? '').length < 8 ? l.passwordRule : null,
          onFieldSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey('auth-submit'),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_create ? l.createAccount : l.signIn),
        ),
      ]),
    );
  }
}
