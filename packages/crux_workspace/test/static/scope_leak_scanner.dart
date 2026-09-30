// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The resolved-AST provider read-graph shared by the scope guards in this
// directory.
//
// It was extracted from `per_tab_provider_scope_leak_test.dart` when
// `route_mounted_scope_leak_test.dart` needed the same machinery: both guards
// answer "what does this code read?" over a resolved element model, and they
// must agree on the answer or one of them is quietly wrong. The analysis model
// itself — provider registry, bodies, reads, taint closure — is documented at
// the top of `per_tab_provider_scope_leak_test.dart`, which remains its primary
// reader.
//
// This file declares no tests. It is a plain library, so `flutter test` skips
// it (no `_test.dart` suffix).

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Resolved-AST analysis
// ---------------------------------------------------------------------------

/// The Dart SDK the analyzer should resolve `dart:` libraries against. Under
/// `flutter test` the running executable is the Flutter tester, whose directory
/// is not an SDK, so the bundled `dart-sdk` is located explicitly.
String? _dartSdkPath() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String>[
    if (flutterRoot != null) p.join(flutterRoot, 'bin', 'cache', 'dart-sdk'),
    p.dirname(p.dirname(Platform.resolvedExecutable)),
  ];
  for (final candidate in candidates) {
    if (File(p.join(candidate, 'lib', 'core', 'core.dart')).existsSync()) {
      return candidate;
    }
  }
  return null;
}

/// One provider-to-provider read edge, with the helper declarations the read
/// was found behind (empty when it is written in the provider's own body).
class ProviderRead {
  ProviderRead(this.target, this.via);

  final String target;
  final List<String> via;
}

/// A registered provider: its symbol, the repo-relative path of the library
/// declaring it, and the declarations supplying its build logic.
class ProviderInfo {
  ProviderInfo(this.key, this.name, this.path);

  final String key;
  final String name;
  final String path;
  final Set<String> bodies = <String>{};
  Expression? initializer;
}

/// The resolved provider read-graph over a set of source roots.
class ScopeGraph {
  ScopeGraph._();

  final Map<String, ProviderInfo> providers = <String, ProviderInfo>{};
  final List<String> unresolved = <String>[];

  final Map<String, _Decl> _decls = <String, _Decl>{};
  final Map<String, ResolvedUnitResult> _units = <String, ResolvedUnitResult>{};
  final Map<String, Map<String, String>> _generated =
      <String, Map<String, String>>{};
  final Map<String, _Scan> _scans = <String, _Scan>{};

  /// Every class declared in the source roots, keyed by its element key. Used
  /// by the route guard to pair a widget with its `State` and to read a widget
  /// class's body.
  final Map<String, _ClassInfo> _classes = <String, _ClassInfo>{};
  Map<String, List<ProviderRead>>? _reads;
  Map<String, Set<String>>? _stateDecls;

  static Future<ScopeGraph> resolve(List<Directory> roots) async {
    final files = <String>[];
    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final e in root.listSync(recursive: true)) {
        if (e is File && e.path.endsWith('.dart')) {
          files.add(p.normalize(e.absolute.path));
        }
      }
    }
    final graph = ScopeGraph._();
    if (files.isEmpty) return graph;
    final collection = AnalysisContextCollection(
      includedPaths: files,
      sdkPath: _dartSdkPath(),
    );
    for (final file in files) {
      final result = await collection
          .contextFor(file)
          .currentSession
          .getResolvedUnit(file);
      if (result is! ResolvedUnitResult) {
        graph.unresolved.add(p.relative(file));
        continue;
      }
      graph._units[p.normalize(result.path)] = result;
      result.unit.accept(_UnitVisitor(graph, result));
    }
    graph._linkGenerated();
    return graph;
  }

  String nameOf(String key) =>
      providers[key]?.name ?? key.substring(key.indexOf('::') + 2);

  String? keyOf(String name) {
    for (final e in providers.entries) {
      if (e.value.name == name) return e.key;
    }
    return null;
  }

  /// The helper chain recorded for the first hop of [reach], if the read was
  /// not written in that provider's own body.
  List<String> viaFor(List<String> reach) {
    if (reach.length < 2) return const <String>[];
    for (final r in reads()[reach[0]] ?? const <ProviderRead>[]) {
      if (r.target == reach[1]) return r.via;
    }
    return const <String>[];
  }

  /// Every provider's read set, following the call graph out of its bodies.
  Map<String, List<ProviderRead>> reads() {
    final cached = _reads;
    if (cached != null) return cached;
    final out = <String, List<ProviderRead>>{};
    for (final info in providers.values) {
      out[info.key] = readsFrom(info.bodies, initializer: info.initializer);
    }
    return _reads = out;
  }

  /// The provider reads written in [bodies] (and, optionally, in an inline
  /// [initializer] expression), following the call graph out of them.
  ///
  /// This is the one read-collection routine in the scanner: the provider guard
  /// applies it to a provider's build logic, the route guard applies it to a
  /// widget class and its `State`. Keeping both on the same routine is what
  /// stops the two guards from disagreeing about what a piece of code reads.
  ///
  /// [followCallGraph] controls whether invocations leaving [bodies] are
  /// followed. The provider guard wants that (a provider's build logic IS
  /// whatever it calls). The route guard does not — see the limitation note in
  /// `route_mounted_scope_leak_test.dart`. Reads written anywhere inside a
  /// declaration in [bodies] — including its own private methods, since a
  /// class declaration node contains its members — are collected either way.
  List<ProviderRead> readsFrom(
    Set<String> bodies, {
    Expression? initializer,
    bool followCallGraph = true,
  }) {
    final found = <String, List<String>>{};
    final own = _Scan();
    initializer?.accept(_ReadVisitor(this, own));
    for (final target in own.reads) {
      found.putIfAbsent(target, () => const <String>[]);
    }
    final seen = <String>{...bodies, ...own.callees};
    final queue = <_Frame>[
      // A body IS the subject's own code, so it adds no hop; a helper the
      // initializer calls is already one hop away.
      for (final k in bodies) _Frame(k, const <String>[]),
      if (followCallGraph)
        for (final k in own.callees)
          if (!bodies.contains(k)) _Frame(k, <String>[_decls[k]?.name ?? k]),
    ];
    while (queue.isNotEmpty) {
      final frame = queue.removeLast();
      final scan = _scan(frame.decl);
      for (final target in scan.reads) {
        found.putIfAbsent(target, () => frame.via);
      }
      if (!followCallGraph) continue;
      for (final callee in scan.callees) {
        if (!seen.add(callee)) continue;
        queue.add(
          _Frame(callee, <String>[
            ...frame.via,
            _decls[callee]?.name ?? callee,
          ]),
        );
      }
    }
    return <ProviderRead>[
      for (final e in found.entries) ProviderRead(e.key, e.value),
    ];
  }

  _Scan _scan(String declKey) {
    final cached = _scans[declKey];
    if (cached != null) return cached;
    // Insert before walking so a recursive declaration terminates.
    final scan = _scans[declKey] = _Scan();
    _decls[declKey]?.node.accept(_ReadVisitor(this, scan));
    return scan;
  }

  void _linkGenerated() {
    for (final info in providers.values) {
      final library = info.key.substring(0, info.key.indexOf('::'));
      final decl = _generated[library]?[info.name];
      if (decl != null) info.bodies.add(decl);
    }
  }

  void _noteGenerated(String library, String provider, String declKey) {
    _generated.putIfAbsent(library, () => <String, String>{})[provider] =
        declKey;
  }
}

/// Fixed-point taint propagation. Returns, for every tainted provider, a
/// shortest reach path ending at the scope-key seed it depends on.
Map<String, List<String>> taintClosure(
  Map<String, List<ProviderRead>> reads,
  Set<String> seeds,
) {
  final reach = <String, List<String>>{};
  for (final entry in reads.entries) {
    for (final read in entry.value) {
      if (read.target == entry.key || !seeds.contains(read.target)) continue;
      reach[entry.key] = <String>[entry.key, read.target];
      break;
    }
  }
  var changed = true;
  while (changed) {
    changed = false;
    for (final entry in reads.entries) {
      if (reach.containsKey(entry.key)) continue;
      for (final read in entry.value) {
        if (read.target == entry.key) continue;
        final downstream = reach[read.target];
        if (downstream == null) continue;
        reach[entry.key] = <String>[entry.key, ...downstream];
        changed = true;
        break;
      }
    }
  }
  return reach;
}

class _Frame {
  _Frame(this.decl, this.via);
  final String decl;
  final List<String> via;
}

class _Decl {
  _Decl(this.name, this.node);
  final String name;
  final AstNode node;
}

class _Scan {
  final Set<String> reads = <String>{};
  final Set<String> callees = <String>{};
}

bool _isRiverpodLibrary(Uri? uri) =>
    uri != null && uri.toString().contains('riverpod');

/// True when [type] is, or inherits from, a type declared by riverpod — the
/// test that recognizes hand-written providers, generated providers and
/// families without depending on how the variable is named.
bool _isProviderType(DartType? type) {
  if (type is! InterfaceType) return false;
  if (_isRiverpodLibrary(type.element.library.uri)) return true;
  for (final supertype in type.element.allSupertypes) {
    if (_isRiverpodLibrary(supertype.element.library.uri)) return true;
  }
  return false;
}

/// True when [type] is riverpod's `Ref` or `WidgetRef`, however it was reached
/// — an inline parameter, a stored field, a captured local.
bool _isRefType(DartType? type) {
  if (type is! InterfaceType) return false;
  bool isRef(InterfaceElement element) {
    final name = element.name;
    return _isRiverpodLibrary(element.library.uri) &&
        (name == 'Ref' || name == 'WidgetRef');
  }

  if (isRef(type.element)) return true;
  for (final supertype in type.element.allSupertypes) {
    if (isRef(supertype.element)) return true;
  }
  return false;
}

/// True when [element] is a `Ref` member invoked without an explicit receiver
/// — the shape a `Ref` extension method takes, where `watch(x)` is an implicit
/// `this.watch(x)`.
bool _isImplicitRefReceiver(Element? element) {
  final enclosing = element?.enclosingElement;
  if (enclosing is InterfaceElement) return _isRefType(enclosing.thisType);
  if (enclosing is ExtensionElement) return _isRefType(enclosing.extendedType);
  return false;
}

const Set<String> _refMethods = <String>{
  'watch',
  'read',
  'listen',
  'listenManual',
  'refresh',
  'invalidate',
};

/// The registry key for a provider element, or null if [element] is not a
/// top-level provider variable.
String? _providerKey(Element? element) {
  var target = element;
  if (target is GetterElement) target = target.variable;
  if (target is SetterElement) target = target.variable;
  if (target is! TopLevelVariableElement) return null;
  if (!_isProviderType(target.type)) return null;
  final name = target.name;
  if (name == null) return null;
  return '${target.library.uri}::$name';
}

/// A stable key for a scannable declaration: its source file and name offset.
String? _declKey(Element? element) {
  if (element == null) return null;
  final fragment = element.firstFragment;
  final source = fragment.libraryFragment?.source.fullName;
  final offset = fragment.nameOffset;
  if (source == null || offset == null) return null;
  return '$source@$offset';
}

/// Registers provider definitions and every scannable declaration in one unit.
class _UnitVisitor extends RecursiveAstVisitor<void> {
  _UnitVisitor(this.graph, this.result);

  final ScopeGraph graph;
  final ResolvedUnitResult result;

  void _record(Element? element, String name, AstNode node) {
    final key = _declKey(element);
    if (key == null) return;
    graph._decls.putIfAbsent(key, () => _Decl(name, node));
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    for (final variable in node.variables.variables) {
      final element = variable.declaredFragment?.element;
      final key = _providerKey(element);
      if (key == null) continue;
      final info = graph.providers.putIfAbsent(
        key,
        () => ProviderInfo(
          key,
          element!.name!,
          p.relative(result.libraryElement.firstFragment.source.fullName),
        ),
      );
      final initializer = variable.initializer;
      if (initializer != null) {
        info.initializer = initializer;
        initializer.accept(_BodyReferenceVisitor(info));
      }
    }
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final element = node.declaredFragment?.element;
    final name = element?.name ?? '<function>';
    _record(element, name, node);
    _noteIfGenerated(node.metadata, name, element);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final element = node.declaredFragment?.element;
    _record(element, element?.name ?? '<method>', node);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _record(node.declaredFragment?.element, '<constructor>', node);
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    final name = element?.name ?? '<class>';
    _record(element, name, node);
    _noteIfGenerated(node.metadata, name, element);
    final classKey = _elementKey(element);
    final declKey = _declKey(element);
    if (classKey != null && declKey != null && element != null) {
      graph._classes.putIfAbsent(
        classKey,
        () => _ClassInfo(
          name,
          declKey,
          p.relative(result.libraryElement.firstFragment.source.fullName),
          element,
        ),
      );
    }
    super.visitClassDeclaration(node);
  }

  /// A `@riverpod` function or class generates `<name>Provider` into the same
  /// library's `.g.dart` part; record the association so the generated variable
  /// picks up the annotated declaration as its body.
  void _noteIfGenerated(
    NodeList<Annotation> metadata,
    String name,
    Element? element,
  ) {
    final annotated = metadata.any((a) {
      final n = a.name.name;
      return n == 'riverpod' || n == 'Riverpod';
    });
    if (!annotated || name.isEmpty) return;
    final key = _declKey(element);
    if (key == null) return;
    graph._noteGenerated(
      result.libraryElement.uri.toString(),
      '${name[0].toLowerCase()}${name.substring(1)}Provider',
      key,
    );
  }
}

/// Attaches the declarations a provider's initializer names — `Foo.new` for a
/// notifier class, a bare identifier for a top-level build function — as that
/// provider's bodies.
class _BodyReferenceVisitor extends RecursiveAstVisitor<void> {
  _BodyReferenceVisitor(this.info);

  final ProviderInfo info;

  void _add(Element? element) {
    var target = element;
    if (target is ConstructorElement) target = target.enclosingElement;
    final key = _declKey(target);
    if (key != null) info.bodies.add(key);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element is LocalFunctionElement ||
        element is TopLevelFunctionElement ||
        element is ConstructorElement) {
      _add(element);
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitConstructorReference(ConstructorReference node) {
    _add(node.constructorName.element);
    super.visitConstructorReference(node);
  }
}

/// Collects `ref.*` provider reads and outgoing call-graph edges from one
/// declaration.
class _ReadVisitor extends RecursiveAstVisitor<void> {
  _ReadVisitor(this.graph, this.scan);

  final ScopeGraph graph;
  final _Scan scan;

  void _addCallee(Element? element) {
    final key = _declKey(element);
    if (key != null && graph._decls.containsKey(key)) scan.callees.add(key);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final receiver = node.realTarget;
    final onRef = receiver != null
        ? _isRefType(receiver.staticType)
        : _isImplicitRefReceiver(node.methodName.element);
    if (_refMethods.contains(node.methodName.name) &&
        onRef &&
        node.argumentList.arguments.isNotEmpty) {
      node.argumentList.arguments.first.accept(
        _ProviderArgumentVisitor(graph, scan, <String>{}),
      );
    }
    _addCallee(node.methodName.element);
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    // An extension getter on `Ref` is a call site too.
    _addCallee(node.propertyName.element);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _addCallee(node.identifier.element);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _addCallee(node.constructorName.element);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _addCallee(node.element);
    super.visitFunctionExpressionInvocation(node);
  }
}

/// Resolves the provider(s) an argument expression denotes: a plain reference,
/// a family application, a conditional, or the result of a helper that returns
/// a provider.
class _ProviderArgumentVisitor extends RecursiveAstVisitor<void> {
  _ProviderArgumentVisitor(this.graph, this.scan, this.guard);

  final ScopeGraph graph;
  final _Scan scan;
  final Set<String> guard;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final key = _providerKey(node.element);
    if (key != null) scan.reads.add(key);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final key = _declKey(node.methodName.element);
    if (key != null && guard.add(key)) {
      graph._decls[key]?.node.accept(
        _ProviderArgumentVisitor(graph, scan, guard),
      );
    }
    super.visitMethodInvocation(node);
  }
}

// ---------------------------------------------------------------------------
// Route-mounted widget analysis
// ---------------------------------------------------------------------------

/// A widget constructed inside a route-builder callback.
///
/// One per (route call site, widget class) pair. `showDialog(builder: (_) =>
/// Foo())` yields one; a builder returning a `Column` of two custom widgets
/// yields two.
class RouteMount {
  RouteMount({
    required this.routeApi,
    required this.callSite,
    required this.widget,
    required this.widgetPath,
    required this.scoped,
    required this.reads,
  });

  /// The routing API that mounted it: `showDialog`, `showModalBottomSheet`,
  /// `Navigator.push`, …
  final String routeApi;

  /// `<path>:<line>` of the route call.
  final String callSite;

  /// The constructed widget's class name.
  final String widget;

  /// Repo-relative path of the widget class declaration, or `null` when the
  /// class is declared outside the source roots (a framework widget).
  final String? widgetPath;

  /// Whether an `UncontrolledProviderScope` / `ProviderScope` was found on the
  /// path — in the builder closure itself, or in the widget's own class body.
  final bool scoped;

  /// Provider reads found in the widget's class body and its `State`.
  final List<ProviderRead> reads;
}

/// The route-builder APIs whose callback mounts a subtree on a Navigator that
/// may be outside the per-tab `UncontrolledProviderScope`.
const Set<String> _routeApis = <String>{
  'showDialog',
  'showGeneralDialog',
  'showModalBottomSheet',
  'showBottomSheet',
  'showCupertinoDialog',
  'showCupertinoModalPopup',
  'showAdaptiveDialog',
  'showMenu',
};

/// `NavigatorState` / `Navigator` methods that push a route.
const Set<String> _navigatorPushMethods = <String>{
  'push',
  'pushReplacement',
  'pushAndRemoveUntil',
  'restorablePush',
  'restorablePushReplacement',
};

/// Widgets that re-bind the container for their subtree. Finding one on the
/// path is the fix, so it is also the exemption.
const Set<String> _scopeWidgets = <String>{
  'UncontrolledProviderScope',
  'ProviderScope',
};

extension RouteScopeAnalysis on ScopeGraph {
  /// Providers a designated overrides list re-binds, e.g. a product's per-tab
  /// override factory. [path] is the file, [within] the top-level variable to
  /// restrict to (null = the whole file).
  ///
  /// This is how a product-tree scan learns which providers are per-tab: a
  /// provider is per-tab iff something overrides it per tab.
  Set<String> overrideTargets(String path, String? within) {
    final unit = _units[p.normalize(File(path).absolute.path)];
    if (unit == null) return <String>{};
    AstNode scope = unit.unit;
    if (within != null) {
      for (final d in unit.unit.declarations) {
        if (d is TopLevelVariableDeclaration &&
            d.variables.variables.any((v) => v.name.lexeme == within)) {
          scope = d;
        }
      }
    }
    final out = <String>{};
    scope.accept(_OverrideVisitor(out));
    return out;
  }

  /// Every widget constructed directly inside a route-builder callback,
  /// with the reads of that widget's own class body and `State`.
  List<RouteMount> routeMounts() {
    final out = <RouteMount>[];
    for (final unit in _units.values) {
      unit.unit.accept(_RouteVisitor(this, unit, out));
    }
    return out;
  }

  /// The declarations whose bodies make up the widget class [classKey]: the
  /// class itself plus any `State` / `ConsumerState` subclass declared for it.
  Set<String> _bodiesOfWidget(String classKey) {
    final info = _classes[classKey];
    if (info == null) return const <String>{};
    return <String>{info.declKey, ...?_stateDeclsOf()[classKey]};
  }

  /// True when any of [bodies] constructs a container-rebinding scope widget —
  /// the "the widget installs its own scope" exemption.
  bool _scopesIn(Set<String> bodies) {
    for (final key in bodies) {
      final node = _decls[key]?.node;
      if (node == null) continue;
      final found = <InstanceCreationExpression>[];
      var scoped = false;
      node.accept(_WidgetCollector(found, () => scoped = true));
      if (scoped) return true;
    }
    return false;
  }

  /// Widget class key -> the declaration keys of its `State` subclasses.
  Map<String, Set<String>> _stateDeclsOf() {
    final cached = _stateDecls;
    if (cached != null) return cached;
    final out = <String, Set<String>>{};
    for (final info in _classes.values) {
      for (final supertype in info.element.allSupertypes) {
        final name = supertype.element.name;
        if (name != 'State' && name != 'ConsumerState') continue;
        if (supertype.typeArguments.length != 1) continue;
        final widget = supertype.typeArguments.first;
        if (widget is! InterfaceType) continue;
        final key = _elementKey(widget.element);
        if (key == null) continue;
        out.putIfAbsent(key, () => <String>{}).add(info.declKey);
      }
    }
    return _stateDecls = out;
  }
}

/// True when [type] is a Flutter `Widget`.
bool _isWidgetType(DartType? type) {
  if (type is! InterfaceType) return false;
  if (type.element.name == 'Widget') return true;
  for (final supertype in type.element.allSupertypes) {
    if (supertype.element.name == 'Widget' &&
        supertype.element.library.uri.toString().startsWith(
          'package:flutter/',
        )) {
      return true;
    }
  }
  return false;
}

String? _elementKey(Element? element) {
  if (element == null) return null;
  final name = element.name;
  final uri = element.library?.uri;
  if (name == null || uri == null) return null;
  return '$uri::$name';
}

/// Finds route-builder call sites and the widgets their callbacks construct.
class _RouteVisitor extends RecursiveAstVisitor<void> {
  _RouteVisitor(this.graph, this.unit, this.out);

  final ScopeGraph graph;
  final ResolvedUnitResult unit;
  final List<RouteMount> out;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final api = _routeApiOf(node);
    if (api != null) _collect(api, node);
    super.visitMethodInvocation(node);
  }

  /// The routing API [node] calls, or null when it is not one.
  String? _routeApiOf(MethodInvocation node) {
    final name = node.methodName.name;
    if (_routeApis.contains(name)) {
      // A same-named product helper counts too: it is still the place the
      // builder is written.
      return name;
    }
    if (!_navigatorPushMethods.contains(name)) return null;
    final receiver = node.realTarget;
    final receiverType = receiver?.staticType;
    if (receiverType is InterfaceType &&
        receiverType.element.name == 'NavigatorState') {
      return 'Navigator.$name';
    }
    // `Navigator.push(context, route)` — a static call on the class.
    if (receiver is SimpleIdentifier && receiver.name == 'Navigator') {
      return 'Navigator.$name';
    }
    return null;
  }

  void _collect(String api, MethodInvocation node) {
    // Every closure anywhere in the argument list is a candidate builder. That
    // reaches `builder:`/`pageBuilder:` directly and also the closure nested
    // inside `MaterialPageRoute(builder: …)` in a `Navigator.push`.
    final builders = <FunctionExpression>[];
    node.argumentList.accept(_ClosureCollector(builders));
    if (builders.isEmpty) return;

    final location = _locationOf(node.offset);
    for (final builder in builders) {
      final widgets = <InstanceCreationExpression>[];
      var scoped = false;
      builder.body.accept(_WidgetCollector(widgets, () => scoped = true));
      // A builder may install the scope through a named helper —
      // `wrapInActiveTabScope(context, const FooDialog())` — rather than
      // writing `UncontrolledProviderScope` inline. One hop of resolution
      // recognizes that idiom; without it every call site of such a helper
      // reads as a violation.
      if (!scoped) {
        final callees = <String>[];
        builder.body.accept(_CalleeCollector(graph, callees));
        for (final callee in callees) {
          if (graph._scopesIn(<String>{callee})) {
            scoped = true;
            break;
          }
        }
      }
      if (scoped) {
        // A scope in the builder re-binds the whole callback subtree. Record
        // the mounts anyway so a test can assert the guard saw them.
        for (final w in widgets) {
          out.add(_mountFor(api, location, w, scoped: true));
        }
        continue;
      }
      for (final w in widgets) {
        out.add(_mountFor(api, location, w, scoped: false));
      }
    }
  }

  RouteMount _mountFor(
    String api,
    String location,
    InstanceCreationExpression creation, {
    required bool scoped,
  }) {
    final type = creation.staticType;
    final name = type is InterfaceType
        ? type.element.name ?? '<widget>'
        : '<widget>';
    final classKey = type is InterfaceType ? _elementKey(type.element) : null;
    final info = classKey == null ? null : graph._classes[classKey];
    final bodies = classKey == null
        ? const <String>{}
        : graph._bodiesOfWidget(classKey);
    // A widget declared outside the source roots (a framework widget) has no
    // body here; it contributes no reads, which is correct — its own reads are
    // not the host repo's to fix.
    final reads = bodies.isEmpty
        ? const <ProviderRead>[]
        : graph.readsFrom(bodies, followCallGraph: false);
    final selfScoped = bodies.isNotEmpty && graph._scopesIn(bodies);
    return RouteMount(
      routeApi: api,
      callSite: location,
      widget: name,
      widgetPath: info?.path,
      scoped: scoped || selfScoped,
      reads: reads,
    );
  }

  String _locationOf(int offset) {
    final location = unit.lineInfo.getLocation(offset);
    return '${p.relative(unit.path)}:${location.lineNumber}';
  }
}

/// Collects the closures written in an argument list.
class _ClosureCollector extends RecursiveAstVisitor<void> {
  _ClosureCollector(this.out);

  final List<FunctionExpression> out;

  @override
  void visitFunctionExpression(FunctionExpression node) {
    out.add(node);
    // Do not descend: a closure nested inside a builder belongs to that
    // builder's body, which is scanned as a whole.
  }
}

/// Collects the declaration keys of functions/methods invoked in a builder
/// body, so the scan can look one hop into a scope-installing helper.
class _CalleeCollector extends RecursiveAstVisitor<void> {
  _CalleeCollector(this.graph, this.out);

  final ScopeGraph graph;
  final List<String> out;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final key = _declKey(node.methodName.element);
    if (key != null && graph._decls.containsKey(key)) out.add(key);
    super.visitMethodInvocation(node);
  }
}

/// Collects widget constructions in a builder body, and reports whether a
/// container-rebinding scope widget was found.
class _WidgetCollector extends RecursiveAstVisitor<void> {
  _WidgetCollector(this.out, this.onScope);

  final List<InstanceCreationExpression> out;
  final void Function() onScope;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.staticType;
    final name = type is InterfaceType ? type.element.name : null;
    if (name != null && _scopeWidgets.contains(name)) {
      onScope();
    } else if (_isWidgetType(type)) {
      out.add(node);
    }
    super.visitInstanceCreationExpression(node);
  }
}

/// Collects the providers named by `<provider>.overrideWith*(…)` calls.
class _OverrideVisitor extends RecursiveAstVisitor<void> {
  _OverrideVisitor(this.out);

  final Set<String> out;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name.startsWith('overrideWith')) {
      final target = node.realTarget;
      if (target != null) {
        target.accept(_OverrideTargetVisitor(out));
      }
    }
    super.visitMethodInvocation(node);
  }
}

class _OverrideTargetVisitor extends RecursiveAstVisitor<void> {
  _OverrideTargetVisitor(this.out);

  final Set<String> out;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final key = _providerKey(node.element);
    if (key != null) out.add(key);
    super.visitSimpleIdentifier(node);
  }
}

/// A class declaration inside the source roots.
class _ClassInfo {
  _ClassInfo(this.name, this.declKey, this.path, this.element);

  final String name;
  final String declKey;
  final String path;
  final InterfaceElement element;
}
