/// MCP (Model Context Protocol) integration for code_context.
///
/// Provides a mixin that adds the `dart_query` tool to any MCP server.
///
/// Example:
/// ```dart
/// import 'package:code_context/code_context_mcp.dart';
/// import 'package:dart_mcp/server.dart';
///
/// class MyServer extends MCPServer with CodeContextSupport {
///   // Your server implementation
/// }
/// ```
library;

export 'src/mcp/code_context_mcp.dart' show CodeContextSupport;
