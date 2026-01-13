import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../index/scip_index.dart';

/// Computes a structure hash from SCIP symbols.
///
/// The hash captures the "documentation-relevant structure" of code:
/// - Symbol names and kinds
/// - Signatures (from documentation/display name)
/// - Doc comments
/// - Relationships (implements, calls)
///
/// It does NOT capture:
/// - Implementation bodies
/// - Line numbers
/// - Formatting/whitespace
///
/// This allows us to detect when the structure changes (requiring doc
/// regeneration) vs. when only implementation changes (no regeneration needed).
class StructureHash {
  /// Extract documentation-relevant parts from symbols.
  ///
  /// Returns a list of strings representing the structural elements:
  /// - `symbol:<id>:<kind>` - Symbol identity
  /// - `sig:<id>:<signature>` - Symbol signature (if available)
  /// - `doc:<id>:<hash>` - Doc comment hash (if available)
  /// - `rel:<id>:<target>:<kind>` - Relationships
  static List<String> extractDocRelevantParts(Iterable<SymbolInfo> symbols) {
    final parts = <String>[];

    for (final symbol in symbols) {
      // Skip local/anonymous symbols - they're not doc-relevant
      if (_isLocalOrAnonymous(symbol.symbol)) continue;

      // Symbol identity (name + kind)
      parts.add('symbol:${symbol.symbol}:${symbol.kindString}');

      // Signature from display name (if available)
      if (symbol.displayName != null && symbol.displayName!.isNotEmpty) {
        parts.add('sig:${symbol.symbol}:${symbol.displayName}');
      }

      // Doc comments (hash the content to keep parts manageable)
      if (symbol.documentation.isNotEmpty) {
        final docContent = symbol.documentation.join('\n');
        final docHash = _shortHash(docContent);
        parts.add('doc:${symbol.symbol}:$docHash');
      }

      // Relationships (implements, type definitions, etc.)
      for (final rel in symbol.relationships) {
        final relKind = _relationshipKind(rel);
        if (relKind != null) {
          parts.add('rel:${symbol.symbol}:${rel.symbol}:$relKind');
        }
      }
    }

    return parts;
  }

  /// Compute MD5 hash from a list of structural parts.
  ///
  /// Parts are sorted for deterministic ordering regardless of
  /// symbol declaration order.
  static String computeHash(List<String> parts) {
    if (parts.isEmpty) return '';

    // Sort for consistent ordering
    final sorted = List<String>.from(parts)..sort();

    // Compute MD5 hash
    final content = sorted.join('|');
    final bytes = utf8.encode(content);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// Compute structure hash for all symbols in a folder.
  ///
  /// The [folderPath] should be relative to the project root,
  /// e.g., "lib/features/auth".
  static String computeFolderHash(ScipIndex index, String folderPath) {
    // Normalize folder path (ensure no trailing slash for comparison)
    final normalizedFolder = folderPath.endsWith('/')
        ? folderPath.substring(0, folderPath.length - 1)
        : folderPath;

    // Get all symbols in files within this folder
    final symbols = <SymbolInfo>[];
    for (final file in index.files) {
      if (_isFileInFolder(file, normalizedFolder)) {
        symbols.addAll(index.symbolsInFile(file));
      }
    }

    final parts = extractDocRelevantParts(symbols);
    return computeHash(parts);
  }

  /// Compute structure hash for a single file.
  static String computeFileHash(ScipIndex index, String filePath) {
    final symbols = index.symbolsInFile(filePath);
    final parts = extractDocRelevantParts(symbols);
    return computeHash(parts);
  }

  /// Check if a file is directly within a folder (not in subfolders).
  static bool _isFileInFolder(String filePath, String folderPath) {
    if (!filePath.startsWith(folderPath)) return false;

    // Check it's directly in the folder, not a subfolder
    final remainder = filePath.substring(folderPath.length);
    if (!remainder.startsWith('/')) return false;

    // Should have exactly one slash (the one after folder)
    final afterSlash = remainder.substring(1);
    return !afterSlash.contains('/');
  }

  /// Check if a symbol is local or anonymous (not doc-relevant).
  static bool _isLocalOrAnonymous(String symbolId) {
    // Local symbols contain 'local' in the path
    if (symbolId.contains('/local')) return true;

    // Anonymous symbols (closures, etc.)
    if (symbolId.contains('`<anonymous>')) return true;

    return false;
  }

  /// Get a short hash of content (first 8 chars of MD5).
  static String _shortHash(String content) {
    final bytes = utf8.encode(content);
    final digest = md5.convert(bytes);
    return digest.toString().substring(0, 8);
  }

  /// Get the relationship kind string, or null if not doc-relevant.
  static String? _relationshipKind(RelationshipInfo rel) {
    if (rel.isImplementation) return 'implements';
    if (rel.isTypeDefinition) return 'typedef';
    if (rel.isDefinition) return 'defines';
    // References are not included - too noisy and change frequently
    return null;
  }
}
