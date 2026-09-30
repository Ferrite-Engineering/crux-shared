// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show TimeoutException;
import 'dart:io' show FileSystemException, IOException;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_riverpod/misc.dart' show ProviderException;

/// The event recorded when an uncaught error reaches one of the global error
/// handlers.
///
/// Recorded by `TelemetryUncaughtErrorCounter` on behalf of every product, and
/// never by a product call site — which is why each product's catalog lists it
/// as a shared event rather than finding it in a scan of its own source.
const String kTelemetryUncaughtErrorEvent = 'app.uncaught_error';

/// The `source` property: which global handler saw the error.
///
/// `flutter` is `FlutterError.onError` — errors the framework caught and
/// reported (a throwing `build`, a layout assertion, an image that failed to
/// decode). `platform` is `PlatformDispatcher.onError` — errors nothing caught
/// at all, typically from a `Future` or a stream with no error handler.
///
/// There is no `zone` value because no product runs its app inside a guarded
/// zone: an error that escapes the root zone arrives at `platform`.
const List<String> kTelemetryUncaughtErrorSources = <String>[
  'flutter',
  'platform',
];

/// The `kind` property: the error's class, bucketed by `is` checks into a
/// closed set.
///
/// **Never `runtimeType.toString()`.** A release build may be obfuscated, so a
/// runtime type name is unstable between builds, and it is open-ended in any
/// build — a product-defined exception class names whatever its author chose.
/// Both properties disqualify it from a closed vocabulary. Every value here is
/// a class the Dart or Flutter SDK defines, so the list could appear in our own
/// documentation, and anything else is `other`.
const List<String> kTelemetryUncaughtErrorKinds = <String>[
  'flutter_error',
  'state_error',
  'argument_error',
  'range_error',
  'format_exception',
  'file_system_exception',
  'io_exception',
  'platform_exception',
  'timeout_exception',
  'type_error',
  'no_such_method_error',
  'assertion_error',
  'unsupported_error',
  'concurrent_modification_error',
  'out_of_memory_error',
  'stack_overflow_error',
  'other',
];

/// The `library` property: `FlutterErrorDetails.library`, mapped onto the
/// library names the Flutter framework itself reports.
///
/// `none` is the value for a `platform` error, which arrives without any
/// `FlutterErrorDetails` to name a library. `other` is everything the framework
/// does not emit — including a library name a package or a product chose,
/// which is exactly the free text this vocabulary exists to keep out.
const List<String> kTelemetryUncaughtErrorLibraries = <String>[
  'framework',
  'foundation',
  'animation',
  'gestures',
  'painting',
  'image_resource_service',
  'rendering',
  'scheduler',
  'semantics',
  'services',
  'widgets',
  'widget_inspector',
  'material',
  'none',
  'other',
];

/// Every library name the Flutter framework passes as
/// `FlutterErrorDetails.library`, and the token each one reports as.
///
/// The framework spells some libraries more than one way (`widgets library`,
/// `widget library`, `widgets`), so several names share a token. The test
/// suite reads the resolved Flutter SDK and fails if the framework reports a
/// name this map does not know, so a toolchain upgrade cannot quietly start
/// filing a real library under `other`.
const Map<String, String> kTelemetryFlutterLibraryTokens = <String, String>{
  // `FlutterErrorDetails`'s own default.
  'Flutter framework': 'framework',
  'foundation library': 'foundation',
  'foundation': 'foundation',
  'animation library': 'animation',
  'gesture library': 'gestures',
  'gestures library': 'gestures',
  'gesture': 'gestures',
  'painting library': 'painting',
  'image resource service': 'image_resource_service',
  'rendering library': 'rendering',
  'scheduler library': 'scheduler',
  'semantics library': 'semantics',
  'services library': 'services',
  'widgets library': 'widgets',
  'widget library': 'widgets',
  'widgets': 'widgets',
  'widget inspector': 'widget_inspector',
  'widget inspector library': 'widget_inspector',
  'material library': 'material',
};

/// How many `ProviderException` wrappers [telemetryErrorKindOf] looks through.
///
/// Riverpod rethrows a provider's failure wrapped once per provider that read
/// it, so the wrapper says only "a provider failed" and the class worth
/// counting is inside. The bound keeps a pathological chain from costing more
/// than a few type checks inside an error handler.
const int _maxProviderUnwrap = 4;

/// The `kind` token for [error]: one of [kTelemetryUncaughtErrorKinds].
///
/// Decided by `is` checks alone, most specific first — `FlutterError` before
/// `AssertionError` (it implements it), `RangeError` before `ArgumentError`
/// (it extends it), `FileSystemException` before `IOException`. Nothing is read
/// from the error except its type: not its message, not its `toString`, not its
/// stack.
String telemetryErrorKindOf(Object? error) {
  var subject = error;
  for (var i = 0; i < _maxProviderUnwrap; i++) {
    if (subject is! ProviderException) break;
    subject = subject.exception;
  }
  return switch (subject) {
    FlutterError() => 'flutter_error',
    FileSystemException() => 'file_system_exception',
    IOException() => 'io_exception',
    PlatformException() || MissingPluginException() => 'platform_exception',
    TimeoutException() => 'timeout_exception',
    RangeError() => 'range_error',
    ArgumentError() => 'argument_error',
    StateError() => 'state_error',
    FormatException() => 'format_exception',
    TypeError() => 'type_error',
    NoSuchMethodError() => 'no_such_method_error',
    AssertionError() => 'assertion_error',
    UnsupportedError() => 'unsupported_error',
    ConcurrentModificationError() => 'concurrent_modification_error',
    OutOfMemoryError() => 'out_of_memory_error',
    StackOverflowError() => 'stack_overflow_error',
    _ => 'other',
  };
}

/// The `library` token for a `FlutterErrorDetails.library` value: one of
/// [kTelemetryUncaughtErrorLibraries].
///
/// An exact lookup in [kTelemetryFlutterLibraryTokens]. No normalization, no
/// substring match: a lenient match is how a product's own library string
/// would end up passing for a framework one.
String telemetryErrorLibraryOf(String? library) =>
    kTelemetryFlutterLibraryTokens[library] ?? 'other';
