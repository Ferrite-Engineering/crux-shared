// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_mcp/src/document.dart';
import 'package:crux_mcp/src/outcome.dart';
import 'package:meta/meta.dart';

/// The diagnostic code of a tool the licence does not admit.
const String kMcpTierRequiredCode = 'licence.tier_required';

/// The diagnostic code of a part of an answer the licence withheld.
const String kMcpWithheldCode = 'licence.withheld';

/// The words a closed licence gate says, the same in every product.
///
/// A gate is said in the document, never only on stderr: a tool below its
/// tier answers `licence_error` with a [kMcpTierRequiredCode] diagnostic and
/// runs nothing, and a free tool with a licensed part answers the free part
/// with a [kMcpWithheldCode] warning naming what was left out.
///
/// The question "does the licence admit this tier" is the product's headless
/// tier resolver's, asked on every call; this class only words the answer.
@immutable
class McpTierGate {
  /// The gate of a product whose licence file is named by
  /// [environmentVariable] (`LINTCRUX_LICENSE_FILE`, ...).
  const McpTierGate({required this.environmentVariable});

  /// The environment variable naming a licence file.
  final String environmentVariable;

  /// The fix every licence diagnostic carries: the three places a licence
  /// is read from, in the order they are read.
  String get fix =>
      'Give a licence file with --license-file <path>, or set '
      '$environmentVariable to its path, or set the license key of the '
      "organisation's .crux-policy.json.";

  /// Null when [admitted]; otherwise the `licence.tier_required` error for
  /// [what] (the tool or command), which needs a [tier] licence.
  McpDiagnostic? requireTier(
    String tier, {
    required String what,
    required bool admitted,
  }) {
    if (admitted) return null;
    return McpDiagnostic.error(
      kMcpTierRequiredCode,
      '$what needs a $tier licence, and no licence that admits it was found.',
      fix: fix,
    );
  }

  /// The `licence_error` document for [command] when [admitted] is false,
  /// else null: the whole answer to a call below the tool's [tier], with no
  /// body and nothing run.
  McpDocument? refuse({
    required McpProgram program,
    required String command,
    required String tier,
    required bool admitted,
  }) {
    final diagnostic = requireTier(tier, what: command, admitted: admitted);
    if (diagnostic == null) return null;
    return McpDocument(
      tool: program,
      command: command,
      outcome: McpOutcome.licenceError,
      diagnostics: <McpDiagnostic>[diagnostic],
    );
  }

  /// The `licence.withheld` warning: [what] (a check, a classification)
  /// needs a [tier] licence and was left out; the rest of the answer stands.
  McpDiagnostic withhold(String what, {required String tier}) =>
      McpDiagnostic.warning(
        kMcpWithheldCode,
        '$what needs a $tier licence and was left out of this answer; the '
        'rest of the answer stands.',
        fix: fix,
      );
}
