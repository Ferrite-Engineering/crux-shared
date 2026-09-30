// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Per-product codec for the `Workspace` generic payload type `P`.
///
/// Each product (WaveCrux today; future Crux products) supplies an
/// implementation that knows how to:
///
/// 1. Serialize the product-specific per-tab payload to a JSON map
///    ([payloadToJson]). The keys are merged with the framework keys
///    (`id`, `displayName`, `paneId`) when the workspace is written to disk.
/// 2. Deserialize the per-tab payload back from a JSON map ([payloadFromJson]).
///    The same map that was emitted by [payloadToJson] is supplied — augmented
///    with framework keys.
/// 3. Derive a fallback display name from a payload ([displayNameFor]). Used
///    when an older workspace document predates the canonical `displayName`
///    field.
///
/// Codecs are stateless; a single instance per product is sufficient.
abstract class WorkspaceCodec<P> {
  /// Creates a workspace codec.
  const WorkspaceCodec();

  /// Schema version for the per-tab payload. Bump within the product when
  /// payload-internal fields change in a non-backward-compatible way; the
  /// codec is responsible for migrating older payload shapes inside
  /// [payloadFromJson].
  ///
  /// The framework's `kWorkspaceSchemaVersion` handles framework-level
  /// schema migration separately.
  int get schemaVersion;

  /// Serializes the product-specific per-tab payload to JSON-natural scalars.
  Map<String, Object?> payloadToJson(P payload);

  /// Reconstructs the product-specific per-tab payload from a JSON map. The
  /// implementation must accept any older shape it has ever written (in
  /// addition to the current shape) so on-disk documents survive product
  /// upgrades.
  P payloadFromJson(Map<String, Object?> json);

  /// Returns a fallback user-visible label for [payload]. Used when an older
  /// workspace document predates the canonical `displayName` framework field.
  String displayNameFor(P payload);

  /// Canonical identity of [payload] — the answer to "is this the same thing
  /// the user already has open?" — or `null` when [payload] has no identity.
  ///
  /// Returning `null` (the default) opts the product out entirely: every open
  /// creates a new tab, which is the behaviour every product had before this
  /// method existed. Payloads that legitimately have no identity — a blank
  /// scratch tab, an unsaved document — must keep returning `null`, because
  /// two payloads with the *same* non-null identity are treated as one thing
  /// and folding every empty payload together would make the second blank tab
  /// impossible to open.
  ///
  /// For a payload keyed on a file path, the identity is
  /// `canonicalPathKey(path)` from `package:crux_io` — **not** the raw string.
  /// A raw string does not survive a relative-vs-absolute launch argument, a
  /// `..` segment, a trailing separator, a symlink (`/tmp` → `/private/tmp` on
  /// macOS), or a case-insensitive volume, and each of those failures shows up
  /// as a duplicate tab that accumulates once per launch, unbounded:
  ///
  /// ```dart
  /// @override
  /// String? identityOf(MyPayload payload) {
  ///   final path = payload.projectPath;
  ///   if (path.isEmpty) return null;
  ///   return canonicalPathKey(path);
  /// }
  /// ```
  ///
  /// Identity must be stable across launches — it is compared against tabs
  /// rehydrated from disk — and must not depend on mutable per-session state
  /// such as scroll offset, selection or load status.
  String? identityOf(P payload) => null;
}
