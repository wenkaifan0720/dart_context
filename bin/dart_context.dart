import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_context/dart_context.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'project',
      abbr: 'p',
      help: 'Path to the Dart project (defaults to current directory)',
      defaultsTo: '.',
    )
    ..addOption(
      'format',
      abbr: 'f',
      help: 'Output format: text or json',
      defaultsTo: 'text',
      allowed: ['text', 'json'],
    )
    ..addFlag(
      'watch',
      abbr: 'w',
      help: 'Watch for file changes and show updates',
      defaultsTo: false,
    )
    ..addFlag(
      'interactive',
      abbr: 'i',
      help: 'Run in interactive REPL mode',
      defaultsTo: false,
    )
    ..addFlag(
      'no-cache',
      help: 'Disable cache and force full re-index',
      defaultsTo: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this help message',
      negatable: false,
    );

  ArgResults args;
  try {
    args = parser.parse(arguments);
  } catch (e) {
    stderr.writeln('Error: $e');
    _printUsage(parser);
    exit(1);
  }

  if (args['help'] as bool) {
    _printUsage(parser);
    exit(0);
  }

  final projectPath = args['project'] as String;
  final format = args['format'] as String;
  final watch = args['watch'] as bool;
  final interactive = args['interactive'] as bool;
  final noCache = args['no-cache'] as bool;

  // Validate project path
  final pubspecFile = File('$projectPath/pubspec.yaml');
  if (!await pubspecFile.exists()) {
    stderr.writeln('Error: No pubspec.yaml found in $projectPath');
    stderr.writeln('Make sure you are in a Dart project directory.');
    exit(1);
  }

  stderr.writeln('Opening project: $projectPath');

  DartContext? context;
  try {
    final stopwatch = Stopwatch()..start();
    context = await DartContext.open(
      projectPath,
      watch: watch || interactive,
      useCache: !noCache,
    );
    stopwatch.stop();

    stderr.writeln(
      'Indexed ${context.stats['files']} files, '
      '${context.stats['symbols']} symbols '
      '(${stopwatch.elapsedMilliseconds}ms)',
    );

    if (interactive) {
      await _runInteractive(context, format);
    } else if (watch) {
      // Watch mode: show updates and optionally re-run query
      final query = args.rest.isNotEmpty ? args.rest.join(' ') : null;
      await _runWatch(context, format, query);
    } else if (args.rest.isEmpty) {
      // No query provided, show stats
      final result = await context.query('stats');
      _printResult(result, format);
    } else {
      // Execute the query from command line
      final query = args.rest.join(' ');
      final result = await context.query(query);
      _printResult(result, format);
    }
  } catch (e, st) {
    stderr.writeln('Error: $e');
    if (Platform.environment['DEBUG'] != null) {
      stderr.writeln(st);
    }
    exit(1);
  } finally {
    await context?.dispose();
  }
}

void _printUsage(ArgParser parser) {
  stdout.writeln('dart_context - Lightweight semantic code intelligence for Dart');
  stdout.writeln('');
  stdout.writeln('Usage: dart_context [options] <query>');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(parser.usage);
  stdout.writeln('');
  stdout.writeln('Query DSL:');
  stdout.writeln('  def <symbol>           Find definition');
  stdout.writeln('  refs <symbol>          Find references');
  stdout.writeln('  members <symbol>       Get class members');
  stdout.writeln('  impls <symbol>         Find implementations');
  stdout.writeln('  supertypes <symbol>    Get supertypes');
  stdout.writeln('  subtypes <symbol>      Get subtypes');
  stdout.writeln('  hierarchy <symbol>     Full hierarchy');
  stdout.writeln('  source <symbol>        Get source code');
  stdout.writeln('  find <pattern>         Search symbols');
  stdout.writeln('  files                  List indexed files');
  stdout.writeln('  stats                  Index statistics');
  stdout.writeln('');
  stdout.writeln('Filters (for find):');
  stdout.writeln('  kind:<kind>            Filter by kind (class, method, function, etc.)');
  stdout.writeln('  in:<path>              Filter by file path prefix');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  dart_context def AuthRepository');
  stdout.writeln('  dart_context refs login');
  stdout.writeln('  dart_context "find Auth* kind:class"');
  stdout.writeln('  dart_context -i                    # Interactive mode');
  stdout.writeln('  dart_context -w                    # Watch mode');
  stdout.writeln('  dart_context -w "find * kind:class"  # Watch + re-run query on changes');
}

void _printResult(QueryResult result, String format) {
  if (format == 'json') {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  } else {
    stdout.writeln(result.toText());
  }
}

Future<void> _runWatch(
  DartContext context,
  String format,
  String? query,
) async {
  // Run initial query if provided
  if (query != null) {
    final result = await context.query(query);
    _printResult(result, format);
    stdout.writeln('');
  }

  stderr.writeln('Watching for changes... (Ctrl+C to stop)');
  stderr.writeln('');

  final completer = Completer<void>();

  // Handle Ctrl+C
  late StreamSubscription<ProcessSignal> sigintSubscription;
  sigintSubscription = ProcessSignal.sigint.watch().listen((_) {
    stderr.writeln('');
    stderr.writeln('Stopping watch...');
    sigintSubscription.cancel();
    completer.complete();
  });

  // Watch for file updates
  final subscription = context.updates.listen((update) async {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    
    if (update is FileUpdatedUpdate) {
      stderr.writeln('[$timestamp] Updated: ${update.path}');
      
      // Re-run query if provided
      if (query != null) {
        final result = await context.query(query);
        stdout.writeln('');
        _printResult(result, format);
      }
    } else if (update is FileRemovedUpdate) {
      stderr.writeln('[$timestamp] Removed: ${update.path}');
      
      // Re-run query if provided
      if (query != null) {
        final result = await context.query(query);
        stdout.writeln('');
        _printResult(result, format);
      }
    } else if (update is IndexErrorUpdate) {
      stderr.writeln('[$timestamp] Error: ${update.path} - ${update.message}');
    }
  });

  try {
    await completer.future;
  } finally {
    await subscription.cancel();
  }

  stderr.writeln('Watch mode stopped.');
}

Future<void> _runInteractive(DartContext context, String format) async {
  stdout.writeln('');
  stdout.writeln('Interactive mode. Type "help" for commands, "quit" to exit.');
  stdout.writeln('');

  // Watch for file updates
  final subscription = context.updates.listen((update) {
    stderr.writeln('  [update] $update');
  });

  try {
    while (true) {
      stdout.write('> ');
      final line = stdin.readLineSync();

      if (line == null || line == 'quit' || line == 'exit') {
        break;
      }

      if (line.isEmpty) continue;

      if (line == 'help') {
        stdout.writeln('Commands:');
        stdout.writeln('  def <symbol>        Find definition');
        stdout.writeln('  refs <symbol>       Find references');
        stdout.writeln('  members <symbol>    Get class members');
        stdout.writeln('  impls <symbol>      Find implementations');
        stdout.writeln('  hierarchy <symbol>  Full hierarchy');
        stdout.writeln('  source <symbol>     Get source code');
        stdout.writeln('  find <pattern>      Search symbols');
        stdout.writeln('  files               List files');
        stdout.writeln('  stats               Index statistics');
        stdout.writeln('  refresh             Refresh all files');
        stdout.writeln('  quit                Exit');
        continue;
      }

      if (line == 'refresh') {
        stderr.writeln('Refreshing...');
        await context.refreshAll();
        stderr.writeln('Done. ${context.stats['symbols']} symbols indexed.');
        continue;
      }

      final result = await context.query(line);
      _printResult(result, format);
      stdout.writeln('');
    }
  } finally {
    await subscription.cancel();
  }

  stdout.writeln('Goodbye!');
}

