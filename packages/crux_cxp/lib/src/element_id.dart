// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The element kinds this version of the protocol defines by name.
///
/// Exists so code that handles every kind it knows about can still switch
/// exhaustively — `switch (kind.known) { … case null: … }` — while
/// [ElementKind] itself stays open to kinds defined by products that ship
/// after this library. Adding a value here is a minor protocol revision;
/// receiving an unrecognised kind is not an error.
enum KnownElementKind {
  /// A bit or vector signal in a simulation trace or netlist.
  signal,

  /// A hierarchical scope (module, instance, generate block).
  scope,

  /// A module instance within a parent scope.
  instance,

  /// A net (wire) in a netlist.
  net,

  /// A module port (input, output, inout).
  port,

  /// A named marker (a–z) in a waveform timeline.
  marker,

  /// A lint or design-rule violation site.
  rule,

  /// A testbench or test case in a verification harness.
  test,

  /// A breakpoint set in a simulator or debugger.
  breakpoint,

  /// A free-form source-code location (file + line + optional column).
  source,
}

/// Discriminator for the kind of design element an [ElementId] points to.
///
/// Each Crux product maps its native objects into one of these kinds when
/// emitting CXP messages, and back out of them when receiving messages.
///
/// ### Open by design
///
/// This is an **open** wire type: it wraps the kind string rather than
/// closing over a fixed set, matching the policy `CxpMessageKind` already
/// uses for message kinds. A peer built against a later protocol revision
/// — or a third-party tool with a vocabulary of its own — can put a kind
/// on the wire that this build has never heard of, and the reference
/// still round-trips intact instead of failing to decode. Products
/// forward what they cannot interpret rather than dropping it.
///
/// The kinds this build knows are the [ElementKind] static constants,
/// enumerated in [values], and mirrored by the [KnownElementKind] enum so
/// internal code keeps exhaustive switching:
///
/// ```dart
/// switch (id.kind.known) {
///   case KnownElementKind.signal: …
///   case null:                    // a kind this build does not model
/// }
/// ```
///
/// Equality and hash are by [name], so `ElementKind('signal')` equals
/// [ElementKind.signal].
@immutable
class ElementKind {
  /// Returns the kind named [name], reusing the canonical constant when
  /// [name] is one this build knows and minting an open kind otherwise.
  factory ElementKind(String name) =>
      _byName[name] ?? ElementKind._(name, null);

  const ElementKind._(this.name, this.known);

  /// A bit or vector signal in a simulation trace or netlist.
  static const ElementKind signal = ElementKind._(
    'signal',
    KnownElementKind.signal,
  );

  /// A hierarchical scope (module, instance, generate block).
  static const ElementKind scope = ElementKind._(
    'scope',
    KnownElementKind.scope,
  );

  /// A module instance within a parent scope.
  static const ElementKind instance = ElementKind._(
    'instance',
    KnownElementKind.instance,
  );

  /// A net (wire) in a netlist.
  static const ElementKind net = ElementKind._('net', KnownElementKind.net);

  /// A module port (input, output, inout).
  static const ElementKind port = ElementKind._('port', KnownElementKind.port);

  /// A named marker (a–z) in a waveform timeline.
  static const ElementKind marker = ElementKind._(
    'marker',
    KnownElementKind.marker,
  );

  /// A lint or design-rule violation site.
  static const ElementKind rule = ElementKind._('rule', KnownElementKind.rule);

  /// A testbench or test case in a verification harness.
  static const ElementKind test = ElementKind._('test', KnownElementKind.test);

  /// A breakpoint set in a simulator or debugger.
  static const ElementKind breakpoint = ElementKind._(
    'breakpoint',
    KnownElementKind.breakpoint,
  );

  /// A free-form source-code location (file + line + optional column).
  static const ElementKind source = ElementKind._(
    'source',
    KnownElementKind.source,
  );

  /// Every kind this build defines by name, in declaration order.
  ///
  /// Kinds received from a peer that this build does not know are *not*
  /// in this list — that is the point of the type being open.
  static const List<ElementKind> values = <ElementKind>[
    signal,
    scope,
    instance,
    net,
    port,
    marker,
    rule,
    test,
    breakpoint,
    source,
  ];

  static const Map<String, ElementKind> _byName = <String, ElementKind>{
    'signal': signal,
    'scope': scope,
    'instance': instance,
    'net': net,
    'port': port,
    'marker': marker,
    'rule': rule,
    'test': test,
    'breakpoint': breakpoint,
    'source': source,
  };

  /// The wire form of this kind. Stable; this is what crosses the socket.
  final String name;

  /// The [KnownElementKind] this kind corresponds to, or `null` when the
  /// kind came off the wire and this build does not model it. Switch on
  /// this when exhaustiveness matters.
  final KnownElementKind? known;

  /// Whether this build models this kind. Equivalent to `known != null`.
  bool get isKnown => known != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ElementKind && other.name == name);

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// Opaque, comparable identifier for a cross-tool referenceable element.
///
/// The identifier is the on-the-wire form Crux peers exchange. Each product
/// converts its native references to and from [ElementId] via its own
/// `NameResolver` implementation. The [path] is canonical: peers receiving
/// an [ElementId] match it against their own local objects by canonicalising
/// their objects' paths the same way.
///
/// Equality and hash are value-based — two [ElementId]s with the same
/// [kind] and [path] are equal.
@immutable
class ElementId {
  /// Creates an element identifier with the given [kind] and [path].
  const ElementId({required this.kind, required this.path});

  /// Construct an [ElementId] from its JSON form. Throws [FormatException]
  /// only if [json] is missing a required field.
  ///
  /// An unrecognised `kind` is **not** an error: [ElementKind] is open, so
  /// the reference decodes with `kind.known == null` and round-trips back
  /// onto the wire unchanged. Handlers decide what to do with a kind they
  /// cannot interpret; the transport no longer decides for them.
  factory ElementId.fromJson(Map<String, Object?> json) {
    final kindString = json['kind'];
    final pathValue = json['path'];
    if (kindString is! String) {
      throw const FormatException('ElementId.fromJson: missing "kind"');
    }
    if (kindString.isEmpty) {
      throw const FormatException('ElementId.fromJson: empty "kind"');
    }
    if (pathValue is! String) {
      throw const FormatException('ElementId.fromJson: missing "path"');
    }
    return ElementId(kind: ElementKind(kindString), path: pathValue);
  }

  /// The kind of element this identifier references.
  final ElementKind kind;

  /// The canonical hierarchical path identifying the element.
  ///
  /// Format depends on the [kind] but is always a string chosen so peers
  /// can match references by string equality after canonicalisation. For
  /// signals and scopes the convention is `top.sub.instance.name[range]`.
  final String path;

  /// JSON encoding suitable for embedding in a CXP message payload.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'path': path,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ElementId && other.kind == kind && other.path == path);

  @override
  int get hashCode => Object.hash(kind, path);

  @override
  String toString() => 'ElementId(${kind.name}: $path)';
}
