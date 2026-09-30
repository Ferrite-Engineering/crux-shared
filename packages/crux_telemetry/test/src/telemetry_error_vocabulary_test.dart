// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

/// The ingestion Worker's `PROPERTY_VALUE`.
final _propertyValue = RegExp(r'^[a-z0-9_]{1,64}$');

/// The ingestion Worker's `EVENT_NAME`.
final _eventName = RegExp(r'^[a-z0-9_]+(\.[a-z0-9_]+){1,2}$');

/// A product-defined exception, named as an obfuscated release build would
/// name it. Its `toString` claims to be a `StateError`, which is exactly the
/// lie a name-based classifier would believe.
class _Zq implements Exception {
  @override
  String toString() => 'StateError: Bad state: /Users/someone/design.sv';
}

/// A product's own subclass of an SDK error, under an arbitrary name.
class _Qx extends StateError {
  _Qx() : super('secret');
}

void main() {
  group('the vocabularies', () {
    final lists = <String, List<String>>{
      'source': kTelemetryUncaughtErrorSources,
      'kind': kTelemetryUncaughtErrorKinds,
      'library': kTelemetryUncaughtErrorLibraries,
    };

    test('every value passes the Worker property-value class', () {
      lists.forEach((key, values) {
        for (final value in values) {
          expect(_propertyValue.hasMatch(value), isTrue, reason: '$key=$value');
        }
      });
    });

    test('no value is listed twice', () {
      lists.forEach((key, values) {
        expect(values.toSet(), hasLength(values.length), reason: key);
      });
    });

    test('the event name passes the Worker event-name class', () {
      expect(_eventName.hasMatch(kTelemetryUncaughtErrorEvent), isTrue);
      expect(kTelemetryUncaughtErrorEvent, 'app.uncaught_error');
    });

    test('there is a catch-all in both open-ended dimensions', () {
      expect(kTelemetryUncaughtErrorKinds, contains('other'));
      expect(kTelemetryUncaughtErrorLibraries, contains('other'));
      expect(kTelemetryUncaughtErrorLibraries, contains('none'));
    });

    test('every framework library name maps into the library vocabulary', () {
      for (final token in kTelemetryFlutterLibraryTokens.values) {
        expect(kTelemetryUncaughtErrorLibraries, contains(token));
      }
    });
  });

  group('the ingestion Worker contract', () {
    // The Worker checks this event's values against its own copy of these
    // lists and drops anything else, so a token added here and not there
    // would arrive as an event with a silently empty dimension.
    final contract =
        jsonDecode(
              File(
                'test/fixtures/uncaught-error-vocabulary.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    List<String> listOf(String key) =>
        (contract[key]! as List<Object?>).cast<String>();

    test('names the same event', () {
      expect(contract['event'], kTelemetryUncaughtErrorEvent);
    });

    test('holds the same lists, in the same order', () {
      expect(listOf('source'), kTelemetryUncaughtErrorSources);
      expect(listOf('kind'), kTelemetryUncaughtErrorKinds);
      expect(listOf('library'), kTelemetryUncaughtErrorLibraries);
    });
  });

  group('telemetryErrorKindOf', () {
    // One representative per bucket, including the subclass that must land in
    // its most specific bucket rather than its supertype's.
    final cases = <String, Object>{
      'FlutterError': FlutterError('x'),
      'StateError': StateError('x'),
      'ArgumentError': ArgumentError('x'),
      'RangeError': RangeError('x'),
      'IndexError': IndexError.withLength(3, 1),
      'FormatException': const FormatException('x'),
      'FileSystemException': const FileSystemException('x', '/secret/path'),
      'PathNotFoundException': const PathNotFoundException(
        '/secret/path',
        OSError('x', 2),
      ),
      'SocketException': const SocketException('x'),
      'HttpException': const HttpException('x'),
      'ProcessException': const ProcessException('secret-tool', <String>[]),
      'PlatformException': PlatformException(code: 'x'),
      'MissingPluginException': MissingPluginException('x'),
      'TimeoutException': TimeoutException('x'),
      'TypeError': TypeError(),
      'NoSuchMethodError': NoSuchMethodError.withInvocation(
        Object(),
        Invocation.method(#x, const <Object?>[]),
      ),
      'AssertionError': AssertionError('x'),
      'UnsupportedError': UnsupportedError('x'),
      'UnimplementedError': UnimplementedError('x'),
      'ConcurrentModificationError': ConcurrentModificationError(),
      'OutOfMemoryError': const OutOfMemoryError(),
      'StackOverflowError': const StackOverflowError(),
    };
    const expected = <String, String>{
      'FlutterError': 'flutter_error',
      'StateError': 'state_error',
      'ArgumentError': 'argument_error',
      'RangeError': 'range_error',
      'IndexError': 'range_error',
      'FormatException': 'format_exception',
      'FileSystemException': 'file_system_exception',
      'PathNotFoundException': 'file_system_exception',
      'SocketException': 'io_exception',
      'HttpException': 'io_exception',
      'ProcessException': 'io_exception',
      'PlatformException': 'platform_exception',
      'MissingPluginException': 'platform_exception',
      'TimeoutException': 'timeout_exception',
      'TypeError': 'type_error',
      'NoSuchMethodError': 'no_such_method_error',
      'AssertionError': 'assertion_error',
      'UnsupportedError': 'unsupported_error',
      'UnimplementedError': 'unsupported_error',
      'ConcurrentModificationError': 'concurrent_modification_error',
      'OutOfMemoryError': 'out_of_memory_error',
      'StackOverflowError': 'stack_overflow_error',
    };

    for (final entry in cases.entries) {
      test('${entry.key} → ${expected[entry.key]}', () {
        expect(telemetryErrorKindOf(entry.value), expected[entry.key]);
      });
    }

    test('every bucket but the catch-all is reachable', () {
      expect(
        expected.values.toSet(),
        kTelemetryUncaughtErrorKinds.toSet().difference(<String>{'other'}),
      );
    });

    test('a FlutterError is not filed as the AssertionError it implements', () {
      expect(FlutterError('x'), isA<AssertionError>());
      expect(telemetryErrorKindOf(FlutterError('x')), 'flutter_error');
    });

    test('an obfuscated or unknown type is other, whatever it claims', () {
      // The name-based classifier this replaces would have read the
      // `toString` below and answered `state_error`. An `is` check cannot be
      // talked into it.
      expect(telemetryErrorKindOf(_Zq()), 'other');
      expect(telemetryErrorKindOf(Exception('StateError')), 'other');
      expect(telemetryErrorKindOf('StateError: a thrown string'), 'other');
      expect(telemetryErrorKindOf(42), 'other');
      expect(telemetryErrorKindOf(null), 'other');
      expect(telemetryErrorKindOf(Object()), 'other');
    });

    test('a subclass buckets by what it is, not what it is called', () {
      expect(telemetryErrorKindOf(_Qx()), 'state_error');
    });

    test("looks through Riverpod's ProviderException to the real failure", () {
      final failing = Provider<int>((_) => throw StateError('boom'));
      final dependent = Provider<int>((ref) => ref.watch(failing));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      Object? caught;
      try {
        container.read(dependent);
      } on Object catch (error) {
        caught = error;
      }
      expect(caught, isA<ProviderException>());
      expect(telemetryErrorKindOf(caught), 'state_error');
    });

    test('never reads the message', () {
      // Two errors of one class and wildly different messages are one bucket.
      expect(
        telemetryErrorKindOf(StateError('/Users/someone/secret_design.v')),
        telemetryErrorKindOf(StateError('')),
      );
    });
  });

  group('telemetryErrorLibraryOf', () {
    test('maps the framework spellings onto one token each', () {
      expect(telemetryErrorLibraryOf('widgets library'), 'widgets');
      expect(telemetryErrorLibraryOf('widget library'), 'widgets');
      expect(telemetryErrorLibraryOf('widgets'), 'widgets');
      expect(telemetryErrorLibraryOf('rendering library'), 'rendering');
      expect(
        telemetryErrorLibraryOf('image resource service'),
        'image_resource_service',
      );
      expect(telemetryErrorLibraryOf('gesture'), 'gestures');
    });

    test("reports FlutterErrorDetails' own default as framework", () {
      final details = FlutterErrorDetails(exception: StateError('x'));
      expect(telemetryErrorLibraryOf(details.library), 'framework');
    });

    test('anything the framework does not emit is other', () {
      // A package's or a product's own label is free text by definition.
      expect(telemetryErrorLibraryOf('crux_workspace'), 'other');
      expect(telemetryErrorLibraryOf('/Users/someone/lib'), 'other');
      expect(telemetryErrorLibraryOf(''), 'other');
      expect(telemetryErrorLibraryOf(null), 'other');
      // Exact match only: a lenient match is how a product string would pass
      // for a framework one.
      expect(telemetryErrorLibraryOf('Widgets Library'), 'other');
      expect(telemetryErrorLibraryOf('widgets library '), 'other');
    });

    test(
      'knows every library name the resolved Flutter SDK reports',
      () {
        // Reads the framework source this package is actually built against,
        // so a toolchain upgrade that adds a library name fails here instead
        // of silently filing that library under `other`.
        final flutterLib = _flutterPackageLib();
        final named = RegExp(r"\blibrary:\s*'([^'$]+)'");
        final found = <String, String>{};
        for (final entity in flutterLib.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final lines = entity.readAsLinesSync();
          for (final line in lines) {
            if (line.trimLeft().startsWith('//')) continue;
            for (final match in named.allMatches(line)) {
              found[match.group(1)!] = entity.path;
            }
          }
        }

        expect(
          found.length,
          greaterThan(10),
          reason:
              'the scan matched almost nothing — the SDK moved or the '
              'pattern went blind',
        );
        final unknown = <String>[
          for (final entry in found.entries)
            if (!kTelemetryFlutterLibraryTokens.containsKey(entry.key))
              '${entry.key}  (${entry.value})',
        ];
        expect(
          unknown,
          isEmpty,
          reason:
              'The Flutter SDK reports these library names and the '
              'uncaught-error vocabulary does not know them. Map each onto a '
              'token in kTelemetryFlutterLibraryTokens (adding the token to '
              'kTelemetryUncaughtErrorLibraries, the product catalogs and the '
              "ingestion Worker's schema if it is new):\n${unknown.join('\n')}",
        );
      },
    );
  });
}

/// The `lib/` directory of the `flutter` package this test resolved against,
/// read from the nearest `package_config.json` above the working directory.
Directory _flutterPackageLib() {
  var dir = Directory.current.absolute;
  while (true) {
    final config = File('${dir.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      final json =
          jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
      final packages = (json['packages']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final flutter = packages.firstWhere((p) => p['name'] == 'flutter');
      // `rootUri` is relative to the config's own directory and carries no
      // trailing slash, so one is added before `packageUri` resolves against
      // it.
      final root = config.parent.uri.resolve(flutter['rootUri']! as String);
      final rootDir = root.path.endsWith('/') ? root : Uri.parse('$root/');
      return Directory.fromUri(
        rootDir.resolve(flutter['packageUri'] as String? ?? 'lib/'),
      );
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('no package_config.json above ${Directory.current}');
    }
    dir = parent;
  }
}
