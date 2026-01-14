#!/usr/bin/env dart

/// SCIP Protocol Server.
///
/// A JSON-RPC 2.0 server that provides semantic code intelligence.
///
/// ## Usage
///
/// ```bash
/// # Run over stdio (default)
/// dart run code_context:scip_server
///
/// # Run as TCP server
/// dart run code_context:scip_server --tcp --port 3333
/// ```
///
/// ## Protocol
///
/// The server communicates using JSON-RPC 2.0 over newline-delimited JSON.
///
/// ### Methods
///
/// - `initialize` - Initialize a project
///   - params: `{ rootPath: string, languageId: "dart", useCache?: boolean }`
///   - result: `{ success: boolean, projectName: string, fileCount: int, symbolCount: int }`
///
/// - `query` - Execute a DSL query
///   - params: `{ query: string, format?: "text" | "json" }`
///   - result: `{ success: boolean, result?: any, error?: string }`
///
/// - `status` - Get index status
///   - result: `{ initialized: boolean, languageId?: string, fileCount?: int, ... }`
///
/// - `shutdown` - Graceful shutdown
///   - result: `{ success: boolean }`
///
/// - `file/didChange` - Notify of file change (incremental update)
///   - params: `{ path: string }`
///
/// - `file/didDelete` - Notify of file deletion
///   - params: `{ path: string }`
///
/// ## Example Session
///
/// ```json
/// -> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"rootPath":"/my/project","languageId":"dart"}}
/// <- {"jsonrpc":"2.0","id":1,"result":{"success":true,"projectName":"project","fileCount":42,"symbolCount":1234}}
///
/// -> {"jsonrpc":"2.0","id":2,"method":"query","params":{"query":"def AuthService"}}
/// <- {"jsonrpc":"2.0","id":2,"result":{"success":true,"result":"AuthService [class] ..."}}
///
/// -> {"jsonrpc":"2.0","id":3,"method":"shutdown"}
/// <- {"jsonrpc":"2.0","id":3,"result":{"success":true}}
/// ```
library;

import 'dart:io';

import 'package:code_context/code_context.dart';

void main(List<String> args) async {
  final isTcp = args.contains('--tcp');
  final portIndex = args.indexOf('--port');
  final hostIndex = args.indexOf('--host');
  final help = args.contains('--help') || args.contains('-h');

  if (help) {
    stderr.writeln('''
SCIP Protocol Server

Usage: dart run code_context:scip_server [options]

Options:
  --tcp           Run as TCP server (default: stdio)
  --port <port>   TCP port to listen on (default: 3333)
  --host <host>   Host to bind to (default: localhost)
  -h, --help      Show this help message

Protocol:
  The server communicates using JSON-RPC 2.0 over newline-delimited JSON.
  
  Methods:
    initialize     Initialize a project
    query          Execute a DSL query
    status         Get index status
    shutdown       Graceful shutdown
    file/didChange Notify of file change
    file/didDelete Notify of file deletion

Example:
  # Start server over stdio
  dart run code_context:scip_server

  # Start TCP server on port 3333
  dart run code_context:scip_server --tcp --port 3333
''');
    return;
  }

  final port = portIndex != -1 && portIndex + 1 < args.length
      ? int.tryParse(args[portIndex + 1]) ?? 3333
      : 3333;
  final host = hostIndex != -1 && hostIndex + 1 < args.length
      ? args[hostIndex + 1]
      : 'localhost';

  // Create server with Dart binding
  final server = ScipServer();
  server.registerBinding(DartBinding());

  if (isTcp) {
    final socket = await server.serveTcp(port: port, host: host);
    stderr.writeln(
      'SCIP Server listening on ${socket.address.host}:${socket.port}',
    );
    stderr.writeln('Send JSON-RPC 2.0 messages (one per line)');
    stderr.writeln('Press Ctrl+C to stop.');

    // Wait for shutdown signal
    ProcessSignal.sigint.watch().listen((_) async {
      stderr.writeln('Shutting down...');
      await socket.close();
      exit(0);
    });
  } else {
    stderr.writeln('SCIP Server running over stdio');
    stderr.writeln('Send JSON-RPC 2.0 messages to stdin (one per line)');
    await server.serveStdio();
  }
}
