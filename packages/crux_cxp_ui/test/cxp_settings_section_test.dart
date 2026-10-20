// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the bound settings section shows the saved settings, saves a '
      'change under the product key, and shows the server state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer(
      overrides: [
        cruxCxpProductBindingProvider.overrideWithValue(
          const CruxCxpProductBinding(
            productName: 'wavecrux',
            defaultPort: 54322,
            prefsPrefix: 'settings.',
          ),
        ),
        cruxCxpLaunchSettingsProvider.overrideWithValue(
          const CruxCxpSettings(enabled: true, port: 54322),
        ),
        cruxCxpServerStatusProvider.overrideWithValue((
          running: true,
          port: 54322,
          problem: null,
        )),
        cruxCxpPeersProvider.overrideWithValue(const []),
        cruxCxpRuntimeProvider.overrideWith((_) async => null),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CruxCxpSettingsSection(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enable CXP server'), findsOneWidget);
    expect(
      find.text(
        'Let WaveCrux share selections with other Crux-compatible tools.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Running on port 54322, 0 peers connected'),
      findsOneWidget,
    );

    await tester.tap(find.text('Broadcast selection automatically'));
    await tester.pumpAndSettle();
    expect(container.read(cruxCxpSettingsProvider).broadcastSelection, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('settings.broadcastSelectionOnCrossProbe'), isFalse);

    await tester.enterText(find.byKey(const ValueKey('cxpSettingsPort')), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Enter a port between 1 and 65535.'), findsOneWidget);
    expect(container.read(cruxCxpSettingsProvider).port, 54322);
  });
}
