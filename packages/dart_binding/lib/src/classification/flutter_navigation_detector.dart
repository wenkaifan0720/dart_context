/// Flutter-specific navigation detection for storyboard generation.
///
/// Detects navigation patterns in Flutter code (go_router, Navigator, etc.)
/// to build screen flow diagrams.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:collection/collection.dart';
import 'package:scip_server/scip_server.dart';

import 'dart_navigation_chain.dart';

/// Detects navigation patterns in Flutter code and builds storyboard graphs.
///
/// Implements [NavigationBinding] for Flutter/Dart codebases.
class FlutterNavigationDetector implements NavigationBinding {
  FlutterNavigationDetector(this.index);

  final ScipIndex index;

  /// Chain extractor for detailed navigation context (lazy initialized).
  DartNavigationChainExtractor? _chainExtractor;

  /// Get or create the chain extractor with SCIP type info.
  DartNavigationChainExtractor get chainExtractor {
    return _chainExtractor ??= DartNavigationChainExtractor(
      widgetClasses: _buildWidgetClassSet(),
    );
  }

  /// Build set of widget class names from SCIP type hierarchy.
  Set<String> _buildWidgetClassSet() {
    final widgetClasses = <String>{};

    // Find all classes that extend StatelessWidget or StatefulWidget
    // by looking at their supertypes
    for (final symbol in index.allSymbols) {
      if (symbol.kindString != 'class') continue;

      // Check supertypes
      for (final supertype in index.supertypesOf(symbol.symbol)) {
        final supertypeName = supertype.name;
        if (supertypeName == 'StatelessWidget' ||
            supertypeName == 'StatefulWidget' ||
            supertypeName == 'State' ||
            supertypeName.endsWith('Widget') ||
            widgetClasses.contains(supertypeName)) {
          widgetClasses.add(symbol.name);
          break;
        }
      }
    }

    return widgetClasses;
  }

  /// Screen name suffixes to detect.
  static const _screenSuffixes = ['Page', 'Screen', 'View'];

  /// Navigation patterns for different routers.
  static final _navigatorPushPattern = RegExp(
    r'Navigator\s*\.\s*(?:push|pushReplacement|pushAndRemoveUntil)'
    r'.*?(?:MaterialPageRoute|CupertinoPageRoute|PageRouteBuilder)'
    r'.*?=>\s*(\w+)\s*\(',
    dotAll: true,
  );

  static final _navigatorPushNamedPattern = RegExp(
    r'''Navigator\s*\.\s*(?:pushNamed|pushReplacementNamed|pushNamedAndRemoveUntil)\s*\([^,]*,\s*['"]([^'"]+)['"]''',
  );

  static final _goRouterPattern = RegExp(
    r'''context\s*\.\s*(go|push|pushReplacement)\s*\(\s*['"]([^'"]+)['"]''',
  );

  // go_router with route constant: context.push(Routes.newProject)
  static final _goRouterConstantPattern = RegExp(
    r'''context\s*\.\s*(go|push|pushReplacement)\s*\(\s*Routes\.(\w+)''',
  );

  // Named navigation: context.goNamed('account'), context.pushNamed('login')
  static final _goRouterNamedPattern = RegExp(
    r'''context\s*\.\s*(goNamed|pushNamed|pushReplacementNamed|replaceNamed)\s*\(\s*['"](\w+)['"]''',
  );

  static final _autoRoutePattern = RegExp(
    r'(?:context\.router|AutoRouter\.of\(context\))\s*\.\s*push\s*\(\s*(\w+)Route',
  );

  static final _getXPattern = RegExp(
    r'Get\s*\.\s*(?:to|off|offAll)\s*\(\s*\(\s*\)\s*=>\s*(\w+)\s*\(',
  );

  /// Build navigation graph for the codebase.
  @override
  Future<NavigationGraph> buildNavigationGraph({String? entryPoint}) async {
    // Use page detection (Scaffold + naming) instead of just naming
    final pages = await findPages();
    final edgeSet = <NavigationEdge>{}; // Use Set to auto-deduplicate
    var routerType = RouterType.unknown;

    // Build a map of page names for quick lookup
    final pageNames = pages.map((s) => s.name).toSet();

    // Parse route definitions first to build route→page mapping
    await _buildRouteToScreenMap();

    // Build map of file -> containing page for quick lookup
    final fileToContainingPage = <String, String>{};
    for (final page in pages) {
      if (page.file != null) {
        fileToContainingPage[page.file!] = page.name;
      }
    }

    // Scan each page's source for navigation calls
    for (final page in pages) {
      final source = await _getSource(page);
      if (source == null) continue;

      // Detect router type from imports
      if (routerType == RouterType.unknown) {
        routerType = _detectRouterType(source);
      }

      // Find navigation patterns
      final filePath =
          page.file != null ? '${index.projectRoot}/${page.file}' : null;

      final pageEdges = await _findNavigationCalls(
        page.name,
        source,
        pageNames,
        filePath: filePath,
      );
      edgeSet.addAll(pageEdges);
    }

    // Also scan non-page files for navigation calls (widgets, components, etc.)
    for (final file in index.files) {
      // Skip already-scanned page files
      if (fileToContainingPage.containsKey(file)) continue;

      // Only scan Dart files in lib/
      if (!file.endsWith('.dart') || !file.startsWith('lib/')) continue;

      try {
        final filePath = '${index.projectRoot}/$file';
        final content = await File(filePath).readAsString();

        // Detect router type if not yet known
        if (routerType == RouterType.unknown) {
          routerType = _detectRouterType(content);
        }

        // Try to find the main widget class in this file
        final widgetName = _findWidgetClassInFile(content, file);
        if (widgetName == null) continue;

        // Find navigation patterns - only from pages (not arbitrary widgets)
        // Check if this widget is a page
        if (!pageNames.contains(widgetName)) continue;

        final widgetEdges = await _findNavigationCalls(
          widgetName,
          content,
          pageNames,
          filePath: filePath,
        );
        edgeSet.addAll(widgetEdges);
      } catch (_) {
        // Ignore file read errors
      }
    }

    // Also try to parse route definitions
    final routeEdges = await _parseRouteDefinitions(pageNames);
    edgeSet.addAll(routeEdges);

    // Filter edges to only include pages as targets
    final filteredEdges = edgeSet.where((edge) {
      // fromScreen must be a page
      if (!pageNames.contains(edge.fromScreen)) return false;
      // toScreen must be a page (or a known route target)
      if (!pageNames.contains(edge.toScreen) &&
          !(_routeToScreenMap?.values.contains(edge.toScreen) ?? false)) {
        return false;
      }
      return true;
    }).toList();

    // Determine entry page
    String? entry = entryPoint;
    if (entry == null) {
      // Try to find splash or home page
      entry = pages
          .map((s) => s.name)
          .where((n) =>
              n.contains('Splash') ||
              n.contains('Home') ||
              n.contains('Main') ||
              n.contains('Root'))
          .firstOrNull;
    }

    return NavigationGraph(
      screens:
          pages, // Still called 'screens' in the return type for compatibility
      edges: filteredEdges,
      routerType: routerType,
      entryScreen: entry,
    );
  }

  /// Cache of page names for filtering navigation targets.
  Set<String>? _pageNamesCache;

  /// Find all page widgets in the index (widgets with Scaffold or page naming).
  ///
  /// A widget is considered a page if:
  /// 1. Its build method contains a Scaffold widget (strongest indicator)
  /// 2. Its name ends with 'Page', 'Screen', or 'View' (fallback)
  @override
  Future<List<SymbolInfo>> findPages() async {
    final pages = <SymbolInfo>[];
    final pageNames = <String>{};

    // First pass: collect candidates based on naming
    final candidates = <SymbolInfo>[];
    for (final symbol in index.allSymbols) {
      if (_isScreenByNaming(symbol)) {
        candidates.add(symbol);
        pageNames.add(symbol.name);
      }
    }

    // Second pass: check for Scaffold in other widget classes
    for (final symbol in index.allSymbols) {
      if (pageNames.contains(symbol.name)) continue; // Already a candidate
      if (symbol.kindString.toLowerCase() != 'class') continue;

      // Check if this is a widget class
      if (!_widgetClassNames.contains(symbol.name)) continue;

      // Check if it contains Scaffold
      if (await _containsScaffold(symbol)) {
        candidates.add(symbol);
        pageNames.add(symbol.name);
      }
    }

    pages.addAll(candidates);
    _pageNamesCache = pageNames;
    return pages;
  }

  /// Get cached page names (must call findPages first).
  Set<String> get pageNames => _pageNamesCache ?? {};

  /// Cached set of widget class names from SCIP.
  late final Set<String> _widgetClassNames = _buildWidgetClassSet();

  /// Check if a symbol is a screen widget by naming convention only.
  bool _isScreenByNaming(SymbolInfo symbol) {
    // Must be a class
    if (symbol.kindString.toLowerCase() != 'class') return false;

    // Check naming convention
    for (final suffix in _screenSuffixes) {
      if (symbol.name.endsWith(suffix)) {
        return true;
      }
    }

    return false;
  }

  /// Check if a widget symbol's build method contains a Scaffold.
  Future<bool> _containsScaffold(SymbolInfo symbol) async {
    if (symbol.file == null) return false;

    try {
      final filePath = '${index.projectRoot}/${symbol.file}';
      final file = File(filePath);
      if (!await file.exists()) return false;

      final source = await file.readAsString();

      // Parse the file without resolution (faster)
      final result = parseString(content: source);
      final unit = result.unit;

      // Check for Scaffold in the build method
      final checker = _BuildMethodScaffoldChecker(symbol.name);
      unit.accept(checker);

      return checker.containsScaffold;
    } catch (_) {
      return false;
    }
  }

  /// Get source code for a symbol.
  Future<String?> _getSource(SymbolInfo symbol) async {
    if (symbol.file == null) return null;

    try {
      final filePath = '${index.projectRoot}/${symbol.file}';
      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (_) {
      // Ignore errors
    }
    return null;
  }

  /// Detect router type from source imports.
  RouterType _detectRouterType(String source) {
    if (source.contains("import 'package:go_router/") ||
        source.contains('import "package:go_router/')) {
      return RouterType.goRouter;
    }
    if (source.contains("import 'package:auto_route/") ||
        source.contains('import "package:auto_route/')) {
      return RouterType.autoRoute;
    }
    if (source.contains("import 'package:get/") ||
        source.contains('import "package:get/')) {
      return RouterType.getX;
    }
    if (source.contains('Navigator.')) {
      return RouterType.navigator;
    }
    return RouterType.unknown;
  }

  /// Find the primary widget class name in a file.
  String? _findWidgetClassInFile(String source, String filePath) {
    // Extract class names that extend StatelessWidget or StatefulWidget
    final classPattern = RegExp(
      r'class\s+(\w+)\s+extends\s+(?:Stateless|Stateful)Widget',
    );

    final matches = classPattern.allMatches(source).toList();
    if (matches.isEmpty) return null;

    // If there's only one widget, use it
    if (matches.length == 1) {
      return matches.first.group(1);
    }

    // If multiple widgets, prefer one that matches the file name
    final fileName = filePath.split('/').last.replaceAll('.dart', '');
    // Convert snake_case to PascalCase for matching
    final expectedName = fileName.split('_').map((part) {
      if (part.isEmpty) return '';
      return part[0].toUpperCase() + part.substring(1);
    }).join('');

    for (final match in matches) {
      final className = match.group(1);
      if (className == expectedName) {
        return className;
      }
    }

    // Fall back to first widget class
    return matches.first.group(1);
  }

  /// Find navigation calls in source code with trigger context using AST analysis.
  Future<List<NavigationEdge>> _findNavigationCalls(
    String fromScreen,
    String source,
    Set<String> validScreens, {
    String? filePath,
  }) async {
    final edges = <NavigationEdge>[];

    // Collect all navigation matches with their positions
    final matches =
        <({String toScreen, String? routePath, int line, int column})>[];

    // Navigator.push with PageRoute
    for (final match in _navigatorPushPattern.allMatches(source)) {
      final target = match.group(1);
      if (target != null && validScreens.contains(target)) {
        final line = _offsetToLine(source, match.start);
        final column = _offsetToColumn(source, match.start);
        matches.add(
            (toScreen: target, routePath: null, line: line, column: column));
      }
    }

    // Navigator.pushNamed
    for (final match in _navigatorPushNamedPattern.allMatches(source)) {
      final route = match.group(1);
      if (route != null) {
        final line = _offsetToLine(source, match.start);
        final column = _offsetToColumn(source, match.start);
        // First try exact lookup from router definitions
        var screenName = _lookupScreenFromRoute(route);
        if (screenName == null) {
          // Fall back to heuristic matching
          final baseName = _routeToScreenName(route);
          screenName = _findMatchingScreen(baseName, validScreens) ?? baseName;
        }
        matches.add((
          toScreen: screenName,
          routePath: route,
          line: line,
          column: column,
        ));
      }
    }

    // go_router: context.go/push with path string literal
    for (final match in _goRouterPattern.allMatches(source)) {
      final route = match.group(2);
      if (route != null) {
        final line = _offsetToLine(source, match.start);
        final column = _offsetToColumn(source, match.start);
        // First try exact lookup from router definitions
        var screenName = _lookupScreenFromRoute(route);
        if (screenName == null) {
          // Fall back to heuristic matching
          final baseName = _routeToScreenName(route);
          screenName = _findMatchingScreen(baseName, validScreens) ?? baseName;
        }
        matches.add((
          toScreen: screenName,
          routePath: route,
          line: line,
          column: column,
        ));
      }
    }

    // go_router: context.go/push with Routes.constant
    for (final match in _goRouterConstantPattern.allMatches(source)) {
      final constantName = match.group(2);
      if (constantName != null) {
        final line = _offsetToLine(source, match.start);
        final column = _offsetToColumn(source, match.start);

        // Look up the route path from Routes constants
        final routePath = _routeConstants[constantName];
        String screenName;

        if (routePath != null) {
          // Found the route path, look up the screen
          screenName = _lookupScreenFromRoute(routePath) ??
              _findMatchingScreen(
                  _routeToScreenName(routePath), validScreens) ??
              _routeToScreenName(routePath);
        } else {
          // Fall back to heuristic: convert camelCase constant to screen name
          // newProject -> NewProject -> NewProjectPage
          final baseName =
              constantName[0].toUpperCase() + constantName.substring(1);
          screenName = _findMatchingScreen(baseName, validScreens) ??
              _findMatchingScreen('${baseName}Page', validScreens) ??
              _findMatchingScreen('${baseName}Screen', validScreens) ??
              baseName;
        }

        matches.add((
          toScreen: screenName,
          routePath: routePath ?? 'Routes.$constantName',
          line: line,
          column: column,
        ));
      }
    }

    // go_router: context.goNamed/pushNamed with name
    for (final match in _goRouterNamedPattern.allMatches(source)) {
      final routeName = match.group(2);
      if (routeName != null) {
        final line = _offsetToLine(source, match.start);
        final column = _offsetToColumn(source, match.start);
        // Look up screen from route name
        var screenName = _lookupScreenFromRouteName(routeName);
        if (screenName == null) {
          // Fall back to heuristic: capitalize route name and add Page/Screen suffix
          final baseName = routeName[0].toUpperCase() + routeName.substring(1);
          screenName = _findMatchingScreen(baseName, validScreens) ??
              _findMatchingScreen('${baseName}Page', validScreens) ??
              _findMatchingScreen('${baseName}Screen', validScreens) ??
              baseName;
        }
        matches.add((
          toScreen: screenName,
          routePath: routeName, // Use route name as path for display
          line: line,
          column: column,
        ));
      }
    }

    // auto_route
    for (final match in _autoRoutePattern.allMatches(source)) {
      final target = match.group(1);
      if (target != null) {
        final screenName = target.endsWith('Route')
            ? target.substring(0, target.length - 5)
            : target;
        if (validScreens.contains(screenName) ||
            validScreens.contains('${screenName}Page') ||
            validScreens.contains('${screenName}Screen')) {
          final line = _offsetToLine(source, match.start);
          final column = _offsetToColumn(source, match.start);
          matches.add((
            toScreen:
                _findMatchingScreen(screenName, validScreens) ?? screenName,
            routePath: null,
            line: line,
            column: column,
          ));
        }
      }
    }

    // GetX: Get.to
    for (final match in _getXPattern.allMatches(source)) {
      final target = match.group(1);
      if (target != null && validScreens.contains(target)) {
        final line = _offsetToLine(source, match.start);
        final column = _offsetToColumn(source, match.start);
        matches.add(
            (toScreen: target, routePath: null, line: line, column: column));
      }
    }

    // Extract detailed chains for each match using the AST analyzer
    for (final match in matches) {
      String trigger;

      if (filePath != null) {
        // Use AST-based chain extraction
        final chain = await chainExtractor.extractChain(
          filePath: filePath,
          line: match.line,
          column: match.column,
        );
        trigger = formatChain(chain);
      } else {
        trigger = 'navigate';
      }

      edges.add(NavigationEdge(
        fromScreen: fromScreen,
        toScreen: match.toScreen,
        routePath: match.routePath,
        trigger: trigger,
      ));
    }

    return edges;
  }

  /// Convert byte offset to line number.
  int _offsetToLine(String source, int offset) {
    var line = 0;
    for (var i = 0; i < offset && i < source.length; i++) {
      if (source[i] == '\n') line++;
    }
    return line;
  }

  /// Convert byte offset to column number.
  int _offsetToColumn(String source, int offset) {
    var lastNewline = -1;
    for (var i = 0; i < offset && i < source.length; i++) {
      if (source[i] == '\n') lastNewline = i;
    }
    return offset - lastNewline - 1;
  }

  /// Convert a route path to a likely screen name.
  String _routeToScreenName(String route) {
    // "/home" -> "Home"
    // "/products/:id" -> "ProductDetail" or "Products"
    // "/auth/login" -> "Login"
    // Dynamic routes like "/${projectId}" -> return raw path

    // Check for dynamic routes (containing $ or interpolation)
    if (route.contains(r'$') || route.contains('{')) {
      // Return the raw route path for dynamic routes
      return route;
    }

    final segments = route
        .split('/')
        .where((s) => s.isNotEmpty && !s.startsWith(':'))
        .toList();
    if (segments.isEmpty) return 'Home';

    final lastSegment = segments.last;
    // Convert to PascalCase
    final words = lastSegment.split(RegExp(r'[_-]'));
    return words
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join();
  }

  /// Find matching screen name with common suffixes.
  String? _findMatchingScreen(String baseName, Set<String> validScreens) {
    if (validScreens.contains(baseName)) return baseName;
    if (validScreens.contains('${baseName}Page')) return '${baseName}Page';
    if (validScreens.contains('${baseName}Screen')) return '${baseName}Screen';
    if (validScreens.contains('${baseName}View')) return '${baseName}View';
    return null;
  }

  /// Parse route definitions to extract navigation structure.
  /// Route path to screen mapping parsed from router files.
  Map<String, String>? _routeToScreenMap;

  /// Route name to screen mapping parsed from router files.
  Map<String, String>? _routeNameToScreenMap;

  /// Route constant names to paths (e.g., 'newProject' -> '/projects/new').
  Map<String, String> _routeConstants = {};

  /// Build maps of route paths and names to screen names by parsing router files.
  Future<Map<String, String>> _buildRouteToScreenMap() async {
    if (_routeToScreenMap != null) return _routeToScreenMap!;

    final pathMapping = <String, String>{};
    final nameMapping = <String, String>{};
    final allConstants = <String, String>{};

    // Search for route definition files
    for (final file in index.files) {
      if (file.toLowerCase().contains('route') ||
          file.toLowerCase().contains('router')) {
        try {
          final filePath = '${index.projectRoot}/$file';
          final content = await File(filePath).readAsString();

          // First, parse Routes class constants
          final routeConstants = _parseRouteConstants(content);
          allConstants.addAll(routeConstants);

          // Use AST parsing for accurate GoRoute extraction
          final (paths, names) =
              await _parseGoRoutesWithAnalyzer(filePath, routeConstants);
          pathMapping.addAll(paths);
          nameMapping.addAll(names);
        } catch (_) {
          // Ignore errors
        }
      }
    }

    _routeToScreenMap = pathMapping;
    _routeNameToScreenMap = nameMapping;
    _routeConstants = allConstants;
    return pathMapping;
  }

  /// Parse GoRoute definitions using the Dart analyzer.
  /// Returns a tuple of (path→screen, name→screen) mappings.
  Future<(Map<String, String>, Map<String, String>)> _parseGoRoutesWithAnalyzer(
    String filePath,
    Map<String, String> routeConstants,
  ) async {
    final pathMapping = <String, String>{};
    final nameMapping = <String, String>{};

    try {
      final content = await File(filePath).readAsString();
      final result = parseString(content: content, path: filePath);
      final unit = result.unit;

      // Find all GoRoute instantiations
      final visitor = _GoRouteVisitor(routeConstants);
      unit.accept(visitor);

      for (final route in visitor.routes) {
        if (route.screenName != null) {
          // Add path mapping
          if (route.path != null) {
            final normalizedPath = _normalizePath(route.path!);
            pathMapping[normalizedPath] = route.screenName!;
          }
          // Add name mapping
          if (route.name != null) {
            nameMapping[route.name!] = route.screenName!;
          }
        }
      }
    } catch (_) {
      // Ignore parsing errors
    }

    return (pathMapping, nameMapping);
  }

  /// Parse Routes class to extract constant definitions.
  Map<String, String> _parseRouteConstants(String content) {
    final constants = <String, String>{};

    // Match: static const login = '/login';
    final pattern = RegExp(
      r'''static\s+const\s+(\w+)\s*=\s*['"]([^'"]+)['"]''',
    );

    for (final match in pattern.allMatches(content)) {
      final name = match.group(1);
      final value = match.group(2);
      if (name != null && value != null) {
        constants[name] = value;
      }
    }

    return constants;
  }

  /// Normalize a route path for matching (remove dynamic segments).
  String _normalizePath(String path) {
    var normalized = path;

    // Handle route params: /project/:projectId -> /project/:
    normalized = normalized.replaceAll(RegExp(r':\w+'), ':');

    // Handle Dart interpolation: /project/$projectId -> /project/:
    normalized = normalized.replaceAll(RegExp(r'\$\w+'), ':');

    // Handle Dart interpolation with braces: /project/${...} -> /project/:
    normalized = normalized.replaceAll(RegExp(r'\$\{[^}]+\}'), ':');

    // Remove query params: /path?query=... -> /path
    final queryIdx = normalized.indexOf('?');
    if (queryIdx >= 0) {
      normalized = normalized.substring(0, queryIdx);
    }

    return normalized;
  }

  /// Look up screen name from route path using parsed router definitions.
  String? _lookupScreenFromRoute(String routePath) {
    if (_routeToScreenMap == null) return null;

    final normalized = _normalizePath(routePath);
    return _routeToScreenMap![normalized];
  }

  /// Look up screen name from route name using parsed router definitions.
  String? _lookupScreenFromRouteName(String routeName) {
    if (_routeNameToScreenMap == null) return null;
    return _routeNameToScreenMap![routeName];
  }

  Future<List<NavigationEdge>> _parseRouteDefinitions(
    Set<String> validScreens,
  ) async {
    // Build the route map (side effect: populates _routeToScreenMap)
    await _buildRouteToScreenMap();
    return <NavigationEdge>[];
  }
}

/// Holds parsed GoRoute information.
class _ParsedGoRoute {
  final String? path;
  final String? name;
  final String? screenName;

  _ParsedGoRoute({this.path, this.name, this.screenName});
}

/// AST visitor that extracts GoRoute definitions.
class _GoRouteVisitor extends RecursiveAstVisitor<void> {
  _GoRouteVisitor(this.routeConstants);

  final Map<String, String> routeConstants;
  final List<_ParsedGoRoute> routes = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;

    // Treat GoRoute(...) and ShellRoute(...) method invocations as constructor calls
    if (methodName == 'GoRoute' ||
        methodName == 'ShellRoute' ||
        methodName == 'StatefulShellRoute') {
      String? path;
      String? routeName;
      String? screenName;

      for (final arg in node.argumentList.arguments) {
        if (arg is NamedExpression) {
          final argName = arg.name.label.name;
          final expr = arg.expression;

          if (argName == 'path') {
            path = _extractPath(expr);
          } else if (argName == 'name') {
            routeName = _extractStringLiteral(expr);
          } else if (argName == 'child' ||
              argName == 'pageBuilder' ||
              argName == 'builder') {
            screenName = _extractScreenName(expr);
          }
        }
      }

      if (path != null || routeName != null || screenName != null) {
        routes.add(_ParsedGoRoute(
            path: path, name: routeName, screenName: screenName));
      }
    }

    super.visitMethodInvocation(node);
  }

  /// Extract a simple string literal value.
  String? _extractStringLiteral(Expression expr) {
    if (expr is SimpleStringLiteral) {
      return expr.value;
    }
    return null;
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // ignore: deprecated_member_use
    final typeName = node.constructorName.type.name2.lexeme;

    if (typeName == 'GoRoute' ||
        typeName == 'ShellRoute' ||
        typeName == 'StatefulShellRoute') {
      String? path;
      String? routeName;
      String? screenName;

      // Find named arguments
      for (final arg in node.argumentList.arguments) {
        if (arg is NamedExpression) {
          final argName = arg.name.label.name;
          final expr = arg.expression;

          if (argName == 'path') {
            path = _extractPath(expr);
          } else if (argName == 'name') {
            routeName = _extractStringLiteral(expr);
          } else if (argName == 'child' ||
              argName == 'pageBuilder' ||
              argName == 'builder') {
            screenName = _extractScreenName(expr);
          }
        }
      }

      if (path != null || routeName != null || screenName != null) {
        routes.add(_ParsedGoRoute(
          path: path,
          name: routeName,
          screenName: screenName,
        ));
      }
    }

    super.visitInstanceCreationExpression(node);
  }

  /// Extract path value from expression.
  String? _extractPath(Expression expr) {
    if (expr is SimpleStringLiteral) {
      return expr.value;
    } else if (expr is PrefixedIdentifier) {
      // Routes.dashboard
      final prefix = expr.prefix.name;
      final name = expr.identifier.name;
      if (prefix == 'Routes') {
        return routeConstants[name];
      }
    } else if (expr is Identifier) {
      // Just a constant name
      return routeConstants[expr.name];
    }
    return null;
  }

  /// Extract screen name from child/pageBuilder expression.
  String? _extractScreenName(Expression expr) {
    // Direct: child: const DashboardPage()
    if (expr is InstanceCreationExpression) {
      // ignore: deprecated_member_use
      return expr.constructorName.type.name2.lexeme;
    }

    // pageBuilder: (context, state) { ... child: const DashboardPage() ... }
    if (expr is FunctionExpression) {
      final body = expr.body;
      if (body is BlockFunctionBody) {
        // Search for child: in the function body
        final visitor = _ChildExtractorVisitor();
        body.accept(visitor);
        return visitor.screenName;
      }
    }

    return null;
  }
}

/// Visitor to find child: ScreenName() inside a function body.
class _ChildExtractorVisitor extends RecursiveAstVisitor<void> {
  String? screenName;

  @override
  void visitNamedExpression(NamedExpression node) {
    if (node.name.label.name == 'child') {
      screenName ??= _extractFromExpression(node.expression);
    }
    super.visitNamedExpression(node);
  }

  /// Extract screen name from various expression types.
  String? _extractFromExpression(Expression expr) {
    // Handle both InstanceCreationExpression and MethodInvocation
    // (MethodInvocation is used when type info isn't available)
    if (expr is InstanceCreationExpression) {
      // ignore: deprecated_member_use
      return expr.constructorName.type.name2.lexeme;
    } else if (expr is MethodInvocation) {
      // Screen() looks like a method call without type info
      final name = expr.methodName.name;
      // Only take it if it looks like a screen/page name
      if (name.endsWith('Screen') ||
          name.endsWith('Page') ||
          name.endsWith('View') ||
          name.endsWith('Widget')) {
        return name;
      }
    } else if (expr is ConditionalExpression) {
      // child: condition ? ScreenA() : ScreenB()
      // Take the first option as the primary screen
      return _extractFromExpression(expr.thenExpression);
    }
    return null;
  }
}

/// AST visitor to detect Scaffold widgets in widget build methods.
class _ScaffoldChecker extends RecursiveAstVisitor<void> {
  bool containsScaffold = false;
  int _depth = 0;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Limit depth to 5 to avoid deep recursion
    if (_depth > 5 || containsScaffold) return;

    // Check if this is creating a Scaffold widget
    // ignore: deprecated_member_use
    final typeName = node.constructorName.type.name2.lexeme;
    if (typeName == 'Scaffold') {
      containsScaffold = true;
      return;
    }

    _depth++;
    super.visitInstanceCreationExpression(node);
    _depth--;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Limit depth to 5
    if (_depth > 5 || containsScaffold) return;

    _depth++;
    super.visitMethodInvocation(node);
    _depth--;
  }
}

/// AST visitor to find build method in a class and check for Scaffold.
class _BuildMethodScaffoldChecker extends RecursiveAstVisitor<void> {
  bool containsScaffold = false;
  String? _targetClassName;
  bool _foundTargetClass = false;

  _BuildMethodScaffoldChecker(this._targetClassName);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    // Check if this is our target class or a State class for it
    final className = node.name.lexeme;
    if (className == _targetClassName ||
        className == '_${_targetClassName}State' ||
        className == '${_targetClassName}State') {
      _foundTargetClass = true;
      super.visitClassDeclaration(node);
      _foundTargetClass = false;
    }
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (!_foundTargetClass || containsScaffold) return;

    // Look for build method
    if (node.name.lexeme == 'build') {
      final scaffoldChecker = _ScaffoldChecker();
      node.body.accept(scaffoldChecker);
      if (scaffoldChecker.containsScaffold) {
        containsScaffold = true;
      }
    }
  }
}
