import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../index/scip_index.dart' show ScipIndex, SymbolInfo;
import '../doc_manifest.dart';
import 'llm_service.dart';

/// Handler function for a doc generation tool.
typedef DocToolHandler = FutureOr<String> Function(Map<String, dynamic> args);

/// Registry of tools available to the doc generation agent.
class DocToolRegistry {
  DocToolRegistry({
    required this.projectRoot,
    required this.scipIndex,
    required this.docsPath,
    this.manifest,
  });

  final String projectRoot;
  final ScipIndex scipIndex;
  final String docsPath;
  final DocManifest? manifest;

  /// Get all tool definitions for the LLM.
  List<LlmTool> get tools => [
        _listFolderTool,
        _readFileTool,
        _queryScipTool,
        _readSubfolderDocTool,
        _getPublicApiTool,
      ];

  /// Execute a tool by name.
  Future<String> executeTool(String name, Map<String, dynamic> args) async {
    final handler = _handlers[name];
    if (handler == null) {
      return 'Error: Unknown tool "$name". Available tools: ${_handlers.keys.join(', ')}';
    }
    try {
      return await handler(args);
    } catch (e) {
      return 'Error executing $name: $e';
    }
  }

  Map<String, DocToolHandler> get _handlers => {
        'list_folder': _handleListFolder,
        'read_file': _handleReadFile,
        'query_scip': _handleQueryScip,
        'read_subfolder_doc': _handleReadSubfolderDoc,
        'get_public_api': _handleGetPublicApi,
      };

  // ===== Tool Definitions =====

  LlmTool get _listFolderTool => const LlmTool(
        name: 'list_folder',
        description: '''
List the contents of a folder in the project.
Returns files and subfolders with basic metadata.
Use this to understand the structure before diving into specific files.
''',
        parameters: {
          'path': LlmToolParameter(
            type: 'string',
            description:
                'Relative path to the folder from project root (e.g., "lib/features/auth")',
          ),
        },
        required: ['path'],
      );

  LlmTool get _readFileTool => const LlmTool(
        name: 'read_file',
        description: '''
Read the contents of a source file.
Returns the file content with line numbers for reference.
Use sparingly - prefer get_public_api for understanding interfaces.
''',
        parameters: {
          'path': LlmToolParameter(
            type: 'string',
            description: 'Relative path to the file from project root',
          ),
          'start_line': LlmToolParameter(
            type: 'integer',
            description:
                'Optional: Start line number (1-indexed). Omit to read from beginning.',
          ),
          'end_line': LlmToolParameter(
            type: 'integer',
            description:
                'Optional: End line number (inclusive). Omit to read to end.',
          ),
        },
        required: ['path'],
      );

  LlmTool get _queryScipTool => const LlmTool(
        name: 'query_scip',
        description: '''
Query the SCIP index for semantic code information.
Can find definitions, references, type hierarchy, and more.
''',
        parameters: {
          'query_type': LlmToolParameter(
            type: 'string',
            description: 'Type of query to execute',
            enumValues: [
              'definitions', // Find definitions in a path
              'references', // Find references to a symbol
              'hierarchy', // Get type hierarchy for a class
              'relationships', // Get symbol relationships (extends, implements, etc.)
              'calls', // Find call sites
            ],
          ),
          'path': LlmToolParameter(
            type: 'string',
            description: 'File or folder path to search in',
          ),
          'symbol': LlmToolParameter(
            type: 'string',
            description:
                'Optional: Symbol name to search for (for references, hierarchy, calls)',
          ),
        },
        required: ['query_type', 'path'],
      );

  LlmTool get _readSubfolderDocTool => const LlmTool(
        name: 'read_subfolder_doc',
        description: '''
Read the already-generated documentation for a subfolder.
Use this to understand what a subfolder does without reading all its files.
Only works for folders that have been documented (bottom-up generation).
''',
        parameters: {
          'path': LlmToolParameter(
            type: 'string',
            description:
                'Relative path to the subfolder from project root',
          ),
        },
        required: ['path'],
      );

  LlmTool get _getPublicApiTool => const LlmTool(
        name: 'get_public_api',
        description: '''
Get the public API signatures for a FILE (not a folder).
Returns class, function, and variable declarations without implementation details.
Use this to understand what a specific file exposes without reading all its code.
For folders, use list_folder first, then call this on interesting files.
''',
        parameters: {
          'path': LlmToolParameter(
            type: 'string',
            description:
                'Relative path to a .dart FILE from project root (e.g., "lib/src/button.dart")',
          ),
        },
        required: ['path'],
      );

  // ===== Tool Handlers =====

  Future<String> _handleListFolder(Map<String, dynamic> args) async {
    final relativePath = args['path'] as String;
    final absolutePath = p.join(projectRoot, relativePath);
    final dir = Directory(absolutePath);

    if (!dir.existsSync()) {
      return 'Error: Folder "$relativePath" does not exist.';
    }

    final buffer = StringBuffer();
    buffer.writeln('Contents of $relativePath:');
    buffer.writeln();

    final entries = dir.listSync();
    final files = <FileSystemEntity>[];
    final folders = <FileSystemEntity>[];

    for (final entry in entries) {
      if (entry is File) {
        files.add(entry);
      } else if (entry is Directory) {
        folders.add(entry);
      }
    }

    // List folders first
    if (folders.isNotEmpty) {
      buffer.writeln('Folders:');
      for (final folder in folders) {
        final name = p.basename(folder.path);
        if (name.startsWith('.')) continue; // Skip hidden
        
        // Check if this subfolder has docs
        final subfolderRelPath = p.join(relativePath, name);
        final hasDoc = _hasDocumentation(subfolderRelPath);
        buffer.writeln('  📁 $name${hasDoc ? ' [documented]' : ''}');
      }
      buffer.writeln();
    }

    // List files
    if (files.isNotEmpty) {
      buffer.writeln('Files:');
      for (final file in files) {
        final name = p.basename(file.path);
        if (name.startsWith('.')) continue; // Skip hidden
        
        final size = file.statSync().size;
        final sizeStr = _formatSize(size);
        buffer.writeln('  📄 $name ($sizeStr)');
      }
    }

    return buffer.toString();
  }

  Future<String> _handleReadFile(Map<String, dynamic> args) async {
    final relativePath = args['path'] as String;
    final startLine = args['start_line'] as int?;
    final endLine = args['end_line'] as int?;

    final absolutePath = p.join(projectRoot, relativePath);
    final file = File(absolutePath);

    if (!file.existsSync()) {
      return 'Error: File "$relativePath" does not exist.';
    }

    final lines = file.readAsLinesSync();
    final start = (startLine ?? 1) - 1; // Convert to 0-indexed
    final end = endLine ?? lines.length;

    if (start < 0 || start >= lines.length) {
      return 'Error: Start line $startLine is out of range (file has ${lines.length} lines).';
    }

    final buffer = StringBuffer();
    buffer.writeln('File: $relativePath');
    if (startLine != null || endLine != null) {
      buffer.writeln('Lines: ${start + 1}-$end of ${lines.length}');
    }
    buffer.writeln('---');

    for (var i = start; i < end && i < lines.length; i++) {
      final lineNum = (i + 1).toString().padLeft(4);
      buffer.writeln('$lineNum| ${lines[i]}');
    }

    return buffer.toString();
  }

  Future<String> _handleQueryScip(Map<String, dynamic> args) async {
    final queryType = args['query_type'] as String;
    final path = args['path'] as String;
    final symbol = args['symbol'] as String?;

    final buffer = StringBuffer();
    buffer.writeln('SCIP Query: $queryType');
    buffer.writeln('Path: $path');
    if (symbol != null) {
      buffer.writeln('Symbol: $symbol');
    }
    buffer.writeln('---');

    switch (queryType) {
      case 'definitions':
        final symbols = _getSymbolsInPath(path);
        for (final sym in symbols) {
          buffer.writeln('${sym.kindString} ${sym.name}');
          if (sym.documentation.isNotEmpty) {
            buffer.writeln('  Doc: ${sym.documentation.first}');
          }
        }

      case 'references':
        if (symbol == null) {
          return 'Error: "symbol" parameter required for references query.';
        }
        final symbols = _getSymbolsInPath(path);
        for (final sym in symbols) {
          if (sym.name.contains(symbol)) {
            final refs = scipIndex.findReferences(sym.symbol);
            buffer.writeln('References to ${sym.name}:');
            for (final ref in refs.take(10)) {
              buffer.writeln('  - ${ref.file}:${ref.line}');
            }
            if (refs.length > 10) {
              buffer.writeln('  ... and ${refs.length - 10} more');
            }
          }
        }

      case 'hierarchy':
        if (symbol == null) {
          return 'Error: "symbol" parameter required for hierarchy query.';
        }
        final symbols = _getSymbolsInPath(path);
        for (final sym in symbols) {
          if (sym.name.contains(symbol)) {
            buffer.writeln('Type hierarchy for ${sym.name}:');
            for (final rel in sym.relationships) {
              buffer.writeln('  ${rel.symbol}: ${rel.isImplementation ? 'implements' : 'extends'}');
            }
          }
        }

      case 'relationships':
        final symbols = _getSymbolsInPath(path);
        for (final sym in symbols) {
          if (sym.relationships.isNotEmpty) {
            buffer.writeln('${sym.name}:');
            for (final rel in sym.relationships) {
              final relType = rel.isImplementation
                  ? 'implements'
                  : rel.isTypeDefinition
                      ? 'type'
                      : 'other';
              buffer.writeln('  $relType: ${rel.symbol.split('/').last}');
            }
          }
        }

      case 'calls':
        if (symbol == null) {
          return 'Error: "symbol" parameter required for calls query.';
        }
        final symbols = _getSymbolsInPath(path);
        for (final sym in symbols) {
          if (sym.name.contains(symbol)) {
            final refs = scipIndex.findReferences(sym.symbol);
            buffer.writeln('Call sites for ${sym.name}:');
            for (final ref in refs.take(10)) {
              buffer.writeln('  - ${ref.file}:${ref.line}');
            }
          }
        }

      default:
        return 'Error: Unknown query type "$queryType".';
    }

    return buffer.toString();
  }

  /// Get all symbols in a path (folder or file).
  Iterable<SymbolInfo> _getSymbolsInPath(String path) {
    // If path ends with .dart, it's a file
    if (path.endsWith('.dart')) {
      return scipIndex.symbolsInFile(path);
    }
    // Otherwise, get all symbols in files under this path
    return scipIndex.allSymbols.where((sym) {
      final file = sym.file;
      return file != null && file.startsWith(path);
    });
  }

  Future<String> _handleReadSubfolderDoc(Map<String, dynamic> args) async {
    final relativePath = args['path'] as String;
    final docPath = p.join(docsPath, 'folders', relativePath, 'README.md');
    final file = File(docPath);

    if (!file.existsSync()) {
      return 'Error: No documentation found for "$relativePath". '
          'It may not have been generated yet.';
    }

    final content = file.readAsStringSync();
    return '''
Documentation for: $relativePath
---
$content
''';
  }

  Future<String> _handleGetPublicApi(Map<String, dynamic> args) async {
    final relativePath = args['path'] as String;
    
    // Enforce file-level only to prevent token explosion
    if (!relativePath.endsWith('.dart')) {
      return 'Error: get_public_api only works on .dart files, not folders.\n'
          'Use list_folder to see files, then call get_public_api on specific files.\n'
          'Example: get_public_api("lib/src/components/button.dart")';
    }
    
    final buffer = StringBuffer();
    buffer.writeln('Public API for: $relativePath');
    buffer.writeln('---');

    final symbols = scipIndex.symbolsInFile(relativePath);
    final publicSymbols = symbols.where((s) => !s.name.startsWith('_')).toList();

    if (publicSymbols.isEmpty) {
      buffer.writeln('No public symbols found in this file.');
      return buffer.toString();
    }

    for (final sym in publicSymbols) {
      final kind = sym.kindString;
      final name = sym.name;
      final def = scipIndex.findDefinition(sym.symbol);
      final lineInfo = def != null ? ' (line ${def.line + 1})' : '';
      
      buffer.writeln('- $kind $name$lineInfo');
      
      // Include doc comment if short
      if (sym.documentation.isNotEmpty) {
        final doc = sym.documentation.first;
        if (doc.length < 150) {
          buffer.writeln('  /// $doc');
        } else {
          buffer.writeln('  /// ${doc.substring(0, 100)}...');
        }
      }
      
      // Include signature if available
      if (sym.displayName != null && sym.displayName != name) {
        buffer.writeln('  signature: ${sym.displayName}');
      }
    }

    buffer.writeln();
    buffer.writeln('Total: ${publicSymbols.length} public symbols');

    return buffer.toString();
  }

  // ===== Helpers =====

  bool _hasDocumentation(String relativePath) {
    final docPath = p.join(docsPath, 'folders', relativePath, 'README.md');
    return File(docPath).existsSync();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
