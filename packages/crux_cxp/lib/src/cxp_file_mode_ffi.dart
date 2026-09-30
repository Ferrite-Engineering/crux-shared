// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// The C library's `chmod(2)` where `mode_t` is 16 bits (Darwin).
@Native<Int32 Function(Pointer<Uint8>, Uint16)>(symbol: 'chmod', isLeaf: true)
external int _chmod16(Pointer<Uint8> path, int mode);

/// The C library's `chmod(2)` where `mode_t` is 32 bits (Linux, the BSDs).
@Native<Int32 Function(Pointer<Uint8>, Uint32)>(symbol: 'chmod', isLeaf: true)
external int _chmod32(Pointer<Uint8> path, int mode);

/// Sets [path]'s permission bits to [mode], following links as `chmod(2)`
/// does. True when the call succeeded; false on failure, on Windows (which
/// has access-control lists rather than modes), and wherever the process
/// exports no `chmod`. Never throws.
bool setPosixFileMode(String path, int mode) {
  if (Platform.isWindows) return false;
  final encoded = utf8.encode(path);
  if (encoded.contains(0)) return false;
  final cString = Uint8List(encoded.length + 1)..setAll(0, encoded);
  try {
    final result = Platform.isMacOS || Platform.isIOS
        ? _chmod16(cString.address, mode)
        : _chmod32(cString.address, mode);
    return result == 0;
    // A `@Native` symbol is bound on first call, and a process that does not
    // export it raises ArgumentError there. That is a platform without
    // `chmod`, which is an answer — false — not a crash.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    return false;
  }
}
