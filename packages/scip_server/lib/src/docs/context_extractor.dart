import 'package:path/path.dart' as p;

import '../index/scip_index.dart';

/// Context for a single file within a folder.
class FileContext {
  const FileContext({
    required this.path,
    required this.docComments,
    required this.publicApi,
    required this.symbols,
  });

  /// Relative path to the file.
  final String path;

  /// Doc comments from the file (if any module-level docs).
  final List<String> docComments;

  /// Public API signatures (classes, functions, methods).
  final List<ApiSignature> publicApi;

  /// All symbols defined in this file.
  final List<SymbolSummary> symbols;

  Map<String, dynamic> toJson() => {
        'path': path,
        if (docComments.isNotEmpty) 'docComments': docComments,
        'publicApi': publicApi.map((a) => a.toJson()).toList(),
        'symbols': symbols.map((s) => s.toJson()).toList(),
      };
}

/// A public API signature.
class ApiSignature {
  const ApiSignature({
    required this.name,
    required this.kind,
    required this.signature,
    this.docComment,
  });

  final String name;
  final String kind;
  final String signature;
  final String? docComment;

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind,
        'signature': signature,
        if (docComment != null) 'docComment': docComment,
      };
}

/// Summary of a symbol.
class SymbolSummary {
  const SymbolSummary({
    required this.id,
    required this.name,
    required this.kind,
    this.signature,
    this.docComment,
    this.relationships = const [],
  });

  final String id;
  final String name;
  final String kind;
  final String? signature;
  final String? docComment;
  final List<SymbolRelationship> relationships;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        if (signature != null) 'signature': signature,
        if (docComment != null) 'docComment': docComment,
        if (relationships.isNotEmpty)
          'relationships': relationships.map((r) => r.toJson()).toList(),
      };
}

/// A relationship between symbols.
class SymbolRelationship {
  const SymbolRelationship({
    required this.targetId,
    required this.targetName,
    required this.kind,
  });

  final String targetId;
  final String targetName;
  final String kind; // 'calls', 'implements', 'extends'

  Map<String, dynamic> toJson() => {
        'targetId': targetId,
        'targetName': targetName,
        'kind': kind,
      };
}

/// Context extracted for a folder.
class FolderContext {
  const FolderContext({
    required this.path,
    required this.files,
    required this.internalDeps,
    required this.externalDeps,
    required this.usedSymbols,
  });

  /// Folder path relative to project root.
  final String path;

  /// Files in this folder.
  final List<FileContext> files;

  /// Internal folder dependencies (other project folders).
  final Set<String> internalDeps;

  /// External package dependencies.
  final Set<String> externalDeps;

  /// Which symbols are used from each dependency.
  /// Map of dependency (folder path or package name) -> list of symbol names.
  final Map<String, List<String>> usedSymbols;

  Map<String, dynamic> toJson() => {
        'path': path,
        'files': files.map((f) => f.toJson()).toList(),
        'internalDeps': internalDeps.toList()..sort(),
        'externalDeps': externalDeps.toList()..sort(),
        'usedSymbols': usedSymbols,
      };
}

/// Extracts documentation-relevant context from a SCIP index.
///
/// This provides the raw data needed for LLM doc generation:
/// - File list with doc comments
/// - Public API signatures
/// - Symbol relationships (calls, implements)
/// - Which external symbols are used
class ContextExtractor {
  const ContextExtractor(this.index);

  final ScipIndex index;

  /// Extract context for a single folder.
  ///
  /// The [folderPath] should be relative to the project root,
  /// e.g., "lib/features/auth".
  FolderContext extractFolder(String folderPath) {
    // Normalize folder path
    final normalizedFolder = folderPath.endsWith('/')
        ? folderPath.substring(0, folderPath.length - 1)
        : folderPath;

    // Find files in this folder (not subfolders)
    final filesInFolder = index.files
        .where((file) => _isFileInFolder(file, normalizedFolder))
        .toList()
      ..sort();

    // Extract context for each file
    final fileContexts = <FileContext>[];
    for (final filePath in filesInFolder) {
      fileContexts.add(_extractFileContext(filePath));
    }

    // Collect dependencies and used symbols
    final internalDeps = <String>{};
    final externalDeps = <String>{};
    final usedSymbols = <String, Set<String>>{};

    for (final filePath in filesInFolder) {
      final symbols = index.symbolsInFile(filePath);
      for (final symbol in symbols) {
        // Skip local/anonymous symbols
        if (_isLocalOrAnonymous(symbol.symbol)) continue;

        // Check what this symbol calls
        final calls = index.getCalls(symbol.symbol);
        for (final calledSymbol in calls) {
          _trackDependency(
            calledSymbol,
            normalizedFolder,
            internalDeps,
            externalDeps,
            usedSymbols,
          );
        }

        // Check relationships (implements, type definitions)
        for (final rel in symbol.relationships) {
          final relSymbol = index.getSymbol(rel.symbol);
          if (relSymbol != null) {
            _trackDependency(
              relSymbol,
              normalizedFolder,
              internalDeps,
              externalDeps,
              usedSymbols,
            );
          }
        }
      }
    }

    // Convert used symbols to sorted lists
    final usedSymbolsMap = <String, List<String>>{};
    for (final entry in usedSymbols.entries) {
      usedSymbolsMap[entry.key] = entry.value.toList()..sort();
    }

    return FolderContext(
      path: normalizedFolder,
      files: fileContexts,
      internalDeps: internalDeps,
      externalDeps: externalDeps,
      usedSymbols: usedSymbolsMap,
    );
  }

  /// Extract context for a single file.
  FileContext _extractFileContext(String filePath) {
    final symbols = index.symbolsInFile(filePath).toList();

    // Collect doc comments (module-level if any)
    final docComments = <String>[];

    // Collect public API
    final publicApi = <ApiSignature>[];

    // Collect symbol summaries
    final symbolSummaries = <SymbolSummary>[];

    for (final symbol in symbols) {
      // Skip local/anonymous
      if (_isLocalOrAnonymous(symbol.symbol)) continue;

      // Build signature
      final signature = _buildSignature(symbol);

      // Get doc comment
      final docComment = symbol.documentation.isNotEmpty
          ? symbol.documentation.join('\n')
          : null;

      // Extract relationships
      final relationships = _extractRelationships(symbol);

      symbolSummaries.add(SymbolSummary(
        id: symbol.symbol,
        name: symbol.name,
        kind: symbol.kindString,
        signature: signature,
        docComment: docComment,
        relationships: relationships,
      ));

      // Add to public API if it's a top-level entity
      if (_isPublicApi(symbol)) {
        publicApi.add(ApiSignature(
          name: symbol.name,
          kind: symbol.kindString,
          signature: signature ?? symbol.name,
          docComment: _truncateDocComment(docComment),
        ));
      }
    }

    return FileContext(
      path: filePath,
      docComments: docComments,
      publicApi: publicApi,
      symbols: symbolSummaries,
    );
  }

  /// Build a signature string for a symbol.
  String? _buildSignature(SymbolInfo symbol) {
    // Use display name if available (contains full signature)
    if (symbol.displayName != null && symbol.displayName!.isNotEmpty) {
      return symbol.displayName;
    }

    // For methods/functions, try to build from members
    if (symbol.kind.name == 'Method' || symbol.kind.name == 'Function') {
      return '${symbol.name}()';
    }

    return null;
  }

  /// Extract relationships for a symbol.
  List<SymbolRelationship> _extractRelationships(SymbolInfo symbol) {
    final relationships = <SymbolRelationship>[];

    // Add implements/extends relationships
    for (final rel in symbol.relationships) {
      if (rel.isImplementation) {
        final target = index.getSymbol(rel.symbol);
        if (target != null) {
          relationships.add(SymbolRelationship(
            targetId: rel.symbol,
            targetName: target.name,
            kind: 'implements',
          ));
        }
      }
    }

    // Add call relationships (limited to avoid explosion)
    final calls = index.getCalls(symbol.symbol).take(10);
    for (final calledSymbol in calls) {
      // Skip external symbols for call relationships
      if (!calledSymbol.isExternal) {
        relationships.add(SymbolRelationship(
          targetId: calledSymbol.symbol,
          targetName: calledSymbol.name,
          kind: 'calls',
        ));
      }
    }

    return relationships;
  }

  /// Check if a symbol is part of the public API.
  bool _isPublicApi(SymbolInfo symbol) {
    // Classes, top-level functions, enums, mixins, extensions
    final kind = symbol.kindString;
    if (!['class', 'function', 'enum', 'mixin', 'extension'].contains(kind)) {
      return false;
    }

    // Skip private symbols
    if (symbol.name.startsWith('_')) {
      return false;
    }

    return true;
  }

  /// Truncate doc comment to first line/sentence for summaries.
  String? _truncateDocComment(String? doc) {
    if (doc == null || doc.isEmpty) return null;

    // Get first line
    final firstLine = doc.split('\n').first.trim();

    // Truncate if too long
    if (firstLine.length > 100) {
      return '${firstLine.substring(0, 97)}...';
    }

    return firstLine;
  }

  /// Track a dependency from a symbol reference.
  void _trackDependency(
    SymbolInfo calledSymbol,
    String currentFolder,
    Set<String> internalDeps,
    Set<String> externalDeps,
    Map<String, Set<String>> usedSymbols,
  ) {
    if (calledSymbol.isExternal) {
      // External package
      final packageName = _extractPackageName(calledSymbol.symbol);
      if (packageName != null) {
        externalDeps.add(packageName);
        usedSymbols.putIfAbsent(packageName, () => {}).add(calledSymbol.name);
      }
    } else if (calledSymbol.file != null) {
      // Internal dependency
      final targetFolder = p.dirname(calledSymbol.file!);
      if (targetFolder != currentFolder) {
        internalDeps.add(targetFolder);
        usedSymbols
            .putIfAbsent(targetFolder, () => {})
            .add(calledSymbol.name);
      }
    }
  }

  /// Check if a file is directly in a folder (not subfolder).
  bool _isFileInFolder(String filePath, String folderPath) {
    if (!filePath.startsWith(folderPath)) return false;
    
    final remainder = filePath.substring(folderPath.length);
    if (!remainder.startsWith('/')) return false;
    
    // Should have exactly one slash (the one after folder)
    final afterSlash = remainder.substring(1);
    return !afterSlash.contains('/');
  }

  /// Check if a symbol is local or anonymous.
  bool _isLocalOrAnonymous(String symbolId) {
    if (symbolId.contains('/local')) return true;
    if (symbolId.contains('`<anonymous>')) return true;
    return false;
  }

  /// Extract package name from a SCIP symbol ID.
  String? _extractPackageName(String symbol) {
    // Pattern: scip-dart <manager> <package> <version> <path>
    final parts = symbol.split(' ');
    if (parts.length >= 3) {
      return parts[2];
    }
    return null;
  }
}
