// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// The C library's `mkstemp(3)`: creates a file from a template ending in
/// `XXXXXX`, exclusively and with mode `0600`, and returns its descriptor.
@Native<Int32 Function(Pointer<Uint8>)>(symbol: 'mkstemp', isLeaf: true)
external int _mkstemp(Pointer<Uint8> template);

/// The C library's `close(2)`.
@Native<Int32 Function(Int32)>(symbol: 'close', isLeaf: true)
external int _close(int descriptor);

/// Creates an empty file named `<path>.XXXXXX` beside [path] that only its
/// owner can read or write, and returns its path.
///
/// `mkstemp` creates the file with mode `0600` in the same system call that
/// creates it, so there is no instant at which another user could open it:
/// creating it first and setting the mode afterwards leaves a window in which
/// another user can open the empty file and read whatever is written into it
/// later, because a descriptor keeps the access it was opened with.
///
/// `null` on Windows, which has access-control lists rather than modes, when
/// the call fails, and wherever the process exports no `mkstemp`. Never
/// throws.
String? createOwnerOnlyScratchFile(String path) {
  if (Platform.isWindows) return null;
  final encoded = utf8.encode('$path.XXXXXX');
  if (encoded.contains(0)) return null;
  final template = Uint8List(encoded.length + 1)..setAll(0, encoded);
  try {
    final descriptor = _mkstemp(template.address);
    if (descriptor < 0) return null;
    _close(descriptor);
    // A `@Native` symbol is bound on first call, and a process that does not
    // export it raises ArgumentError there. That is a platform without
    // `mkstemp`, which is an answer (null), not a crash.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    return null;
  }
  return utf8.decode(template.sublist(0, encoded.length));
}
