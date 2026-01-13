import 'package:path/path.dart' as p;

import '../index/scip_index.dart';

/// A folder-level dependency graph built from SCIP index.
///
/// Aggregates file-level imports to folder level, providing:
/// - Internal dependencies (folders this folder imports from)
/// - External dependencies (packages this folder imports)
/// - Dependents (folders that import from this folder)
///
/// This is used to determine the order of documentation generation
/// and to track which folders need regeneration when dependencies change.
class FolderDependencyGraph {
  FolderDependencyGraph._({
    required this.folders,
    required Map<String, Set<String>> internalDeps,
    required Map<String, Set<String>> externalDeps,
    required Map<String, Set<String>> dependents,
  })  : _internalDeps = internalDeps,
        _externalDeps = externalDeps,
        _dependents = dependents;

  /// All folders in the graph.
  final Set<String> folders;

  /// folder -> folders it imports from (internal project folders)
  final Map<String, Set<String>> _internalDeps;

  /// folder -> packages it imports (external dependencies)
  final Map<String, Set<String>> _externalDeps;

  /// folder -> folders that import from it
  final Map<String, Set<String>> _dependents;

  /// Build a folder dependency graph from a SCIP index.
  ///
  /// Analyzes all files in the index, extracts their imports,
  /// and aggregates to folder level.
  static FolderDependencyGraph build(ScipIndex index) {
    final folders = <String>{};
    final internalDeps = <String, Set<String>>{};
    final externalDeps = <String, Set<String>>{};
    final dependents = <String, Set<String>>{};

    // First pass: collect all folders
    for (final file in index.files) {
      final folder = p.dirname(file);
      folders.add(folder);
      internalDeps.putIfAbsent(folder, () => {});
      externalDeps.putIfAbsent(folder, () => {});
      dependents.putIfAbsent(folder, () => {});
    }

    // Second pass: analyze imports via SCIP relationships
    for (final file in index.files) {
      final sourceFolder = p.dirname(file);
      final symbols = index.symbolsInFile(file);

      for (final symbol in symbols) {
        // Look at what this symbol calls/references
        final calls = index.getCalls(symbol.symbol);
        for (final calledSymbol in calls) {
          _addDependency(
            sourceFolder: sourceFolder,
            calledSymbol: calledSymbol,
            folders: folders,
            internalDeps: internalDeps,
            externalDeps: externalDeps,
            dependents: dependents,
          );
        }

        // Also look at relationships (implements, etc.)
        for (final rel in symbol.relationships) {
          final relSymbol = index.getSymbol(rel.symbol);
          if (relSymbol != null) {
            _addDependency(
              sourceFolder: sourceFolder,
              calledSymbol: relSymbol,
              folders: folders,
              internalDeps: internalDeps,
              externalDeps: externalDeps,
              dependents: dependents,
            );
          }
        }
      }
    }

    return FolderDependencyGraph._(
      folders: folders,
      internalDeps: internalDeps,
      externalDeps: externalDeps,
      dependents: dependents,
    );
  }

  static void _addDependency({
    required String sourceFolder,
    required SymbolInfo calledSymbol,
    required Set<String> folders,
    required Map<String, Set<String>> internalDeps,
    required Map<String, Set<String>> externalDeps,
    required Map<String, Set<String>> dependents,
  }) {
    if (calledSymbol.isExternal) {
      // External package dependency
      final packageName = _extractPackageName(calledSymbol.symbol);
      if (packageName != null) {
        externalDeps[sourceFolder]?.add(packageName);
      }
    } else if (calledSymbol.file != null) {
      // Internal dependency
      final targetFolder = p.dirname(calledSymbol.file!);
      if (targetFolder != sourceFolder && folders.contains(targetFolder)) {
        internalDeps[sourceFolder]?.add(targetFolder);
        dependents[targetFolder]?.add(sourceFolder);
      }
    }
  }

  /// Extract package name from a SCIP symbol ID.
  ///
  /// SCIP symbols look like:
  /// `scip-dart pub firebase_auth 4.6.0 lib/src/firebase_auth.dart/FirebaseAuth#`
  static String? _extractPackageName(String symbol) {
    // Pattern: scip-dart <manager> <package> <version> <path>
    final parts = symbol.split(' ');
    if (parts.length >= 3) {
      // parts[0] = "scip-dart", parts[1] = "pub", parts[2] = package name
      return parts[2];
    }
    return null;
  }

  /// Get internal folders that this folder depends on.
  Set<String> getInternalDependencies(String folder) {
    return _internalDeps[folder] ?? {};
  }

  /// Get external packages that this folder depends on.
  Set<String> getExternalDependencies(String folder) {
    return _externalDeps[folder] ?? {};
  }

  /// Get folders that depend on this folder.
  Set<String> getDependents(String folder) {
    return _dependents[folder] ?? {};
  }

  /// Get the internal dependency graph as a map.
  ///
  /// Returns folder -> set of folders it depends on.
  Map<String, Set<String>> get internalDependencyGraph => _internalDeps;

  /// Check if folder A depends on folder B (directly).
  bool dependsOn(String folderA, String folderB) {
    return _internalDeps[folderA]?.contains(folderB) ?? false;
  }

  /// Check if folder A transitively depends on folder B.
  bool transitivelyDependsOn(String folderA, String folderB) {
    final visited = <String>{};
    final queue = <String>[folderA];

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (current == folderB) return true;
      if (visited.contains(current)) continue;
      visited.add(current);

      final deps = _internalDeps[current];
      if (deps != null) {
        queue.addAll(deps);
      }
    }

    return false;
  }

  /// Get summary statistics.
  Map<String, int> get stats => {
        'folders': folders.length,
        'internalEdges':
            _internalDeps.values.fold(0, (sum, deps) => sum + deps.length),
        'externalPackages': _externalDeps.values
            .expand((deps) => deps)
            .toSet()
            .length,
      };

  @override
  String toString() {
    final buffer = StringBuffer('FolderDependencyGraph(\n');
    for (final folder in folders.toList()..sort()) {
      final internal = _internalDeps[folder] ?? {};
      final external = _externalDeps[folder] ?? {};
      buffer.writeln('  $folder:');
      if (internal.isNotEmpty) {
        buffer.writeln('    internal: ${internal.join(", ")}');
      }
      if (external.isNotEmpty) {
        buffer.writeln('    external: ${external.join(", ")}');
      }
    }
    buffer.write(')');
    return buffer.toString();
  }
}
