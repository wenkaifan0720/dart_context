import 'dart:async';

import 'package:dart_mcp/server.dart';

import '../dart_context.dart';

/// Mix this in to any MCPServer to add Dart code intelligence via dart_context.
///
/// Provides a single `dart_query` tool that accepts DSL queries like:
/// - `def AuthRepository` - Find definition
/// - `refs login` - Find references
/// - `find Auth* kind:class` - Search with filters
/// - `members MyClass` - Get class members
/// - `hierarchy MyWidget` - Get type hierarchy
///
/// Example usage:
/// ```dart
/// class MyServer extends MCPServer with DartContextSupport {
///   // ...
/// }
/// ```
base mixin DartContextSupport on ToolsSupport, RootsTrackingSupport {
  /// Cached DartContext instances per project root.
  final Map<String, DartContext> _contexts = {};

  /// Whether to use cached indexes.
  bool get useCache => true;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    final result = await super.initialize(request);

    if (!supportsRoots) {
      log(
        LoggingLevel.warning,
        'DartContextSupport requires the "roots" capability which is not '
        'supported. dart_query tool has been disabled.',
      );
      return result;
    }

    registerTool(dartQueryTool, _handleDartQuery);

    return result;
  }

  @override
  Future<void> updateRoots() async {
    await super.updateRoots();

    final currentRoots = await roots;
    final currentRootUris = currentRoots.map((r) => r.uri).toSet();

    // Remove contexts for roots that no longer exist
    final removedRoots =
        _contexts.keys.where((r) => !currentRootUris.contains(r)).toList();
    for (final root in removedRoots) {
      await _contexts[root]?.dispose();
      _contexts.remove(root);
      log(LoggingLevel.debug, 'Removed DartContext for: $root');
    }

    // Add contexts for new roots (lazily - will be created on first query)
  }

  @override
  Future<void> shutdown() async {
    for (final context in _contexts.values) {
      await context.dispose();
    }
    _contexts.clear();
    await super.shutdown();
  }

  /// Get or create a DartContext for the given project path.
  Future<DartContext?> _getContextForPath(String filePath) async {
    final currentRoots = await roots;

    // Find the root that contains this file
    for (final root in currentRoots) {
      final rootPath = Uri.parse(root.uri).toFilePath();
      if (filePath.startsWith(rootPath)) {
        // Check if we already have a context for this root
        if (_contexts.containsKey(root.uri)) {
          return _contexts[root.uri];
        }

        // Create a new context
        try {
          log(LoggingLevel.info, 'Creating DartContext for: ${root.uri}');
          final context = await DartContext.open(
            rootPath,
            watch: true,
            useCache: useCache,
          );
          _contexts[root.uri] = context;

          log(
            LoggingLevel.info,
            'Indexed ${context.stats['files']} files, '
            '${context.stats['symbols']} symbols',
          );

          return context;
        } catch (e) {
          log(LoggingLevel.error, 'Failed to create DartContext: $e');
          return null;
        }
      }
    }

    return null;
  }

  /// Get context for the first available root.
  Future<DartContext?> _getDefaultContext() async {
    final currentRoots = await roots;
    if (currentRoots.isEmpty) return null;

    final firstRoot = currentRoots.first;
    final rootPath = Uri.parse(firstRoot.uri).toFilePath();

    if (_contexts.containsKey(firstRoot.uri)) {
      return _contexts[firstRoot.uri];
    }

    try {
      log(LoggingLevel.info, 'Creating DartContext for: ${firstRoot.uri}');
      final context = await DartContext.open(
        rootPath,
        watch: true,
        useCache: useCache,
      );
      _contexts[firstRoot.uri] = context;

      log(
        LoggingLevel.info,
        'Indexed ${context.stats['files']} files, '
        '${context.stats['symbols']} symbols',
      );

      return context;
    } catch (e) {
      log(LoggingLevel.error, 'Failed to create DartContext: $e');
      return null;
    }
  }

  Future<CallToolResult> _handleDartQuery(CallToolRequest request) async {
    final query = request.arguments?['query'] as String?;
    if (query == null || query.isEmpty) {
      return CallToolResult(
        content: [TextContent(text: 'Missing required argument `query`.')],
        isError: true,
      );
    }

    // Get context - use project hint if provided, otherwise use default
    final projectHint = request.arguments?['project'] as String?;
    DartContext? context;

    if (projectHint != null) {
      context = await _getContextForPath(projectHint);
    } else {
      context = await _getDefaultContext();
    }

    if (context == null) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'No Dart project found. Make sure roots are set and contain a pubspec.yaml.',
          ),
        ],
        isError: true,
      );
    }

    try {
      final result = await context.query(query);
      return CallToolResult(
        content: [TextContent(text: result.toText())],
        isError: false,
      );
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Query error: $e')],
        isError: true,
      );
    }
  }

  /// The dart_query tool definition.
  static final dartQueryTool = Tool(
    name: 'dart_query',
    description: '''Query Dart codebase for semantic information using a simple DSL.

## Query DSL

| Query | Description | Example |
|-------|-------------|---------|
| `def <symbol>` | Find definition of a symbol | `def AuthRepository` |
| `refs <symbol>` | Find all references to a symbol | `refs login` |
| `members <symbol>` | Get members of a class/mixin | `members UserService` |
| `impls <symbol>` | Find implementations of interface | `impls Repository` |
| `hierarchy <symbol>` | Get type hierarchy (super + sub) | `hierarchy MyWidget` |
| `source <symbol>` | Get full source code | `source handleLogin` |
| `find <pattern>` | Search symbols with wildcards | `find Auth*` |
| `files` | List all indexed files | `files` |
| `stats` | Get index statistics | `stats` |

## Filters (for `find` queries)

| Filter | Description | Example |
|--------|-------------|---------|
| `kind:<type>` | Filter by symbol kind | `find * kind:class` |
| `in:<path>` | Filter by file path | `find * in:lib/auth/` |

Symbol kinds: class, method, function, field, enum, mixin, extension, getter, setter, constructor

## Examples

```
def AuthRepository          # Find where AuthRepository is defined
refs login                  # Find all usages of 'login'
find Auth* kind:class       # Find all classes starting with 'Auth'
find * kind:method in:lib/  # Find all methods in lib/
members UserService         # List all members of UserService
hierarchy StatefulWidget    # Show inheritance tree
source validateEmail        # Get full source code
```

Works like grep but for semantic code navigation - understands definitions, references, types, and relationships.''',
    annotations: ToolAnnotations(
      title: 'Dart Code Query',
      readOnlyHint: true,
    ),
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          description:
              'The query in DSL format. Examples: "def AuthRepository", "refs login", "find Auth* kind:class"',
        ),
        'project': Schema.string(
          description:
              'Optional path hint to select which project root to query (if multiple roots are configured).',
        ),
      },
      required: ['query'],
    ),
  );
}


