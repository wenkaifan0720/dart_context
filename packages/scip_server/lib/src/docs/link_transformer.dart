import 'package:path/path.dart' as p;

import '../index/scip_index.dart';

/// Style for rendering links in documentation.
enum LinkStyle {
  /// Relative paths from the doc file location.
  /// Example: `../../lib/features/auth/auth_service.dart#L42`
  relative,

  /// GitHub-style links with full repository path.
  /// Example: `https://github.com/owner/repo/blob/main/lib/auth.dart#L42`
  github,

  /// Absolute file:// paths.
  /// Example: `file:///Users/me/project/lib/auth.dart`
  absolute,
}

/// Transforms `scip://` URIs in documentation to navigable links.
///
/// This is the "cheap" stage of the two-stage doc pipeline:
/// - Source docs use stable `scip://` URIs
/// - Rendered docs use navigable links (relative, GitHub, absolute)
///
/// Link transformation happens on every file change (cheap) without
/// requiring LLM regeneration.
class LinkTransformer {
  LinkTransformer({
    required this.index,
    required this.docsRoot,
    this.projectRoot,
    this.githubBaseUrl,
  });

  /// SCIP index for resolving symbols.
  final ScipIndex index;

  /// Root directory where rendered docs are stored.
  /// Used to compute relative paths.
  final String docsRoot;

  /// Project root (for absolute paths).
  final String? projectRoot;

  /// Base URL for GitHub links.
  /// Example: `https://github.com/owner/repo/blob/main`
  final String? githubBaseUrl;

  /// Pattern to match scip:// reference definitions in markdown.
  ///
  /// Matches:
  /// - `[label]: scip://path/to/file/Symbol#member`
  /// - `[label]: scip://package@version/path/Symbol#`
  static final _refPattern = RegExp(
    r'\[([^\]]+)\]:\s*scip://([^\s]+)',
    multiLine: true,
  );

  /// Pattern to match scip:// inline links in markdown.
  ///
  /// Matches:
  /// - `[label](scip://path/to/file/Symbol#member)`
  /// - `[label](scip://package@version/path/Symbol#)`
  static final _inlineLinkPattern = RegExp(
    r'\[([^\]]+)\]\(scip://([^)]+)\)',
    multiLine: true,
  );

  /// Transform a source doc to rendered doc.
  ///
  /// Replaces all `scip://` URIs with navigable links based on the
  /// specified [style].
  String transform(String sourceDoc, {LinkStyle style = LinkStyle.relative}) {
    // First, transform reference-style links
    var result = sourceDoc.replaceAllMapped(_refPattern, (match) {
      final label = match.group(1)!;
      final scipUri = match.group(2)!;

      final resolved = resolveUri(scipUri, style: style);
      if (resolved != null) {
        return '[$label]: $resolved';
      } else {
        return '[$label]: #symbol-not-found';
      }
    });

    // Then, transform inline links
    result = result.replaceAllMapped(_inlineLinkPattern, (match) {
      final label = match.group(1)!;
      final scipUri = match.group(2)!;

      final resolved = resolveUri(scipUri, style: style);
      if (resolved != null) {
        return '[$label]($resolved)';
      } else {
        return '[$label](#symbol-not-found)';
      }
    });

    return result;
  }

  /// Resolve a single scip:// URI to a navigable link.
  ///
  /// Returns null if the symbol cannot be found.
  String? resolveUri(String scipUri, {LinkStyle style = LinkStyle.relative}) {
    final parsed = ScipUri.parse(scipUri);
    if (parsed == null) return null;

    // Strategy 1: Try exact symbol ID match
    final symbolId = parsed.toSymbolId();
    final definition = index.findDefinition(symbolId);
    if (definition != null) {
      return _formatLink(
        file: definition.file,
        line: definition.line + 1, // Convert to 1-based
        style: style,
      );
    }

    // Strategy 2: Try looking up by the URI path directly
    final symbol = index.getSymbol(symbolId);
    if (symbol != null && symbol.file != null) {
      final def = index.findDefinition(symbol.symbol);
      if (def != null) {
        return _formatLink(
          file: def.file,
          line: def.line + 1,
          style: style,
        );
      }
    }

    // Strategy 3: Search for symbol by name in the specified file
    // This handles simplified URIs like scip://lib/path/file.dart/SymbolName#
    // Escape regex special characters in the symbol name
    final escapedName = RegExp.escape(parsed.symbolName);
    final symbols = index.findSymbols(escapedName);
    for (final sym in symbols) {
      // Check if the symbol is in the expected file
      if (sym.file != null && parsed.path.contains(sym.file!.replaceAll('`', ''))) {
        final def = index.findDefinition(sym.symbol);
        if (def != null) {
          return _formatLink(
            file: def.file,
            line: def.line + 1,
            style: style,
          );
        }
        // Fall back to file location if no definition found
        return _formatLink(
          file: sym.file!,
          line: 1,
          style: style,
        );
      }
    }

    // Strategy 4: Try partial match on symbol name alone
    if (symbols.isNotEmpty) {
      final firstMatch = symbols.first;
      final def = index.findDefinition(firstMatch.symbol);
      if (def != null) {
        return _formatLink(
          file: def.file,
          line: def.line + 1,
          style: style,
        );
      }
      if (firstMatch.file != null) {
        return _formatLink(
          file: firstMatch.file!,
          line: 1,
          style: style,
        );
      }
    }

    return null;
  }

  /// Format a link based on the style.
  String? _formatLink({
    required String file,
    required int line,
    required LinkStyle style,
  }) {
    switch (style) {
      case LinkStyle.relative:
        // Compute relative path from docsRoot to source file
        final relativePath = p.relative(
          p.join(projectRoot ?? index.projectRoot, file),
          from: docsRoot,
        );
        return '$relativePath#L$line';

      case LinkStyle.github:
        if (githubBaseUrl == null) {
          // Fall back to relative
          return _formatLink(
            file: file,
            line: line,
            style: LinkStyle.relative,
          );
        }
        return '$githubBaseUrl/$file#L$line';

      case LinkStyle.absolute:
        final absolutePath = p.join(projectRoot ?? index.projectRoot, file);
        return 'file://$absolutePath';
    }
  }

  /// Extract all scip:// URIs from a document.
  List<String> extractScipUris(String doc) {
    final uris = <String>[];
    // Extract from reference-style links
    for (final match in _refPattern.allMatches(doc)) {
      uris.add(match.group(2)!);
    }
    // Extract from inline links
    for (final match in _inlineLinkPattern.allMatches(doc)) {
      uris.add(match.group(2)!);
    }
    return uris;
  }

  /// Validate all scip:// URIs in a document.
  ///
  /// Returns a map of URI -> resolution status.
  Map<String, bool> validateUris(String doc) {
    final uris = extractScipUris(doc);
    final results = <String, bool>{};
    for (final uri in uris) {
      results[uri] = resolveUri(uri) != null;
    }
    return results;
  }
}

/// Parsed scip:// URI.
///
/// Format: `scip://[package@version/]path/to/file/SymbolName#[member]`
///
/// Examples:
/// - `scip://lib/auth/service.dart/AuthService#`
/// - `scip://lib/auth/service.dart/AuthService#login().`
/// - `scip://firebase_auth@4.6.0/lib/src/firebase_auth.dart/FirebaseAuth#`
class ScipUri {
  ScipUri({
    this.package,
    this.version,
    required this.path,
    required this.symbolName,
    this.member,
  });

  /// Package name (for external dependencies).
  final String? package;

  /// Package version (for external dependencies).
  final String? version;

  /// Path to the file.
  final String path;

  /// Symbol name (class, function, etc.).
  final String symbolName;

  /// Member name (method, field, etc.).
  final String? member;

  /// Parse a scip:// URI string.
  ///
  /// Returns null if the URI is malformed.
  static ScipUri? parse(String uri) {
    // Remove scip:// prefix if present
    var cleaned = uri;
    if (cleaned.startsWith('scip://')) {
      cleaned = cleaned.substring(7);
    }

    String? package;
    String? version;

    // Check for package@version prefix
    final atIndex = cleaned.indexOf('@');
    if (atIndex > 0) {
      final slashAfterVersion = cleaned.indexOf('/');
      if (slashAfterVersion > atIndex) {
        package = cleaned.substring(0, atIndex);
        version = cleaned.substring(atIndex + 1, slashAfterVersion);
        cleaned = cleaned.substring(slashAfterVersion + 1);
      }
    }

    // Find the # separator between path and symbol
    final hashIndex = cleaned.lastIndexOf('#');
    if (hashIndex < 0) {
      // No hash - try to extract from path
      final lastSlash = cleaned.lastIndexOf('/');
      if (lastSlash < 0) return null;

      return ScipUri(
        package: package,
        version: version,
        path: cleaned.substring(0, lastSlash),
        symbolName: cleaned.substring(lastSlash + 1),
      );
    }

    // Split by # - everything before last / before # is path
    final pathAndSymbol = cleaned.substring(0, hashIndex);
    final member = cleaned.substring(hashIndex + 1);

    final lastSlash = pathAndSymbol.lastIndexOf('/');
    if (lastSlash < 0) return null;

    return ScipUri(
      package: package,
      version: version,
      path: pathAndSymbol.substring(0, lastSlash),
      symbolName: pathAndSymbol.substring(lastSlash + 1),
      member: member.isNotEmpty ? member : null,
    );
  }

  /// Convert to a SCIP symbol ID for lookup.
  ///
  /// This constructs an approximate symbol ID. The actual SCIP symbol ID
  /// format may vary, so we try multiple variations.
  String toSymbolId() {
    final buffer = StringBuffer();

    // For external packages
    if (package != null) {
      buffer.write('scip-dart pub $package ');
      if (version != null) {
        buffer.write('$version ');
      }
    }

    buffer.write('$path/$symbolName#');

    if (member != null) {
      buffer.write(member);
    }

    return buffer.toString();
  }

  @override
  String toString() {
    final buffer = StringBuffer('scip://');
    if (package != null) {
      buffer.write('$package@$version/');
    }
    buffer.write('$path/$symbolName#');
    if (member != null) {
      buffer.write(member);
    }
    return buffer.toString();
  }
}
