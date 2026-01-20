import '../index/scip_index.dart';

/// Result of a query execution.
///
/// All query results implement [toText] for human/LLM-readable output
/// and [toJson] for structured programmatic access.
///
/// Result types:
/// - [DefinitionResult] - Symbol definitions (`def`)
/// - [ReferencesResult] - Symbol references (`refs`)
/// - [MembersResult] - Class/mixin members (`members`)
/// - [SearchResult] - Symbol search matches (`find`)
/// - [SourceResult] - Source code (`source`)
/// - [HierarchyResult] - Type hierarchy (`hierarchy`)
/// - [CallGraphResult] - Call relationships (`calls`, `callers`)
/// - [ImportsResult] - Import/export analysis (`imports`, `exports`)
/// - [FilesResult] - Indexed files (`files`)
/// - [StatsResult] - Index statistics (`stats`)
/// - [PipelineResult] - Aggregated pipe query results
/// - [NotFoundResult] - No matches found
/// - [ErrorResult] - Query error
sealed class QueryResult {
  const QueryResult();

  /// Convert to human/LLM readable text format.
  ///
  /// Output uses Markdown formatting with headers, lists, and code blocks
  /// for optimal display in terminals and LLM interfaces.
  String toText();

  /// Convert to structured JSON for programmatic access.
  ///
  /// All results include a `type` field indicating the result kind,
  /// and a `count` field with the number of matches.
  Map<String, dynamic> toJson();

  /// Whether the query found any results.
  bool get isEmpty;

  /// Number of results (0 for errors/not found).
  int get count;
}

/// Result containing symbol definitions from `def` queries.
///
/// Each definition includes:
/// - Symbol metadata (name, kind, documentation)
/// - File location (path, line, column)
/// - Source code snippet (when available)
///
/// Example output:
/// ```
/// ## MyClass (class)
/// File: lib/my_class.dart:5
///
/// A description of MyClass.
///
/// ```dart
/// class MyClass { ... }
/// ```
/// ```
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

/// Result containing references from `refs` queries.
///
/// References are grouped by file and include:
/// - File path
/// - Line and column numbers
/// - Context snippet showing the reference
///
/// Example output:
/// ```
/// ## References to login (5)
///
/// ### lib/auth/service.dart
/// - Line 42
///   ```dart
///   await login(credentials);
///   ```
/// ```
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
    this.sourceRoot,
  });

  final OccurrenceInfo location;
  final String? context;

  /// Source root for resolving file paths (useful in workspace mode).
  final String? sourceRoot;

  /// Get the full file path.
  String get fullPath =>
      sourceRoot != null ? '$sourceRoot/${location.file}' : location.file;
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
      buffer.writeln('### ${_pluralize(entry.key)}');
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

}

/// Result containing symbol search matches.
///
/// Output includes container context (like `which` used to provide):
/// ```
/// ## Found 3 symbols
///
/// 1. login [method] in AuthService (lib/auth/service.dart)
/// 2. login [method] in UserRepository (lib/data/repo.dart)
/// 3. LoginPage [class] (lib/ui/login_page.dart)
/// ```
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

    for (var i = 0; i < symbols.length; i++) {
      final sym = symbols[i];
      final container = _extractContainer(sym.symbol);
      final containerStr = container != null ? ' in $container' : '';
      final location = sym.file != null ? ' (${sym.file})' : '';

      buffer.writeln('${i + 1}. ${sym.name} [${sym.kindString}]$containerStr$location');
    }

    return buffer.toString().trimRight();
  }

  /// Extract the container (parent class/mixin) from a SCIP symbol ID.
  ///
  /// Symbol format: `scheme package version path/Class#method().`
  /// Returns the class name if this is a member, null otherwise.
  static String? _extractContainer(String symbolId) {
    // Look for Class#member pattern
    final match = RegExp(r'/([A-Za-z_][A-Za-z0-9_]*)#[^/]+$').firstMatch(symbolId);
    if (match != null) {
      return match.group(1);
    }
    return null;
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
                if (_extractContainer(s.symbol) != null)
                  'container': _extractContainer(s.symbol),
              },
            )
            .toList(),
      };
}

/// Result containing symbol signature (without body).
///
/// Signatures show the declaration without implementation details:
/// - Classes: full class with method signatures (bodies as `{}`)
/// - Methods: `Future<User> login(String email, String password) {}`
/// - Fields: `final String name;`
///
/// Useful for quick API exploration without reading full source.
class SignatureResult extends QueryResult {
  const SignatureResult({
    required this.symbol,
    required this.signature,
    required this.file,
    required this.line,
  });

  final SymbolInfo symbol;
  final String signature;
  final String file;
  final int line;

  @override
  bool get isEmpty => signature.isEmpty;

  @override
  int get count => 1;

  @override
  String toText() {
    final buffer = StringBuffer();
    buffer.writeln('## ${symbol.name} (${symbol.kindString})');
    buffer.writeln('File: $file:${line + 1}');
    buffer.writeln('');
    buffer.writeln('```dart');
    buffer.writeln(signature);
    buffer.writeln('```');
    return buffer.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'signature',
        'symbol': symbol.symbol,
        'name': symbol.name,
        'kind': symbol.kindString,
        'file': file,
        'line': line + 1,
        'signature': signature,
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
        'supertypes': supertypes
            .map((s) => {'symbol': s.symbol, 'name': s.name})
            .toList(),
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

/// Result containing symbols in a specific file.
///
/// Used by the `symbols <file>` query to list all symbols defined in a file.
class FileSymbolsResult extends QueryResult {
  const FileSymbolsResult({
    required this.file,
    required this.symbols,
  });

  final String file;
  final List<SymbolInfo> symbols;

  @override
  bool get isEmpty => symbols.isEmpty;

  @override
  int get count => symbols.length;

  @override
  String toText() {
    if (symbols.isEmpty) {
      return 'No symbols found in $file.';
    }

    final buffer = StringBuffer();
    buffer.writeln('## Symbols in $file (${symbols.length})');
    buffer.writeln('');

    // Group by kind for better readability
    final byKind = <String, List<SymbolInfo>>{};
    for (final sym in symbols) {
      byKind.putIfAbsent(sym.kindString, () => []).add(sym);
    }

    for (final kind in byKind.keys) {
      final kindSymbols = byKind[kind]!;
      buffer.writeln('### ${kind}s (${kindSymbols.length})');
      for (final sym in kindSymbols) {
        buffer.writeln('- ${sym.name} [${sym.kindString}]');
      }
      buffer.writeln('');
    }

    return buffer.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'file_symbols',
        'file': file,
        'count': symbols.length,
        'symbols': symbols.map((s) => {
          'name': s.name,
          'kind': s.kindString,
          'symbol': s.symbol,
        }).toList(),
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
    if (stats.containsKey('packages')) {
      buffer.writeln('- Packages: ${stats['packages']}');
    }
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

/// Result containing aggregated references from multiple symbols.
class AggregatedReferencesResult extends QueryResult {
  const AggregatedReferencesResult({
    required this.query,
    required this.symbolRefs,
  });

  final String query;
  final List<SymbolReferences> symbolRefs;

  @override
  bool get isEmpty => symbolRefs.every((sr) => sr.references.isEmpty);

  @override
  int get count => symbolRefs.fold(0, (sum, sr) => sum + sr.references.length);

  @override
  String toText() {
    if (isEmpty) {
      return 'No references found for "$query".';
    }

    final buffer = StringBuffer();
    buffer.writeln(
        '## References to "$query" (${symbolRefs.length} symbols, $count total refs)',);
    buffer.writeln('');

    for (final sr in symbolRefs) {
      final container = sr.container != null ? '${sr.container}.' : '';
      buffer.writeln(
          '### $container${sr.symbol.name} [${sr.symbol.kindString}] (${sr.references.length} refs)',);
      if (sr.symbol.file != null) {
        buffer.writeln('Defined in: ${sr.symbol.file}');
      }
      buffer.writeln('');

      // Group by file
      final byFile = <String, List<ReferenceMatch>>{};
      for (final ref in sr.references) {
        byFile.putIfAbsent(ref.location.file, () => []).add(ref);
      }

      for (final entry in byFile.entries) {
        buffer.writeln('  **${entry.key}**');
        for (final ref in entry.value) {
          buffer.writeln('  - Line ${ref.location.line + 1}');
        }
      }
      buffer.writeln('');
    }

    return buffer.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'aggregated_references',
        'query': query,
        'totalRefs': count,
        'symbols': symbolRefs
            .map(
              (sr) => {
                'symbol': sr.symbol.symbol,
                'name': sr.symbol.name,
                'kind': sr.symbol.kindString,
                if (sr.container != null) 'container': sr.container,
                'refCount': sr.references.length,
                'references': sr.references
                    .map(
                      (r) => {
                        'file': r.location.file,
                        'line': r.location.line + 1,
                        'column': r.location.column + 1,
                      },
                    )
                    .toList(),
              },
            )
            .toList(),
      };
}

/// References for a single symbol (used in aggregated results).
class SymbolReferences {
  const SymbolReferences({
    required this.symbol,
    required this.references,
    this.container,
  });

  final SymbolInfo symbol;
  final List<ReferenceMatch> references;
  final String? container;
}

/// Result of a call graph query.
class CallGraphResult extends QueryResult {
  const CallGraphResult({
    required this.symbol,
    required this.direction,
    required this.connections,
  });

  final SymbolInfo symbol;
  final String direction; // "calls" or "callers"
  final List<SymbolInfo> connections;

  @override
  bool get isEmpty => connections.isEmpty;

  @override
  int get count => connections.length;

  @override
  String toText() {
    if (connections.isEmpty) {
      return direction == 'calls'
          ? '${symbol.name} does not call any symbols.'
          : '${symbol.name} is not called by any symbols.';
    }

    final buffer = StringBuffer();
    final verb = direction == 'calls' ? 'calls' : 'is called by';
    buffer.writeln('## ${symbol.name} $verb ${connections.length} symbols:');
    buffer.writeln('');

    // Group by kind
    final byKind = <String, List<SymbolInfo>>{};
    for (final conn in connections) {
      final kind = conn.kindString;
      byKind.putIfAbsent(kind, () => []).add(conn);
    }

    for (final entry in byKind.entries) {
      buffer.writeln('### ${_pluralize(entry.key)} (${entry.value.length})');
      for (final sym in entry.value) {
        final file = sym.file ?? 'external';
        buffer.writeln('- `${sym.name}` ($file)');
      }
      buffer.writeln('');
    }

    return buffer.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'call_graph',
        'symbol': symbol.name,
        'direction': direction,
        'count': connections.length,
        'connections': connections
            .map(
              (c) => {
                'name': c.name,
                'kind': c.kindString,
                'file': c.file,
              },
            )
            .toList(),
      };
}

/// Result of imports/exports analysis.
class ImportsResult extends QueryResult {
  const ImportsResult({
    required this.file,
    required this.imports,
    required this.exports,
    this.importedSymbols = const [],
    this.exportedSymbols = const [],
  });

  final String file;
  final List<String> imports; // Import paths
  final List<String> exports; // Export paths/names
  final List<SymbolInfo> importedSymbols; // Symbols from imported files
  final List<SymbolInfo> exportedSymbols; // Symbols exported from this file

  @override
  bool get isEmpty => imports.isEmpty && exports.isEmpty;

  @override
  int get count => imports.length + exports.length;

  @override
  String toText() {
    final buffer = StringBuffer();
    buffer.writeln('## $file');
    buffer.writeln('');

    if (imports.isNotEmpty) {
      buffer.writeln('### Imports (${imports.length})');
      for (final imp in imports) {
        buffer.writeln('- $imp');
      }
      buffer.writeln('');
    }

    if (exports.isNotEmpty) {
      buffer.writeln('### Exports (${exports.length})');
      for (final exp in exports) {
        buffer.writeln('- $exp');
      }
      buffer.writeln('');
    }

    if (isEmpty) {
      buffer.writeln('No imports or exports found.');
    }

    return buffer.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'imports',
        'file': file,
        'imports': imports,
        'exports': exports,
      };
}

/// Result of a pipeline query (aggregation of multiple results).
class PipelineResult extends QueryResult {
  const PipelineResult({
    required this.action,
    required this.results,
  });

  final String action;
  final List<QueryResult> results;

  @override
  bool get isEmpty => results.isEmpty || results.every((r) => r.isEmpty);

  @override
  int get count => results.fold(0, (sum, r) => sum + r.count);

  @override
  String toText() {
    if (results.isEmpty) {
      return 'Pipeline produced no results.';
    }

    final buffer = StringBuffer();
    buffer.writeln('## Pipeline Results: $action (${results.length} queries)');
    buffer.writeln('');

    for (var i = 0; i < results.length; i++) {
      buffer.writeln('### Result ${i + 1}');
      buffer.writeln(results[i].toText());
      buffer.writeln('');
    }

    return buffer.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'pipeline',
        'action': action,
        'count': results.length,
        'totalCount': count,
        'results': results.map((r) => r.toJson()).toList(),
      };
}

/// Properly pluralize a kind string.
///
/// Handles common pluralization rules:
/// - 'class' → 'classes'
/// - 'alias' → 'aliases' (typealias → type aliases)
/// - 'property' → 'properties'
/// - 'method' → 'methods'
String _pluralize(String kind) {
  // Special cases
  switch (kind) {
    case 'class':
      return 'Classes';
    case 'typealias':
      return 'Type Aliases';
    case 'property':
      return 'Properties';
    case 'unspecifiedkind':
      return 'Other';
  }

  // Capitalize and add 's'
  final capitalized = kind.isEmpty
      ? kind
      : '${kind[0].toUpperCase()}${kind.substring(1)}';

  // Words ending in 's', 'x', 'z', 'ch', 'sh' add 'es'
  if (kind.endsWith('s') ||
      kind.endsWith('x') ||
      kind.endsWith('z') ||
      kind.endsWith('ch') ||
      kind.endsWith('sh')) {
    return '${capitalized}es';
  }

  // Words ending in consonant + 'y' → 'ies'
  if (kind.endsWith('y') && kind.length > 1) {
    final beforeY = kind[kind.length - 2];
    if (!'aeiou'.contains(beforeY)) {
      return '${capitalized.substring(0, capitalized.length - 1)}ies';
    }
  }

  return '${capitalized}s';
}
