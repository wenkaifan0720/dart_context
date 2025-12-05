// ignore_for_file: avoid_print

/// Example usage of dart_context.
///
/// Run with: `dart run example/example.dart /path/to/dart/project`
library;

import 'dart:io';

import 'package:dart_context/dart_context.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run example/example.dart <project_path>');
    print('');
    print('Example: dart run example/example.dart .');
    exit(1);
  }

  final projectPath = args.first;
  print('Opening project: $projectPath\n');

  // Open a Dart project
  final context = await DartContext.open(projectPath);

  try {
    // ═══════════════════════════════════════════════════════════════════════
    // BASIC QUERIES
    // ═══════════════════════════════════════════════════════════════════════

    print('═══ Index Statistics ═══');
    final stats = await context.query('stats');
    print(stats.toText());
    print('');

    print('═══ List Files ═══');
    final files = await context.query('files');
    print('Found ${files.count} files');
    print('');

    // ═══════════════════════════════════════════════════════════════════════
    // SYMBOL SEARCHES
    // ═══════════════════════════════════════════════════════════════════════

    print('═══ Find All Classes ═══');
    final classes = await context.query('find * kind:class');
    print(classes.toText());
    print('');

    print('═══ Find Symbols Starting with "D" ═══');
    final dSymbols = await context.query('find D*');
    print(dSymbols.toText());
    print('');

    // ═══════════════════════════════════════════════════════════════════════
    // PATTERN MATCHING
    // ═══════════════════════════════════════════════════════════════════════

    print('═══ Fuzzy Search (typo-tolerant) ═══');
    final fuzzy = await context.query('find ~contxt'); // finds "context"
    print(fuzzy.toText());
    print('');

    print('═══ Regex Search ═══');
    final regex = await context.query('find /^[A-Z].*Result\$/');
    print(regex.toText());
    print('');

    // ═══════════════════════════════════════════════════════════════════════
    // GREP (SOURCE CODE SEARCH)
    // ═══════════════════════════════════════════════════════════════════════

    print('═══ Grep for TODOs ═══');
    final todos = await context.query('grep /TODO|FIXME/');
    print(todos.toText());
    print('');

    print('═══ Grep: Count TODOs per file (-c) ═══');
    final todoCount = await context.query('grep TODO -c');
    print(todoCount.toText());
    print('');

    print('═══ Grep: Files with TODOs (-l) ═══');
    final todoFiles = await context.query('grep TODO -l');
    print(todoFiles.toText());
    print('');

    // ═══════════════════════════════════════════════════════════════════════
    // PIPE QUERIES
    // ═══════════════════════════════════════════════════════════════════════

    print('═══ Pipe: Find Classes → Get Members ═══');
    final classMembers = await context.query('find * kind:class | members');
    print(classMembers.toText());
    print('');

    // ═══════════════════════════════════════════════════════════════════════
    // WATCHING FOR CHANGES
    // ═══════════════════════════════════════════════════════════════════════

    print('═══ Watching for Changes (press Ctrl+C to exit) ═══');
    print('Edit a file in $projectPath to see updates...');

    await for (final update in context.updates) {
      print('Index update: $update');
    }
  } finally {
    await context.dispose();
  }
}

