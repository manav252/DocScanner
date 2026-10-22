// Short, skippable 3-screen first-run guide.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_settings.dart';
import '../../core/l10n.dart';
import '../home/home_page.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key, this.popOnFinish = false});

  /// Opened from Settings: close instead of replacing with Home.
  final bool popOnFinish;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final s = ref.read(appSettingsProvider);
    await ref.read(appSettingsProvider.notifier).update(s.copyWith(onboardingDone: true));
    if (!mounted) return;
    if (widget.popOnFinish) {
      Navigator.of(context).pop();
    } else {
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const HomePage()));
    }
  }

  void _go(int i) {
    final reduce = MediaQuery.of(context).disableAnimations;
    reduce
        ? _pages.jumpToPage(i)
        : _pages.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final steps = [
      (Icons.document_scanner_outlined, l.guide1Title, l.guide1Body),
      (Icons.auto_fix_high_outlined, l.guide2Title, l.guide2Body),
      (Icons.ios_share, l.guide3Title, l.guide3Body),
    ];
    final last = _index == steps.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appName),
        actions: [
          if (!last)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                key: const ValueKey('guide-skip'),
                onPressed: _finish,
                icon: const Icon(Icons.skip_next),
                label: Text(l.skip),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _index = i),
              children: [
                for (final (icon, title, body) in steps)
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(icon, size: 96, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 24),
                          Semantics(
                            header: true,
                            child: Text(title,
                                textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                          ),
                          const SizedBox(height: 12),
                          Text(body, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Semantics(
            liveRegion: true,
            child: Text(l.guideStep(_index + 1, steps.length), key: const ValueKey('guide-step')),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              if (_index > 0)
                OutlinedButton.icon(onPressed: () => _go(_index - 1), icon: const Icon(Icons.arrow_back), label: Text(l.back)),
              const Spacer(),
              FilledButton.icon(
                key: const ValueKey('guide-next'),
                onPressed: last ? _finish : () => _go(_index + 1),
                icon: Icon(last ? Icons.check : Icons.arrow_forward),
                label: Text(last ? l.getStarted : l.next),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
