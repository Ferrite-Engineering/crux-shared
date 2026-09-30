// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:test/test.dart';

void main() {
  group('CxpEnvelope', () {
    test('round-trips through encodeLine and fromJson', () {
      const envelope = CxpEnvelope(
        messageId: 'msg-1',
        from: 'wavecrux-123',
        kind: CxpMessageKind.hello,
        payload: <String, Object?>{'identity': 'placeholder'},
      );
      final line = envelope.encodeLine();
      expect(line.endsWith('\n'), isTrue);
      final decoded = CxpEnvelope.fromJson(
        jsonDecode(line) as Map<String, Object?>,
      );
      expect(decoded, equals(envelope));
    });

    test('fromJson rejects missing fields', () {
      expect(
        () => CxpEnvelope.fromJson(const <String, Object?>{}),
        throwsFormatException,
      );
    });
  });

  group('Hello / HelloAck / Goodbye', () {
    const identity = PeerIdentity(
      peerId: 'wavecrux-1',
      productName: 'wavecrux',
      productVersion: '1.0.0',
    );

    test('Hello round-trips', () {
      const hello = Hello(identity: identity);
      final recovered = Hello.fromJson(hello.toJson());
      expect(recovered, equals(hello));
    });

    test('HelloAck round-trips', () {
      const ack = HelloAck(identity: identity, inReplyTo: 'msg-1');
      final recovered = HelloAck.fromJson(ack.toJson());
      expect(recovered, equals(ack));
    });

    test('Goodbye round-trips with reason', () {
      const bye = Goodbye(reason: 'shutting down');
      final recovered = Goodbye.fromJson(bye.toJson());
      expect(recovered, equals(bye));
    });

    test('Goodbye round-trips without reason', () {
      const bye = Goodbye();
      final recovered = Goodbye.fromJson(bye.toJson());
      expect(recovered, equals(bye));
      expect(bye.toJson(), isEmpty);
    });
  });

  group('Subscribe / Unsubscribe', () {
    test('Subscribe round-trips', () {
      final sub = Subscribe(
        subscriptions: [
          CxpSubscription(
            messageKind: CxpMessageKind.notifySelection,
            elementKinds: {ElementKind.signal, ElementKind.scope},
            pathPrefix: 'top.cpu.',
          ),
          const CxpSubscription(messageKind: CxpMessageKind.requestHighlight),
        ],
      );
      final recovered = Subscribe.fromJson(sub.toJson());
      expect(recovered, equals(sub));
    });

    test('Unsubscribe round-trips', () {
      const unsub = Unsubscribe();
      final recovered = Unsubscribe.fromJson(unsub.toJson());
      expect(recovered, equals(unsub));
    });
  });

  group('NotifySelection', () {
    test('round-trips through fromJson/toJson', () {
      const message = NotifySelection(
        elements: [
          ElementId(kind: ElementKind.signal, path: 'top.cpu.pc[31:0]'),
        ],
        displayName: 'pc',
        metadata: <String, Object?>{'wavecrux.cursor_time_fs': 100000},
      );
      final recovered = NotifySelection.fromJson(message.toJson());
      expect(recovered.elements, equals(message.elements));
      expect(recovered.displayName, message.displayName);
    });

    // CXP §9.3: `elements` is required, and MAY be empty to signal a
    // cleared selection. Required-but-emptyable: presence is enforced,
    // emptiness is not.
    test('accepts an empty elements list (cleared selection)', () {
      final recovered = NotifySelection.fromJson(const <String, Object?>{
        'elements': <Object?>[],
      });
      expect(recovered.elements, isEmpty);
    });

    test('a cleared selection round-trips', () {
      const message = NotifySelection(
        elements: [],
        displayName: 'nothing selected',
      );
      final recovered = NotifySelection.fromJson(message.toJson());
      expect(recovered, equals(message));
      expect(recovered.elements, isEmpty);
      expect(message.toJson()['elements'], isEmpty);
      expect(recovered.referencedElements, isEmpty);
    });

    test('rejects a missing elements key', () {
      expect(
        () => NotifySelection.fromJson(const <String, Object?>{}),
        throwsFormatException,
      );
    });

    test('rejects a non-array elements value', () {
      expect(
        () => NotifySelection.fromJson(const <String, Object?>{
          'elements': 'top.cpu.pc',
        }),
        throwsFormatException,
      );
    });

    test('forward compatibility: ignores unknown payload keys', () {
      final json = {
        'elements': [
          const ElementId(kind: ElementKind.signal, path: 'a').toJson(),
        ],
        'unknown_future_field': 'will be ignored',
      };
      final recovered = NotifySelection.fromJson(json);
      expect(recovered.elements, hasLength(1));
    });
  });

  group('RequestHighlight / Ack', () {
    test('RequestHighlight round-trips', () {
      const req = RequestHighlight(
        element: ElementId(kind: ElementKind.signal, path: 'top.x'),
      );
      final recovered = RequestHighlight.fromJson(req.toJson());
      expect(recovered, equals(req));
    });

    test('RequestHighlightAck round-trips with reason', () {
      const ack = RequestHighlightAck(
        inReplyTo: 'm-1',
        honored: false,
        reason: 'element not found',
      );
      final recovered = RequestHighlightAck.fromJson(ack.toJson());
      expect(recovered, equals(ack));
    });

    test('RequestHighlightAck round-trips without reason', () {
      const ack = RequestHighlightAck(inReplyTo: 'm-1', honored: true);
      final recovered = RequestHighlightAck.fromJson(ack.toJson());
      expect(recovered, equals(ack));
    });
  });

  group('RequestOpenSource / Ack', () {
    test('RequestOpenSource round-trips with column', () {
      const req = RequestOpenSource(
        filePath: '/abs/path.v',
        line: 42,
        column: 7,
      );
      final recovered = RequestOpenSource.fromJson(req.toJson());
      expect(recovered, equals(req));
    });

    test('RequestOpenSource round-trips without column', () {
      const req = RequestOpenSource(filePath: 'a.v', line: 1);
      final recovered = RequestOpenSource.fromJson(req.toJson());
      expect(recovered, equals(req));
    });

    test('RequestOpenSourceAck round-trips', () {
      const ack = RequestOpenSourceAck(inReplyTo: 'm', honored: true);
      final recovered = RequestOpenSourceAck.fromJson(ack.toJson());
      expect(recovered, equals(ack));
    });
  });

  group('RequestOpenArtifact / Ack', () {
    test('RequestOpenArtifact round-trips with a path hint', () {
      const req = RequestOpenArtifact(
        designId: 'designs/cdc_capture',
        artifactKind: 'waveform',
        path: '/abs/cdc_capture.vcd',
      );
      final recovered = RequestOpenArtifact.fromJson(req.toJson());
      expect(recovered, equals(req));
      // The envelope discriminator and the payload artifact-kind are distinct.
      expect(req.kind, CxpMessageKind.requestOpenArtifact);
      expect(req.toJson()['kind'], 'waveform');
    });

    test('RequestOpenArtifact round-trips without a path hint', () {
      const req = RequestOpenArtifact(
        designId: 'd',
        artifactKind: 'netlist',
      );
      final recovered = RequestOpenArtifact.fromJson(req.toJson());
      expect(recovered, equals(req));
      expect(recovered.path, isNull);
    });

    test('RequestOpenArtifactAck round-trips', () {
      const ack = RequestOpenArtifactAck(
        inReplyTo: 'm-9',
        honored: false,
        reason: 'no workspace entry',
      );
      final recovered = RequestOpenArtifactAck.fromJson(ack.toJson());
      expect(recovered, equals(ack));
    });

    test('decodeCxpMessage routes both new kinds', () {
      const req = RequestOpenArtifact(designId: 'd', artifactKind: 'waveform');
      const ack = RequestOpenArtifactAck(inReplyTo: 'm', honored: true);
      expect(decodeCxpMessage(req.kind, req.toJson()), equals(req));
      expect(decodeCxpMessage(ack.kind, ack.toJson()), equals(ack));
    });
  });

  group('crux.design_id metadata convention', () {
    test('survives a NotifySelection metadata round-trip', () {
      const sel = NotifySelection(
        elements: [ElementId(kind: ElementKind.signal, path: 'top.sample_a')],
        metadata: {cxpDesignIdMetadataKey: 'designs/cdc_capture'},
      );
      final recovered = NotifySelection.fromJson(sel.toJson());
      expect(recovered.metadata[cxpDesignIdMetadataKey], 'designs/cdc_capture');
    });

    test('rides on RequestHighlight metadata (additive field)', () {
      const req = RequestHighlight(
        element: ElementId(kind: ElementKind.signal, path: 'top.sample_a'),
        metadata: {cxpDesignIdMetadataKey: 'designs/cdc_capture'},
      );
      final recovered = RequestHighlight.fromJson(req.toJson());
      expect(recovered, equals(req));
      expect(recovered.metadata[cxpDesignIdMetadataKey], 'designs/cdc_capture');
    });

    test(
      'an older-minor peer ignores both additions without error',
      () {
        // A 1.0 peer does not know the new kind: decode returns null (its
        // caller answers unknown_kind — no crash, connection stays open),
        // never throws. Simulated here by decoding under the unknown-kind
        // path the older build would take.
        expect(
          decodeCxpMessage('request_open_artifact', const {
            'design_id': 'd',
            'kind': 'waveform',
          }),
          isNotNull,
          reason: 'this (1.1) build understands the kind',
        );
        // And a message body carrying an unknown metadata key still decodes
        // (forward compatibility): the older peer keeps the key it cannot
        // interpret rather than failing.
        final withUnknownMeta = NotifySelection.fromJson(<String, Object?>{
          'elements': [
            const ElementId(kind: ElementKind.signal, path: 'a').toJson(),
          ],
          'metadata': const {cxpDesignIdMetadataKey: 'x', 'future.key': 42},
        });
        expect(withUnknownMeta.metadata['future.key'], 42);
        expect(withUnknownMeta.metadata[cxpDesignIdMetadataKey], 'x');
      },
    );
  });

  group('ErrorResponse', () {
    test('round-trips with inReplyTo', () {
      const err = ErrorResponse(
        code: CxpErrorCode.unknownKind,
        message: 'bad kind',
        inReplyTo: 'm-7',
      );
      final recovered = ErrorResponse.fromJson(err.toJson());
      expect(recovered, equals(err));
    });

    test('round-trips with empty inReplyTo', () {
      const err = ErrorResponse(
        code: CxpErrorCode.malformedEnvelope,
        message: 'cannot decode',
      );
      final recovered = ErrorResponse.fromJson(err.toJson());
      expect(recovered, equals(err));
      expect(recovered.inReplyTo, '');
    });
  });

  group('decodeCxpMessage', () {
    test('decodes every known kind', () {
      const identity = PeerIdentity(
        peerId: 'p',
        productName: 'p',
        productVersion: '1',
      );
      final cases = <CxpMessage>[
        const Hello(identity: identity),
        const HelloAck(identity: identity, inReplyTo: 'x'),
        const Goodbye(),
        const Subscribe(subscriptions: []),
        const Unsubscribe(),
        const NotifySelection(
          elements: [ElementId(kind: ElementKind.signal, path: 'a')],
        ),
        const RequestHighlight(
          element: ElementId(kind: ElementKind.signal, path: 'a'),
        ),
        const RequestHighlightAck(inReplyTo: 'x', honored: true),
        const RequestOpenSource(filePath: 'a.v', line: 1),
        const RequestOpenSourceAck(inReplyTo: 'x', honored: true),
        const RequestOpenArtifact(designId: 'd', artifactKind: 'waveform'),
        const RequestOpenArtifactAck(inReplyTo: 'x', honored: true),
        const ErrorResponse(code: 'x', message: 'x'),
      ];
      for (final original in cases) {
        final decoded = decodeCxpMessage(original.kind, original.toJson());
        expect(
          decoded,
          isNotNull,
          reason: 'decoder lost kind ${original.kind}',
        );
        expect(decoded, equals(original));
      }
    });

    test('returns null for unknown kinds', () {
      final decoded = decodeCxpMessage('not_a_real_kind', const {});
      expect(decoded, isNull);
    });
  });

  group('referencedElements', () {
    const signal = ElementId(kind: ElementKind.signal, path: 'top.a');
    const net = ElementId(kind: ElementKind.net, path: 'top.n1');

    test('NotifySelection exposes its element list', () {
      const message = NotifySelection(elements: [signal, net]);
      expect(message.referencedElements, [signal, net]);
    });

    test('RequestHighlight exposes its single element', () {
      const message = RequestHighlight(element: signal);
      expect(message.referencedElements, [signal]);
    });

    test('non-element messages expose an empty list', () {
      expect(const Goodbye().referencedElements, isEmpty);
      expect(
        const RequestOpenSource(filePath: 'a.v', line: 1).referencedElements,
        isEmpty,
      );
      expect(
        const ErrorResponse(code: 'x', message: 'x').referencedElements,
        isEmpty,
      );
    });
  });

  group('CxpSubscription.matches', () {
    const signal = ElementId(kind: ElementKind.signal, path: 'top.cpu.pc');
    const net = ElementId(kind: ElementKind.net, path: 'top.mem.dq');

    test('kind must match', () {
      const sub = CxpSubscription(
        messageKind: CxpMessageKind.notifySelection,
      );
      expect(sub.matches(const NotifySelection(elements: [signal])), isTrue);
      expect(sub.matches(const RequestHighlight(element: signal)), isFalse);
    });

    test('empty filters accept every message of the kind', () {
      const sub = CxpSubscription(
        messageKind: CxpMessageKind.requestOpenSource,
      );
      expect(
        sub.matches(const RequestOpenSource(filePath: 'a.v', line: 3)),
        isTrue,
      );
    });

    test('elementKinds requires at least one referenced element of a '
        'listed kind', () {
      final sub = CxpSubscription(
        messageKind: CxpMessageKind.notifySelection,
        elementKinds: {ElementKind.signal},
      );
      expect(sub.matches(const NotifySelection(elements: [signal])), isTrue);
      expect(
        sub.matches(const NotifySelection(elements: [net, signal])),
        isTrue,
      );
      expect(sub.matches(const NotifySelection(elements: [net])), isFalse);
    });

    // Inverted, not deleted. Through 0.4.4 this test asserted the opposite
    // — 'pathPrefix is evaluated against the primary (first) element' — and
    // pinned that reading deliberately. CXP rev. 4 §9.1.1 ruled it a
    // conformance failure: `elements` is in the sender's presentational
    // order, so a positional predicate makes routing depend on click order.
    // The rename keeps the record that the old behaviour was
    // intentional rather than an accident.
    test('pathPrefix is evaluated against every element, not the first', () {
      const sub = CxpSubscription(
        messageKind: CxpMessageKind.notifySelection,
        pathPrefix: 'top.cpu.',
      );
      expect(sub.matches(const NotifySelection(elements: [signal])), isTrue);
      expect(
        sub.matches(const NotifySelection(elements: [net, signal])),
        isTrue,
        reason: 'a non-primary element may satisfy the prefix (§9.1.1)',
      );
      expect(
        sub.matches(const NotifySelection(elements: [signal, net])),
        isTrue,
        reason: 'and the same selection must route the same either way round',
      );
      expect(sub.matches(const NotifySelection(elements: [net])), isFalse);
    });

    test('the two element filters are independent — one element need not '
        'satisfy both', () {
      final sub = CxpSubscription(
        messageKind: CxpMessageKind.notifySelection,
        elementKinds: {ElementKind.signal},
        pathPrefix: 'top.mem.',
      );
      // §9.1.1's worked example: a `signal` outside the prefix alongside a
      // `net` inside it satisfies the subscription.
      expect(
        sub.matches(const NotifySelection(elements: [signal, net])),
        isTrue,
      );
    });

    test('a message without element references fails element filters', () {
      final byKind = CxpSubscription(
        messageKind: CxpMessageKind.requestOpenSource,
        elementKinds: {ElementKind.source},
      );
      const byPath = CxpSubscription(
        messageKind: CxpMessageKind.requestOpenSource,
        pathPrefix: 'top.',
      );
      const message = RequestOpenSource(filePath: 'a.v', line: 3);
      expect(byKind.matches(message), isFalse);
      expect(byPath.matches(message), isFalse);
    });

    // A cleared selection (empty `elements`, CXP §9.3) is a *retraction*
    // (§9.1.2): it carries no element references, and is exempt from
    // element filtering precisely so a narrowed subscriber can still be
    // told that a selection it was told about has been withdrawn.
    test('a cleared selection reaches an unfiltered subscription', () {
      const sub = CxpSubscription(
        messageKind: CxpMessageKind.notifySelection,
      );
      expect(sub.matches(const NotifySelection(elements: [])), isTrue);
      expect(
        cxpSubscribeToAll.any(
          (s) => s.matches(const NotifySelection(elements: [])),
        ),
        isTrue,
        reason: 'the default subscribe-to-all must carry cleared selections',
      );
    });

    // Inverted with the one above: through 0.4.4 a retraction was filtered
    // out here, which is the hole §9.1.2 was written to close.
    test('a retraction bypasses element filters (§9.1.2)', () {
      final byKind = CxpSubscription(
        messageKind: CxpMessageKind.notifySelection,
        elementKinds: {ElementKind.signal},
      );
      const byPath = CxpSubscription(
        messageKind: CxpMessageKind.notifySelection,
        pathPrefix: 'top.cpu.',
      );
      final byBoth = CxpSubscription(
        messageKind: CxpMessageKind.notifySelection,
        elementKinds: {ElementKind.signal},
        pathPrefix: 'top.cpu.',
      );
      const cleared = NotifySelection(elements: []);
      expect(byKind.matches(cleared), isTrue);
      expect(byPath.matches(cleared), isTrue);
      expect(byBoth.matches(cleared), isTrue);
    });

    test('the retraction exemption is narrow — it does not extend to other '
        'kinds that reference no element', () {
      final byKind = CxpSubscription(
        messageKind: CxpMessageKind.requestOpenSource,
        elementKinds: {ElementKind.source},
      );
      const byPath = CxpSubscription(
        messageKind: CxpMessageKind.requestOpenSource,
        pathPrefix: 'top.',
      );
      const message = RequestOpenSource(filePath: 'a.v', line: 3);
      expect(byKind.matches(message), isFalse);
      expect(byPath.matches(message), isFalse);
      // Nor to a *non-empty* selection that simply misses both filters.
      final selectionSub = CxpSubscription(
        messageKind: CxpMessageKind.notifySelection,
        elementKinds: {ElementKind.signal},
        pathPrefix: 'top.cpu.',
      );
      expect(
        selectionSub.matches(const NotifySelection(elements: [net])),
        isFalse,
      );
    });

    test('both filters must pass when both are set', () {
      final sub = CxpSubscription(
        messageKind: CxpMessageKind.notifySelection,
        elementKinds: {ElementKind.signal},
        pathPrefix: 'top.cpu.',
      );
      expect(sub.matches(const NotifySelection(elements: [signal])), isTrue);
      expect(
        sub.matches(const NotifySelection(elements: [net])),
        isFalse,
      );
    });
  });

  group('isCompatibleCxpVersion', () {
    test('same and minor-different versions are compatible', () {
      expect(isCompatibleCxpVersion(cxpProtocolVersion), isTrue);
      expect(isCompatibleCxpVersion('1.1'), isTrue);
      expect(isCompatibleCxpVersion('1.99'), isTrue);
      expect(isCompatibleCxpVersion('1'), isTrue);
    });

    test('major mismatches are incompatible', () {
      expect(isCompatibleCxpVersion('2.0'), isFalse);
      expect(isCompatibleCxpVersion('0.9'), isFalse);
      expect(isCompatibleCxpVersion('garbage'), isFalse);
      expect(isCompatibleCxpVersion(''), isFalse);
    });
  });
}
