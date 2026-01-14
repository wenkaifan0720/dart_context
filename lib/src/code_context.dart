import 'dart:io';

import 'package:scip_server/scip_server.dart';

/// Language-agnostic semantic code intelligence.
///
/// Provides incremental indexing and a query DSL for navigating
/// codebases in any supported language.
///
/// ## Usage
///
/// ```dart
/// // Auto-detect language from project files
/// final context = await CodeContext.open('/path/to/project');
///
/// // Or specify a language binding explicitly
/// final context = await CodeContext.open(
///   '/path/to/project',
///   binding: DartBinding(),
/// );
///
/// // Query with DSL
/// final result = await context.query('def AuthRepository');
/// print(result.toText());
///
/// // Load dependencies for cross-package queries
/// await context.loadDependencies();
///
/// // Query with full dependency support
/// final hierarchy = await context.query('hierarchy MyWidget');
///
/// // Cleanup
/// await context.dispose();
/// ```
///
/// ## Supported Languages
///
/// - Dart (via `DartBinding` from `dart_binding` package)
/// - More languages coming soon...
class CodeContext {
  CodeContext._({
    required LanguageContext languageContext,
    required QueryExecutor executor,
  })  : _context = languageContext,
        _executor = executor;

  final LanguageContext _context;
  final QueryExecutor _executor;

  // Registered language bindings for auto-detection
  static final List<LanguageBinding> _registeredBindings = [];

  /// Register a language binding for auto-detection.
  ///
  /// Call this at startup to enable auto-detection of languages:
  /// ```dart
  /// CodeContext.registerBinding(DartBinding());
  /// CodeContext.registerBinding(TypeScriptBinding());
  /// ```
  static void registerBinding(LanguageBinding binding) {
    if (!_registeredBindings.any((b) => b.languageId == binding.languageId)) {
      _registeredBindings.add(binding);
    }
  }

  /// Get all registered language bindings.
  static List<LanguageBinding> get registeredBindings =>
      List.unmodifiable(_registeredBindings);

  /// Open a project with optional language binding.
  ///
  /// If no [binding] is provided, attempts to auto-detect the language
  /// by looking for package manifest files (pubspec.yaml, package.json, etc.)
  /// in registered bindings.
  ///
  /// This will:
  /// 1. Detect or use the specified language binding
  /// 2. Discover all packages in the path
  /// 3. Create indexers for each package
  /// 4. Load from cache (if valid and [useCache] is true)
  /// 5. Start file watching (if [watch] is true)
  ///
  /// Example:
  /// ```dart
  /// // Auto-detect language
  /// final context = await CodeContext.open('/path/to/project');
  ///
  /// // Explicitly specify language
  /// final context = await CodeContext.open(
  ///   '/path/to/project',
  ///   binding: DartBinding(),
  /// );
  /// ```
  static Future<CodeContext> open(
    String projectPath, {
    LanguageBinding? binding,
    bool watch = true,
    bool useCache = true,
    bool loadDependencies = false,
    void Function(String message)? onProgress,
  }) async {
    final normalizedPath = Directory(projectPath).absolute.path;

    // 1. Detect or use specified binding
    final detectedBinding = binding ?? await _detectLanguage(normalizedPath);
    if (detectedBinding == null) {
      throw StateError(
        'Could not detect project language. '
        'Register a binding with CodeContext.registerBinding() or specify one explicitly.',
      );
    }

    onProgress?.call('Using ${detectedBinding.languageId} binding...');

    // 2. Create language context
    final languageContext = await detectedBinding.createContext(
      normalizedPath,
      useCache: useCache,
      watch: watch,
      onProgress: onProgress,
    );

    // 3. Load dependencies if requested
    if (loadDependencies && detectedBinding.supportsDependencies) {
      onProgress?.call('Loading dependencies...');
      await languageContext.loadDependencies();
    }

    // 4. Create query executor with provider for cross-package queries
    final executor = QueryExecutor(
      languageContext.index,
      provider: languageContext.provider,
    );

    onProgress?.call('Ready');

    return CodeContext._(
      languageContext: languageContext,
      executor: executor,
    );
  }

  /// Auto-detect language from project files.
  static Future<LanguageBinding?> _detectLanguage(String path) async {
    for (final binding in _registeredBindings) {
      final packageFile = File('$path/${binding.packageFile}');
      if (await packageFile.exists()) {
        return binding;
      }

      // Also check subdirectories for monorepos
      final dir = Directory(path);
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith(binding.packageFile)) {
          return binding;
        }
      }
    }
    return null;
  }

  /// The language binding used for this context.
  LanguageBinding get binding {
    // Get from registered bindings based on context
    return _registeredBindings.firstWhere(
      (b) => b.languageId == languageId,
      orElse: () => throw StateError('No binding found for $languageId'),
    );
  }

  /// The language identifier (e.g., "dart", "typescript").
  String get languageId {
    // Infer from provider or default to first registered
    if (_registeredBindings.isNotEmpty) {
      return _registeredBindings.first.languageId;
    }
    return 'unknown';
  }

  /// The root path for this context.
  String get rootPath => _context.rootPath;

  /// The underlying language context.
  LanguageContext get context => _context;

  /// Primary index for direct programmatic queries.
  ScipIndex get index => _context.index;

  /// Provider for cross-package queries.
  IndexProvider? get provider => _context.provider;

  /// All discovered packages.
  List<DiscoveredPackage> get packages => _context.packages;

  /// Number of packages.
  int get packageCount => _context.packageCount;

  /// Stream of index updates from all packages.
  Stream<IndexUpdate> get updates => _context.updates;

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
  /// - `grep <pattern>` - Search source code
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
  Future<bool> refreshFile(String filePath) {
    return _context.refreshFile(filePath);
  }

  /// Manually refresh all files in all packages.
  Future<void> refreshAll() {
    return _context.refreshAll();
  }

  /// Get combined index statistics.
  Map<String, dynamic> get stats => _context.stats;

  /// Whether external dependencies are loaded.
  bool get hasDependencies => _context.hasDependencies;

  /// Load external dependencies for cross-package queries.
  ///
  /// For Dart: loads SDK, Flutter, and pub.dev package indexes.
  Future<void> loadDependencies() {
    return _context.loadDependencies();
  }

  /// Dispose of resources.
  ///
  /// Stops file watching and cleans up all indexers.
  Future<void> dispose() {
    return _context.dispose();
  }
}
