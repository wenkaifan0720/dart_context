import 'dart:async';

import 'package:scip_server/scip_server.dart' as scip_server;

import 'cache/cache_paths.dart';
import 'incremental_indexer.dart';
import 'package_discovery.dart';
import 'package_registry.dart';
import 'package_registry_provider.dart';

/// Dart language binding for scip_server.
///
/// Provides Dart-specific implementation of:
/// - Package discovery (pubspec.yaml detection)
/// - Incremental indexing (using Dart analyzer)
/// - Cache management
/// - Dependency loading (SDK, Flutter, pub packages)
///
/// ## Usage
///
/// ```dart
/// final binding = DartBinding();
///
/// // Create a context for a project (recommended)
/// final context = await binding.createContext('/path/to/project');
/// print('Indexed ${context.stats['symbols']} symbols');
///
/// // Load dependencies for cross-package queries
/// await context.loadDependencies();
///
/// // Query with full cross-package support
/// final executor = QueryExecutor(context.index, provider: context.provider);
/// final result = await executor.execute('hierarchy MyWidget');
///
/// await context.dispose();
/// ```
class DartBinding implements scip_server.LanguageBinding {
  @override
  String get languageId => 'dart';

  @override
  List<String> get extensions => const ['.dart'];

  @override
  String get packageFile => 'pubspec.yaml';

  @override
  bool get supportsIncremental => true;

  @override
  String get globalCachePath => CachePaths.globalCacheDir;

  @override
  bool get supportsDependencies => true;

  @override
  Future<List<scip_server.DiscoveredPackage>> discoverPackages(
    String rootPath,
  ) async {
    final discovery = PackageDiscovery();
    final result = await discovery.discoverPackages(rootPath);

    return result.packages.map((pkg) {
      return scip_server.DiscoveredPackage(
        name: pkg.name,
        path: pkg.path,
        version: '0.0.0', // Version is not available in LocalPackage
      );
    }).toList();
  }

  @override
  Future<scip_server.LanguageContext> createContext(
    String rootPath, {
    bool useCache = true,
    bool watch = true,
    void Function(String message)? onProgress,
  }) async {
    return DartLanguageContext.create(
      rootPath,
      useCache: useCache,
      watch: watch,
      onProgress: onProgress,
    );
  }

  @override
  Future<scip_server.PackageIndexer> createIndexer(
    String packagePath, {
    bool useCache = true,
  }) async {
    final indexer = await IncrementalScipIndexer.open(
      packagePath,
      useCache: useCache,
    );
    return DartPackageIndexer(indexer);
  }
}

/// Dart-specific language context using [PackageRegistry].
///
/// Provides full Dart functionality including:
/// - Multi-package support (monorepos, workspaces)
/// - Dependency loading (SDK, Flutter, pub packages)
/// - Cross-package query support via [provider]
class DartLanguageContext implements scip_server.LanguageContext {
  DartLanguageContext._({
    required this.rootPath,
    required PackageRegistry registry,
    required List<scip_server.DiscoveredPackage> packages,
    RootWatcher? watcher,
  })  : _registry = registry,
        _packages = packages,
        _watcher = watcher;

  final PackageRegistry _registry;
  final List<scip_server.DiscoveredPackage> _packages;
  final RootWatcher? _watcher;

  /// Create a Dart context for a project.
  static Future<DartLanguageContext> create(
    String rootPath, {
    bool useCache = true,
    bool watch = true,
    void Function(String message)? onProgress,
  }) async {
    // 1. Discover all packages
    onProgress?.call('Discovering packages...');
    final packageDiscovery = PackageDiscovery();
    final discovery = await packageDiscovery.discoverPackages(rootPath);

    // 2. Create registry
    final registry = PackageRegistry(rootPath: discovery.rootPath);

    // 3. Initialize local packages
    await registry.initializeLocalPackages(
      discovery.packages,
      useCache: useCache,
      onProgress: onProgress,
    );

    // 4. Start file watcher
    RootWatcher? watcher;
    if (watch) {
      watcher = RootWatcher(
        rootPath: discovery.rootPath,
        registry: registry,
      );
      await watcher.start();
    }

    // 5. Convert to DiscoveredPackage list
    final packages = discovery.packages.map((pkg) {
      return scip_server.DiscoveredPackage(
        name: pkg.name,
        path: pkg.path,
        version: '0.0.0',
      );
    }).toList();

    onProgress?.call('Ready');

    return DartLanguageContext._(
      rootPath: discovery.rootPath,
      registry: registry,
      packages: packages,
      watcher: watcher,
    );
  }

  @override
  final String rootPath;

  @override
  List<scip_server.DiscoveredPackage> get packages => _packages;

  @override
  int get packageCount => _packages.length;

  @override
  scip_server.ScipIndex get index {
    final localPackages = _registry.localPackages.values.toList();
    if (localPackages.isEmpty) {
      return scip_server.ScipIndex.empty(projectRoot: rootPath);
    }
    return localPackages.first.indexer.index;
  }

  /// Combined index across all local packages.
  scip_server.ScipIndex get projectIndex => _registry.projectIndex;

  @override
  scip_server.IndexProvider? get provider => PackageRegistryProvider(_registry);

  @override
  Stream<scip_server.IndexUpdate> get updates {
    final streams = _registry.localPackages.values
        .map((pkg) => pkg.indexer.updates.map(_mapIndexUpdate))
        .toList();
    if (streams.isEmpty) return const Stream.empty();
    if (streams.length == 1) return streams.first;
    return _mergeStreams(streams);
  }

  /// Map dart_binding IndexUpdate to scip_server IndexUpdate.
  static scip_server.IndexUpdate _mapIndexUpdate(IndexUpdate update) {
    return switch (update) {
      InitialIndexUpdate u => scip_server.InitialIndexUpdate(
          fileCount: u.stats['files'] ?? 0,
          symbolCount: u.stats['symbols'] ?? 0,
          fromCache: false,
          duration: Duration.zero,
        ),
      CachedIndexUpdate u => scip_server.InitialIndexUpdate(
          fileCount: u.stats['files'] ?? 0,
          symbolCount: u.stats['symbols'] ?? 0,
          fromCache: true,
          duration: Duration.zero,
        ),
      IncrementalIndexUpdate u => scip_server.InitialIndexUpdate(
          fileCount: u.stats['files'] ?? 0,
          symbolCount: u.stats['symbols'] ?? 0,
          fromCache: false,
          duration: Duration.zero,
        ),
      FileUpdatedUpdate u => scip_server.FileUpdatedUpdate(
          path: u.path,
          symbolCount: 0, // Not available in this update type
        ),
      FileRemovedUpdate u => scip_server.FileRemovedUpdate(path: u.path),
      IndexErrorUpdate u => scip_server.IndexErrorUpdate(
          message: u.message,
          path: u.path,
        ),
    };
  }

  @override
  Map<String, dynamic> get stats => _registry.stats;

  @override
  Future<void> loadDependencies() async {
    await _registry.loadAllDependencies();
  }

  @override
  bool get hasDependencies =>
      _registry.sdkIndex != null ||
      _registry.hostedPackages.isNotEmpty ||
      _registry.flutterPackages.isNotEmpty;

  @override
  Future<bool> refreshFile(String filePath) async {
    final pkg = _registry.findPackageForPath(filePath);
    if (pkg == null) return false;
    return pkg.indexer.refreshFile(filePath);
  }

  @override
  Future<void> refreshAll() async {
    for (final pkg in _registry.localPackages.values) {
      await pkg.indexer.refreshAll();
    }
  }

  @override
  Future<void> dispose() async {
    await _watcher?.stop();
    _registry.dispose();
  }

  /// Access to the underlying registry for Dart-specific operations.
  PackageRegistry get registry => _registry;

  /// Merge multiple streams into one.
  static Stream<T> _mergeStreams<T>(List<Stream<T>> streams) {
    final controller = StreamController<T>.broadcast();
    for (final stream in streams) {
      stream.listen(
        controller.add,
        onError: controller.addError,
      );
    }
    return controller.stream;
  }
}

/// Dart-specific package indexer wrapping [IncrementalScipIndexer].
class DartPackageIndexer implements scip_server.PackageIndexer {
  DartPackageIndexer(this._indexer);

  final IncrementalScipIndexer _indexer;
  final _updateController =
      StreamController<scip_server.IndexUpdate>.broadcast();

  @override
  scip_server.ScipIndex get index => _indexer.index;

  @override
  Stream<scip_server.IndexUpdate> get updates => _updateController.stream;

  @override
  Future<void> updateFile(String path) async {
    try {
      await _indexer.refreshFile(path);
      final symbolCount = _indexer.index.symbolsInFile(path).length;
      _updateController.add(scip_server.FileUpdatedUpdate(
        path: path,
        symbolCount: symbolCount,
      ));
    } catch (e) {
      _updateController.add(scip_server.IndexErrorUpdate(
        message: e.toString(),
        path: path,
      ));
    }
  }

  @override
  Future<void> removeFile(String path) async {
    try {
      _updateController.add(scip_server.FileRemovedUpdate(path: path));
    } catch (e) {
      _updateController.add(scip_server.IndexErrorUpdate(
        message: e.toString(),
        path: path,
      ));
    }
  }

  @override
  Future<void> dispose() async {
    await _updateController.close();
    await _indexer.dispose();
  }

  /// Access to the underlying indexer for Dart-specific operations.
  IncrementalScipIndexer get dartIndexer => _indexer;
}

/// File watcher for Dart projects.
///
/// Watches for changes across all packages in a project.
class RootWatcher {
  RootWatcher({
    required this.rootPath,
    required this.registry,
  });

  final String rootPath;
  final PackageRegistry registry;

  StreamSubscription<dynamic>? _subscription;

  /// Start watching for file changes.
  Future<void> start() async {
    // Use the registry's built-in file watching
    // The IncrementalScipIndexer already handles file watching internally
  }

  /// Stop watching.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

/// Create a DartBinding for use with scip_server.
DartBinding createDartBinding() => DartBinding();
