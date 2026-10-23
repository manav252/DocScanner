// A screen that throws while building shows "Something went wrong" with Retry
// (not Flutter's grey box), and Retry rebuilds it.
import 'package:docscanner/core/error_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

var failBuilds = 1;

class Flaky extends StatelessWidget {
  const Flaky({super.key});

  @override
  Widget build(BuildContext context) {
    if (failBuilds-- > 0) throw StateError('boom');
    return const Text('Recovered');
  }
}

void main() {
  testWidgets('error screen with Retry', (tester) async {
    final previous = ErrorWidget.builder;
    ErrorWidget.builder = (details) => SomethingWentWrong(details: details);

    failBuilds = 1;
    await tester.pumpWidget(
      testApp(
        ValueListenableBuilder(
          valueListenable: appRetry,
          builder: (_, n, _) => KeyedSubtree(key: ValueKey(n), child: const Flaky()),
        ),
      ),
    );
    expect(tester.takeException(), isA<StateError>());
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.textContaining('Your documents are safe'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('error-retry')));
    await tester.pump();
    expect(find.text('Recovered'), findsOneWidget);
    expect(find.text('Something went wrong'), findsNothing);
    ErrorWidget.builder = previous; // must be restored before the test ends
  });
}
