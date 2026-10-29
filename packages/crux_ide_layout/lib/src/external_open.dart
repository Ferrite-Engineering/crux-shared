// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/src/crux_toast.dart';
import 'package:crux_ide_layout/src/debug_stderr_stub.dart'
    if (dart.library.io) 'package:crux_ide_layout/src/debug_stderr_io.dart';
import 'package:crux_io/crux_io.dart' show revealInFileManager;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

/// Opens a link: `url_launcher`'s `launchUrl` shape, answering whether
/// anything opened it.
typedef CruxUrlLauncher = Future<bool> Function(Uri uri);

/// Reveals a file in the platform file manager: `crux_io`'s
/// `revealInFileManager` shape, answering whether a file manager took it.
typedef CruxFileRevealer = Future<bool> Function(String path);

/// Opens [uri] in the user's browser, and says so when nothing could.
///
/// On a Linux host displayed remotely there is often no browser to hand the
/// link to, and `launchUrl` answers false (or throws) without anything on
/// screen; the user clicks again and nothing happens again. This shows an
/// error toast instead, naming the address with a Copy action, and writes
/// the same line to standard error for a session started from a terminal.
///
/// The toast is the context-free one (`CruxToasts.showError`), so the
/// function can stand wherever a bare `launchUrl` stood: as a tear-off bound
/// to a launcher seam (`updateUrlLauncherProvider`, a product's own
/// `fooLaunchUrl` variable) or called from a callback whose widget has gone.
/// Its words are [CruxExternalOpenStrings] in the toast host's locale.
///
/// Every product calls this, never `launchUrl` directly; a static test in
/// each product holds that line.
Future<bool> cruxOpenUrl(Uri uri) =>
    cruxReportingUrlLauncher(url_launcher.launchUrl)(uri);

/// Wraps [launch] so a link it does not open is reported as [cruxOpenUrl]
/// reports it. [cruxOpenUrl] is this over `url_launcher`; tests pass their
/// own [launch].
CruxUrlLauncher cruxReportingUrlLauncher(CruxUrlLauncher launch) =>
    (uri) async {
      var opened = false;
      Object? error;
      try {
        opened = await launch(uri);
      } on Object catch (e) {
        error = e;
      }
      if (!opened) {
        final address = uri.toString();
        _report(
          (strings) => strings.linkNotOpened(address),
          copy: address,
          detail: error,
        );
      }
      return opened;
    };

/// Reveals [path] in the platform file manager, and says so when none took
/// it: an error toast naming the path, with a Copy action, and the same line
/// on standard error.
///
/// [reveal] defaults to `crux_io`'s `revealInFileManager`, which answers
/// false when no file manager could be reached (on a remote display: no
/// session bus for `dbus-send`, no desktop for `xdg-open`). Every product's
/// "Reveal in Finder / Explorer / Files" goes through this.
Future<bool> cruxRevealFile(String path, {CruxFileRevealer? reveal}) async {
  var revealed = false;
  Object? error;
  try {
    revealed = await (reveal ?? revealInFileManager)(path);
  } on Object catch (e) {
    error = e;
  }
  if (!revealed) {
    _report(
      (strings) => strings.fileNotRevealed(path),
      copy: path,
      detail: error,
    );
  }
  return revealed;
}

void _report(
  String Function(CruxExternalOpenStrings strings) message, {
  required String copy,
  required Object? detail,
}) {
  CruxToasts.showErrorFor(
    (context) => message(CruxExternalOpenStrings.of(context)),
    action: (context) => CruxToastAction(
      label: CruxExternalOpenStrings.of(context).copy,
      onPressed: () => Clipboard.setData(ClipboardData(text: copy)),
    ),
  );
  // A session started from a terminal sees it there too, and a host with no
  // toast (a phone theme, a window still starting) still says it somewhere.
  if (!kIsWeb) {
    final line = message(CruxExternalOpenStrings.en);
    writeDebugStderr(detail == null ? line : '$line ($detail)');
  }
}

/// The words for a link or a file the user asked to open that nothing could
/// open, the same in every product.
///
/// [CruxExternalOpenStrings.of] gives the suite's wording for the current
/// locale (English, Simplified Chinese, Japanese and Korean).
@immutable
class CruxExternalOpenStrings {
  /// Creates a set of strings.
  const CruxExternalOpenStrings({
    required this.linkNotOpened,
    required this.fileNotRevealed,
    required this.copy,
  });

  /// The suite's strings for [locale]; English for a locale the suite does
  /// not translate.
  factory CruxExternalOpenStrings.forLocale(Locale locale) =>
      switch (locale.languageCode) {
        'zh' => zh,
        'ja' => ja,
        'ko' => ko,
        _ => en,
      };

  /// The suite's strings in the ambient locale.
  factory CruxExternalOpenStrings.of(BuildContext context) =>
      CruxExternalOpenStrings.forLocale(
        Localizations.maybeLocaleOf(context) ?? const Locale('en'),
      );

  /// No browser opened a link, given its address.
  final String Function(String url) linkNotOpened;

  /// No file manager showed a file, given its path.
  final String Function(String path) fileNotRevealed;

  /// The action that copies the address or the path.
  final String copy;

  /// English.
  static final CruxExternalOpenStrings en = CruxExternalOpenStrings(
    linkNotOpened: (url) =>
        'No web browser could be opened for this link. Copy it to open it '
        'elsewhere: $url',
    fileNotRevealed: (path) =>
        'No file manager could be opened. The file is at $path',
    copy: 'Copy',
  );

  /// Simplified Chinese.
  static final CruxExternalOpenStrings zh = CruxExternalOpenStrings(
    linkNotOpened: (url) => '无法打开网页浏览器来访问此链接。请复制链接，在其他地方打开：$url',
    fileNotRevealed: (path) => '无法打开文件管理器。文件位于 $path',
    copy: '复制',
  );

  /// Japanese.
  static final CruxExternalOpenStrings ja = CruxExternalOpenStrings(
    linkNotOpened: (url) =>
        'このリンクを開くウェブブラウザーを起動できませんでした。コピーして別の場所で開いてください: $url',
    fileNotRevealed: (path) => 'ファイルマネージャーを開けませんでした。ファイルの場所: $path',
    copy: 'コピー',
  );

  /// Korean.
  static final CruxExternalOpenStrings ko = CruxExternalOpenStrings(
    linkNotOpened: (url) => '이 링크를 열 웹 브라우저를 실행할 수 없습니다. 복사하여 다른 곳에서 여세요: $url',
    fileNotRevealed: (path) => '파일 관리자를 열 수 없습니다. 파일 위치: $path',
    copy: '복사',
  );
}
