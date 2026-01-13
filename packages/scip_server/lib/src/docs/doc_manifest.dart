import 'dart:convert';
import 'dart:io';

/// Manifest for tracking documentation state and enabling incremental updates.
///
/// Stores:
/// - Structure hashes for each folder (to detect when regeneration is needed)
/// - Document hashes (to detect content changes)
/// - Dependencies (to propagate dirty state)
/// - Smart symbols (to track what code is referenced)
///
/// The manifest is stored as JSON alongside the generated docs.
class DocManifest {
  DocManifest({
    this.version = 1,
    Map<String, FolderDocState>? folders,
    Map<String, ModuleDocState>? modules,
    this.project,
    DateTime? lastUpdated,
  })  : folders = folders ?? {},
        modules = modules ?? {},
        lastUpdated = lastUpdated ?? DateTime.now();

  /// Manifest format version.
  final int version;

  /// State for each folder's documentation.
  final Map<String, FolderDocState> folders;

  /// State for each module's documentation.
  final Map<String, ModuleDocState> modules;

  /// State for project-level documentation.
  ProjectDocState? project;

  /// When the manifest was last updated.
  DateTime lastUpdated;

  /// Load manifest from a JSON file.
  ///
  /// Returns an empty manifest if the file doesn't exist.
  static Future<DocManifest> load(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return DocManifest();
    }

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return DocManifest.fromJson(json);
    } catch (e) {
      // If file is corrupted, return empty manifest
      return DocManifest();
    }
  }

  /// Create manifest from JSON.
  factory DocManifest.fromJson(Map<String, dynamic> json) {
    return DocManifest(
      version: json['version'] as int? ?? 1,
      folders: (json['folders'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              key,
              FolderDocState.fromJson(value as Map<String, dynamic>),
            ),
          ) ??
          {},
      modules: (json['modules'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              key,
              ModuleDocState.fromJson(value as Map<String, dynamic>),
            ),
          ) ??
          {},
      project: json['project'] != null
          ? ProjectDocState.fromJson(json['project'] as Map<String, dynamic>)
          : null,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'] as String)
          : null,
    );
  }

  /// Convert manifest to JSON.
  Map<String, dynamic> toJson() => {
        'version': version,
        'folders': folders.map((key, value) => MapEntry(key, value.toJson())),
        'modules': modules.map((key, value) => MapEntry(key, value.toJson())),
        if (project != null) 'project': project!.toJson(),
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  /// Save manifest to a JSON file.
  Future<void> save(String path) async {
    lastUpdated = DateTime.now();
    final file = File(path);
    await file.parent.create(recursive: true);
    final content = const JsonEncoder.withIndent('  ').convert(toJson());
    await file.writeAsString(content);
  }

  /// Check if a folder needs regeneration.
  ///
  /// A folder is dirty if:
  /// - It has no previous state (never generated)
  /// - Its structure hash has changed
  bool isFolderDirty(String folder, String currentStructureHash) {
    final state = folders[folder];
    if (state == null) return true;
    return state.structureHash != currentStructureHash;
  }

  /// Check if a module needs regeneration.
  ///
  /// A module is dirty if any of its child folders have changed.
  bool isModuleDirty(String module, List<String> childFolders) {
    final state = modules[module];
    if (state == null) return true;

    // Check if any child folder's doc hash has changed
    for (final folder in childFolders) {
      final folderState = folders[folder];
      if (folderState == null) return true;

      final previousHash = state.folderDocHashes[folder];
      if (previousHash != folderState.docHash) return true;
    }

    return false;
  }

  /// Check if the project doc needs regeneration.
  bool isProjectDirty(List<String> moduleNames) {
    if (project == null) return true;

    for (final module in moduleNames) {
      final moduleState = modules[module];
      if (moduleState == null) return true;

      final previousHash = project!.moduleDocHashes[module];
      if (previousHash != moduleState.docHash) return true;
    }

    return false;
  }

  /// Update folder state after regeneration.
  void updateFolder(String folder, FolderDocState state) {
    folders[folder] = state;
  }

  /// Update module state after regeneration.
  void updateModule(String module, ModuleDocState state) {
    modules[module] = state;
  }

  /// Update project state after regeneration.
  void updateProject(ProjectDocState state) {
    project = state;
  }

  /// Get all dirty folders given current structure hashes.
  List<String> getDirtyFolders(Map<String, String> currentHashes) {
    final dirty = <String>[];
    for (final entry in currentHashes.entries) {
      if (isFolderDirty(entry.key, entry.value)) {
        dirty.add(entry.key);
      }
    }
    return dirty;
  }

  /// Remove state for folders that no longer exist.
  void pruneRemovedFolders(Set<String> existingFolders) {
    folders.removeWhere((key, _) => !existingFolders.contains(key));
  }
}

/// State for a folder's documentation.
class FolderDocState {
  FolderDocState({
    required this.structureHash,
    required this.docHash,
    required this.generatedAt,
    this.internalDeps = const [],
    this.externalDeps = const [],
    this.smartSymbols = const [],
  });

  /// Hash of the folder's doc-relevant structure (from SCIP).
  final String structureHash;

  /// Hash of the generated documentation content.
  final String docHash;

  /// When the doc was last generated.
  final DateTime generatedAt;

  /// Internal folder dependencies.
  final List<String> internalDeps;

  /// External package dependencies.
  final List<String> externalDeps;

  /// Smart symbols referenced in the doc (scip:// URIs).
  final List<String> smartSymbols;

  factory FolderDocState.fromJson(Map<String, dynamic> json) {
    return FolderDocState(
      structureHash: json['structureHash'] as String? ?? '',
      docHash: json['docHash'] as String? ?? '',
      generatedAt: json['generatedAt'] != null
          ? DateTime.parse(json['generatedAt'] as String)
          : DateTime.now(),
      internalDeps: (json['internalDeps'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      externalDeps: (json['externalDeps'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      smartSymbols: (json['smartSymbols'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'structureHash': structureHash,
        'docHash': docHash,
        'generatedAt': generatedAt.toIso8601String(),
        'internalDeps': internalDeps,
        'externalDeps': externalDeps,
        'smartSymbols': smartSymbols,
      };
}

/// State for a module's documentation.
class ModuleDocState {
  ModuleDocState({
    required this.docHash,
    required this.generatedAt,
    required this.childFolders,
    this.folderDocHashes = const {},
  });

  /// Hash of the generated module documentation.
  final String docHash;

  /// When the doc was last generated.
  final DateTime generatedAt;

  /// Child folders that comprise this module.
  final List<String> childFolders;

  /// Hash of each child folder's doc at generation time.
  /// Used to detect when child docs have changed.
  final Map<String, String> folderDocHashes;

  factory ModuleDocState.fromJson(Map<String, dynamic> json) {
    return ModuleDocState(
      docHash: json['docHash'] as String? ?? '',
      generatedAt: json['generatedAt'] != null
          ? DateTime.parse(json['generatedAt'] as String)
          : DateTime.now(),
      childFolders: (json['childFolders'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      folderDocHashes:
          (json['folderDocHashes'] as Map<String, dynamic>?)?.map(
                (key, value) => MapEntry(key, value as String),
              ) ??
              {},
    );
  }

  Map<String, dynamic> toJson() => {
        'docHash': docHash,
        'generatedAt': generatedAt.toIso8601String(),
        'childFolders': childFolders,
        'folderDocHashes': folderDocHashes,
      };
}

/// State for project-level documentation.
class ProjectDocState {
  ProjectDocState({
    required this.docHash,
    required this.generatedAt,
    this.moduleDocHashes = const {},
  });

  /// Hash of the generated project documentation.
  final String docHash;

  /// When the doc was last generated.
  final DateTime generatedAt;

  /// Hash of each module's doc at generation time.
  final Map<String, String> moduleDocHashes;

  factory ProjectDocState.fromJson(Map<String, dynamic> json) {
    return ProjectDocState(
      docHash: json['docHash'] as String? ?? '',
      generatedAt: json['generatedAt'] != null
          ? DateTime.parse(json['generatedAt'] as String)
          : DateTime.now(),
      moduleDocHashes:
          (json['moduleDocHashes'] as Map<String, dynamic>?)?.map(
                (key, value) => MapEntry(key, value as String),
              ) ??
              {},
    );
  }

  Map<String, dynamic> toJson() => {
        'docHash': docHash,
        'generatedAt': generatedAt.toIso8601String(),
        'moduleDocHashes': moduleDocHashes,
      };
}
