// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/src/element_id.dart';
import 'package:crux_cxp/src/messages/cxp_message.dart';
import 'package:meta/meta.dart';

/// Subscriptions covering every v1 message kind a peer can receive via
/// broadcast.
///
/// This is the "subscribe to everything" default a `CxpPeerConnector`
/// sends after each handshake so cross-product gossip flows without any
/// per-product wiring. Handshake/control kinds (`hello`, `hello_ack`,
/// `goodbye`, `subscribe`, `unsubscribe`) are transport-level and never
/// subscription-routed, so they are not listed. The wire format has no
/// wildcard kind — "all" is this explicit enumeration.
const List<CxpSubscription> cxpSubscribeToAll = <CxpSubscription>[
  CxpSubscription(messageKind: CxpMessageKind.notifySelection),
  CxpSubscription(messageKind: CxpMessageKind.requestHighlight),
  CxpSubscription(messageKind: CxpMessageKind.requestHighlightAck),
  CxpSubscription(messageKind: CxpMessageKind.requestOpenSource),
  CxpSubscription(messageKind: CxpMessageKind.requestOpenSourceAck),
  CxpSubscription(messageKind: CxpMessageKind.requestOpenArtifact),
  CxpSubscription(messageKind: CxpMessageKind.requestOpenArtifactAck),
  CxpSubscription(messageKind: CxpMessageKind.errorResponse),
];

/// Subscription filter applied to one message kind.
///
/// A subscriber asks to receive every message of the given [messageKind].
/// The delivery predicate is CXP §9.1.1, and [matches] is its single
/// evaluation point:
///
/// 1. the message's kind equals [messageKind]; **and**
/// 2. [elementKinds] is empty, **or** at least one referenced element
///    ([CxpMessage.referencedElements]) is of a listed kind; **and**
/// 3. [pathPrefix] is null, **or** at least one referenced element's
///    [ElementId.path] begins with it.
///
/// Both element filters are **existential and independent**. Each is
/// evaluated over *all* the referenced elements, and the same element need
/// not satisfy both: `elementKinds: {signal}` with `pathPrefix: 'top.cpu'`
/// is satisfied by a selection holding a `signal` outside `top.cpu`
/// alongside a `net` inside it. Position is not part of the predicate —
/// `elements` is in the sender's own, presentational order (§9.3, usually
/// click order), so privileging the first element would make routing depend
/// on the order the user happened to click. Prefix-testing only the first
/// element is a conformance failure, not a permitted narrowing; this class
/// did exactly that before 0.5.0 (see the changelog and CXP §9.1.1,
/// <https://edacrux.app/cxp#sec-9-1-1>).
///
/// A message that carries no element references satisfies no subscription
/// carrying either filter — with one exemption. A `notify_selection` whose
/// `elements` array is empty is a **retraction** (§9.1.2): the sender states
/// that its selection is now empty. It is exempt from element filtering and
/// reaches *every* subscriber of `notify_selection`, whatever filters that
/// subscription carries, because a peer that had narrowed its subscription
/// could otherwise never learn that a selection it *was* told about has been
/// withdrawn, and would hold a stale highlight for as long as both peers
/// run. The exemption is deliberately narrow: it covers `notify_selection`
/// with an empty `elements` array and nothing else. Any other kind carrying
/// no element references stays undeliverable to an element-filtered
/// subscription. Delivery implies nothing about what was selected before —
/// a subscriber **MUST NOT** read a retraction as evidence that the
/// withdrawn selection matched its filters (CXP §9.1.2,
/// <https://edacrux.app/cxp#sec-9-1-2>).
///
/// The predicate is a floor, not a ceiling. A router **MUST** deliver every
/// message a subscription is satisfied by; delivering one it is *not*
/// satisfied by is not an error. Filters reduce traffic and receiver work —
/// they are never access control (§11).
@immutable
class CxpSubscription {
  /// Creates a subscription filter.
  const CxpSubscription({
    required this.messageKind,
    this.elementKinds = const <ElementKind>{},
    this.pathPrefix,
  });

  /// Decodes a [CxpSubscription] from its JSON payload.
  factory CxpSubscription.fromJson(Map<String, Object?> json) {
    final kind = json['message_kind'];
    if (kind is! String) {
      throw const FormatException(
        'CxpSubscription.fromJson: missing "message_kind"',
      );
    }
    final rawElementKinds = json['element_kinds'];
    final elementKinds = <ElementKind>{};
    if (rawElementKinds is List) {
      for (final entry in rawElementKinds) {
        // Kinds this build does not know are kept, not dropped:
        // [ElementKind] is open, and silently discarding an unrecognised
        // filter term would widen the subscription rather than narrow it
        // — in the all-unknown case turning a filtered subscription into
        // an unfiltered one.
        if (entry is String && entry.isNotEmpty) {
          elementKinds.add(ElementKind(entry));
        }
      }
    }
    final pathPrefix = json['path_prefix'];
    return CxpSubscription(
      messageKind: kind,
      elementKinds: elementKinds,
      pathPrefix: pathPrefix is String ? pathPrefix : null,
    );
  }

  /// Message-kind discriminator this subscription applies to.
  final String messageKind;

  /// Element kinds to filter for, or empty for "any kind".
  final Set<ElementKind> elementKinds;

  /// Path prefix at least one referenced [ElementId.path] must begin with,
  /// or null for "any path".
  final String? pathPrefix;

  /// Whether [message] satisfies this subscription (CXP §9.1.1).
  ///
  /// The message kind must equal [messageKind]. Element filters are
  /// evaluated against [CxpMessage.referencedElements], existentially and
  /// independently of one another: [elementKinds] requires at least one
  /// referenced element of a listed kind, [pathPrefix] requires at least
  /// one referenced element whose path starts with the prefix, and neither
  /// privileges the first element or any other. A message without element
  /// references fails either filter, except that an empty-`elements`
  /// `notify_selection` — a retraction, §9.1.2 — bypasses both.
  bool matches(CxpMessage message) {
    if (message.kind != messageKind) return false;
    if (elementKinds.isEmpty && pathPrefix == null) return true;
    final elements = message.referencedElements;
    // §9.1.2: a retraction is exempt from element filtering and MUST reach
    // every subscriber of the kind. Narrow by construction — the test is
    // `notify_selection` *and* an empty element set, so every other kind
    // that references no element still falls through to the filters below
    // and fails them.
    if (message.kind == CxpMessageKind.notifySelection && elements.isEmpty) {
      return true;
    }
    if (elementKinds.isNotEmpty &&
        !elements.any((e) => elementKinds.contains(e.kind))) {
      return false;
    }
    final prefix = pathPrefix;
    if (prefix != null && !elements.any((e) => e.path.startsWith(prefix))) {
      return false;
    }
    return true;
  }

  /// JSON encoding.
  Map<String, Object?> toJson() => <String, Object?>{
    'message_kind': messageKind,
    'element_kinds': elementKinds.map((k) => k.name).toList(growable: false),
    'path_prefix': ?pathPrefix,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CxpSubscription &&
          other.messageKind == messageKind &&
          _setEquals(other.elementKinds, elementKinds) &&
          other.pathPrefix == pathPrefix);

  @override
  int get hashCode => Object.hash(
    messageKind,
    Object.hashAllUnordered(elementKinds),
    pathPrefix,
  );

  @override
  String toString() =>
      'CxpSubscription($messageKind, elements=$elementKinds, '
      'prefix=$pathPrefix)';
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) return false;
  for (final v in a) {
    if (!b.contains(v)) return false;
  }
  return true;
}

/// Subscribe to one or more message kinds with optional element filters.
@immutable
class Subscribe extends CxpMessage {
  /// Creates a Subscribe message.
  const Subscribe({required this.subscriptions});

  /// Decodes a [Subscribe] from its JSON payload.
  factory Subscribe.fromJson(Map<String, Object?> json) {
    final raw = json['subscriptions'];
    final list = <CxpSubscription>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map<String, Object?>) {
          list.add(CxpSubscription.fromJson(entry));
        } else if (entry is Map) {
          list.add(CxpSubscription.fromJson(entry.cast<String, Object?>()));
        }
      }
    }
    return Subscribe(subscriptions: list);
  }

  /// The set of filter rules the subscriber asks for.
  final List<CxpSubscription> subscriptions;

  @override
  String get kind => CxpMessageKind.subscribe;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'subscriptions': subscriptions
        .map((s) => s.toJson())
        .toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Subscribe && _listEq(other.subscriptions, subscriptions));

  @override
  int get hashCode => Object.hashAll(subscriptions);

  @override
  String toString() => 'Subscribe($subscriptions)';
}

/// Cancel a previous [Subscribe].
@immutable
class Unsubscribe extends CxpMessage {
  /// Creates an Unsubscribe message that drops every existing subscription.
  const Unsubscribe();

  /// Decodes an [Unsubscribe] from its JSON payload (no fields).
  // ignore: avoid_unused_constructor_parameters
  factory Unsubscribe.fromJson(Map<String, Object?> json) =>
      const Unsubscribe();

  @override
  String get kind => CxpMessageKind.unsubscribe;

  @override
  Map<String, Object?> toJson() => const <String, Object?>{};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Unsubscribe;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'Unsubscribe()';
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
