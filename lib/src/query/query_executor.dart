import '../index/scip_index.dart';
import 'query_parser.dart';
import 'query_result.dart';

/// Executes queries against a ScipIndex.
class QueryExecutor {
  QueryExecutor(this.index);

  final ScipIndex index;

  /// Execute a query string and return the result.
  Future<QueryResult> execute(String queryString) async {
    try {
      final query = ScipQuery.parse(queryString);
      return executeQuery(query);
    } on FormatException catch (e) {
      return ErrorResult(e.message);
    }
  }

  /// Execute a parsed query.
  Future<QueryResult> executeQuery(ScipQuery query) async {
    return switch (query.action) {
      QueryAction.definition => _findDefinition(query),
      QueryAction.references => _findReferences(query),
      QueryAction.members => _findMembers(query),
      QueryAction.implementations => _findImplementations(query),
      QueryAction.supertypes => _findSupertypes(query),
      QueryAction.subtypes => _findSubtypes(query),
      QueryAction.hierarchy => _findHierarchy(query),
      QueryAction.source => _getSource(query),
      QueryAction.find => _search(query),
      QueryAction.files => _listFiles(),
      QueryAction.stats => _getStats(),
    };
  }

  Future<QueryResult> _findDefinition(ScipQuery query) async {
    final allSymbols = index.findSymbols(query.target).toList();

    if (allSymbols.isEmpty) {
      return NotFoundResult('No symbol found matching "${query.target}"');
    }

    // Filter to primary definitions only (exclude parameters, local variables)
    // and prefer exact name matches
    final primaryKinds = {
      'class',
      'method',
      'function',
      'field',
      'constructor',
      'enum',
      'mixin',
      'extension',
      'getter',
      'setter',
      'property',
    };

    final primarySymbols = allSymbols
        .where((s) => primaryKinds.contains(s.kindString))
        .toList();

    // If we have primary symbols, use those; otherwise fall back to all
    final symbols = primarySymbols.isNotEmpty ? primarySymbols : allSymbols;

    // Sort by relevance: exact name match first, then by kind priority
    symbols.sort((a, b) {
      final aExact = a.name.toLowerCase() == query.target.toLowerCase();
      final bExact = b.name.toLowerCase() == query.target.toLowerCase();
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;

      // Prefer classes/functions over methods/fields
      final kindPriority = {
        'class': 0,
        'function': 1,
        'enum': 2,
        'mixin': 3,
        'extension': 4,
        'method': 5,
        'field': 6,
        'constructor': 7,
        'getter': 8,
        'setter': 9,
      };
      final aPriority = kindPriority[a.kindString] ?? 10;
      final bPriority = kindPriority[b.kindString] ?? 10;
      return aPriority.compareTo(bPriority);
    });

    // For def, only return the best match (or a few if same priority)
    final bestMatch = symbols.first;
    final bestMatches = symbols.where((s) {
      // Include symbols with same name and similar priority
      return s.name.toLowerCase() == bestMatch.name.toLowerCase() &&
          _isPrimaryKind(s.kindString);
    }).take(3); // Limit to top 3 matches

    final definitions = <DefinitionMatch>[];

    for (final sym in bestMatches) {
      final def = index.findDefinition(sym.symbol);
      if (def != null) {
        final source = await index.getSource(sym.symbol);
        definitions.add(
          DefinitionMatch(
            symbol: sym,
            location: def,
            source: source,
          ),
        );
      }
    }

    if (definitions.isEmpty) {
      return NotFoundResult(
        'Symbol "${query.target}" found but no definition available (may be external)',
      );
    }

    return DefinitionResult(definitions);
  }

  bool _isPrimaryKind(String kind) {
    return {
      'class',
      'method',
      'function',
      'enum',
      'mixin',
      'extension',
    }.contains(kind);
  }

  Future<QueryResult> _findReferences(ScipQuery query) async {
    final symbols = index.findSymbols(query.target).toList();

    if (symbols.isEmpty) {
      return NotFoundResult('No symbol found matching "${query.target}"');
    }

    // For now, just use the first matching symbol
    final sym = symbols.first;
    final refs = index.findReferences(sym.symbol);

    final referenceMatches = <ReferenceMatch>[];
    for (final ref in refs) {
      final context = await index.getContext(ref);
      referenceMatches.add(
        ReferenceMatch(
          location: ref,
          context: context,
        ),
      );
    }

    return ReferencesResult(
      symbol: sym,
      references: referenceMatches,
    );
  }

  Future<QueryResult> _findMembers(ScipQuery query) async {
    final symbols = index
        .findSymbols(query.target)
        .where(
          (s) =>
              s.kindString == 'class' ||
              s.kindString == 'mixin' ||
              s.kindString == 'extension' ||
              s.kindString == 'enum',
        )
        .toList();

    if (symbols.isEmpty) {
      return NotFoundResult(
        'No class/mixin/extension found matching "${query.target}"',
      );
    }

    final sym = symbols.first;
    final members = index.membersOf(sym.symbol).toList();

    return MembersResult(
      symbol: sym,
      members: members,
    );
  }

  Future<QueryResult> _findImplementations(ScipQuery query) async {
    final symbols = index.findSymbols(query.target).toList();

    if (symbols.isEmpty) {
      return NotFoundResult('No symbol found matching "${query.target}"');
    }

    final sym = symbols.first;
    final impls = index.findImplementations(sym.symbol).toList();

    return SearchResult(impls);
  }

  Future<QueryResult> _findSupertypes(ScipQuery query) async {
    final symbols = index.findSymbols(query.target).toList();

    if (symbols.isEmpty) {
      return NotFoundResult('No symbol found matching "${query.target}"');
    }

    final sym = symbols.first;
    final supertypes = index.supertypesOf(sym.symbol).toList();

    return HierarchyResult(
      symbol: sym,
      supertypes: supertypes,
      subtypes: const <SymbolInfo>[],
    );
  }

  Future<QueryResult> _findSubtypes(ScipQuery query) async {
    final symbols = index.findSymbols(query.target).toList();

    if (symbols.isEmpty) {
      return NotFoundResult('No symbol found matching "${query.target}"');
    }

    final sym = symbols.first;
    final subtypes = index.subtypesOf(sym.symbol).toList();

    return HierarchyResult(
      symbol: sym,
      supertypes: const <SymbolInfo>[],
      subtypes: subtypes,
    );
  }

  Future<QueryResult> _findHierarchy(ScipQuery query) async {
    final symbols = index.findSymbols(query.target).toList();

    if (symbols.isEmpty) {
      return NotFoundResult('No symbol found matching "${query.target}"');
    }

    final sym = symbols.first;
    final supertypes = index.supertypesOf(sym.symbol).toList();
    final subtypes = index.subtypesOf(sym.symbol).toList();

    return HierarchyResult(
      symbol: sym,
      supertypes: supertypes,
      subtypes: subtypes,
    );
  }

  Future<QueryResult> _getSource(ScipQuery query) async {
    final symbols = index.findSymbols(query.target).toList();

    if (symbols.isEmpty) {
      return NotFoundResult('No symbol found matching "${query.target}"');
    }

    final sym = symbols.first;
    final def = index.findDefinition(sym.symbol);

    if (def == null) {
      return NotFoundResult(
        'Symbol "${query.target}" has no definition (may be external)',
      );
    }

    final source = await index.getSource(sym.symbol);
    if (source == null) {
      return NotFoundResult('Could not read source for "${query.target}"');
    }

    return SourceResult(
      symbol: sym,
      source: source,
      file: def.file,
      startLine: def.line,
    );
  }

  Future<QueryResult> _search(ScipQuery query) async {
    var results = index.findSymbols(query.target);

    // Apply kind filter
    final kind = query.kindFilter;
    if (kind != null) {
      results = results.where((s) => s.kind == kind);
    }

    // Apply path filter
    final pathFilter = query.pathFilter;
    if (pathFilter != null) {
      results = results.where(
        (s) => s.file != null && s.file!.startsWith(pathFilter),
      );
    }

    return SearchResult(results.toList());
  }

  Future<QueryResult> _listFiles() async {
    return FilesResult(index.files.toList()..sort());
  }

  Future<QueryResult> _getStats() async {
    return StatsResult(index.stats);
  }
}

