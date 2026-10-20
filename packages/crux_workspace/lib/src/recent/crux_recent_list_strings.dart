// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// What a Recent list holds, which sets its wording.
enum CruxRecentKind {
  /// Files: "Recent files", "Clear Recent Files".
  files,

  /// Projects: "Recent projects", "Clear Recent Projects".
  projects,

  /// Workspaces: "Recent workspaces", "Clear Recent Workspaces".
  workspaces,
}

/// The words a Recent list shows, the same in every product.
///
/// [CruxRecentListStrings.of] gives the suite's wording for the current
/// locale (English, Simplified Chinese, Japanese and Korean) and a
/// [CruxRecentKind], so four products do not keep four translations of
/// "Remove from Recent Files". A product with a different noun builds its own
/// with the constructor.
@immutable
class CruxRecentListStrings {
  /// Creates a set of strings.
  const CruxRecentListStrings({
    required this.heading,
    required this.empty,
    required this.removeTooltip,
    required this.missing,
    required this.clearCommand,
    required this.cleared,
    required this.removedMissing,
  });

  /// The suite's strings for [kind] in [locale]; English for a locale the
  /// suite does not translate.
  factory CruxRecentListStrings.forLocale(Locale locale, CruxRecentKind kind) {
    final table = switch (locale.languageCode) {
      'zh' => _zh,
      'ja' => _ja,
      'ko' => _ko,
      _ => _en,
    };
    return table[kind]!;
  }

  /// The suite's strings for [kind] in the ambient locale.
  factory CruxRecentListStrings.of(BuildContext context, CruxRecentKind kind) =>
      CruxRecentListStrings.forLocale(
        Localizations.maybeLocaleOf(context) ?? const Locale('en'),
        kind,
      );

  /// The section heading: "Recent files".
  final String heading;

  /// Shown when the list is empty: "No recent files".
  final String empty;

  /// The row's remove button, its tooltip and accessible name: "Remove from
  /// Recent Files".
  final String removeTooltip;

  /// The second line of a row whose file is gone: "File not found".
  final String missing;

  /// The Clear Recent command in the palette, the File menu and on the
  /// welcome screen: "Clear Recent Files".
  final String clearCommand;

  /// The confirmation after clearing: "Recent files cleared."
  final String cleared;

  /// Reported when an entry did not open and was dropped, given the entry's
  /// file name.
  final String Function(String name) removedMissing;

  static final Map<CruxRecentKind, CruxRecentListStrings> _en = {
    CruxRecentKind.files: CruxRecentListStrings(
      heading: 'Recent files',
      empty: 'No recent files',
      removeTooltip: 'Remove from Recent Files',
      missing: 'File not found',
      clearCommand: 'Clear Recent Files',
      cleared: 'Recent files cleared.',
      removedMissing: (name) =>
          '$name could not be opened and was removed from Recent Files.',
    ),
    CruxRecentKind.projects: CruxRecentListStrings(
      heading: 'Recent projects',
      empty: 'No recent projects',
      removeTooltip: 'Remove from Recent Projects',
      missing: 'Project file not found',
      clearCommand: 'Clear Recent Projects',
      cleared: 'Recent projects cleared.',
      removedMissing: (name) =>
          '$name could not be opened and was removed from Recent Projects.',
    ),
    CruxRecentKind.workspaces: CruxRecentListStrings(
      heading: 'Recent workspaces',
      empty: 'No recent workspaces',
      removeTooltip: 'Remove from Recent Workspaces',
      missing: 'Workspace file not found',
      clearCommand: 'Clear Recent Workspaces',
      cleared: 'Recent workspaces cleared.',
      removedMissing: (name) =>
          '$name could not be opened and was removed from Recent Workspaces.',
    ),
  };

  static final Map<CruxRecentKind, CruxRecentListStrings> _zh = {
    CruxRecentKind.files: CruxRecentListStrings(
      heading: '最近的文件',
      empty: '没有最近的文件',
      removeTooltip: '从最近的文件中移除',
      missing: '未找到文件',
      clearCommand: '清除最近的文件',
      cleared: '已清除最近的文件。',
      removedMissing: (name) => '无法打开 $name，已将其从最近的文件中移除。',
    ),
    CruxRecentKind.projects: CruxRecentListStrings(
      heading: '最近的项目',
      empty: '没有最近的项目',
      removeTooltip: '从最近的项目中移除',
      missing: '未找到项目文件',
      clearCommand: '清除最近的项目',
      cleared: '已清除最近的项目。',
      removedMissing: (name) => '无法打开 $name，已将其从最近的项目中移除。',
    ),
    CruxRecentKind.workspaces: CruxRecentListStrings(
      heading: '最近的工作区',
      empty: '没有最近的工作区',
      removeTooltip: '从最近的工作区中移除',
      missing: '未找到工作区文件',
      clearCommand: '清除最近的工作区',
      cleared: '已清除最近的工作区。',
      removedMissing: (name) => '无法打开 $name，已将其从最近的工作区中移除。',
    ),
  };

  static final Map<CruxRecentKind, CruxRecentListStrings> _ja = {
    CruxRecentKind.files: CruxRecentListStrings(
      heading: '最近のファイル',
      empty: '最近のファイルはありません',
      removeTooltip: '最近のファイルから削除',
      missing: 'ファイルが見つかりません',
      clearCommand: '最近のファイルを消去',
      cleared: '最近のファイルを消去しました。',
      removedMissing: (name) => '$name を開けなかったため、最近のファイルから削除しました。',
    ),
    CruxRecentKind.projects: CruxRecentListStrings(
      heading: '最近のプロジェクト',
      empty: '最近のプロジェクトはありません',
      removeTooltip: '最近のプロジェクトから削除',
      missing: 'プロジェクトファイルが見つかりません',
      clearCommand: '最近のプロジェクトを消去',
      cleared: '最近のプロジェクトを消去しました。',
      removedMissing: (name) => '$name を開けなかったため、最近のプロジェクトから削除しました。',
    ),
    CruxRecentKind.workspaces: CruxRecentListStrings(
      heading: '最近のワークスペース',
      empty: '最近のワークスペースはありません',
      removeTooltip: '最近のワークスペースから削除',
      missing: 'ワークスペースファイルが見つかりません',
      clearCommand: '最近のワークスペースを消去',
      cleared: '最近のワークスペースを消去しました。',
      removedMissing: (name) => '$name を開けなかったため、最近のワークスペースから削除しました。',
    ),
  };

  static final Map<CruxRecentKind, CruxRecentListStrings> _ko = {
    CruxRecentKind.files: CruxRecentListStrings(
      heading: '최근 파일',
      empty: '최근 파일 없음',
      removeTooltip: '최근 파일에서 제거',
      missing: '파일을 찾을 수 없음',
      clearCommand: '최근 파일 지우기',
      cleared: '최근 파일을 지웠습니다.',
      removedMissing: (name) => '$name을(를) 열 수 없어 최근 파일에서 제거했습니다.',
    ),
    CruxRecentKind.projects: CruxRecentListStrings(
      heading: '최근 프로젝트',
      empty: '최근 프로젝트 없음',
      removeTooltip: '최근 프로젝트에서 제거',
      missing: '프로젝트 파일을 찾을 수 없음',
      clearCommand: '최근 프로젝트 지우기',
      cleared: '최근 프로젝트를 지웠습니다.',
      removedMissing: (name) => '$name을(를) 열 수 없어 최근 프로젝트에서 제거했습니다.',
    ),
    CruxRecentKind.workspaces: CruxRecentListStrings(
      heading: '최근 작업 공간',
      empty: '최근 작업 공간 없음',
      removeTooltip: '최근 작업 공간에서 제거',
      missing: '작업 공간 파일을 찾을 수 없음',
      clearCommand: '최근 작업 공간 지우기',
      cleared: '최근 작업 공간을 지웠습니다.',
      removedMissing: (name) => '$name을(를) 열 수 없어 최근 작업 공간에서 제거했습니다.',
    ),
  };
}
