// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_file_dialogs/crux_file_dialogs.dart';
import 'package:crux_file_dialogs/src/gtk_file_picker.dart'
    show cruxFileDialogExtensions;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Stands in for file_picker's own implementation behind the GTK picker.
class _FallbackPicker extends FilePickerPlatform {
  final List<String> calls = <String>[];
  String? answer;

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
    calls.add('pickFiles');
    final path = answer;
    if (path == null) return null;
    return FilePickerResult(<PlatformFile>[
      PlatformFile(path: path, name: p.basename(path), size: 0),
    ]);
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
    AndroidSAFOptions? androidSafOptions,
  }) async {
    calls.add('getDirectoryPath');
    return answer;
  }

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
    calls.add('saveFile');
    return answer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kCruxFileDialogChannel);
  late List<MethodCall> calls;
  late List<String> answer;
  late Directory dir;

  void serveChannel() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return answer;
        });
  }

  setUp(() {
    calls = <MethodCall>[];
    answer = const <String>[];
    dir = Directory.systemTemp.createTempSync('gtk_file_picker_test');
    serveChannel();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    dir.deleteSync(recursive: true);
  });

  test('pickFiles sends the filter and returns the chosen files', () async {
    final top = File(p.join(dir.path, 'top.v'))
      ..writeAsStringSync('module top;');
    answer = <String>[top.path];

    final result = await GtkFilePicker().pickFiles(
      dialogTitle: 'Open Source Files',
      initialDirectory: dir.path,
      type: FileType.custom,
      allowedExtensions: const <String>['v', 'sv'],
      allowMultiple: true,
      withData: true,
    );

    expect(calls.single.method, 'open');
    expect(calls.single.arguments, <String, Object?>{
      'title': 'Open Source Files',
      'folder': dir.path,
      'multiple': true,
      'extensions': <String>['v', 'sv'],
    });
    final file = result!.files.single;
    expect(file.path, top.path);
    expect(file.name, 'top.v');
    expect(file.size, 'module top;'.length);
    // The field file_picker fills for withData, which callers still read.
    // ignore: deprecated_member_use
    expect(String.fromCharCodes(file.bytes!), 'module top;');
  });

  test('pickFiles hands back a read stream when asked for one', () async {
    final top = File(p.join(dir.path, 'top.v'))..writeAsStringSync('abc');
    answer = <String>[top.path];

    final result = await GtkFilePicker().pickFiles(withReadStream: true);

    // The field file_picker fills for withReadStream.
    // ignore: deprecated_member_use
    final chunks = await result!.files.single.readStream!.toList();
    expect(String.fromCharCodes(chunks.expand((c) => c)), 'abc');
  });

  test('pickFiles returns null when the user cancels', () async {
    expect(await GtkFilePicker().pickFiles(), isNull);
    expect(
      (calls.single.arguments as Map<Object?, Object?>)['extensions'],
      isNull,
    );
  });

  test(
    'saveFile returns the path and writes only bytes it was given',
    () async {
      final target = p.join(dir.path, 'session.json');
      answer = <String>[target];

      final path = await GtkFilePicker().saveFile(
        fileName: 'session.json',
        bytes: Uint8List(0),
      );

      expect(path, target);
      expect(calls.single.method, 'save');
      expect(
        (calls.single.arguments as Map<Object?, Object?>)['name'],
        'session.json',
      );
      expect(File(target).existsSync(), isFalse);

      await GtkFilePicker().saveFile(
        fileName: 'theme.json',
        bytes: Uint8List.fromList('{}'.codeUnits),
      );
      expect(File(target).readAsStringSync(), '{}');
    },
  );

  test('getDirectoryPath returns the chosen folder or null', () async {
    answer = <String>[dir.path];
    expect(await GtkFilePicker().getDirectoryPath(), dir.path);
    expect(calls.single.method, 'directory');

    answer = const <String>[];
    expect(await GtkFilePicker().getDirectoryPath(), isNull);
  });

  test('the media types filter by file_picker extension lists', () {
    expect(cruxFileDialogExtensions(FileType.any, const ['v']), isNull);
    expect(cruxFileDialogExtensions(FileType.custom, const ['v']), ['v']);
    expect(cruxFileDialogExtensions(FileType.image, null), contains('png'));
    expect(cruxFileDialogExtensions(FileType.video, null), contains('mp4'));
    expect(cruxFileDialogExtensions(FileType.audio, null), contains('wav'));
    expect(
      cruxFileDialogExtensions(FileType.media, null),
      containsAll(<String>['mp4', 'png']),
    );
  });

  group('a runner without the channel', () {
    setUp(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    // MUTATION: dropping the MissingPluginException catch turns these red.
    test('hands every call to the fallback', () async {
      final fallback = _FallbackPicker()..answer = p.join(dir.path, 'a.v');
      File(fallback.answer!).writeAsStringSync('x');
      final picker = GtkFilePicker(fallback: fallback);

      expect((await picker.pickFiles())!.files.single.path, fallback.answer);
      expect(await picker.getDirectoryPath(), fallback.answer);
      expect(
        await picker.saveFile(
          fileName: 'a.v',
          bytes: Uint8List.fromList('new'.codeUnits),
        ),
        fallback.answer,
      );
      expect(fallback.calls, <String>[
        'pickFiles',
        'getDirectoryPath',
        'saveFile',
      ]);
      // file_picker's saveFile writes the bytes; the picker must not again.
      expect(File(fallback.answer!).readAsStringSync(), 'x');
    });

    test('rethrows when there is no fallback', () async {
      await expectLater(
        GtkFilePicker().pickFiles(),
        throwsA(isA<MissingPluginException>()),
      );
    });
  });

  test('useGtkFileDialogsOnLinux installs it on Linux only, once', () {
    final original = FilePickerPlatform.instance;
    addTearDown(() {
      FilePickerPlatform.instance = original;
      debugDefaultTargetPlatformOverride = null;
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    useGtkFileDialogsOnLinux();
    expect(FilePickerPlatform.instance, same(original));

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    useGtkFileDialogsOnLinux();
    final installed = FilePickerPlatform.instance;
    expect(installed, isA<GtkFilePicker>());
    expect((installed as GtkFilePicker).fallback, same(original));

    useGtkFileDialogsOnLinux();
    expect(FilePickerPlatform.instance, same(installed));
  });
}
