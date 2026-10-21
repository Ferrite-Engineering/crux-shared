// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/src/cross_probe_panel_controller.dart';
import 'package:crux_cxp_ui/src/cxp_settings_controls.dart';
import 'package:flutter/widgets.dart';

// Japanese and Chinese sentences have no spaces between words, so a long
// one split across two literals is correctly joined without one.
// ignore_for_file: missing_whitespace_between_adjacent_strings

/// Every word the shared cross-probe surfaces show, the same in all four
/// products: the settings section, the panel and its event log, the
/// "Cross-probe to" menus, the Cross-probe Selection command and the
/// outcome of every send.
///
/// [CruxCxpStrings.of] gives the suite's wording for the current locale
/// (English, Simplified Chinese, Japanese, Korean; English otherwise), so the
/// products keep no copies of these strings. A product overrides a line that
/// is genuinely its own with [copyWith].
@immutable
class CruxCxpStrings {
  const CruxCxpStrings._({
    required this.sectionTitle,
    required this.enableLabel,
    required this._enableHelp,
    required this.portLabel,
    required this.portHelp,
    required this.portError,
    required this.attentionLabel,
    required this.attentionHelp,
    required this.broadcastLabel,
    required this.broadcastHelp,
    required this.statusLabel,
    required this.statusRunning,
    required this.statusStopped,
    required this.peersConnected,
    required this.showPanel,
    required this.panelTitle,
    required this.closePanel,
    required this.serverOffline,
    required this.peersSection,
    required this.noPeers,
    required this.sendToPeer,
    required this.unreachableSection,
    required this.eventsSection,
    required this.noEvents,
    required this.clearEvents,
    required this.eventPeerConnected,
    required this.eventPeerDisconnected,
    required this.eventSelectionSent,
    required this.eventSelectionReceived,
    required this.eventHighlightSent,
    required this.eventHighlightReceived,
    required this.eventOpenArtifact,
    required this.eventOther,
    required this.crossProbeTo,
    required this.crossProbeToProduct,
    required this.noPeersRunning,
    required this.noPeersRunningHelp,
    required this.selectionCommand,
    required this.instanceLabel,
    required this.instanceDocumentLabel,
    required this.outcomeSent,
    required this.outcomeRefused,
    required this.outcomeNoResponse,
    required this.outcomePeerGone,
    required this.outcomeServerOff,
    required this.outcomeNothingSelected,
    required this.outcomeNotShowable,
    required this.outcomeNoPeers,
    this._product,
  });

  /// The suite's strings for [locale], naming [product] (a display name,
  /// `WaveCrux`) where a line refers to this product.
  factory CruxCxpStrings.forLocale(Locale locale, {required String product}) {
    final base = switch (locale.languageCode) {
      'zh' => _zh,
      'ja' => _ja,
      'ko' => _ko,
      _ => _en,
    };
    return base.copyWith(product: product);
  }

  /// The suite's strings for the ambient locale.
  factory CruxCxpStrings.of(BuildContext context, {required String product}) =>
      CruxCxpStrings.forLocale(
        Localizations.maybeLocaleOf(context) ?? const Locale('en'),
        product: product,
      );

  final String Function(String product) _enableHelp;
  final String? _product;

  /// Settings section title: "CXP Cross-Probe".
  final String sectionTitle;

  /// The enable switch: "Enable CXP server".
  final String enableLabel;

  /// The enable switch's help, naming this product.
  String get enableHelp => _enableHelp(_product ?? 'This app');

  /// The port field: "CXP port".
  final String portLabel;

  /// The port field's help.
  final String portHelp;

  /// The port field's error.
  final String portError;

  /// The attention switch.
  final String attentionLabel;

  /// The attention switch's help.
  final String attentionHelp;

  /// The broadcast switch.
  final String broadcastLabel;

  /// The broadcast switch's help.
  final String broadcastHelp;

  /// The status row's label: "CXP status".
  final String statusLabel;

  /// The status row while running.
  final String Function(int port) statusRunning;

  /// The status row while stopped.
  final String statusStopped;

  /// The connected-peer count.
  final String Function(int count) peersConnected;

  /// The View-menu and palette toggle: "Show Cross-Probe Panel".
  final String showPanel;

  /// The panel title: "Cross-Probe".
  final String panelTitle;

  /// The panel's close button.
  final String closePanel;

  /// The panel's banner while the server is off.
  final String serverOffline;

  /// "Connected peers".
  final String peersSection;

  /// No connected peers.
  final String noPeers;

  /// A peer row's send button.
  final String sendToPeer;

  /// "Unreachable peers".
  final String unreachableSection;

  /// "Recent events".
  final String eventsSection;

  /// No events yet.
  final String noEvents;

  /// The log's Clear button.
  final String clearEvents;

  /// Event: a peer connected.
  final String eventPeerConnected;

  /// Event: a peer left.
  final String eventPeerDisconnected;

  /// Event: a selection was sent.
  final String eventSelectionSent;

  /// Event: a selection arrived.
  final String eventSelectionReceived;

  /// Event: a highlight request was sent.
  final String eventHighlightSent;

  /// Event: a highlight request arrived.
  final String eventHighlightReceived;

  /// Event: an open-artifact request.
  final String eventOpenArtifact;

  /// Event: any other message.
  final String eventOther;

  /// The context-menu submenu: "Cross-probe to". The submenu chevron is
  /// drawn, never part of the text.
  final String crossProbeTo;

  /// A one-click send to one product: "Cross-probe to WaveCrux".
  final String Function(String target) crossProbeToProduct;

  /// The disabled submenu when no peer runs.
  final String noPeersRunning;

  /// Its tooltip: what to start.
  final String noPeersRunningHelp;

  /// The command in the palette and the menu bar.
  final String selectionCommand;

  /// One of several windows of a product: "WaveCrux 2".
  final String Function(String product, int ordinal) instanceLabel;

  /// One of several windows of a product, with the design that window has
  /// open: "WaveCrux 2 (alu.vcd)". The document is the peer's announced
  /// active document, already reduced to display text.
  final String Function(String instance, String document) instanceDocumentLabel;

  /// Spoken after a send landed.
  final String Function(String target) outcomeSent;

  /// The peer refused, with its reason.
  final String Function(String target, String reason) outcomeRefused;

  /// The peer did not acknowledge in time.
  final String Function(String target) outcomeNoResponse;

  /// The peer went away before the send.
  final String Function(String target) outcomePeerGone;

  /// The local server is off.
  final String outcomeServerOff;

  /// Nothing is selected to send.
  final String outcomeNothingSelected;

  /// The target cannot show any kind this selection has.
  final String Function(String target) outcomeNotShowable;

  /// No peer is running to send to.
  final String outcomeNoPeers;

  /// A copy naming [product], or replacing the lines a product words its
  /// own way.
  CruxCxpStrings copyWith({
    String? product,
    String? portHelp,
    String? outcomeNothingSelected,
  }) => CruxCxpStrings._(
    sectionTitle: sectionTitle,
    enableLabel: enableLabel,
    enableHelp: _enableHelp,
    portLabel: portLabel,
    portHelp: portHelp ?? this.portHelp,
    portError: portError,
    attentionLabel: attentionLabel,
    attentionHelp: attentionHelp,
    broadcastLabel: broadcastLabel,
    broadcastHelp: broadcastHelp,
    statusLabel: statusLabel,
    statusRunning: statusRunning,
    statusStopped: statusStopped,
    peersConnected: peersConnected,
    showPanel: showPanel,
    panelTitle: panelTitle,
    closePanel: closePanel,
    serverOffline: serverOffline,
    peersSection: peersSection,
    noPeers: noPeers,
    sendToPeer: sendToPeer,
    unreachableSection: unreachableSection,
    eventsSection: eventsSection,
    noEvents: noEvents,
    clearEvents: clearEvents,
    eventPeerConnected: eventPeerConnected,
    eventPeerDisconnected: eventPeerDisconnected,
    eventSelectionSent: eventSelectionSent,
    eventSelectionReceived: eventSelectionReceived,
    eventHighlightSent: eventHighlightSent,
    eventHighlightReceived: eventHighlightReceived,
    eventOpenArtifact: eventOpenArtifact,
    eventOther: eventOther,
    crossProbeTo: crossProbeTo,
    crossProbeToProduct: crossProbeToProduct,
    noPeersRunning: noPeersRunning,
    noPeersRunningHelp: noPeersRunningHelp,
    selectionCommand: selectionCommand,
    instanceLabel: instanceLabel,
    instanceDocumentLabel: instanceDocumentLabel,
    outcomeSent: outcomeSent,
    outcomeRefused: outcomeRefused,
    outcomeNoResponse: outcomeNoResponse,
    outcomePeerGone: outcomePeerGone,
    outcomeServerOff: outcomeServerOff,
    outcomeNothingSelected:
        outcomeNothingSelected ?? this.outcomeNothingSelected,
    outcomeNotShowable: outcomeNotShowable,
    outcomeNoPeers: outcomeNoPeers,
    product: product ?? _product,
  );

  /// The settings controls' strings.
  CruxCxpSettingsStrings get settings => CruxCxpSettingsStrings(
    enableLabel: enableLabel,
    enableHelp: enableHelp,
    portLabel: portLabel,
    portHelp: portHelp,
    portError: portError,
    attentionLabel: attentionLabel,
    attentionHelp: attentionHelp,
    broadcastLabel: broadcastLabel,
    broadcastHelp: broadcastHelp,
  );

  /// The panel's strings.
  CrossProbePanelStrings get panel => CrossProbePanelStrings(
    title: panelTitle,
    closeTooltip: closePanel,
    serverOffline: serverOffline,
    peersSectionTitle: peersSection,
    noPeers: noPeers,
    sendTooltip: sendToPeer,
    unreachableSectionTitle: unreachableSection,
    eventsSectionTitle: eventsSection,
    noEvents: noEvents,
    clearEventsLabel: clearEvents,
    sendRejected: (peer, reason) => reason == null || reason.isEmpty
        ? outcomeNoResponse(peer)
        : outcomeRefused(peer, reason),
    eventPeerConnected: eventPeerConnected,
    eventPeerDisconnected: eventPeerDisconnected,
    eventSelectionSent: eventSelectionSent,
    eventSelectionReceived: eventSelectionReceived,
    eventHighlightSent: eventHighlightSent,
    eventHighlightReceived: eventHighlightReceived,
    eventOpenArtifact: eventOpenArtifact,
    eventOther: eventOther,
  );

  static final CruxCxpStrings _en = CruxCxpStrings._(
    sectionTitle: 'CXP Cross-Probe',
    enableLabel: 'Enable CXP server',
    enableHelp: (product) =>
        'Let $product share selections with other Crux-compatible tools.',
    portLabel: 'CXP port',
    portHelp: 'TCP port number, 1 to 65535.',
    portError: 'Enter a port between 1 and 65535.',
    attentionLabel: 'Request attention on cross-probe',
    attentionHelp:
        'Bounce the dock icon (or flash the taskbar) when a peer sends a '
        'cross-probe. Never steals focus.',
    broadcastLabel: 'Broadcast selection automatically',
    broadcastHelp:
        'Announce your selection to connected peers as you select it. When '
        'off, only explicit sends are shared.',
    statusLabel: 'CXP status',
    statusRunning: (port) => 'Running on port $port',
    statusStopped: 'Stopped',
    peersConnected: (count) =>
        count == 1 ? '1 peer connected' : '$count peers connected',
    showPanel: 'Show Cross-Probe Panel',
    panelTitle: 'Cross-Probe',
    closePanel: 'Close cross-probe panel',
    serverOffline:
        'The CXP server is off. Turn it on in Settings > CXP Cross-Probe.',
    peersSection: 'Connected peers',
    noPeers: 'No peers connected',
    sendToPeer: 'Send selection to this peer',
    unreachableSection: 'Unreachable peers',
    eventsSection: 'Recent events',
    noEvents: 'No events yet',
    clearEvents: 'Clear events',
    eventPeerConnected: 'Peer connected',
    eventPeerDisconnected: 'Peer disconnected',
    eventSelectionSent: 'Selection sent',
    eventSelectionReceived: 'Selection received',
    eventHighlightSent: 'Highlight sent',
    eventHighlightReceived: 'Highlight received',
    eventOpenArtifact: 'Open artifact',
    eventOther: 'Event',
    crossProbeTo: 'Cross-probe to',
    crossProbeToProduct: (target) => 'Cross-probe to $target',
    noPeersRunning: 'Cross-probe to (no peers running)',
    noPeersRunningHelp:
        'Start WaveCrux, NetCrux, LintCrux or SimCrux with CXP on to '
        'cross-probe to it.',
    selectionCommand: 'Cross-probe Selection…',
    instanceLabel: (product, ordinal) => '$product $ordinal',
    instanceDocumentLabel: (instance, document) => '$instance ($document)',
    outcomeSent: (target) => 'Cross-probed to $target',
    outcomeRefused: (target, reason) => 'Cross-probe to $target: $reason',
    outcomeNoResponse: (target) => '$target did not answer the cross-probe',
    outcomePeerGone: (target) => '$target is no longer connected',
    outcomeServerOff:
        'The CXP server is off. Turn it on in Settings > CXP Cross-Probe.',
    outcomeNothingSelected: 'Select something to cross-probe first.',
    outcomeNotShowable: (target) => '$target cannot show this selection',
    outcomeNoPeers: 'No peers are running to cross-probe to.',
  );

  static final CruxCxpStrings _zh = CruxCxpStrings._(
    sectionTitle: 'CXP 交叉探测',
    enableLabel: '启用 CXP 服务器',
    enableHelp: (product) => '让 $product 与其他兼容 Crux 的工具共享选择。',
    portLabel: 'CXP 端口',
    portHelp: 'TCP 端口号，1 到 65535。',
    portError: '请输入 1 到 65535 之间的端口。',
    attentionLabel: '交叉探测时请求注意',
    attentionHelp: '当对等端发送交叉探测时，弹跳程序坞图标（或闪烁任务栏）。绝不抢占焦点。',
    broadcastLabel: '自动广播选择',
    broadcastHelp: '在您选择时，将选择内容通知已连接的对等端。关闭时，仅共享显式发送的内容。',
    statusLabel: 'CXP 状态',
    statusRunning: (port) => '正在端口 $port 上运行',
    statusStopped: '已停止',
    peersConnected: (count) => '已连接 $count 个对等端',
    showPanel: '显示交叉探测面板',
    panelTitle: '交叉探测',
    closePanel: '关闭交叉探测面板',
    serverOffline: 'CXP 服务器已关闭。请在 设置 > CXP 交叉探测 中开启。',
    peersSection: '已连接的对等端',
    noPeers: '未连接对等端',
    sendToPeer: '将选择发送到此对等端',
    unreachableSection: '无法连接的对等端',
    eventsSection: '最近事件',
    noEvents: '暂无事件',
    clearEvents: '清除事件',
    eventPeerConnected: '对等端已连接',
    eventPeerDisconnected: '对等端已断开',
    eventSelectionSent: '已发送选择',
    eventSelectionReceived: '已收到选择',
    eventHighlightSent: '已发送高亮',
    eventHighlightReceived: '已收到高亮',
    eventOpenArtifact: '打开工件',
    eventOther: '事件',
    crossProbeTo: '交叉探测到',
    crossProbeToProduct: (target) => '交叉探测到 $target',
    noPeersRunning: '交叉探测到（没有正在运行的对等端）',
    noPeersRunningHelp:
        '启动 WaveCrux、NetCrux、LintCrux 或 SimCrux 并开启 CXP，即可交叉探测到它。',
    selectionCommand: '交叉探测所选内容…',
    instanceLabel: (product, ordinal) => '$product $ordinal',
    instanceDocumentLabel: (instance, document) => '$instance（$document）',
    outcomeSent: (target) => '已交叉探测到 $target',
    outcomeRefused: (target, reason) => '发送到 $target 的交叉探测：$reason',
    outcomeNoResponse: (target) => '$target 未响应交叉探测',
    outcomePeerGone: (target) => '$target 已不再连接',
    outcomeServerOff: 'CXP 服务器已关闭。请在 设置 > CXP 交叉探测 中开启。',
    outcomeNothingSelected: '请先选择要交叉探测的内容。',
    outcomeNotShowable: (target) => '$target 无法显示此选择',
    outcomeNoPeers: '没有可交叉探测的正在运行的对等端。',
  );

  static final CruxCxpStrings _ja = CruxCxpStrings._(
    sectionTitle: 'CXP クロスプローブ',
    enableLabel: 'CXP サーバーを有効化',
    enableHelp: (product) => '$product が他の Crux 対応ツールと選択を共有できるようにします。',
    portLabel: 'CXP ポート',
    portHelp: 'TCP ポート番号、1 から 65535。',
    portError: '1 から 65535 の範囲でポートを入力してください。',
    attentionLabel: 'クロスプローブ時に注意を要求',
    attentionHelp:
        'ピアがクロスプローブを送信したとき、Dock アイコンをバウンス（またはタスクバーを点滅）させます。'
        'フォーカスは奪いません。',
    broadcastLabel: '選択を自動的にブロードキャスト',
    broadcastHelp: '選択するたびに、接続中のピアに選択内容を通知します。オフの場合は、明示的な送信のみが共有されます。',
    statusLabel: 'CXP ステータス',
    statusRunning: (port) => 'ポート $port で実行中',
    statusStopped: '停止中',
    peersConnected: (count) => '$count 件のピアが接続中',
    showPanel: 'クロスプローブパネルを表示',
    panelTitle: 'クロスプローブ',
    closePanel: 'クロスプローブパネルを閉じる',
    serverOffline: 'CXP サーバーはオフです。設定 > CXP クロスプローブ でオンにしてください。',
    peersSection: '接続中のピア',
    noPeers: '接続中のピアはありません',
    sendToPeer: '選択項目をこのピアに送信',
    unreachableSection: '接続できないピア',
    eventsSection: '最近のイベント',
    noEvents: 'まだイベントはありません',
    clearEvents: 'イベントをクリア',
    eventPeerConnected: 'ピアが接続しました',
    eventPeerDisconnected: 'ピアが切断しました',
    eventSelectionSent: '選択を送信しました',
    eventSelectionReceived: '選択を受信しました',
    eventHighlightSent: 'ハイライトを送信しました',
    eventHighlightReceived: 'ハイライトを受信しました',
    eventOpenArtifact: 'アーティファクトを開く',
    eventOther: 'イベント',
    crossProbeTo: 'クロスプローブ先',
    crossProbeToProduct: (target) => '$target へクロスプローブ',
    noPeersRunning: 'クロスプローブ先（実行中のピアはありません）',
    noPeersRunningHelp:
        'WaveCrux、NetCrux、LintCrux、SimCrux のいずれかを CXP オンで起動すると、'
        'クロスプローブできます。',
    selectionCommand: '選択をクロスプローブ…',
    instanceLabel: (product, ordinal) => '$product $ordinal',
    instanceDocumentLabel: (instance, document) => '$instance（$document）',
    outcomeSent: (target) => '$target へクロスプローブしました',
    outcomeRefused: (target, reason) => '$target へのクロスプローブ: $reason',
    outcomeNoResponse: (target) => '$target はクロスプローブに応答しませんでした',
    outcomePeerGone: (target) => '$target はもう接続されていません',
    outcomeServerOff: 'CXP サーバーはオフです。設定 > CXP クロスプローブ でオンにしてください。',
    outcomeNothingSelected: '先にクロスプローブする対象を選択してください。',
    outcomeNotShowable: (target) => '$target はこの選択を表示できません',
    outcomeNoPeers: 'クロスプローブできる実行中のピアはありません。',
  );

  static final CruxCxpStrings _ko = CruxCxpStrings._(
    sectionTitle: 'CXP 교차 프로브',
    enableLabel: 'CXP 서버 활성화',
    enableHelp: (product) => '$product가 다른 Crux 호환 도구와 선택 항목을 공유할 수 있게 합니다.',
    portLabel: 'CXP 포트',
    portHelp: 'TCP 포트 번호, 1부터 65535까지.',
    portError: '1부터 65535 사이의 포트를 입력하세요.',
    attentionLabel: '교차 프로브 시 주의 요청',
    attentionHelp:
        '피어가 교차 프로브를 보낼 때 Dock 아이콘을 튕기거나 작업 표시줄을 깜박입니다. '
        '포커스를 빼앗지 않습니다.',
    broadcastLabel: '선택 항목 자동 브로드캐스트',
    broadcastHelp: '선택할 때마다 연결된 피어에 선택 항목을 알립니다. 꺼져 있으면 명시적으로 보낸 항목만 공유됩니다.',
    statusLabel: 'CXP 상태',
    statusRunning: (port) => '포트 $port에서 실행 중',
    statusStopped: '중지됨',
    peersConnected: (count) => '피어 $count개 연결됨',
    showPanel: '교차 프로브 패널 표시',
    panelTitle: '교차 프로브',
    closePanel: '교차 프로브 패널 닫기',
    serverOffline: 'CXP 서버가 꺼져 있습니다. 설정 > CXP 교차 프로브에서 켜세요.',
    peersSection: '연결된 피어',
    noPeers: '연결된 피어 없음',
    sendToPeer: '이 피어로 선택 항목 보내기',
    unreachableSection: '연결할 수 없는 피어',
    eventsSection: '최근 이벤트',
    noEvents: '아직 이벤트 없음',
    clearEvents: '이벤트 지우기',
    eventPeerConnected: '피어 연결됨',
    eventPeerDisconnected: '피어 연결 끊김',
    eventSelectionSent: '선택 항목 보냄',
    eventSelectionReceived: '선택 항목 받음',
    eventHighlightSent: '강조 표시 보냄',
    eventHighlightReceived: '강조 표시 받음',
    eventOpenArtifact: '아티팩트 열기',
    eventOther: '이벤트',
    crossProbeTo: '교차 프로브 대상',
    crossProbeToProduct: (target) => '$target(으)로 교차 프로브',
    noPeersRunning: '교차 프로브 대상(실행 중인 피어 없음)',
    noPeersRunningHelp:
        'WaveCrux, NetCrux, LintCrux 또는 SimCrux를 CXP를 켠 상태로 시작하면 '
        '교차 프로브할 수 있습니다.',
    selectionCommand: '선택 항목 교차 프로브…',
    instanceLabel: (product, ordinal) => '$product $ordinal',
    instanceDocumentLabel: (instance, document) => '$instance ($document)',
    outcomeSent: (target) => '$target(으)로 교차 프로브했습니다',
    outcomeRefused: (target, reason) => '$target에 보낸 교차 프로브: $reason',
    outcomeNoResponse: (target) => '$target이(가) 교차 프로브에 응답하지 않았습니다',
    outcomePeerGone: (target) => '$target이(가) 더 이상 연결되어 있지 않습니다',
    outcomeServerOff: 'CXP 서버가 꺼져 있습니다. 설정 > CXP 교차 프로브에서 켜세요.',
    outcomeNothingSelected: '먼저 교차 프로브할 항목을 선택하세요.',
    outcomeNotShowable: (target) => '$target은(는) 이 선택 항목을 표시할 수 없습니다',
    outcomeNoPeers: '교차 프로브할 실행 중인 피어가 없습니다.',
  );
}
