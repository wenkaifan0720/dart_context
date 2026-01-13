import 'dart:io';

import 'context_extractor.dart';
import 'folder_graph.dart';
import '../index/scip_index.dart';

/// Summary of an already-generated folder doc.
class FolderSummary {
  const FolderSummary({
    required this.path,
    required this.docSummary,
    required this.publicApi,
    required this.usedSymbols,
  });

  /// Folder path.
  final String path;

  /// Compressed summary from the generated doc.
  final String? docSummary;

  /// Public API signatures.
  final List<String> publicApi;

  /// Which symbols from this folder are used by the current folder.
  final List<String> usedSymbols;

  Map<String, dynamic> toJson() => {
        'path': path,
        if (docSummary != null) 'docSummary': docSummary,
        'publicApi': publicApi,
        'usedSymbols': usedSymbols,
      };
}

/// Summary of an external package dependency.
class PackageSummary {
  const PackageSummary({
    required this.name,
    this.version,
    this.docSummary,
    required this.usedSymbols,
  });

  /// Package name (e.g., "firebase_auth").
  final String name;

  /// Package version (if known).
  final String? version;

  /// Summary from package README or pub.dev.
  final String? docSummary;

  /// Symbols used from this package.
  final List<String> usedSymbols;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (version != null) 'version': version,
        if (docSummary != null) 'docSummary': docSummary,
        'usedSymbols': usedSymbols,
      };
}

/// How the current folder is used by its dependents.
class DependentUsage {
  const DependentUsage({
    required this.path,
    required this.usedSymbols,
  });

  /// Path of the dependent folder.
  final String path;

  /// Symbols from current folder that are used.
  final List<String> usedSymbols;

  Map<String, dynamic> toJson() => {
        'path': path,
        'usedSymbols': usedSymbols,
      };
}

/// Full context for LLM doc generation.
///
/// This is the complete package of information sent to the LLM
/// to generate documentation for a folder.
class DocContext {
  const DocContext({
    required this.current,
    required this.internalDeps,
    required this.externalDeps,
    required this.dependents,
  });

  /// Full context for the current folder.
  final FolderContext current;

  /// Summary context for internal folder dependencies.
  final List<FolderSummary> internalDeps;

  /// Summary context for external package dependencies.
  final List<PackageSummary> externalDeps;

  /// How this folder is used by dependents.
  final List<DependentUsage> dependents;

  Map<String, dynamic> toJson() => {
        'current': current.toJson(),
        'internalDeps': internalDeps.map((d) => d.toJson()).toList(),
        'externalDeps': externalDeps.map((d) => d.toJson()).toList(),
        'dependents': dependents.map((d) => d.toJson()).toList(),
      };
}

/// Builds complete documentation context for a folder.
///
/// Assembles:
/// - Full detail for the current folder
/// - Summary context from already-generated dependency docs
/// - External package summaries
/// - How dependents use this folder
class ContextBuilder {
  ContextBuilder({
    required this.index,
    required this.graph,
    required this.projectRoot,
    this.docsRoot,
  }) : _extractor = ContextExtractor(index);

  final ScipIndex index;
  final FolderDependencyGraph graph;
  final String projectRoot;
  final String? docsRoot;
  final ContextExtractor _extractor;

  /// Build complete context for a folder.
  ///
  /// The [folder] should be a relative path like "lib/features/auth".
  Future<DocContext> buildForFolder(String folder) async {
    // Extract current folder context
    final current = _extractor.extractFolder(folder);

    // Build internal dependency summaries
    final internalDeps = <FolderSummary>[];
    for (final depFolder in current.internalDeps) {
      final summary = await _buildFolderSummary(
        depFolder,
        current.usedSymbols[depFolder] ?? [],
      );
      internalDeps.add(summary);
    }

    // Build external package summaries
    final externalDeps = <PackageSummary>[];
    for (final pkg in current.externalDeps) {
      final summary = _buildPackageSummary(
        pkg,
        current.usedSymbols[pkg] ?? [],
      );
      externalDeps.add(summary);
    }

    // Build dependent usage info
    final dependents = <DependentUsage>[];
    for (final depFolder in graph.getDependents(folder)) {
      final usage = await _buildDependentUsage(depFolder, folder);
      if (usage != null) {
        dependents.add(usage);
      }
    }

    return DocContext(
      current: current,
      internalDeps: internalDeps,
      externalDeps: externalDeps,
      dependents: dependents,
    );
  }

  /// Build summary for an internal folder dependency.
  Future<FolderSummary> _buildFolderSummary(
    String folder,
    List<String> usedSymbols,
  ) async {
    // Try to read existing generated doc
    String? docSummary;
    if (docsRoot != null) {
      final docPath = '$docsRoot/source/folders/$folder/README.md';
      final docFile = File(docPath);
      if (await docFile.exists()) {
        final content = await docFile.readAsString();
        docSummary = _extractSummary(content);
      }
    }

    // Extract public API from SCIP
    final publicApi = <String>[];
    final folderContext = _extractor.extractFolder(folder);
    for (final file in folderContext.files) {
      for (final api in file.publicApi) {
        publicApi.add('${api.kind} ${api.signature}');
      }
    }

    return FolderSummary(
      path: folder,
      docSummary: docSummary,
      publicApi: publicApi,
      usedSymbols: usedSymbols,
    );
  }

  /// Build summary for an external package.
  PackageSummary _buildPackageSummary(String pkg, List<String> usedSymbols) {
    // For now, just note the package and used symbols
    // TODO: Read from cached package docs when available
    return PackageSummary(
      name: pkg,
      usedSymbols: usedSymbols,
    );
  }

  /// Build usage info for a dependent folder.
  Future<DependentUsage?> _buildDependentUsage(
    String dependentFolder,
    String currentFolder,
  ) async {
    // Extract what symbols from currentFolder are used by dependentFolder
    final dependentContext = _extractor.extractFolder(dependentFolder);
    final usedSymbols = dependentContext.usedSymbols[currentFolder];

    if (usedSymbols == null || usedSymbols.isEmpty) {
      return null;
    }

    return DependentUsage(
      path: dependentFolder,
      usedSymbols: usedSymbols,
    );
  }

  /// Extract summary from a generated doc.
  ///
  /// Looks for an "Overview" section and extracts first paragraph.
  String? _extractSummary(String docContent) {
    // Look for ## Overview section
    final overviewMatch = RegExp(
      r'## Overview\s*\n+(.*?)(?=\n##|\n\n\n|$)',
      multiLine: true,
      dotAll: true,
    ).firstMatch(docContent);

    if (overviewMatch != null) {
      final overview = overviewMatch.group(1)?.trim();
      if (overview != null && overview.isNotEmpty) {
        // Take first paragraph (up to 500 chars)
        final firstPara = overview.split('\n\n').first;
        if (firstPara.length > 500) {
          return '${firstPara.substring(0, 497)}...';
        }
        return firstPara;
      }
    }

    // Fallback: try first non-heading line
    final lines = docContent.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        if (trimmed.length > 200) {
          return '${trimmed.substring(0, 197)}...';
        }
        return trimmed;
      }
    }

    return null;
  }
}
