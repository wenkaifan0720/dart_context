import '../index/scip_index.dart';

/// Result of a query execution.
sealed class QueryResult {
  const QueryResult();

  /// Convert to human/LLM readable text.
  String toText();

  /// Convert to structured JSON.
  Map<String, dynamic> toJson();

  /// Whether the query found any results.
  bool get isEmpty;

  /// Number of results.
  int get count;
}

/// Result containing symbol definitions.
class DefinitionResult extends QueryResult {
  const DefinitionResult(this.definitions);

  final List<DefinitionMatch> definitions;

  @override
  bool get isEmpty => definitions.isEmpty;

  @override
  int get count => definitions.length;

  @override
  String toText() {
    if (definitions.isEmpty) {
      return 'No definitions found.';
    }

    final buffer = StringBuffer();
    for (final def in definitions) {
      buffer.writeln('## ${def.symbol.name} (${def.symbol.kindString})');
      buffer.writeln('File: ${def.location.location}');
      if (def.symbol.documentation.isNotEmpty) {
        buffer.writeln('');
        buffer.writeln(def.symbol.documentation.join('\n'));
      }
      if (def.source != null) {
        buffer.writeln('');
        buffer.writeln('```dart');
        buffer.writeln(def.source);
        buffer.writeln('```');
      }
      buffer.writeln('');
    }
    return buffer.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'definitions',
        'count': definitions.length,
        'results': definitions
            .map(
              (d) => {
                'symbol': d.symbol.symbol,
                'name': d.symbol.name,
                'kind': d.symbol.kindString,
                'file': d.location.file,
                'line': d.location.line + 1,
                'column': d.location.column + 1,
                if (d.source != null) 'source': d.source,
              },
            )
            .toList(),
      };
}

/// A single definition match.
class DefinitionMatch {
  const DefinitionMatch({
    required this.symbol,
    required this.location,
    this.source,
  });

  final SymbolInfo symbol;
  final OccurrenceInfo location;
  final String? source;
}

/// Result containing references.
class ReferencesResult extends QueryResult {
  const ReferencesResult({
    required this.symbol,
    required this.references,
  });

  final SymbolInfo symbol;
  final List<ReferenceMatch> references;

  @override
  bool get isEmpty => references.isEmpty;

  @override
  int get count => references.length;

  @override
  String toText() {
    if (references.isEmpty) {
      return 'No references found for ${symbol.name}.';
    }

    final buffer = StringBuffer();
    buffer.writeln('## References to ${symbol.name} (${references.length})');
    buffer.writeln('');

    // Group by file
    final byFile = <String, List<ReferenceMatch>>{};
    for (final ref in references) {
      byFile.putIfAbsent(ref.location.file, () => []).add(ref);
    }

    for (final entry in byFile.entries) {
      buffer.writeln('### ${entry.key}');
      for (final ref in entry.value) {
        buffer.writeln('- Line ${ref.location.line + 1}');
        if (ref.context != null) {
          buffer.writeln('  ```dart');
          for (final line in ref.context!.split('\n')) {
            buffer.writeln('  $line');
          }
          buffer.writeln('  ```');
        }
      }
      buffer.writeln('');
    }

    return buffer.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'references',
        'symbol': symbol.symbol,
        'name': symbol.name,
        'count': references.length,
        'results': references
            .map(
              (r) => {
                'file': r.location.file,
                'line': r.location.line + 1,
                'column': r.location.column + 1,
                if (r.context != null) 'context': r.context,
              },
            )
            .toList(),
      };
}

/// A single reference match.
class ReferenceMatch {
  const ReferenceMatch({
    required this.location,
    this.context,
  });

  final OccurrenceInfo location;
  final String? context;
}

/// Result containing class members.
class MembersResult extends QueryResult {
  const MembersResult({
    required this.symbol,
    required this.members,
  });

  final SymbolInfo symbol;
  final List<SymbolInfo> members;

  @override
  bool get isEmpty => members.isEmpty;

  @override
  int get count => members.length;

  @override
  String toText() {
    if (members.isEmpty) {
      return 'No members found for ${symbol.name}.';
    }

    final buffer = StringBuffer();
    buffer.writeln('## Members of ${symbol.name} (${members.length})');
    buffer.writeln('');

    // Group by kind
    final byKind = <String, List<SymbolInfo>>{};
    for (final member in members) {
      byKind.putIfAbsent(member.kindString, () => []).add(member);
    }

    for (final entry in byKind.entries) {
      buffer.writeln('### ${_capitalize(entry.key)}s');
      for (final member in entry.value) {
        buffer.writeln('- ${member.name}');
      }
      buffer.writeln('');
    }

    return buffer.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'members',
        'symbol': symbol.symbol,
        'name': symbol.name,
        'count': members.length,
        'results': members
            .map(
              (m) => {
                'symbol': m.symbol,
                'name': m.name,
                'kind': m.kindString,
              },
            )
            .toList(),
      };

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    final capitalized = '${s[0].toUpperCase()}${s.substring(1)}';
    // Fix common pluralization issues
    if (capitalized.endsWith('ys') && !capitalized.endsWith('ays')) {
      return '${capitalized.substring(0, capitalized.length - 2)}ies';
    }
    return capitalized;
  }
}

/// Result containing symbol search matches.
class SearchResult extends QueryResult {
  const SearchResult(this.symbols);

  final List<SymbolInfo> symbols;

  @override
  bool get isEmpty => symbols.isEmpty;

  @override
  int get count => symbols.length;

  @override
  String toText() {
    if (symbols.isEmpty) {
      return 'No symbols found.';
    }

    final buffer = StringBuffer();
    buffer.writeln('## Found ${symbols.length} symbols');
    buffer.writeln('');

    for (final sym in symbols) {
      final location = sym.file != null ? ' (${sym.file})' : ' (external)';
      buffer.writeln('- **${sym.name}** [${sym.kindString}]$location');
    }

    return buffer.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'search',
        'count': symbols.length,
        'results': symbols
            .map(
              (s) => {
                'symbol': s.symbol,
                'name': s.name,
                'kind': s.kindString,
                if (s.file != null) 'file': s.file,
              },
            )
            .toList(),
      };
}

/// Result containing source code.
class SourceResult extends QueryResult {
  const SourceResult({
    required this.symbol,
    required this.source,
    required this.file,
    required this.startLine,
  });

  final SymbolInfo symbol;
  final String source;
  final String file;
  final int startLine;

  @override
  bool get isEmpty => source.isEmpty;

  @override
  int get count => 1;

  @override
  String toText() {
    final buffer = StringBuffer();
    buffer.writeln('## ${symbol.name} (${symbol.kindString})');
    buffer.writeln('File: $file:${startLine + 1}');
    buffer.writeln('');
    buffer.writeln('```dart');
    buffer.writeln(source);
    buffer.writeln('```');
    return buffer.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'source',
        'symbol': symbol.symbol,
        'name': symbol.name,
        'kind': symbol.kindString,
        'file': file,
        'startLine': startLine + 1,
        'source': source,
      };
}

/// Result containing hierarchy information.
class HierarchyResult extends QueryResult {
  const HierarchyResult({
    required this.symbol,
    required this.supertypes,
    required this.subtypes,
  });

  final SymbolInfo symbol;
  final List<SymbolInfo> supertypes;
  final List<SymbolInfo> subtypes;

  @override
  bool get isEmpty => supertypes.isEmpty && subtypes.isEmpty;

  @override
  int get count => supertypes.length + subtypes.length;

  @override
  String toText() {
    final buffer = StringBuffer();
    buffer.writeln('## Hierarchy of ${symbol.name}');
    buffer.writeln('');

    if (supertypes.isNotEmpty) {
      buffer.writeln('### Supertypes (${supertypes.length})');
      for (final st in supertypes) {
        buffer.writeln('- ${st.name}');
      }
      buffer.writeln('');
    }

    if (subtypes.isNotEmpty) {
      buffer.writeln('### Subtypes (${subtypes.length})');
      for (final st in subtypes) {
        buffer.writeln('- ${st.name}');
      }
      buffer.writeln('');
    }

    if (isEmpty) {
      buffer.writeln('No supertypes or subtypes found.');
    }

    return buffer.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'hierarchy',
        'symbol': symbol.symbol,
        'name': symbol.name,
        'supertypes':
            supertypes.map((s) => {'symbol': s.symbol, 'name': s.name}).toList(),
        'subtypes':
            subtypes.map((s) => {'symbol': s.symbol, 'name': s.name}).toList(),
      };
}

/// Result containing file list.
class FilesResult extends QueryResult {
  const FilesResult(this.files);

  final List<String> files;

  @override
  bool get isEmpty => files.isEmpty;

  @override
  int get count => files.length;

  @override
  String toText() {
    if (files.isEmpty) {
      return 'No files indexed.';
    }

    final buffer = StringBuffer();
    buffer.writeln('## Indexed Files (${files.length})');
    buffer.writeln('');
    for (final file in files) {
      buffer.writeln('- $file');
    }
    return buffer.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'files',
        'count': files.length,
        'files': files,
      };
}

/// Result containing index statistics.
class StatsResult extends QueryResult {
  const StatsResult(this.stats);

  final Map<String, int> stats;

  @override
  bool get isEmpty => false;

  @override
  int get count => 1;

  @override
  String toText() {
    final buffer = StringBuffer();
    buffer.writeln('## Index Statistics');
    buffer.writeln('');
    buffer.writeln('- Files: ${stats['files'] ?? 0}');
    buffer.writeln('- Symbols: ${stats['symbols'] ?? 0}');
    buffer.writeln('- References: ${stats['references'] ?? 0}');
    return buffer.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'stats',
        'stats': stats,
      };
}

/// Result for not found / no match.
class NotFoundResult extends QueryResult {
  const NotFoundResult(this.message);

  final String message;

  @override
  bool get isEmpty => true;

  @override
  int get count => 0;

  @override
  String toText() => message;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'not_found',
        'message': message,
      };
}

/// Result for errors.
class ErrorResult extends QueryResult {
  const ErrorResult(this.error);

  final String error;

  @override
  bool get isEmpty => true;

  @override
  int get count => 0;

  @override
  String toText() => 'Error: $error';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'error',
        'error': error,
      };
}

