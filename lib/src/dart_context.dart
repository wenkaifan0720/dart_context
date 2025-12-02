import 'dart:async';

import 'index/incremental_indexer.dart';
import 'index/scip_index.dart';
import 'query/query_executor.dart';
import 'query/query_parser.dart';
import 'query/query_result.dart';

export 'index/incremental_indexer.dart'
    show
        IndexUpdate,
        InitialIndexUpdate,
        CachedIndexUpdate,
        IncrementalIndexUpdate,
        FileUpdatedUpdate,
        FileRemovedUpdate,
        IndexErrorUpdate;

/// Lightweight semantic code intelligence for Dart.
///
/// Provides incremental indexing and a query DSL for navigating
/// Dart codebases.
///
/// ```dart
/// final context = await DartContext.open('/path/to/project');
///
/// // Query with DSL
/// final result = await context.query('def AuthRepository');
/// print(result.toText());
///
/// // Watch for updates
/// context.updates.listen((update) {
///   print('Index updated: $update');
/// });
///
/// // Cleanup
/// await context.dispose();
/// ```
class DartContext {
  DartContext._({
    required IncrementalScipIndexer indexer,
    required QueryExecutor executor,
  })  : _indexer = indexer,
        _executor = executor;

  final IncrementalScipIndexer _indexer;
  final QueryExecutor _executor;

  /// Open a Dart project and create a context.
  ///
  /// This will:
  /// 1. Parse project configuration
  /// 2. Load from cache (if valid and [useCache] is true)
  /// 3. Create analyzer context
  /// 4. Perform incremental indexing of changed files
  /// 5. Start file watching (if [watch] is true)
  ///
  /// Set [useCache] to false to force a full re-index.
  ///
  /// Example:
  /// ```dart
  /// final context = await DartContext.open('/path/to/project');
  /// ```
  static Future<DartContext> open(
    String projectPath, {
    bool watch = true,
    bool useCache = true,
  }) async {
    final indexer = await IncrementalScipIndexer.open(
      projectPath,
      watch: watch,
      useCache: useCache,
    );

    final executor = QueryExecutor(
      indexer.index,
      signatureProvider: indexer.getSignature,
    );

    return DartContext._(
      indexer: indexer,
      executor: executor,
    );
  }

  /// The project root path.
  String get projectRoot => _indexer.projectRoot;

  /// The underlying index.
  ScipIndex get index => _indexer.index;

  /// Stream of index updates (file changes, errors, etc.)
  Stream<IndexUpdate> get updates => _indexer.updates;

  /// Execute a query using the DSL.
  ///
  /// Supported queries:
  /// - `def <symbol>` - Find definition
  /// - `refs <symbol>` - Find references
  /// - `members <symbol>` - Get class members
  /// - `impls <symbol>` - Find implementations
  /// - `supertypes <symbol>` - Get supertypes
  /// - `subtypes <symbol>` - Get subtypes
  /// - `hierarchy <symbol>` - Full hierarchy
  /// - `source <symbol>` - Get source code
  /// - `find <pattern> [kind:<kind>] [in:<path>]` - Search
  /// - `files` - List indexed files
  /// - `stats` - Index statistics
  ///
  /// Example:
  /// ```dart
  /// final result = await context.query('refs AuthRepository.login');
  /// print(result.toText());
  /// ```
  Future<QueryResult> query(String queryString) {
    return _executor.execute(queryString);
  }

  /// Execute a parsed query.
  Future<QueryResult> executeQuery(ScipQuery query) {
    return _executor.executeQuery(query);
  }

  /// Manually refresh a specific file.
  ///
  /// Useful when file watching is disabled.
  Future<bool> refreshFile(String filePath) {
    return _indexer.refreshFile(filePath);
  }

  /// Manually refresh all files.
  Future<void> refreshAll() {
    return _indexer.refreshAll();
  }

  /// Get index statistics.
  Map<String, int> get stats => _indexer.index.stats;

  /// Dispose of resources.
  ///
  /// Stops file watching and cleans up.
  Future<void> dispose() {
    return _indexer.dispose();
  }
}

