// Copyright (c) 2025. Code intelligence MCP server.
///
/// This server provides semantic code intelligence via MCP.
///
/// ## Usage with Cursor
///
/// Add to ~/.cursor/mcp.json:
/// ```json
/// {
///   "mcpServers": {
///     "code_context": {
///       "command": "dart",
///       "args": ["run", "/path/to/code_context/bin/mcp_server.dart"]
///     }
///   }
/// }
/// ```
///
/// ## Available Tools
///
/// - `dart_query` - Query Dart codebase with DSL
/// - `dart_index_flutter` - Index Flutter SDK packages
/// - `dart_index_deps` - Index pub dependencies
/// - `dart_refresh` - Refresh project index
/// - `dart_status` - Show index status
library;

import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:code_context/code_context_mcp.dart';

void main() {
  // Create the server and connect it to stdio.
  CodeContextServer(stdioChannel(input: io.stdin, output: io.stdout));
}

/// MCP server with code intelligence support.
base class CodeContextServer extends MCPServer
    with
        LoggingSupport,
        ToolsSupport,
        RootsTrackingSupport,
        CodeContextSupport {
  CodeContextServer(super.channel)
      : super.fromStreamChannel(
          implementation: Implementation(
            name: 'code_context',
            version: '1.0.0',
          ),
          instructions: '''Code intelligence server.

Use dart_status to check index status.
Use dart_index_flutter to index Flutter SDK (one-time setup).
Use dart_index_deps to index project dependencies.
Use dart_query to query the codebase with DSL.

Example queries:
- "def AuthRepository" - Find definition
- "refs login" - Find references  
- "hierarchy MyWidget" - Type hierarchy
- "grep /TODO|FIXME/ -l" - Search source code
''',
        );
}
