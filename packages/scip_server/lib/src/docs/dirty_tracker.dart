import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'doc_manifest.dart';
import 'folder_graph.dart';
import 'structure_hash.dart';
import 'topological_sort.dart';
import '../index/scip_index.dart';

/// Result of dirty detection.
class DirtyState {
  const DirtyState({
    required this.dirtyFolders,
    required this.dirtyModules,
    required this.projectDirty,
    required this.generationOrder,
    required this.structureHashes,
  });

  /// Folders that need regeneration.
  final Set<String> dirtyFolders;

  /// Modules that need regeneration.
  final Set<String> dirtyModules;

  /// Whether the project doc needs regeneration.
  final bool projectDirty;

  /// Order to generate folders (topological sort, respecting cycles).
  final List<List<String>> generationOrder;

  /// Current structure hashes for all folders.
  final Map<String, String> structureHashes;

  /// Check if anything is dirty.
  bool get isDirty =>
      dirtyFolders.isNotEmpty || dirtyModules.isNotEmpty || projectDirty;

  /// Get summary stats.
  Map<String, dynamic> toSummary() => {
        'dirtyFolders': dirtyFolders.length,
        'dirtyModules': dirtyModules.length,
        'projectDirty': projectDirty,
        'totalFolders': structureHashes.length,
        'generationLevels': generationOrder.length,
      };
}

/// Tracks dirty state for documentation.
///
/// Uses the Phase 1 infrastructure to:
/// - Compute structure hashes for all folders
/// - Compare against manifest to find dirty folders
/// - Propagate dirty state upward (folder → module → project)
/// - Determine generation order via topological sort
class DirtyTracker {
  const DirtyTracker({
    required this.index,
    required this.graph,
    required this.manifest,
    this.moduleDefinitions = const {},
  });

  final ScipIndex index;
  final FolderDependencyGraph graph;
  final DocManifest manifest;

  /// Module definitions: module name → list of folders.
  /// If empty, modules are auto-detected from folder structure.
  final Map<String, List<String>> moduleDefinitions;

  /// Compute the current dirty state.
  DirtyState computeDirtyState() {
    // Compute structure hashes for all folders
    final structureHashes = <String, String>{};
    for (final folder in graph.folders) {
      structureHashes[folder] = StructureHash.computeFolderHash(index, folder);
    }

    // Find directly dirty folders (structure changed)
    final dirtyFolders = <String>{};
    for (final entry in structureHashes.entries) {
      if (manifest.isFolderDirty(entry.key, entry.value)) {
        dirtyFolders.add(entry.key);
      }
    }

    // Propagate dirty via smart symbol references
    _propagateViaSmartSymbols(dirtyFolders, structureHashes);

    // Determine modules (auto-detect or use definitions)
    final modules = moduleDefinitions.isNotEmpty
        ? moduleDefinitions
        : _autoDetectModules();

    // Find dirty modules
    final dirtyModules = <String>{};
    for (final entry in modules.entries) {
      // Module is dirty if any of its folders are dirty OR
      // if its folder doc hashes have changed
      if (entry.value.any((f) => dirtyFolders.contains(f))) {
        dirtyModules.add(entry.key);
      } else if (manifest.isModuleDirty(entry.key, entry.value)) {
        dirtyModules.add(entry.key);
      }
    }

    // Project is dirty if any module is dirty
    final projectDirty =
        dirtyModules.isNotEmpty || manifest.isProjectDirty(modules.keys.toList());

    // Compute generation order
    final generationOrder = TopologicalSort.sort(graph);

    return DirtyState(
      dirtyFolders: dirtyFolders,
      dirtyModules: dirtyModules,
      projectDirty: projectDirty,
      generationOrder: generationOrder,
      structureHashes: structureHashes,
    );
  }

  /// Propagate dirty state via smart symbol references.
  ///
  /// If folder A's doc references symbols from folder B, and B changes,
  /// then A's doc may have stale references and should be regenerated.
  void _propagateViaSmartSymbols(
    Set<String> dirtyFolders,
    Map<String, String> structureHashes,
  ) {
    // Build a map of symbol ID prefixes to folders that changed
    final changedSymbolPrefixes = <String>{};
    for (final folder in dirtyFolders) {
      // Symbols in this folder will have IDs containing the folder path
      changedSymbolPrefixes.add(folder);
    }

    // Check each folder's smart symbols
    for (final entry in manifest.folders.entries) {
      final folder = entry.key;
      final state = entry.value;

      // Skip if already dirty
      if (dirtyFolders.contains(folder)) continue;

      // Check if any referenced symbols are in changed folders
      for (final symbolUri in state.smartSymbols) {
        // Extract folder path from scip:// URI
        // Format: scip://lib/path/file.dart/SymbolName#
        final folderPath = _extractFolderFromUri(symbolUri);
        if (folderPath != null && changedSymbolPrefixes.contains(folderPath)) {
          dirtyFolders.add(folder);
          break;
        }
      }
    }
  }

  /// Extract folder path from a scip:// URI.
  String? _extractFolderFromUri(String uri) {
    // scip://lib/features/auth/auth_service.dart/AuthService#
    if (!uri.startsWith('scip://')) return null;

    final path = uri.substring(7); // Remove "scip://"
    final lastSlash = path.lastIndexOf('/');
    if (lastSlash <= 0) return null;

    // Find the .dart part to get the file
    final dartIndex = path.indexOf('.dart');
    if (dartIndex < 0) return null;

    // Get path up to the file, then take the directory
    final filePath = path.substring(0, dartIndex + 5); // Include ".dart"
    final folderEnd = filePath.lastIndexOf('/');
    if (folderEnd <= 0) return null;

    return filePath.substring(0, folderEnd);
  }

  /// Auto-detect modules from folder structure.
  ///
  /// Groups folders by their top-level feature directories:
  /// - lib/features/auth/ → "auth" module
  /// - lib/features/products/ → "products" module
  /// - lib/core/ → "core" module
  Map<String, List<String>> _autoDetectModules() {
    final modules = <String, List<String>>{};

    for (final folder in graph.folders) {
      final module = _inferModule(folder);
      modules.putIfAbsent(module, () => []).add(folder);
    }

    return modules;
  }

  /// Infer module name from folder path.
  String _inferModule(String folder) {
    final parts = folder.split('/');

    // Look for "features" or "modules" directory
    final featuresIdx = parts.indexOf('features');
    if (featuresIdx >= 0 && featuresIdx + 1 < parts.length) {
      return parts[featuresIdx + 1];
    }

    final modulesIdx = parts.indexOf('modules');
    if (modulesIdx >= 0 && modulesIdx + 1 < parts.length) {
      return parts[modulesIdx + 1];
    }

    // Use second-level directory under lib
    if (parts.isNotEmpty && parts[0] == 'lib' && parts.length > 1) {
      return parts[1];
    }

    // Fallback to "main"
    return 'main';
  }

  /// Compute hash of generated doc content.
  static String computeDocHash(String docContent) {
    final bytes = utf8.encode(docContent);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// Create updated folder state after regeneration.
  static FolderDocState createFolderState({
    required String structureHash,
    required String docContent,
    required List<String> internalDeps,
    required List<String> externalDeps,
    required List<String> smartSymbols,
  }) {
    return FolderDocState(
      structureHash: structureHash,
      docHash: computeDocHash(docContent),
      generatedAt: DateTime.now(),
      internalDeps: internalDeps,
      externalDeps: externalDeps,
      smartSymbols: smartSymbols,
    );
  }

  /// Create updated module state after regeneration.
  static ModuleDocState createModuleState({
    required String docContent,
    required List<String> childFolders,
    required Map<String, String> folderDocHashes,
  }) {
    return ModuleDocState(
      docHash: computeDocHash(docContent),
      generatedAt: DateTime.now(),
      childFolders: childFolders,
      folderDocHashes: folderDocHashes,
    );
  }

  /// Create updated project state after regeneration.
  static ProjectDocState createProjectState({
    required String docContent,
    required Map<String, String> moduleDocHashes,
  }) {
    return ProjectDocState(
      docHash: computeDocHash(docContent),
      generatedAt: DateTime.now(),
      moduleDocHashes: moduleDocHashes,
    );
  }
}
