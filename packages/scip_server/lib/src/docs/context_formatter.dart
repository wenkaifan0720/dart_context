import 'context_builder.dart';
import 'context_extractor.dart';

/// Formats [DocContext] as YAML for LLM consumption.
///
/// The YAML format is designed to be:
/// - Human-readable for debugging
/// - Token-efficient for LLM context windows
/// - Structured for easy parsing
class ContextFormatter {
  const ContextFormatter();

  /// Format a [DocContext] as YAML string.
  String formatAsYaml(DocContext context) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('# Documentation Context for: ${context.current.path}');
    buffer.writeln();

    // Current folder (full detail)
    buffer.writeln('# ═══════════════════════════════════════════════════════');
    buffer.writeln('# CURRENT FOLDER (full detail)');
    buffer.writeln('# ═══════════════════════════════════════════════════════');
    buffer.writeln();
    _writeFolderContext(buffer, context.current);

    // Internal dependencies (summaries)
    if (context.internalDeps.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('# ═══════════════════════════════════════════════════════');
      buffer.writeln('# INTERNAL DEPENDENCIES (summaries)');
      buffer.writeln('# ═══════════════════════════════════════════════════════');
      buffer.writeln();
      buffer.writeln('internal_dependencies:');
      for (final dep in context.internalDeps) {
        _writeFolderSummary(buffer, dep);
      }
    }

    // External dependencies
    if (context.externalDeps.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('# ═══════════════════════════════════════════════════════');
      buffer.writeln('# EXTERNAL PACKAGES');
      buffer.writeln('# ═══════════════════════════════════════════════════════');
      buffer.writeln();
      buffer.writeln('external_dependencies:');
      for (final pkg in context.externalDeps) {
        _writePackageSummary(buffer, pkg);
      }
    }

    // Dependents
    if (context.dependents.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('# ═══════════════════════════════════════════════════════');
      buffer.writeln('# DEPENDENTS (who uses this folder)');
      buffer.writeln('# ═══════════════════════════════════════════════════════');
      buffer.writeln();
      buffer.writeln('dependents:');
      for (final dep in context.dependents) {
        _writeDependentUsage(buffer, dep);
      }
    }

    return buffer.toString();
  }

  /// Write current folder context.
  void _writeFolderContext(StringBuffer buffer, FolderContext folder) {
    buffer.writeln('folder:');
    buffer.writeln('  path: ${folder.path}');
    buffer.writeln();

    // Files with their content
    buffer.writeln('  files:');
    for (final file in folder.files) {
      buffer.writeln('    - path: ${file.path}');

      // Doc comments
      if (file.docComments.isNotEmpty) {
        buffer.writeln('      doc_comments: |');
        for (final comment in file.docComments) {
          buffer.writeln('        $comment');
        }
      }

      // Public API
      if (file.publicApi.isNotEmpty) {
        buffer.writeln('      public_api:');
        for (final api in file.publicApi) {
          buffer.writeln('        - "${_escapeYamlString(api.signature)}"');
          if (api.docComment != null) {
            buffer.writeln(
                '          # ${_escapeYamlString(api.docComment!)}');
          }
        }
      }

      // Symbols with relationships
      if (file.symbols.isNotEmpty) {
        buffer.writeln('      symbols:');
        for (final sym in file.symbols) {
          _writeSymbolSummary(buffer, sym, indent: 8);
        }
      }
    }
  }

  /// Write a symbol summary.
  void _writeSymbolSummary(
    StringBuffer buffer,
    SymbolSummary symbol, {
    int indent = 0,
  }) {
    final pad = ' ' * indent;
    buffer.writeln('$pad- id: "${_escapeYamlString(symbol.id)}"');
    buffer.writeln('$pad  name: ${symbol.name}');
    buffer.writeln('$pad  kind: ${symbol.kind}');

    if (symbol.signature != null) {
      buffer.writeln(
          '$pad  signature: "${_escapeYamlString(symbol.signature!)}"');
    }

    if (symbol.docComment != null) {
      // Multi-line doc comments
      if (symbol.docComment!.contains('\n')) {
        buffer.writeln('$pad  doc_comment: |');
        for (final line in symbol.docComment!.split('\n')) {
          buffer.writeln('$pad    ${_escapeYamlString(line)}');
        }
      } else {
        buffer.writeln(
            '$pad  doc_comment: "${_escapeYamlString(symbol.docComment!)}"');
      }
    }

    if (symbol.relationships.isNotEmpty) {
      buffer.writeln('$pad  relationships:');
      for (final rel in symbol.relationships) {
        buffer.writeln('$pad    - ${rel.kind}: ${rel.targetName}');
      }
    }
  }

  /// Write folder summary for a dependency.
  void _writeFolderSummary(StringBuffer buffer, FolderSummary dep) {
    buffer.writeln('  - path: ${dep.path}');

    if (dep.docSummary != null) {
      buffer.writeln('    summary: |');
      for (final line in dep.docSummary!.split('\n')) {
        buffer.writeln('      ${_escapeYamlString(line)}');
      }
    }

    if (dep.publicApi.isNotEmpty) {
      buffer.writeln('    public_api:');
      for (final api in dep.publicApi) {
        buffer.writeln('      - "${_escapeYamlString(api)}"');
      }
    }

    if (dep.usedSymbols.isNotEmpty) {
      buffer.writeln('    used_symbols:');
      for (final sym in dep.usedSymbols) {
        buffer.writeln('      - $sym');
      }
    }

    buffer.writeln();
  }

  /// Write package summary.
  void _writePackageSummary(StringBuffer buffer, PackageSummary pkg) {
    buffer.writeln('  - name: ${pkg.name}');

    if (pkg.version != null) {
      buffer.writeln('    version: ${pkg.version}');
    }

    if (pkg.docSummary != null) {
      buffer.writeln('    summary: "${_escapeYamlString(pkg.docSummary!)}"');
    }

    if (pkg.usedSymbols.isNotEmpty) {
      buffer.writeln('    used_symbols:');
      for (final sym in pkg.usedSymbols) {
        buffer.writeln('      - $sym');
      }
    }

    buffer.writeln();
  }

  /// Write dependent usage info.
  void _writeDependentUsage(StringBuffer buffer, DependentUsage dep) {
    buffer.writeln('  - path: ${dep.path}');
    buffer.writeln('    uses:');
    for (final sym in dep.usedSymbols) {
      buffer.writeln('      - $sym');
    }
    buffer.writeln();
  }

  /// Escape special characters for YAML strings.
  String _escapeYamlString(String s) {
    return s
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
  }
}
