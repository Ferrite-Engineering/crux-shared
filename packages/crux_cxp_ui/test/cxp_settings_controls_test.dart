// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _strings = CruxCxpSettingsStrings(
  enableLabel: 'Enable CXP server',
  enableHelp: 'Allow other Crux apps to connect',
  portLabel: 'Port',
  portHelp: 'TCP port to listen on',
  portError: 'Enter a port between 1 and 65535',
  attentionLabel: 'Request attention',
  attentionHelp: 'Bounce the dock on cross-probe',
  broadcastLabel: 'Broadcast selection',
  broadcastHelp: 'Send selections automatically',
);

Widget _host({
  bool enabled = true,
  ValueChanged<bool>? onEnabled,
  ValueChanged<int>? onPort,
  ValueChanged<bool>? onAttention,
  ValueChanged<bool>? onBroadcast,
  Widget? statusTile,
}) => MaterialApp(
  home: Scaffold(
    body: CruxCxpSettingsControls(
      strings: _strings,
      enabled: enabled,
      port: 9000,
      requestAttention: true,
      broadcastSelection: false,
      onEnabledChanged: onEnabled ?? (_) {},
      onPortSubmitted: onPort ?? (_) {},
      onRequestAttentionChanged: onAttention ?? (_) {},
      onBroadcastSelectionChanged: onBroadcast ?? (_) {},
      statusTile: statusTile,
    ),
  ),
);

void main() {
  group('CruxCxpSettingsControls', () {
    testWidgets('renders the four controls with the supplied values', (
      tester,
    ) async {
      await tester.pumpWidget(_host());
      expect(find.text('Enable CXP server'), findsOneWidget);
      expect(find.text('9000'), findsOneWidget);
      expect(find.text('Request attention'), findsOneWidget);
      expect(find.text('Broadcast selection'), findsOneWidget);
    });

    testWidgets('a valid port submit reports the parsed int; an invalid one '
        'shows the error and reports nothing', (tester) async {
      int? submitted;
      await tester.pumpWidget(_host(onPort: (p) => submitted = p));

      await tester.enterText(
        find.byKey(const ValueKey('cxpSettingsPort')),
        '9010',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted, 9010);

      submitted = null;
      await tester.enterText(
        find.byKey(const ValueKey('cxpSettingsPort')),
        '99999',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted, isNull);
      expect(find.text('Enter a port between 1 and 65535'), findsOneWidget);
    });

    testWidgets('attention/broadcast switches disable with the server', (
      tester,
    ) async {
      var attention = false;
      await tester.pumpWidget(
        _host(enabled: false, onAttention: (_) => attention = true),
      );
      await tester.tap(find.byKey(const ValueKey('cxpSettingsAttention')));
      await tester.pump();
      expect(attention, isFalse);
    });

    testWidgets('the app-specific status tile renders below the controls', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(statusTile: const Text('STATUS: running, 2 peers')),
      );
      expect(find.text('STATUS: running, 2 peers'), findsOneWidget);
    });
  });
}
