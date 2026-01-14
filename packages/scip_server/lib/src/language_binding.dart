import 'dart:async';

import 'index/index_provider.dart';
import 'index/scip_index.dart';

/// Interface for language-specific SCIP implementations.
///
/// Each supported language (Dart, TypeScript, Python, etc.) implements this
/// interface to provide:
/// - Package discovery (finding projects in a directory)
/// - Context creation (building indexes for projects)
/// - Dependency loading (optional)
///
/// ## Basic Usage
///
/// ```dart
/// final binding = DartBinding();
///
/// // Create a context for a project
/// final context = await binding.createContext('/path/to/project');
///
/// // Query the index
/// final executor = QueryExecutor(context.index, provider: context.provider);
/// final result = await executor.execute('def MyClass');
///
/// // Cleanup
/// await context.dispose();
/// ```
abstract class LanguageBinding {
  /// Language identifier (e.g., "dart", "typescript", "python").
  String get languageId;

  /// File extensions for this language (e.g., [".dart"], [".ts", ".tsx"]).
  List<String> get extensions;

  /// Package manifest filename (e.g., "pubspec.yaml", "package.json").
  String get packageFile;

  /// Whether this binding supports true incremental indexing.
  ///
  /// If true, the indexer can update individual files without re-indexing
  /// the entire package. If false, any file change triggers a full re-index.
  bool get supportsIncremental;

  /// Global cache directory for external package indexes.
  ///
  /// For Dart: ~/.dart_context/
  /// For TypeScript: ~/.ts_context/ (or similar)
  String get globalCachePath;

  /// Whether this binding supports external dependencies.
  ///
  /// If true, [LanguageContext.loadDependencies] can be called.
  bool get supportsDependencies => false;

  /// Discover packages in a directory.
  ///
  /// Recursively searches [rootPath] for packages (identified by [packageFile]).
  /// Returns a list of discovered packages with their metadata.
  Future<List<DiscoveredPackage>> discoverPackages(String rootPath);

  /// Create a context for a project.
  ///
  /// This is the preferred way to work with a project. The context:
  /// - Discovers and indexes all packages in [rootPath]
  /// - Provides a combined index for queries
  /// - Supports file watching (if [watch] is true)
  /// - Supports dependency loading (if [supportsDependencies] is true)
  Future<LanguageContext> createContext(
    String rootPath, {
    bool useCache = true,
    bool watch = true,
    void Function(String message)? onProgress,
  });

  /// Create an indexer for a single package.
  ///
  /// For simple use cases. For multi-package projects, use [createContext].
  Future<PackageIndexer> createIndexer(
    String packagePath, {
    bool useCache = true,
  });
}

/// Context for a language-specific project.
///
/// Created by [LanguageBinding.createContext], this provides:
/// - Combined index for all packages
/// - Cross-package query support via [provider]
/// - Optional dependency loading
abstract class LanguageContext {
  /// Root path of the project.
  String get rootPath;

  /// All packages in this context.
  List<DiscoveredPackage> get packages;

  /// Number of packages.
  int get packageCount => packages.length;

  /// Combined index for all local packages.
  ScipIndex get index;

  /// Provider for cross-package queries (includes dependencies if loaded).
  ///
  /// Pass this to [QueryExecutor] for full cross-package support.
  IndexProvider? get provider;

  /// Stream of index updates from all packages.
  Stream<IndexUpdate> get updates;

  /// Statistics for all packages.
  Map<String, dynamic> get stats;

  /// Load external dependencies (SDK, libraries, frameworks).
  ///
  /// Only available if [LanguageBinding.supportsDependencies] is true.
  /// For Dart: loads SDK, Flutter, and pub.dev package indexes.
  Future<void> loadDependencies();

  /// Whether external dependencies are loaded.
  bool get hasDependencies;

  /// Refresh a specific file in the index.
  Future<bool> refreshFile(String filePath);

  /// Refresh all files in all packages.
  Future<void> refreshAll();

  /// Dispose of resources (file watchers, analyzer contexts, etc.).
  Future<void> dispose();
}

/// A discovered package.
class DiscoveredPackage {
  const DiscoveredPackage({
    required this.name,
    required this.path,
    required this.version,
  });

  /// Package name (e.g., "my_app").
  final String name;

  /// Absolute path to the package root.
  final String path;

  /// Package version (e.g., "1.0.0").
  final String version;

  @override
  String toString() => 'DiscoveredPackage($name@$version at $path)';
}

/// Interface for package indexers.
///
/// Each language binding creates indexers that implement this interface.
/// The indexer manages the SCIP index for a single package.
abstract class PackageIndexer {
  /// The current SCIP index for this package.
  ScipIndex get index;

  /// Stream of index updates.
  ///
  /// Emits events when the index changes (file added, modified, removed).
  Stream<IndexUpdate> get updates;

  /// Update the index for a specific file.
  ///
  /// Called when a file changes. If the binding doesn't support incremental
  /// indexing, this may trigger a full re-index.
  Future<void> updateFile(String path);

  /// Remove a file from the index.
  Future<void> removeFile(String path);

  /// Dispose of resources (file watchers, analyzer contexts, etc.).
  Future<void> dispose();
}

/// Base class for index update events.
sealed class IndexUpdate {
  const IndexUpdate();
}

/// Initial index was built (fresh or from cache).
class InitialIndexUpdate extends IndexUpdate {
  const InitialIndexUpdate({
    required this.fileCount,
    required this.symbolCount,
    required this.fromCache,
    required this.duration,
  });

  final int fileCount;
  final int symbolCount;
  final bool fromCache;
  final Duration duration;
}

/// A file was updated in the index.
class FileUpdatedUpdate extends IndexUpdate {
  const FileUpdatedUpdate({
    required this.path,
    required this.symbolCount,
  });

  final String path;
  final int symbolCount;
}

/// A file was removed from the index.
class FileRemovedUpdate extends IndexUpdate {
  const FileRemovedUpdate({required this.path});

  final String path;
}

/// An error occurred during indexing.
class IndexErrorUpdate extends IndexUpdate {
  const IndexErrorUpdate({
    required this.message,
    this.path,
  });

  final String message;
  final String? path;
}
