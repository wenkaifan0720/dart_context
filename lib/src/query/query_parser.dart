/// Query DSL parser for dart_context.
///
/// Supported queries:
/// - `def <symbol>` - Find definition
/// - `refs <symbol>` - Find references
/// - `members <symbol>` - Get class members
/// - `impls <symbol>` - Find implementations
/// - `supertypes <symbol>` - Get supertypes
/// - `subtypes <symbol>` - Get subtypes
/// - `hierarchy <symbol>` - Full hierarchy (supertypes + subtypes)
/// - `source <symbol>` - Get source code
/// - `find <pattern> [kind:<kind>] [in:<path>]` - Search symbols
/// - `which <symbol>` - Show all matches for disambiguation
///
/// Qualified names:
/// - `refs MyClass.login` - References to login method in MyClass
/// - `def AuthService.authenticate` - Definition of authenticate in AuthService
///
/// Filters (for `find`):
/// - `kind:class` - Filter by symbol kind
/// - `in:lib/` - Filter by file path prefix
///
/// Examples:
/// - `def AuthRepository`
/// - `refs MyClass.login`
/// - `which login`
/// - `members MyClass`
/// - `find Auth* kind:class`
/// - `find * kind:method in:lib/auth/`
library;

// ignore: implementation_imports
import 'package:scip_dart/src/gen/scip.pb.dart' as scip;

/// Parsed query from the DSL.
class ScipQuery {
  ScipQuery._({
    required this.action,
    required this.target,
    required this.filters,
  });

  /// The query action (def, refs, members, etc.)
  final QueryAction action;

  /// The target symbol pattern.
  final String target;

  /// Optional filters (kind, in).
  final Map<String, String> filters;

  /// Parse a query string into a structured query.
  ///
  /// Throws [FormatException] if the query is invalid.
  factory ScipQuery.parse(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw FormatException('Empty query');
    }

    // Tokenize (respecting quoted strings)
    final tokens = _tokenize(trimmed);
    if (tokens.isEmpty) {
      throw FormatException('Empty query');
    }

    // Parse action
    final actionStr = tokens[0].toLowerCase();
    final action = _parseAction(actionStr);

    // Parse target and filters
    String? target;
    final filters = <String, String>{};

    for (var i = 1; i < tokens.length; i++) {
      final token = tokens[i];

      if (token.contains(':')) {
        // It's a filter
        final colonIndex = token.indexOf(':');
        final key = token.substring(0, colonIndex);
        final value = token.substring(colonIndex + 1);
        filters[key] = value;
      } else if (target == null) {
        target = token;
      } else {
        // Multiple targets - join them (e.g., "Class.method")
        target = '$target.$token';
      }
    }

    // Some actions don't require a target
    if (action != QueryAction.files &&
        action != QueryAction.stats &&
        (target == null || target.isEmpty)) {
      throw FormatException('Missing target symbol for action: $actionStr');
    }

    return ScipQuery._(
      action: action,
      target: target ?? '',
      filters: filters,
    );
  }

  /// Tokenize a query string.
  static List<String> _tokenize(String query) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    String? quoteChar;

    for (var i = 0; i < query.length; i++) {
      final char = query[i];

      if ((char == '"' || char == "'") && !inQuotes) {
        inQuotes = true;
        quoteChar = char;
      } else if (char == quoteChar && inQuotes) {
        inQuotes = false;
        quoteChar = null;
      } else if (char == ' ' && !inQuotes) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(char);
      }
    }

    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }

    return tokens;
  }

  /// Parse action string to enum.
  static QueryAction _parseAction(String action) {
    return switch (action) {
      'def' || 'definition' => QueryAction.definition,
      'refs' || 'references' => QueryAction.references,
      'members' => QueryAction.members,
      'impls' || 'implementations' => QueryAction.implementations,
      'supertypes' || 'super' => QueryAction.supertypes,
      'subtypes' || 'sub' => QueryAction.subtypes,
      'hierarchy' => QueryAction.hierarchy,
      'source' || 'src' => QueryAction.source,
      'find' || 'search' => QueryAction.find,
      'which' || 'disambiguate' => QueryAction.which,
      'files' => QueryAction.files,
      'stats' => QueryAction.stats,
      _ => throw FormatException('Unknown action: $action'),
    };
  }

  /// Get the kind filter as a SymbolKind.
  scip.SymbolInformation_Kind? get kindFilter {
    final kindStr = filters['kind'];
    if (kindStr == null) return null;

    return switch (kindStr.toLowerCase()) {
      'class' => scip.SymbolInformation_Kind.Class,
      'method' => scip.SymbolInformation_Kind.Method,
      'function' => scip.SymbolInformation_Kind.Function,
      'field' => scip.SymbolInformation_Kind.Field,
      'constructor' => scip.SymbolInformation_Kind.Constructor,
      'enum' => scip.SymbolInformation_Kind.Enum,
      'enummember' => scip.SymbolInformation_Kind.EnumMember,
      'interface' => scip.SymbolInformation_Kind.Interface,
      'variable' => scip.SymbolInformation_Kind.Variable,
      'property' => scip.SymbolInformation_Kind.Property,
      'parameter' => scip.SymbolInformation_Kind.Parameter,
      'mixin' => scip.SymbolInformation_Kind.Mixin,
      'extension' => scip.SymbolInformation_Kind.Extension,
      'getter' => scip.SymbolInformation_Kind.Getter,
      'setter' => scip.SymbolInformation_Kind.Setter,
      _ => null,
    };
  }

  /// Get the path filter.
  String? get pathFilter => filters['in'];

  /// Check if target is a qualified name (e.g., "MyClass.method").
  bool get isQualified => target.contains('.');

  /// Get the container part of a qualified name (e.g., "MyClass" from "MyClass.method").
  String? get container => isQualified ? target.split('.').first : null;

  /// Get the member part of a qualified name (e.g., "method" from "MyClass.method").
  String get memberName => isQualified ? target.split('.').last : target;

  @override
  String toString() {
    final filterStr =
        filters.entries.map((e) => '${e.key}:${e.value}').join(' ');
    return 'ScipQuery(${action.name} $target${filterStr.isNotEmpty ? ' $filterStr' : ''})';
  }
}

/// Query action types.
enum QueryAction {
  /// Find definition of a symbol.
  definition,

  /// Find all references to a symbol.
  references,

  /// Get members of a class/type.
  members,

  /// Find implementations of a class/interface.
  implementations,

  /// Get supertypes of a class.
  supertypes,

  /// Get subtypes (implementations) of a class.
  subtypes,

  /// Get full hierarchy (supertypes + subtypes).
  hierarchy,

  /// Get source code for a symbol.
  source,

  /// Search for symbols matching a pattern.
  find,

  /// Show all matches for a symbol (disambiguation).
  which,

  /// List all indexed files.
  files,

  /// Get index statistics.
  stats,
}

