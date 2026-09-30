// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_policy/crux_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A refused policy file is said out loud, where a human looks.
///
/// Before this, a refusal was a `policy.rejected` line on stderr and nothing
/// else: from inside the app a refused file and an absent one were the same
/// ungoverned seat. The licence panel is where an administrator checks a
/// seat, and a refused policy is exactly what makes a managed seat look
/// unmanaged, so it is where the refusal is explained.
void main() {
  const strings = CruxLicensePanelStringsEn();

  Future<void> pump(WidgetTester tester, PolicyLoadResult policy) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            cruxPolicyProvider.overrideWithValue(policy),
            licenseStatusProvider.overrideWithValue(
              CruxLicenseStatus.openCore,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CruxLicensePanel(product: CruxProduct.waveCrux),
              ),
            ),
          ),
        ),
      );

  PolicyLoadResult refused(
    PolicyRejection why, {
    bool signed = true,
    PolicyKeyStatus key = PolicyKeyStatus.none,
    PolicyDiscovery discovery = PolicyDiscovery.wellKnownPath,
  }) => PolicyLoadResult(
    document: PolicyDocument.absent,
    rejection: why,
    sourcePath: '/Users/martin/secret_project/.crux-policy.json',
    discovery: discovery,
    signed: signed,
    keyStatus: key,
    detail: 'the file is signed but no organization public key is installed',
  );

  group('nothing is shown', () {
    testWidgets('when there is no policy file', (tester) async {
      await pump(
        tester,
        const PolicyLoadResult(document: PolicyDocument.absent),
      );
      expect(find.text(strings.licensePolicyRefused), findsNothing);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('when the file was honoured', (tester) async {
      await pump(
        tester,
        PolicyLoadResult(
          document: PolicyDocument.parse('{"schema":1}'),
          discovery: PolicyDiscovery.wellKnownPath,
          signed: true,
          keyStatus: PolicyKeyStatus.configured,
        ),
      );
      expect(find.text(strings.licensePolicyRefused), findsNothing);
    });
  });

  group('a refused file', () {
    testWidgets('is named, with the reason and the log line', (tester) async {
      await pump(tester, refused(PolicyRejection.noPublicKey));

      expect(find.text(strings.licensePolicyRefused), findsOneWidget);
      expect(
        find.text(strings.licensePolicyRefusedNoPublicKey),
        findsOneWidget,
      );
      // The same line the process log carries, so a screenshot and a support
      // bundle agree. Reason and key state are the two facts that decide the
      // fix.
      expect(
        find.textContaining('policy.rejected'),
        findsOneWidget,
      );
      expect(find.textContaining('reason=noPublicKey'), findsOneWidget);
      expect(find.textContaining('key=none'), findsOneWidget);
    });

    testWidgets('never shows the file path', (tester) async {
      // CRUX_POLICY can point at a home directory. The rule the audit log
      // follows holds on screen too.
      await pump(
        tester,
        refused(
          PolicyRejection.untrustedUnsigned,
          signed: false,
          discovery: PolicyDiscovery.environmentVariable,
        ),
      );
      expect(find.textContaining('martin'), findsNothing);
      expect(find.textContaining('secret_project'), findsNothing);
    });

    testWidgets('sits above the status, first thing on the panel', (
      tester,
    ) async {
      await pump(tester, refused(PolicyRejection.badSignature));
      final notice = tester.getTopLeft(find.text(strings.licensePolicyRefused));
      // The status section carries no heading of its own; the key-entry
      // heading is the first titled section and follows it directly.
      final keyEntry = tester.getTopLeft(
        find.text(strings.licenseKeySectionTitle),
      );
      expect(notice.dy, lessThan(keyEntry.dy));
    });

    testWidgets('leaves key entry available — the seat is unmanaged now', (
      tester,
    ) async {
      // A refused file yields an absent document, so the managed-licence
      // binding is false and the user can still enter their own key. Hiding
      // the entry would strand a seat whose organization's file is broken.
      await pump(tester, refused(PolicyRejection.badSignature));
      expect(find.byType(TextField), findsOneWidget);
    });

    for (final (why, sentence) in <(PolicyRejection, String)>[
      (PolicyRejection.noPublicKey, strings.licensePolicyRefusedNoPublicKey),
      (PolicyRejection.badSignature, strings.licensePolicyRefusedBadSignature),
      (
        PolicyRejection.untrustedUnsigned,
        strings.licensePolicyRefusedUntrustedUnsigned,
      ),
      (
        PolicyRejection.malformedSignature,
        strings.licensePolicyRefusedMalformedSignature,
      ),
      (PolicyRejection.insecurePath, strings.licensePolicyRefusedInsecurePath),
    ]) {
      testWidgets('${why.name} gets its own sentence', (tester) async {
        // One sentence per reason because the fixes differ: install a key,
        // compare fingerprints, sign the file, fix the permissions.
        await pump(tester, refused(why));
        expect(find.text(sentence), findsOneWidget);
      });
    }
  });
}
