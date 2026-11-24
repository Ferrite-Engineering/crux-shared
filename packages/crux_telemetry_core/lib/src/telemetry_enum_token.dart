// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Snake-cases a Dart enum's `.name` into a telemetry property value.
///
/// The ingestion Worker validates every property value against
/// `^[a-z0-9_]{1,64}$` and **silently drops** anything else — the event is
/// still stored, minus the property, and nothing anywhere reports an error.
/// Dart enum constants are `lowerCamelCase` by convention, so
/// `DebugAdvisorRuleId.xPropagationChain` sent verbatim would arrive as an
/// event with no `rule_id` at all. This is the one function that bridges the
/// two vocabularies.
///
/// **The parameter is [Enum], deliberately, and not [String].** A
/// `String → String` sanitizer would accept a file name, a signal name, or a
/// rule message and wash it into a token that passes the Worker's character
/// class — which is precisely the failure the suite's never-collect rule
/// exists to prevent, and the Worker cannot catch it because the output *is*
/// well
/// formed. Requiring an `Enum` puts the closed vocabulary in the type system
/// instead of in reviewer attention: the only values that can reach here are
/// values a Dart `enum` declaration already enumerates, which is the same
/// thing as saying they appear in our own documentation.
///
/// Call sites whose vocabulary is not a Dart enum (a decoder id, a widget
/// family id, a rule pack name) do not route through here — they map to a
/// literal in a `switch`, which is the same closed-set guarantee spelled out
/// by hand.
///
/// ```dart
/// telemetryEnumToken(DebugAdvisorRuleId.xPropagationChain); // x_propagation_chain
/// telemetryEnumToken(DisplayFormat.ieee754Single);          // ieee754_single
/// ```
String telemetryEnumToken<T extends Enum>(T value) {
  final token = value.name
      // Split an acronym run before the word that follows it, so
      // `htmlParser`-style and `parseHTMLDoc`-style names both break at the
      // reader's word boundary rather than mid-acronym.
      .replaceAllMapped(_acronymTail, (m) => '_${m.group(1)}')
      // Split at every lower/digit → upper transition: `stuckAt` → `stuck_At`.
      .replaceAllMapped(_camelHump, (m) => '_${m.group(1)}')
      .toLowerCase();
  // An enum name outside `[A-Za-z0-9_]` cannot occur — Dart identifiers are
  // constrained to it — but the assert states the postcondition the Worker
  // enforces, so a future non-ASCII identifier fails a debug build here rather
  // than losing a property in production.
  assert(
    RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(token),
    'telemetryEnumToken produced a value the ingestion Worker would drop: '
    '$token',
  );
  return token;
}

/// The last capital of an acronym run that begins a new word (`MLPa` in
/// `htmlParser` has no run; `HTMLParser` matches at `P`).
final RegExp _acronymTail = RegExp('(?<=[A-Z])([A-Z])(?=[a-z])');

/// A capital directly after a lowercase letter or a digit.
final RegExp _camelHump = RegExp('(?<=[a-z0-9])([A-Z])');
