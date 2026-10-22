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
            Expanded(child: Text(describeSync(status), key: const ValueKey('sync-status'))),
            TextButton(
              onPressed: status.phase == SyncPhase.syncing ? null : () => ref.read(syncControllerProvider.notifier).syncNow(),
              child: const Text('Sync now'),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Process photos on the server'),
        subtitle: const Text('For slow devices: page detection, flattening and filters run on the server. '
            'The live camera preview still runs on this device.'),
        value: settings.processOnServer,
        onChanged: (v) => ref.read(appSettingsProvider.notifier).update(settings.copyWith(processOnServer: v)),
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Sign out?'),
              content: const Text('Your scans stay on this device. Changes made while signed out sync after you sign in again.'),
              actions: [
                TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Sign out')),
              ],
            ),
          );
          if (ok == true) await ref.read(sessionProvider.notifier).set(null);
        },
      ),
      const SizedBox(height: 12),
      Text('Scans are stored on this device and backed up to your account. They keep working offline.',
          style: theme.textTheme.bodySmall),
    ]);
  }
}

String describeSync(SyncStatus s) {
  String ago(DateTime? t) {
    if (t == null) return 'never';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }

  return switch (s.phase) {
    SyncPhase.signedOut => 'Not signed in',
    SyncPhase.syncing => 'Syncing…',
    SyncPhase.idle => 'Synced ${ago(s.lastSynced)}',
    SyncPhase.offline => 'Offline. Changes are saved on this device and will sync later.',
    SyncPhase.error => 'Sync problem: ${s.message ?? 'unknown error'}',
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
      _error = "Can't reach the server at ${_server.text.trim()}. Check the address and that the backend is running.";
    } on ApiException catch (e) {
      _error = switch (e.status) {
        401 => 'Wrong email or password.',
        409 => 'An account with this email already exists. Sign in instead.',
        422 => 'Check the email address; passwords need at least 8 characters.',
        _ => e.message,
      };
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Back up and sync your scans', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Without an account everything stays on this device. Sign in to sync between your phone and the web app.'),
        const SizedBox(height: 20),
        TextFormField(
          key: const ValueKey('server-url'),
          controller: _server,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Server',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Test connection',
              onPressed: _testServer,
              icon: Icon(switch (_serverOk) {
                true => Icons.check_circle,
                false => Icons.error_outline,
                null => Icons.wifi_tethering,
              }, color: switch (_serverOk) {
                true => Colors.green,
                false => Theme.of(context).colorScheme.error,
                null => null,
              }),
            ),
          ),
          validator: (v) {
            final u = Uri.tryParse(v?.trim() ?? '');
            return u == null || !(u.isScheme('http') || u.isScheme('https')) || u.host.isEmpty
                ? 'Enter a URL like http://192.168.1.20:8000'
                : null;
          },
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Sign in')),
            ButtonSegment(value: true, label: Text('Create account')),
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
          decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
          validator: (v) => (v ?? '').contains('@') ? null : 'Enter your email',
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('password'),
          controller: _password,
          obscureText: _obscure,
          autofillHints: [_create ? AutofillHints.newPassword : AutofillHints.password],
          decoration: InputDecoration(
            labelText: 'Password',
            helperText: _create ? 'At least 8 characters' : null,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          validator: (v) => (v ?? '').length < 8 ? 'At least 8 characters' : null,
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
              : Text(_create ? 'Create account' : 'Sign in'),
        ),
      ]),
    );
  }
}
