// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/keygen_signing.dart';
import 'support/license_fixtures.dart';

/// The client's machine calls under a shared fingerprint: release by
/// fingerprint, and the lookup that recovers an id a sibling product's
/// registration left this one without.
void main() {
  late TestIssuerKeys keys;

  setUpAll(() async {
    keys = await TestIssuerKeys.fromSeed(7);
  });

  KeygenLicenseClient clientOver(http.Client client) => KeygenLicenseClient(
    accountId: testAccountId,
    verifyKey: keys.verifyKey,
    client: client,
  );

  group('findMachine', () {
    test(
      'asks GET machines/<fingerprint> with the licence as the credential, '
      'and answers the id',
      () async {
        late http.BaseRequest seen;
        final client = clientOver(
          stubClient((request) {
            seen = request;
            return signedIssuerResponse(
              keys: keys,
              request: request,
              body: <String, Object?>{
                'data': <String, Object?>{
                  'type': 'machines',
                  'id': 'machine-42',
                },
              },
            );
          }),
        );
        addTearDown(client.close);

        expect(
          await client.findMachine(
            key: 'key/abc.def',
            fingerprint: 'A-t7h1HuYE4iTMMcZt-H3w',
          ),
          'machine-42',
        );
        expect(seen.method, 'GET');
        expect(
          seen.url.path,
          endsWith('/accounts/$testAccountId/machines/A-t7h1HuYE4iTMMcZt-H3w'),
        );
        expect(seen.headers['Authorization'], 'License key/abc.def');
      },
    );

    test('an answer that is not this machine is no machine', () async {
      // The id becomes the machine this product believes it holds, and a
      // later release is made with it — so a licence object, a machine with
      // someone else's fingerprint, or no resource at all must read as
      // "not found" rather than be remembered.
      for (final body in <Map<String, Object?>>[
        <String, Object?>{
          'data': <String, Object?>{'type': 'licenses', 'id': 'lic-1'},
        },
        <String, Object?>{
          'data': <String, Object?>{
            'type': 'machines',
            'id': 'machine-elsewhere',
            'attributes': <String, Object?>{'fingerprint': 'someone-else'},
          },
        },
        <String, Object?>{'data': null},
      ]) {
        final client = clientOver(signedJsonClient(keys, body));
        addTearDown(client.close);

        expect(
          await client.findMachine(key: 'key/abc.def', fingerprint: 'fp-1'),
          isNull,
          reason: '$body',
        );
      }
    });

    test('not found, refused and unreachable are all null', () async {
      for (final (client, why) in <(http.Client, String)>[
        (
          signedJsonClient(keys, <String, Object?>{
            'errors': <Object?>[
              <String, Object?>{
                'title': 'Not found',
                'detail': 'not found',
                'code': 'NOT_FOUND',
              },
            ],
          }, status: 404),
          'not found',
        ),
        (
          signedJsonClient(keys, <String, Object?>{
            'errors': <Object?>[
              <String, Object?>{'title': 'Forbidden', 'detail': 'refused'},
            ],
          }, status: 403),
          'refused',
        ),
        (stubClient((_) => throw const _Down()), 'unreachable'),
        (
          signedJsonClient(keys, <String, Object?>{
            'data': <String, Object?>{'type': 'machines'},
          }),
          'an answer with no id',
        ),
      ]) {
        final wrapped = clientOver(client);
        addTearDown(wrapped.close);
        expect(
          await wrapped.findMachine(key: 'key/abc.def', fingerprint: 'fp-1'),
          isNull,
          reason: why,
        );
      }
    });
  });

  group('deactivateMachine', () {
    test('deletes machines/<machine>; a fingerprint goes in the path as '
        'is', () async {
      late http.BaseRequest seen;
      final client = clientOver(
        stubClient((request) {
          seen = request;
          return http.StreamedResponse(const Stream<List<int>>.empty(), 204);
        }),
      );
      addTearDown(client.close);

      final result = await client.deactivateMachine(
        key: 'key/abc.def',
        machine: 'A-t7h1HuYE4iTMMcZt-H3w',
      );
      expect(result.outcome, KeygenMachineOutcome.ok);
      expect(seen.method, 'DELETE');
      expect(
        seen.url.path,
        endsWith('/accounts/$testAccountId/machines/A-t7h1HuYE4iTMMcZt-H3w'),
      );
      expect(seen.headers['Authorization'], 'License key/abc.def');
    });

    test(
      'the former machineId parameter still works and means the same',
      () async {
        late http.BaseRequest seen;
        final client = clientOver(
          stubClient((request) {
            seen = request;
            return http.StreamedResponse(const Stream<List<int>>.empty(), 204);
          }),
        );
        addTearDown(client.close);

        final result = await client.deactivateMachine(
          key: 'key/abc.def',
          // The alias under test is the deprecated one, on purpose.
          // ignore: deprecated_member_use_from_same_package
          machineId: 'machine-9',
        );
        expect(result.outcome, KeygenMachineOutcome.ok);
        expect(seen.url.path, endsWith('/machines/machine-9'));
      },
    );

    test('given neither name, or both, it is a programming error', () async {
      final client = clientOver(
        stubClient((_) => throw StateError('must not be sent')),
      );
      addTearDown(client.close);

      expect(
        () => client.deactivateMachine(key: 'key/abc.def'),
        throwsArgumentError,
      );
      expect(
        () => client.deactivateMachine(
          key: 'key/abc.def',
          machine: 'fp-1',
          // Both names at once is the error under test.
          // ignore: deprecated_member_use_from_same_package
          machineId: 'machine-9',
        ),
        throwsArgumentError,
      );
    });
  });
}

class _Down implements Exception {
  const _Down();
}
