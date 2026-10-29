// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// The method channel the Linux runner serves GTK file choosers on.
///
/// The runner side is `native/linux/crux_file_dialogs.cc` in this package,
/// which every product's Linux runner compiles; its header spells the same
/// name as `CRUX_FILE_DIALOG_CHANNEL`, and a test holds the two equal.
const String kCruxFileDialogChannel = 'crux/file_dialog';

/// file_picker's dialogs on Linux, drawn by the runner with GTK.
///
/// file_picker's own Linux code asks the XDG desktop portal to draw every
/// dialog, over the DBus session bus. A Linux host displayed remotely (ssh X
/// forwarding, VNC, ETX, a farm job started from another host) often has no
/// reachable session bus, and then every Open, Save and Export fails with a
/// `SocketException`. Where a bus is reachable it can belong to the desktop
/// of the machine's console, which puts the dialog on that screen instead.
///
/// The runner's [kCruxFileDialogChannel] channel shows a GTK file chooser in
/// the app's own process, on the display its window is on, and needs no
/// desktop service. A runner that does not serve the channel answers with a
/// `MissingPluginException`; the picker then hands the call to [fallback],
/// file_picker's own implementation, so a build without the runner half
/// behaves exactly as it did before.
class GtkFilePicker extends FilePickerPlatform {
  /// Creates a picker that talks to the runner over [channel] and falls back
  /// to [fallback] when the runner does not serve it.
  GtkFilePicker({
    this.channel = const MethodChannel(kCruxFileDialogChannel),
    this.fallback,
  });

  /// The runner's channel, [kCruxFileDialogChannel] unless a test says
  /// otherwise.
  final MethodChannel channel;

  /// The implementation a call goes to when the runner has no channel:
  /// file_picker's own, as [useGtkFileDialogsOnLinux] installs it.
  final FilePickerPlatform? fallback;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
    AndroidSAFOptions? androidSafOptions,
  }) async {
    final paths = await _show(
      'open',
      <String, Object?>{
        'title': dialogTitle,
        'folder': initialDirectory,
        'multiple': allowMultiple,
        'extensions': cruxFileDialogExtensions(type, allowedExtensions),
      },
      orElse: (fallback) async => <String>[
        ...?(await fallback.pickFiles(
          dialogTitle: dialogTitle,
          initialDirectory: initialDirectory,
          type: type,
          allowedExtensions: allowedExtensions,
          onFileLoading: onFileLoading,
          compressionQuality: compressionQuality,
          allowMultiple: allowMultiple,
          lockParentWindow: lockParentWindow,
          readSequential: readSequential,
          cancelUploadOnWindowBlur: cancelUploadOnWindowBlur,
          androidSafOptions: androidSafOptions,
        ))?.paths.nonNulls,
      ],
    );
    if (paths.isEmpty) return null;
    return FilePickerResult(<PlatformFile>[
      for (final path in paths)
        await _platformFile(
          path,
          withData: withData,
          withReadStream: withReadStream,
        ),
    ]);
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
    AndroidSAFOptions? androidSafOptions,
  }) async {
    final paths = await _show(
      'directory',
      <String, Object?>{'title': dialogTitle, 'folder': initialDirectory},
      orElse: (fallback) async => <String>[
        ?await fallback.getDirectoryPath(
          dialogTitle: dialogTitle,
          lockParentWindow: lockParentWindow,
          initialDirectory: initialDirectory,
          androidSafOptions: androidSafOptions,
        ),
      ],
    );
    return paths.firstOrNull;
  }

  /// Writes [bytes] to the chosen path when there are any, as file_picker
  /// does. Callers that write the file themselves pass none.
  @override
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    bool lockParentWindow = false,
  }) async {
    var written = false;
    final paths = await _show(
      'save',
      <String, Object?>{
        'title': dialogTitle,
        'folder': initialDirectory,
        'name': fileName,
        'extensions': cruxFileDialogExtensions(type, allowedExtensions),
      },
      orElse: (fallback) async {
        // file_picker writes the bytes itself.
        written = true;
        return <String>[
          ?await fallback.saveFile(
            fileName: fileName,
            bytes: bytes,
            dialogTitle: dialogTitle,
            initialDirectory: initialDirectory,
            type: type,
            allowedExtensions: allowedExtensions,
            onFileLoading: onFileLoading,
            lockParentWindow: lockParentWindow,
          ),
        ];
      },
    );
    final path = paths.firstOrNull;
    if (path != null && bytes.isNotEmpty && !written) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return path;
  }

  Future<List<String>> _show(
    String method,
    Map<String, Object?> arguments, {
    required Future<List<String>> Function(FilePickerPlatform fallback) orElse,
  }) async {
    try {
      final paths = await channel.invokeListMethod<String>(method, arguments);
      return paths ?? const <String>[];
    } on MissingPluginException {
      final fallback = this.fallback;
      if (fallback == null) rethrow;
      return await orElse(fallback);
    }
  }

  static Future<PlatformFile> _platformFile(
    String path, {
    required bool withData,
    required bool withReadStream,
  }) async {
    final file = File(path);
    return PlatformFile(
      path: path,
      name: p.basename(path),
      size: await file.length(),
      bytes: withData ? await file.readAsBytes() : null,
      readStream: withReadStream ? file.openRead() : null,
    );
  }
}

/// The extensions a dialog filters by for [type]: [extensions] for
/// [FileType.custom], file_picker's own lists for the media types, and none
/// (every file shown) for [FileType.any].
@visibleForTesting
List<String>? cruxFileDialogExtensions(
  FileType type,
  List<String>? extensions,
) => switch (type) {
  FileType.any => null,
  FileType.custom => extensions,
  FileType.image => _image,
  FileType.video => _video,
  FileType.audio => const <String>['aac', 'midi', 'mp3', 'ogg', 'wav'],
  FileType.media => const <String>[..._video, ..._image],
};

const List<String> _image = <String>[
  'bmp',
  'gif',
  'jpeg',
  'jpg',
  'png',
  'webp',
];

const List<String> _video = <String>[
  'avi',
  'flv',
  'm4v',
  'mkv',
  'mov',
  'mp4',
  'mpeg',
  'webm',
  'wmv',
];

/// Makes file_picker use [GtkFilePicker] on Linux, keeping file_picker's own
/// implementation as its fallback. Does nothing on any other platform, the
/// web included, and nothing the second time.
///
/// Each product's `bootstrap()` calls it once the binding is initialized, and
/// each product's Linux runner serves the channel; a static test in each
/// product holds both halves in place.
void useGtkFileDialogsOnLinux() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux) return;
  final current = FilePickerPlatform.instance;
  if (current is GtkFilePicker) return;
  FilePickerPlatform.instance = GtkFilePicker(fallback: current);
}
