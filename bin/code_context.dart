import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:code_context/code_context.dart';
import 'package:scip_server/scip_server.dart' show
    ContextBuilder,
    ContextFormatter,
    DirtyTracker,
    DocManifest,
    FolderDependencyGraph,
    LinkStyle,
    LinkTransformer,
    StructureHash,
    StubDocGenerator;

void main(List<String> arguments) async {
  // Check for subcommands first
  if (arguments.isNotEmpty) {
    switch (arguments.first) {
      case 'index-sdk':
        await _indexSdk(arguments.skip(1).toList());
        return;
      case 'index-flutter':
        await _indexFlutter(arguments.skip(1).toList());
        return;
      case 'index-deps':
        await _indexDependencies(arguments.skip(1).toList());
        return;
      case 'list-indexes':
        await _listIndexes();
        return;
      case 'list-packages':
        await _listPackages(arguments.skip(1).toList());
        return;
      case 'generate-docs':
        await _generateDocs(arguments.skip(1).toList());
        return;
      case 'docs':
        await _handleDocs(arguments.skip(1).toList());
        return;
    }
  }

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
    ..addOption(
      'output',
      abbr: 'o',
      help: 'Write output to file instead of stdout',
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
      'with-deps',
      help: 'Load pre-indexed dependencies for cross-package queries',
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
  final outputPath = args['output'] as String?;
  final watch = args['watch'] as bool;
  final interactive = args['interactive'] as bool;
  final noCache = args['no-cache'] as bool;
  final withDeps = args['with-deps'] as bool;

  // Validate project path
  final pubspecFile = File('$projectPath/pubspec.yaml');
  if (!await pubspecFile.exists()) {
    // Check if there are any packages in the directory
    final discovery = await PackageDiscovery().discoverPackages(projectPath);
    if (discovery.packages.isEmpty) {
      stderr.writeln('Error: No Dart packages found in $projectPath');
      stderr.writeln('Make sure you are in a Dart project directory.');
      exit(1);
    }
  }

  stderr.writeln('Opening project: $projectPath');
  if (withDeps) {
    stderr.writeln('Loading pre-indexed dependencies...');
  }

  CodeContext? context;
  try {
    final stopwatch = Stopwatch()..start();
    context = await CodeContext.open(
      projectPath,
      watch: watch || interactive,
      useCache: !noCache,
      loadDependencies: withDeps,
    );
    stopwatch.stop();

    final pkgCount = context.packageCount;
    final pkgInfo = pkgCount > 1 ? ' across $pkgCount packages' : '';
    final depsInfo = withDeps && context.hasDependencies
        ? ', ${context.registry.packageIndexes.length} external packages loaded'
        : '';
    stderr.writeln(
      'Indexed ${context.stats['files']} files, '
      '${context.stats['symbols']} symbols$pkgInfo'
      '$depsInfo '
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
      _outputResult(result, format, outputPath);
    } else {
      // Execute the query from command line
      final query = args.rest.join(' ');
      final result = await context.query(query);
      _outputResult(result, format, outputPath);
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
  stdout.writeln(
      'code_context - Lightweight semantic code intelligence');
  stdout.writeln('');
  stdout.writeln('Usage: code_context [options] <query>');
  stdout.writeln('       code_context <subcommand> [args]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(parser.usage);
  stdout.writeln('');
  stdout.writeln('Subcommands:');
  stdout.writeln('  docs <subcommand>      Auto-docs pipeline (status, context, generate, resolve)');
  stdout.writeln('  generate-docs [opts]   Generate documentation to docs/');
  stdout.writeln('  index-sdk <sdk-path>   Pre-index the Dart SDK');
  stdout.writeln('  index-flutter [path]   Pre-index Flutter packages');
  stdout.writeln('  index-deps [path]      Pre-index all pub dependencies');
  stdout.writeln(
      '  list-indexes           List available pre-computed indexes');
  stdout.writeln('  list-packages [path]   List discovered packages');
  stdout.writeln('');
  stdout.writeln('Query DSL:');
  stdout.writeln('  def <symbol>           Find definition');
  stdout.writeln('  refs <symbol>          Find references');
  stdout.writeln('  sig <symbol>           Get signature (without body)');
  stdout.writeln('  source <symbol>        Get full source code');
  stdout.writeln('  members <symbol>       Get class members');
  stdout.writeln('  impls <symbol>         Find implementations');
  stdout.writeln('  supertypes <symbol>    Get supertypes');
  stdout.writeln('  subtypes <symbol>      Get subtypes');
  stdout.writeln('  hierarchy <symbol>     Full hierarchy');
  stdout.writeln('  calls <symbol>         What does symbol call?');
  stdout.writeln('  callers <symbol>       What calls symbol?');
  stdout.writeln('  deps <symbol>          Dependencies of symbol');
  stdout.writeln('  find <pattern>         Search symbols');
  stdout.writeln('  which <symbol>         Show all matches (disambiguation)');
  stdout.writeln('  grep <pattern>         Search source code');
  stdout.writeln('  imports <file>         File imports');
  stdout.writeln('  exports <path>         File/directory exports');
  stdout.writeln('  classify               Layer/feature classification');
  stdout.writeln('  storyboard             Navigation flow diagram');
  stdout.writeln('  files                  List indexed files');
  stdout.writeln('  stats                  Index statistics');
  stdout.writeln('');
  stdout.writeln('Filters:');
  stdout.writeln(
      '  kind:<kind>            Filter by kind (class, method, function, etc.)');
  stdout.writeln('  in:<path>              Filter by file path prefix');
  stdout.writeln('');
  stdout.writeln('Grep Flags:');
  stdout.writeln('  -i  Case insensitive     -c  Count per file');
  stdout.writeln('  -l  Files with matches   -L  Files without matches');
  stdout.writeln('  -o  Only matching text   -w  Word boundary');
  stdout.writeln('  -v  Invert match         -F  Fixed strings (literal)');
  stdout.writeln('  -D  Search dependencies  (with --with-deps)');
  stdout.writeln('  -C:n Context lines       -A:n/-B:n After/before lines');
  stdout.writeln('  --include:glob  Only search matching files');
  stdout.writeln('  --exclude:glob  Skip matching files');
  stdout.writeln('');
  stdout.writeln('Pipe Queries:');
  stdout.writeln('  find Auth* | members     Chain queries with |');
  stdout.writeln('  grep TODO | refs         Process results through pipes');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  code_context def AuthRepository');
  stdout.writeln('  code_context refs login');
  stdout.writeln('  code_context "find Auth* kind:class"');
  stdout.writeln('  code_context "grep TODO -c"');
  stdout.writeln('  code_context "grep /TODO|FIXME/ -l"');
  stdout.writeln('  code_context "find *Service | members"');
  stdout.writeln('  code_context -i                    # Interactive mode');
  stdout.writeln('  code_context -w                    # Watch mode');
  stdout.writeln(
      '  code_context -w "find * kind:class"  # Watch + re-run on changes');
  stdout.writeln('');
  stdout.writeln('Pre-indexing dependencies (for cross-package queries):');
  stdout.writeln('  code_context index-sdk /path/to/dart-sdk');
  stdout.writeln('  code_context index-deps');
  stdout.writeln('  code_context --with-deps "hierarchy MyClass"');
  stdout.writeln('');
  stdout.writeln('Mono repo / workspace support:');
  stdout.writeln('  code_context list-packages /path/to/monorepo');
  stdout.writeln('  code_context -p /path/to/monorepo stats');
}

void _printResult(QueryResult result, String format) {
  if (format == 'json') {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  } else {
    stdout.writeln(result.toText());
  }
}

/// Output result to stdout or a file.
Future<void> _outputResult(
  QueryResult result,
  String format,
  String? outputPath,
) async {
  final content = format == 'json'
      ? const JsonEncoder.withIndent('  ').convert(result.toJson())
      : result.toText();

  if (outputPath != null) {
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    stderr.writeln('Written to: $outputPath');
  } else {
    stdout.writeln(content);
  }
}

Future<void> _runWatch(
  CodeContext context,
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

Future<void> _runInteractive(CodeContext context, String format) async {
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
        stdout.writeln('Query Commands:');
        stdout.writeln('  def <symbol>          Find definition');
        stdout.writeln('  refs <symbol>         Find references');
        stdout.writeln('  sig <symbol>          Get signature (without body)');
        stdout.writeln('  source <symbol>       Get full source code');
        stdout.writeln('  members <symbol>      Get class members');
        stdout.writeln('  impls <symbol>        Find implementations');
        stdout.writeln('  supertypes <symbol>   Get supertypes');
        stdout.writeln('  subtypes <symbol>     Get subtypes');
        stdout.writeln('  hierarchy <symbol>    Full hierarchy (super + sub)');
        stdout.writeln('  calls <symbol>        What does it call?');
        stdout.writeln('  callers <symbol>      What calls it?');
        stdout.writeln('  deps <symbol>         Dependencies of a symbol');
        stdout.writeln('  find <pattern>        Search symbols');
        stdout.writeln(
            '  which <symbol>        Show all matches (disambiguation)');
        stdout.writeln('  grep <pattern>        Search in source code');
        stdout.writeln('  imports <file>        What does this file import?');
        stdout.writeln('  exports <path>        What does this path export?');
        stdout.writeln('');
        stdout.writeln('Pattern Syntax:');
        stdout.writeln('  Auth*                 Glob wildcard matching');
        stdout.writeln('  /TODO|FIXME/          Regex pattern');
        stdout.writeln('  /error/i              Case-insensitive regex');
        stdout.writeln('  ~authentcate          Fuzzy (typo-tolerant)');
        stdout
            .writeln('  Class.method          Qualified name (disambiguation)');
        stdout.writeln('');
        stdout.writeln('Filters (for find/grep):');
        stdout.writeln('  kind:class            Filter by kind');
        stdout.writeln('  in:lib/auth/          Filter by path');
        stdout.writeln('');
        stdout.writeln('Grep Flags:');
        stdout.writeln('  -i                    Case insensitive');
        stdout.writeln('  -c                    Count matches per file');
        stdout.writeln('  -l                    List files with matches');
        stdout.writeln('  -L                    List files without matches');
        stdout.writeln('  -o                    Show only matching text');
        stdout.writeln('  -w                    Word boundary matching');
        stdout.writeln('  -v                    Invert match');
        stdout.writeln('  -D                    Search external dependencies');
        stdout
            .writeln('  -C:3                  Context lines (before + after)');
        stdout.writeln('  -A:5 -B:2             Lines after / before');
        stdout.writeln('');
        stdout.writeln('Pipe Queries:');
        stdout.writeln('  find Auth* | members  Chain queries with |');
        stdout.writeln('  grep TODO | refs      Process results through pipes');
        stdout.writeln('');
        stdout.writeln('Utility:');
        stdout.writeln('  files                 List indexed files');
        stdout.writeln('  stats                 Index statistics');
        stdout.writeln('  refresh               Refresh all files');
        stdout.writeln('  quit                  Exit');
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

/// Index the Dart/Flutter SDK for cross-package queries.
Future<void> _indexSdk(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: code_context index-sdk <sdk-path>');
    stderr.writeln('');
    stderr.writeln('Example:');
    stderr.writeln('  code_context index-sdk /opt/flutter/bin/cache/dart-sdk');
    stderr.writeln('  code_context index-sdk \$(dirname \$(which dart))/..');
    exit(1);
  }

  final sdkPath = args.first;
  final sdkDir = Directory(sdkPath);

  if (!await sdkDir.exists()) {
    stderr.writeln('Error: SDK path does not exist: $sdkPath');
    exit(1);
  }

  // Check for version file
  final versionFile = File('$sdkPath/version');
  if (!await versionFile.exists()) {
    stderr.writeln('Error: Not a valid Dart SDK (no version file found)');
    exit(1);
  }

  final version = (await versionFile.readAsString()).trim();
  stderr.writeln('Indexing Dart SDK $version...');
  stderr.writeln('This may take a few minutes.');
  stderr.writeln('');

  // Create a temporary registry
  final registry = PackageRegistry(rootPath: sdkPath);
  final builder = ExternalIndexBuilder(registry: registry);

  final stopwatch = Stopwatch()..start();
  final result = await builder.indexSdk(sdkPath);
  stopwatch.stop();

  if (result.success) {
    stdout.writeln('✓ SDK indexed successfully');
    stdout.writeln('  Version: ${result.stats?['version']}');
    stdout.writeln('  Symbols: ${result.stats?['symbols']}');
    stdout.writeln('  Files: ${result.stats?['files']}');
    stdout.writeln('  Time: ${stopwatch.elapsed.inSeconds}s');
    stdout.writeln('');
    stdout.writeln('Index saved to: ${CachePaths.sdkDir(version)}');
  } else {
    stderr.writeln('✗ Failed to index SDK: ${result.error}');
    exit(1);
  }
}

/// Index the Flutter framework packages.
Future<void> _indexFlutter(List<String> args) async {
  // Default to FLUTTER_ROOT env var or common paths
  String? flutterPath;
  if (args.isNotEmpty) {
    flutterPath = args.first;
  } else {
    flutterPath = Platform.environment['FLUTTER_ROOT'];
    if (flutterPath == null) {
      // Try to find Flutter from the flutter command
      try {
        final result = await Process.run('which', ['flutter']);
        if (result.exitCode == 0) {
          final flutterBin = result.stdout.toString().trim();
          // Flutter binary is at FLUTTER_ROOT/bin/flutter
          flutterPath = Directory(flutterBin).parent.parent.path;
        }
      } catch (_) {}
    }
  }

  if (flutterPath == null || !await Directory(flutterPath).exists()) {
    stderr.writeln('Usage: code_context index-flutter [flutter-path]');
    stderr.writeln('');
    stderr.writeln(
        'If no path is provided, uses FLUTTER_ROOT environment variable');
    stderr.writeln('or tries to find Flutter from PATH.');
    stderr.writeln('');
    stderr.writeln('Example:');
    stderr.writeln('  code_context index-flutter');
    stderr.writeln('  code_context index-flutter /opt/flutter');
    exit(1);
  }

  final packagesPath = '$flutterPath/packages';
  if (!await Directory(packagesPath).exists()) {
    stderr.writeln('Error: Flutter packages not found at $packagesPath');
    exit(1);
  }

  // Get Flutter version
  final versionFile = File('$flutterPath/version');
  final version = await versionFile.exists()
      ? (await versionFile.readAsString()).trim()
      : 'unknown';

  stderr.writeln('Indexing Flutter $version packages...');
  stderr.writeln('Path: $flutterPath');
  stderr.writeln('');

  // List of Flutter packages to index
  final flutterPackages = [
    'flutter',
    'flutter_test',
    'flutter_driver',
    'flutter_localizations',
    'flutter_web_plugins',
  ];

  final registry = PackageRegistry(rootPath: flutterPath);
  final builder = ExternalIndexBuilder(registry: registry);

  final stopwatch = Stopwatch()..start();
  var successCount = 0;
  var failCount = 0;

  for (final pkgName in flutterPackages) {
    final pkgPath = '$packagesPath/$pkgName';
    if (!await Directory(pkgPath).exists()) {
      stderr.writeln('  Skipping $pkgName (not found)');
      continue;
    }

    // Check if package_config.json exists, run flutter pub get if not
    final pkgConfigFile = File('$pkgPath/.dart_tool/package_config.json');
    if (!await pkgConfigFile.exists()) {
      stderr.writeln('  Running flutter pub get in $pkgName...');
      final result = await Process.run(
        'flutter',
        ['pub', 'get'],
        workingDirectory: pkgPath,
      );
      if (result.exitCode != 0) {
        stderr.writeln('  ✗ Failed to get dependencies for $pkgName');
        failCount++;
        continue;
      }
    }

    stderr.write('  Indexing $pkgName... ');
    final result = await builder.indexFlutterPackage(
      pkgName,
      version,
      pkgPath,
    );

    if (result.success) {
      stdout.writeln('✓ (${result.stats?['symbols']} symbols)');
      successCount++;
    } else {
      stdout.writeln('✗ ${result.error}');
      failCount++;
    }
  }

  stopwatch.stop();
  stdout.writeln('');
  stdout.writeln('Results:');
  stdout.writeln('  Indexed: $successCount packages');
  stdout.writeln('  Failed: $failCount packages');
  stdout.writeln('  Time: ${stopwatch.elapsed.inSeconds}s');
  stdout.writeln('');
  stdout.writeln('Indexes saved to: ${CachePaths.globalCacheDir}/flutter/');
}

/// Index all pub dependencies for cross-package queries.
Future<void> _indexDependencies(List<String> args) async {
  final projectPath = args.isNotEmpty ? args.first : '.';

  final lockfile = File('$projectPath/pubspec.lock');
  if (!await lockfile.exists()) {
    stderr.writeln('Error: No pubspec.lock found in $projectPath');
    stderr.writeln('Run "dart pub get" first.');
    exit(1);
  }

  stderr.writeln('Indexing dependencies from $projectPath...');
  stderr.writeln('This may take several minutes for large projects.');
  stderr.writeln('');

  // Create a temporary registry
  final registry = PackageRegistry(rootPath: projectPath);
  final builder = ExternalIndexBuilder(registry: registry);

  final stopwatch = Stopwatch()..start();
  final result = await builder.indexDependencies(projectPath);
  stopwatch.stop();

  if (!result.success) {
    stderr.writeln('✗ Failed: ${result.error}');
    exit(1);
  }

  stdout.writeln('Results:');
  stdout.writeln('  Indexed: ${result.indexed}');
  stdout.writeln('  Skipped (already indexed): ${result.skipped}');
  stdout.writeln('  Failed: ${result.failed}');
  stdout.writeln('  Time: ${stopwatch.elapsed.inSeconds}s');
  stdout.writeln('');

  if (result.failed > 0) {
    stdout.writeln('Failed packages:');
    for (final pkg in result.results.where((r) => !r.success && !r.skipped)) {
      stdout.writeln('  - ${pkg.name}-${pkg.version}: ${pkg.error}');
    }
  }
}

/// List available pre-computed indexes.
Future<void> _listIndexes() async {
  final registry = PackageRegistry(rootPath: '.');
  final builder = ExternalIndexBuilder(registry: registry);

  stdout.writeln('Pre-computed indexes in ${CachePaths.globalCacheDir}:');
  stdout.writeln('');

  // List SDK indexes
  final sdkVersions = await builder.listSdkIndexes();
  stdout.writeln('SDK Indexes:');
  if (sdkVersions.isEmpty) {
    stdout.writeln('  (none)');
  } else {
    for (final version in sdkVersions) {
      stdout.writeln('  - Dart SDK $version');
    }
  }
  stdout.writeln('');

  // List Flutter indexes
  final flutterDir = Directory('${CachePaths.globalCacheDir}/flutter');
  stdout.writeln('Flutter Indexes:');
  if (await flutterDir.exists()) {
    final versions = await flutterDir
        .list()
        .where((e) => e is Directory)
        .map((e) => e.path.split('/').last)
        .toList();
    if (versions.isEmpty) {
      stdout.writeln('  (none)');
    } else {
      for (final version in versions) {
        final pkgDir = Directory('${flutterDir.path}/$version');
        final packages = await pkgDir
            .list()
            .where((e) => e is Directory)
            .map((e) => e.path.split('/').last)
            .toList();
        stdout.writeln('  - Flutter $version (${packages.length} packages)');
      }
    }
  } else {
    stdout.writeln('  (none)');
  }
  stdout.writeln('');

  // List package indexes
  final packages = await builder.listPackageIndexes();
  stdout.writeln('Hosted Package Indexes:');
  if (packages.isEmpty) {
    stdout.writeln('  (none)');
  } else {
    for (final pkg in packages) {
      stdout.writeln('  - ${pkg.name} ${pkg.version}');
    }
  }
  stdout.writeln('');

  // List git indexes
  final gitDir = Directory('${CachePaths.globalCacheDir}/git');
  stdout.writeln('Git Package Indexes:');
  if (await gitDir.exists()) {
    final gitPackages = await gitDir
        .list()
        .where((e) => e is Directory)
        .map((e) => e.path.split('/').last)
        .toList();
    if (gitPackages.isEmpty) {
      stdout.writeln('  (none)');
    } else {
      for (final pkg in gitPackages) {
        stdout.writeln('  - $pkg');
      }
    }
  } else {
    stdout.writeln('  (none)');
  }
  stdout.writeln('');

  stdout.writeln('To index SDK: code_context index-sdk <path>');
  stdout.writeln('To index Flutter: code_context index-flutter');
  stdout.writeln('To index deps: code_context index-deps');
}

/// List discovered packages in a directory.
Future<void> _listPackages(List<String> args) async {
  final path = args.isNotEmpty ? args.first : '.';

  stderr.writeln('Discovering packages in $path...');

  final stopwatch = Stopwatch()..start();
  final discovery = await PackageDiscovery().discoverPackages(path);
  stopwatch.stop();

  stdout.writeln('');
  stdout.writeln('Discovered ${discovery.packages.length} packages in ${stopwatch.elapsedMilliseconds}ms:');
  stdout.writeln('');

  if (discovery.packages.isEmpty) {
    stdout.writeln('  (no packages found)');
    stdout.writeln('');
    stdout.writeln('Make sure the directory contains Dart packages with pubspec.yaml files.');
    return;
  }

  for (final pkg in discovery.packages) {
    stdout.writeln('  ${pkg.name}');
    stdout.writeln('    Path: ${pkg.relativePath}');
  }
  stdout.writeln('');

  // Check for existing workspace cache
  final cacheDir = CachePaths.workspaceDir(discovery.rootPath);
  final cacheExists = await Directory(cacheDir).exists();
  if (cacheExists) {
    stdout.writeln('Cache: $cacheDir');
    final localDir = Directory('$cacheDir/local');
    if (await localDir.exists()) {
      final indexed =
          await localDir.list().where((e) => e is Directory).length;
      stdout.writeln('Indexed packages: $indexed');
    }
  } else {
    stdout.writeln('Cache: (not initialized)');
  }
}

/// Generate documentation files for a project.
///
/// Creates:
/// - docs/architecture-*.md - Layer/feature/module classification
/// - docs/navigation.md - Storyboard/navigation flow
/// - docs/index.md - Overview with links to other docs
Future<void> _generateDocs(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'project',
      abbr: 'p',
      help: 'Path to the Dart project',
      defaultsTo: '.',
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'Output directory for documentation',
      defaultsTo: 'docs',
    )
    ..addOption(
      'format',
      abbr: 'f',
      help: 'Output format: text (markdown) or json',
      defaultsTo: 'text',
      allowed: ['text', 'json'],
    )
    ..addOption(
      'mode',
      abbr: 'm',
      help: 'Documentation organization mode',
      defaultsTo: 'all',
      allowed: ['all', 'layer', 'feature', 'module'],
      allowedHelp: {
        'all': 'Generate all views (layer, feature, module)',
        'layer': 'Group by architectural layer (UI → Service → Data)',
        'feature': 'Group by feature/user journey (auth, products, etc.)',
        'module': 'Group by package/module structure',
      },
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show help',
      negatable: false,
    );

  ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } catch (e) {
    stderr.writeln('Error: $e');
    _printGenerateDocsUsage(parser);
    exit(1);
  }

  if (parsed['help'] as bool) {
    _printGenerateDocsUsage(parser);
    exit(0);
  }

  // Support both positional arg and --project option
  var projectPath = parsed['project'] as String;
  if (parsed.rest.isNotEmpty && projectPath == '.') {
    projectPath = parsed.rest.first;
  }
  final outputDir = parsed['output'] as String;
  final format = parsed['format'] as String;
  final mode = parsed['mode'] as String;
  final ext = format == 'json' ? 'json' : 'md';

  // Validate project path
  final pubspecFile = File('$projectPath/pubspec.yaml');
  if (!await pubspecFile.exists()) {
    final discovery = await PackageDiscovery().discoverPackages(projectPath);
    if (discovery.packages.isEmpty) {
      stderr.writeln('Error: No Dart packages found in $projectPath');
      exit(1);
    }
  }

  stderr.writeln('Generating documentation for: $projectPath');
  stderr.writeln('Output directory: $outputDir');
  stderr.writeln('Mode: $mode');
  stderr.writeln('');

  CodeContext? context;
  try {
    final stopwatch = Stopwatch()..start();
    context = await CodeContext.open(projectPath, useCache: true);
    stopwatch.stop();
    stderr.writeln(
      'Indexed ${context.stats['files']} files, '
      '${context.stats['symbols']} symbols '
      '(${stopwatch.elapsedMilliseconds}ms)',
    );
    stderr.writeln('');

    // Create output directory
    final docsDir = Directory(
      projectPath == '.' ? outputDir : '$projectPath/$outputDir',
    );
    await docsDir.create(recursive: true);

    final createdFiles = <String>[];

    // Generate layer-based architecture documentation
    if (mode == 'all' || mode == 'layer') {
      stderr.write('Generating architecture-layer.$ext... ');
      final classifyResult = await context.query('classify');
      final archFile = File('${docsDir.path}/architecture-layer.$ext');
      final archContent = format == 'json'
          ? const JsonEncoder.withIndent('  ').convert(classifyResult.toJson())
          : _wrapArchitectureDoc(classifyResult.toText(), 'Layer');
      await archFile.writeAsString(archContent);
      createdFiles.add('${docsDir.path}/architecture-layer.$ext');
      stderr.writeln('✓');
    }

    // Generate feature-based architecture documentation
    if (mode == 'all' || mode == 'feature') {
      stderr.write('Generating architecture-feature.$ext... ');
      final classifyResult = await context.query('classify');
      final archFile = File('${docsDir.path}/architecture-feature.$ext');
      final archContent = format == 'json'
          ? const JsonEncoder.withIndent('  ')
              .convert(_groupByFeature(classifyResult.toJson()))
          : _wrapArchitectureDoc(
              _formatByFeature(classifyResult.toJson()),
              'Feature',
            );
      await archFile.writeAsString(archContent);
      createdFiles.add('${docsDir.path}/architecture-feature.$ext');
      stderr.writeln('✓');
    }

    // Generate module-based architecture documentation (for monorepos)
    if (mode == 'all' || mode == 'module') {
      stderr.write('Generating architecture-module.$ext... ');
      final archContent = format == 'json'
          ? const JsonEncoder.withIndent('  ')
              .convert(_generateModuleJson(context))
          : _wrapArchitectureDoc(
              _formatByModule(context),
              'Module',
            );
      final archFile = File('${docsDir.path}/architecture-module.$ext');
      await archFile.writeAsString(archContent);
      createdFiles.add('${docsDir.path}/architecture-module.$ext');
      stderr.writeln('✓');
    }

    // Generate navigation documentation
    stderr.write('Generating navigation.md... ');
    final storyboardResult = await context.query('storyboard');
    final navFile = File('${docsDir.path}/navigation.md');
    final navContent = _wrapNavigationDoc(storyboardResult.toText());
    await navFile.writeAsString(navContent);
    createdFiles.add('${docsDir.path}/navigation.md');
    stderr.writeln('✓');

    // Generate index/overview
    stderr.write('Generating index.$ext... ');
    final indexFile = File('${docsDir.path}/index.$ext');
    if (format == 'json') {
      final indexJson = {
        'type': 'docs_index',
        'generated_at': DateTime.now().toIso8601String(),
        'mode': mode,
        'files': createdFiles.map((f) => f.split('/').last).toList(),
        'stats': context.stats,
      };
      await indexFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(indexJson),
      );
    } else {
      await indexFile.writeAsString(_generateIndexDoc(context, mode: mode));
    }
    createdFiles.add('${docsDir.path}/index.$ext');
    stderr.writeln('✓');

    stderr.writeln('');
    stderr.writeln('Documentation generated successfully!');
    stderr.writeln('');
    stderr.writeln('Files created:');
    for (final file in createdFiles) {
      stderr.writeln('  $file');
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

void _printGenerateDocsUsage(ArgParser parser) {
  stdout.writeln('Generate documentation for a Dart/Flutter project.');
  stdout.writeln('');
  stdout.writeln('Usage: code_context generate-docs [options]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(parser.usage);
  stdout.writeln('');
  stdout.writeln('Generated files (mode=all):');
  stdout.writeln('  index.md                - Overview with links to other docs');
  stdout.writeln('  architecture-layer.md   - Symbols grouped by layer (UI/Service/Data)');
  stdout.writeln('  architecture-feature.md - Symbols grouped by feature (auth/products)');
  stdout.writeln('  architecture-module.md  - Symbols grouped by package/module');
  stdout.writeln('  navigation.md           - Screen storyboard and navigation flow');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  code_context generate-docs');
  stdout.writeln('  code_context generate-docs -p ./my_app -o generated_docs');
  stdout.writeln('  code_context generate-docs --mode feature');
  stdout.writeln('  code_context generate-docs --format json');
}

String _wrapArchitectureDoc(String content, String viewType) {
  final descriptions = {
    'Layer': 'Symbols organized by architectural layer (UI → Service → Data → Model).',
    'Feature': 'Symbols organized by feature/domain (auth, products, settings, etc.).',
    'Module': 'Symbols organized by package/module structure.',
  };
  
  return '''# Architecture ($viewType View)

> Auto-generated by code_context. Last updated: ${DateTime.now().toIso8601String()}

${descriptions[viewType] ?? 'Architectural organization of the codebase.'}

$content

---
*Generated by [code_context](https://github.com/user/code_context)*
''';
}

String _wrapNavigationDoc(String content) {
  return '''# Navigation Flow

> Auto-generated by code_context. Last updated: ${DateTime.now().toIso8601String()}

Screen-to-screen navigation structure of the application.

$content

---
*Generated by [code_context](https://github.com/user/code_context)*
''';
}

String _generateIndexDoc(CodeContext context, {String mode = 'all'}) {
  final stats = context.stats;
  
  final archLinks = <String>[];
  if (mode == 'all' || mode == 'layer') {
    archLinks.add('- [Architecture (Layer)](./architecture-layer.md) - Grouped by architectural layer');
  }
  if (mode == 'all' || mode == 'feature') {
    archLinks.add('- [Architecture (Feature)](./architecture-feature.md) - Grouped by feature/domain');
  }
  if (mode == 'all' || mode == 'module') {
    archLinks.add('- [Architecture (Module)](./architecture-module.md) - Grouped by package/module');
  }
  
  return '''# Project Documentation

> Auto-generated by code_context. Last updated: ${DateTime.now().toIso8601String()}

## Overview

- Files: ${stats['files']}
- Symbols: ${stats['symbols']}

## Documentation

### Architecture Views

${archLinks.join('\n')}

### Navigation

- [Navigation](./navigation.md) - Screen storyboard and navigation flow

## Quick Start

To regenerate this documentation:

```bash
code_context generate-docs
```

To generate a specific view:

```bash
code_context generate-docs --mode layer   # Layer view only
code_context generate-docs --mode feature # Feature view only
code_context generate-docs --mode module  # Module view only
```

To generate JSON output:

```bash
code_context generate-docs --format json
```

---
*Generated by [code_context](https://github.com/user/code_context)*
''';
}

/// Group classification results by feature instead of layer.
Map<String, dynamic> _groupByFeature(Map<String, dynamic> json) {
  if (json['type'] != 'classify') return json;
  
  final byFeature = <String, List<Map<String, dynamic>>>{};
  final classifications = json['classifications'] as List<dynamic>? ?? [];
  
  for (final c in classifications) {
    final classification = c as Map<String, dynamic>;
    final feature = classification['feature'] as String? ?? 'uncategorized';
    byFeature.putIfAbsent(feature, () => []).add(classification);
  }
  
  return {
    'type': 'classify',
    'view': 'feature',
    'generated_at': DateTime.now().toIso8601String(),
    'features': byFeature.map((feature, items) => MapEntry(feature, {
      'count': items.length,
      'symbols': items,
    })),
  };
}

/// Format classification results grouped by feature as markdown.
String _formatByFeature(Map<String, dynamic> json) {
  if (json['type'] != 'classify') return json.toString();
  
  final byFeature = <String, List<Map<String, dynamic>>>{};
  final classifications = json['classifications'] as List<dynamic>? ?? [];
  
  for (final c in classifications) {
    final classification = c as Map<String, dynamic>;
    final feature = classification['feature'] as String? ?? 'uncategorized';
    byFeature.putIfAbsent(feature, () => []).add(classification);
  }
  
  final buffer = StringBuffer();
  
  // Sort features alphabetically
  final sortedFeatures = byFeature.keys.toList()..sort();
  
  for (final feature in sortedFeatures) {
    final items = byFeature[feature]!;
    buffer.writeln('## $feature (${items.length})');
    buffer.writeln('');
    
    for (final item in items) {
      final name = item['name'] ?? 'unknown';
      final layer = item['layer'] ?? 'unknown';
      final file = item['file'] ?? 'external';
      buffer.writeln('- $name [$layer]');
      buffer.writeln('  $file');
    }
    buffer.writeln('');
  }
  
  return buffer.toString();
}

/// Generate module-based JSON for monorepo structure.
Map<String, dynamic> _generateModuleJson(CodeContext context) {
  final localPackages = context.registry.localPackages.values.toList();
  
  if (localPackages.isEmpty) {
    // Single package mode
    final stats = context.stats;
    return {
      'type': 'modules',
      'view': 'module',
      'generated_at': DateTime.now().toIso8601String(),
      'packages': [
        {
          'name': context.rootPath.split('/').last,
          'path': context.rootPath,
          'files': stats['files'],
          'symbols': stats['symbols'],
        },
      ],
    };
  }
  
  return {
    'type': 'modules',
    'view': 'module',
    'generated_at': DateTime.now().toIso8601String(),
    'packages': localPackages.map((pkg) {
      final index = pkg.index;
      return {
        'name': pkg.name,
        'path': pkg.path,
        'files': index.files.length,
        'symbols': index.allSymbols.length,
      };
    }).toList(),
  };
}

/// Format module structure as markdown.
String _formatByModule(CodeContext context) {
  final localPackages = context.registry.localPackages.values.toList();
  final buffer = StringBuffer();
  
  if (localPackages.isEmpty) {
    // Single package mode
    final stats = context.stats;
    buffer.writeln('## ${context.rootPath.split('/').last}');
    buffer.writeln('');
    buffer.writeln('- Files: ${stats['files']}');
    buffer.writeln('- Symbols: ${stats['symbols']}');
  } else {
    buffer.writeln('## Packages (${localPackages.length})');
    buffer.writeln('');
    
    for (final pkg in localPackages) {
      final index = pkg.index;
      buffer.writeln('- ${pkg.name}');
      buffer.writeln('  Files: ${index.files.length}, Symbols: ${index.allSymbols.length}');
    }
  }
  
  return buffer.toString();
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTO-DOCS PIPELINE COMMANDS
// ═══════════════════════════════════════════════════════════════════════════

/// Handle the `docs` subcommand and its subcommands.
Future<void> _handleDocs(List<String> args) async {
  if (args.isEmpty) {
    _printDocsUsage();
    exit(1);
  }

  final subcommand = args.first;
  final subArgs = args.skip(1).toList();

  switch (subcommand) {
    case 'status':
      await _docsStatus(subArgs);
    case 'context':
      await _docsContext(subArgs);
    case 'generate':
      await _docsGenerate(subArgs);
    case 'resolve':
      await _docsResolve(subArgs);
    case 'help':
    case '--help':
    case '-h':
      _printDocsUsage();
    default:
      stderr.writeln('Unknown docs subcommand: $subcommand');
      _printDocsUsage();
      exit(1);
  }
}

void _printDocsUsage() {
  stdout.writeln('Auto-docs pipeline for folder-level documentation.');
  stdout.writeln('');
  stdout.writeln('Usage: code_context docs <subcommand> [options]');
  stdout.writeln('');
  stdout.writeln('Subcommands:');
  stdout.writeln('  status    Show what needs regeneration');
  stdout.writeln('  context   Build and output context YAML for a folder');
  stdout.writeln('  generate  Generate/update docs (uses stub generator for now)');
  stdout.writeln('  resolve   Re-resolve links only (no LLM calls)');
  stdout.writeln('');
  stdout.writeln('Options (all subcommands):');
  stdout.writeln('  -p, --project <path>   Path to the Dart project (default: .)');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  code_context docs status');
  stdout.writeln('  code_context docs status -p /path/to/project');
  stdout.writeln('  code_context docs context -f lib/features/auth');
  stdout.writeln('  code_context docs generate');
  stdout.writeln('  code_context docs generate --force');
  stdout.writeln('  code_context docs resolve');
  stdout.writeln('  code_context docs resolve --style github');
}

/// Show documentation status - what needs regeneration.
Future<void> _docsStatus(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'project',
      abbr: 'p',
      help: 'Path to the Dart project',
      defaultsTo: '.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show detailed information',
      defaultsTo: false,
    )
    ..addFlag('help', abbr: 'h', help: 'Show help', negatable: false);

  final parsed = parser.parse(args);
  if (parsed['help'] as bool) {
    stdout.writeln('Show documentation status - what needs regeneration.');
    stdout.writeln('');
    stdout.writeln('Usage: code_context docs status [options]');
    stdout.writeln('');
    stdout.writeln('Options:');
    stdout.writeln(parser.usage);
    return;
  }

  final projectPath = parsed['project'] as String;
  final verbose = parsed['verbose'] as bool;

  CodeContext? context;
  try {
    stderr.writeln('Opening project: $projectPath');
    context = await CodeContext.open(projectPath, useCache: true);
    stderr.writeln(
      'Indexed ${context.stats['files']} files, '
      '${context.stats['symbols']} symbols',
    );
    stderr.writeln('');

    // Get the primary index
    final index = context.registry.localPackages.isEmpty
        ? context.registry.projectIndex
        : context.registry.localPackages.values.first.index;

    // Build folder dependency graph
    final graph = FolderDependencyGraph.build(index);

    // Load existing manifest
    final manifestPath = '$projectPath/.dart_context/docs/manifest.json';
    final manifest = await DocManifest.load(manifestPath);

    // Create dirty tracker and compute state
    final tracker = DirtyTracker(
      index: index,
      graph: graph,
      manifest: manifest,
    );
    final dirtyState = tracker.computeDirtyState();

    // Output status
    stdout.writeln('Documentation Status');
    stdout.writeln('====================');
    stdout.writeln('');
    stdout.writeln('Folders: ${graph.folders.length}');
    stdout.writeln('Dirty folders: ${dirtyState.dirtyFolders.length}');
    stdout.writeln('Dirty modules: ${dirtyState.dirtyModules.length}');
    stdout.writeln('Project dirty: ${dirtyState.projectDirty}');
    stdout.writeln('');

    if (dirtyState.dirtyFolders.isNotEmpty) {
      stdout.writeln('Folders needing regeneration:');
      for (final folder in dirtyState.dirtyFolders.toList()..sort()) {
        stdout.writeln('  - $folder');
      }
      stdout.writeln('');
    }

    if (dirtyState.dirtyModules.isNotEmpty) {
      stdout.writeln('Modules needing regeneration:');
      for (final module in dirtyState.dirtyModules.toList()..sort()) {
        stdout.writeln('  - $module');
      }
      stdout.writeln('');
    }

    if (verbose) {
      stdout.writeln('Generation order (${dirtyState.generationOrder.length} levels):');
      for (var i = 0; i < dirtyState.generationOrder.length; i++) {
        final level = dirtyState.generationOrder[i];
        if (level.length == 1) {
          stdout.writeln('  Level $i: ${level.first}');
        } else {
          stdout.writeln('  Level $i (cycle): ${level.join(', ')}');
        }
      }
      stdout.writeln('');

      stdout.writeln('Folder dependency graph stats:');
      for (final entry in graph.stats.entries) {
        stdout.writeln('  ${entry.key}: ${entry.value}');
      }
    }

    if (!dirtyState.isDirty) {
      stdout.writeln('All documentation is up to date.');
    } else {
      stdout.writeln('Run "code_context docs generate" to update documentation.');
    }
  } finally {
    await context?.dispose();
  }
}

/// Build and output context YAML for a folder.
Future<void> _docsContext(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'project',
      abbr: 'p',
      help: 'Path to the Dart project',
      defaultsTo: '.',
    )
    ..addOption(
      'folder',
      abbr: 'f',
      help: 'Folder to build context for (required)',
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'Output file (default: stdout)',
    )
    ..addFlag('help', abbr: 'h', help: 'Show help', negatable: false);

  final parsed = parser.parse(args);
  if (parsed['help'] as bool) {
    stdout.writeln('Build and output context YAML for LLM consumption.');
    stdout.writeln('');
    stdout.writeln('Usage: code_context docs context -f <folder> [options]');
    stdout.writeln('');
    stdout.writeln('Options:');
    stdout.writeln(parser.usage);
    stdout.writeln('');
    stdout.writeln('Example:');
    stdout.writeln('  code_context docs context -f lib/features/auth');
    stdout.writeln('  code_context docs context -f lib/core -o context.yaml');
    return;
  }

  final projectPath = parsed['project'] as String;
  final folder = parsed['folder'] as String?;
  final outputPath = parsed['output'] as String?;

  if (folder == null) {
    stderr.writeln('Error: --folder (-f) is required');
    stderr.writeln('');
    stderr.writeln('Usage: code_context docs context -f <folder>');
    exit(1);
  }

  CodeContext? context;
  try {
    stderr.writeln('Opening project: $projectPath');
    context = await CodeContext.open(projectPath, useCache: true);
    stderr.writeln(
      'Indexed ${context.stats['files']} files, '
      '${context.stats['symbols']} symbols',
    );
    stderr.writeln('');

    // Get the primary index
    final index = context.registry.localPackages.isEmpty
        ? context.registry.projectIndex
        : context.registry.localPackages.values.first.index;

    // Build folder dependency graph
    final graph = FolderDependencyGraph.build(index);

    // Check if folder exists
    if (!graph.folders.contains(folder)) {
      stderr.writeln('Error: Folder not found in index: $folder');
      stderr.writeln('');
      stderr.writeln('Available folders:');
      for (final f in graph.folders.toList()..sort()) {
        stderr.writeln('  - $f');
      }
      exit(1);
    }

    // Build context
    stderr.writeln('Building context for: $folder');
    final builder = ContextBuilder(
      index: index,
      graph: graph,
      projectRoot: projectPath,
    );
    final docContext = await builder.buildForFolder(folder);

    // Format as YAML
    const formatter = ContextFormatter();
    final yaml = formatter.formatAsYaml(docContext);

    // Output
    if (outputPath != null) {
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(yaml);
      stderr.writeln('Written to: $outputPath');
    } else {
      stdout.writeln(yaml);
    }
  } finally {
    await context?.dispose();
  }
}

/// Generate/update documentation.
Future<void> _docsGenerate(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'project',
      abbr: 'p',
      help: 'Path to the Dart project',
      defaultsTo: '.',
    )
    ..addFlag(
      'force',
      help: 'Force regeneration of all docs (ignore hashes)',
      defaultsTo: false,
    )
    ..addFlag(
      'dry-run',
      help: 'Show what would be generated without writing files',
      defaultsTo: false,
    )
    ..addFlag('help', abbr: 'h', help: 'Show help', negatable: false);

  final parsed = parser.parse(args);
  if (parsed['help'] as bool) {
    stdout.writeln('Generate or update folder documentation.');
    stdout.writeln('');
    stdout.writeln('Usage: code_context docs generate [options]');
    stdout.writeln('');
    stdout.writeln('Options:');
    stdout.writeln(parser.usage);
    stdout.writeln('');
    stdout.writeln('Note: Currently uses a stub generator. Real LLM integration');
    stdout.writeln('will be added in a future phase.');
    return;
  }

  final projectPath = parsed['project'] as String;
  final force = parsed['force'] as bool;
  final dryRun = parsed['dry-run'] as bool;

  CodeContext? context;
  try {
    stderr.writeln('Opening project: $projectPath');
    context = await CodeContext.open(projectPath, useCache: true);
    stderr.writeln(
      'Indexed ${context.stats['files']} files, '
      '${context.stats['symbols']} symbols',
    );
    stderr.writeln('');

    // Get the primary index
    final index = context.registry.localPackages.isEmpty
        ? context.registry.projectIndex
        : context.registry.localPackages.values.first.index;

    // Build folder dependency graph
    final graph = FolderDependencyGraph.build(index);

    // Load existing manifest
    final manifestPath = '$projectPath/.dart_context/docs/manifest.json';
    final manifest = await DocManifest.load(manifestPath);

    // Create dirty tracker and compute state
    final tracker = DirtyTracker(
      index: index,
      graph: graph,
      manifest: manifest,
    );
    final dirtyState = tracker.computeDirtyState();

    // Determine what to generate
    final foldersToGenerate = force
        ? graph.folders.toList()
        : dirtyState.dirtyFolders.toList();

    if (foldersToGenerate.isEmpty) {
      stdout.writeln('All documentation is up to date.');
      return;
    }

    stdout.writeln('Folders to generate: ${foldersToGenerate.length}');
    if (dryRun) {
      stdout.writeln('');
      stdout.writeln('Dry run - would generate:');
      for (final folder in foldersToGenerate..sort()) {
        stdout.writeln('  - $folder');
      }
      return;
    }

    // Create output directories
    final docsRoot = '$projectPath/.dart_context/docs';
    final sourceDir = Directory('$docsRoot/source/folders');
    final renderedDir = Directory('$docsRoot/rendered/folders');
    await sourceDir.create(recursive: true);
    await renderedDir.create(recursive: true);

    // Generate docs in topological order
    const generator = StubDocGenerator();
    var generatedCount = 0;

    for (final level in dirtyState.generationOrder) {
      for (final folder in level) {
        if (!foldersToGenerate.contains(folder)) continue;

        stderr.write('Generating: $folder... ');

        // Build context
        final builder = ContextBuilder(
          index: index,
          graph: graph,
          projectRoot: projectPath,
          docsRoot: docsRoot,
        );
        final docContext = await builder.buildForFolder(folder);

        // Generate doc
        final generatedDoc = await generator.generateFolderDoc(docContext);

        // Write source doc
        final sourceFile = File('$docsRoot/source/folders/$folder/README.md');
        await sourceFile.parent.create(recursive: true);
        await sourceFile.writeAsString(generatedDoc.content);

        // Transform links and write rendered doc
        final transformer = LinkTransformer(
          index: index,
          docsRoot: docsRoot,
        );
        final renderedContent = transformer.transform(generatedDoc.content);
        final renderedFile = File('$docsRoot/rendered/folders/$folder/README.md');
        await renderedFile.parent.create(recursive: true);
        await renderedFile.writeAsString(renderedContent);

        // Update manifest
        final structureHash = StructureHash.computeFolderHash(index, folder);
        manifest.updateFolder(
          folder,
          DirtyTracker.createFolderState(
            structureHash: structureHash,
            docContent: generatedDoc.content,
            internalDeps: docContext.current.internalDeps.toList(),
            externalDeps: docContext.current.externalDeps.toList(),
            smartSymbols: generatedDoc.smartSymbols,
          ),
        );

        generatedCount++;
        stderr.writeln('✓');
      }
    }

    // Save manifest
    await manifest.save(manifestPath);

    stdout.writeln('');
    stdout.writeln('Generated $generatedCount folder docs.');
    stdout.writeln('Source docs: $docsRoot/source/folders/');
    stdout.writeln('Rendered docs: $docsRoot/rendered/folders/');
    stdout.writeln('Manifest: $manifestPath');
  } finally {
    await context?.dispose();
  }
}

/// Re-resolve links in documentation.
Future<void> _docsResolve(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'project',
      abbr: 'p',
      help: 'Path to the Dart project',
      defaultsTo: '.',
    )
    ..addOption(
      'style',
      abbr: 's',
      help: 'Link style for rendered docs',
      defaultsTo: 'relative',
      allowed: ['relative', 'github', 'absolute'],
    )
    ..addFlag('help', abbr: 'h', help: 'Show help', negatable: false);

  final parsed = parser.parse(args);
  if (parsed['help'] as bool) {
    stdout.writeln('Re-resolve links in source docs to create rendered docs.');
    stdout.writeln('');
    stdout.writeln('Usage: code_context docs resolve [options]');
    stdout.writeln('');
    stdout.writeln('This is a cheap operation that updates line numbers in links');
    stdout.writeln('without regenerating the documentation content.');
    stdout.writeln('');
    stdout.writeln('Options:');
    stdout.writeln(parser.usage);
    return;
  }

  final projectPath = parsed['project'] as String;
  final styleStr = parsed['style'] as String;
  final linkStyle = switch (styleStr) {
    'github' => LinkStyle.github,
    'absolute' => LinkStyle.absolute,
    _ => LinkStyle.relative,
  };

  CodeContext? context;
  try {
    stderr.writeln('Opening project: $projectPath');
    context = await CodeContext.open(projectPath, useCache: true);
    stderr.writeln(
      'Indexed ${context.stats['files']} files, '
      '${context.stats['symbols']} symbols',
    );
    stderr.writeln('');

    // Get the primary index
    final index = context.registry.localPackages.isEmpty
        ? context.registry.projectIndex
        : context.registry.localPackages.values.first.index;

    final docsRoot = '$projectPath/.dart_context/docs';
    final sourceDir = Directory('$docsRoot/source/folders');
    final renderedDir = Directory('$docsRoot/rendered/folders');

    if (!await sourceDir.exists()) {
      stderr.writeln('No source docs found. Run "code_context docs generate" first.');
      return;
    }

    await renderedDir.create(recursive: true);

    // Create transformer
    final transformer = LinkTransformer(
      index: index,
      docsRoot: docsRoot,
    );

    // Find all source docs and transform them
    var resolvedCount = 0;
    await for (final entity in sourceDir.list(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.md')) continue;

      final relativePath = entity.path.substring(sourceDir.path.length);
      stderr.write('Resolving: $relativePath... ');

      final sourceContent = await entity.readAsString();
      final renderedContent = transformer.transform(sourceContent, style: linkStyle);

      final renderedFile = File('${renderedDir.path}$relativePath');
      await renderedFile.parent.create(recursive: true);
      await renderedFile.writeAsString(renderedContent);

      resolvedCount++;
      stderr.writeln('✓');
    }

    stdout.writeln('');
    stdout.writeln('Resolved $resolvedCount docs with style: $styleStr');
    stdout.writeln('Rendered docs: $docsRoot/rendered/folders/');
  } finally {
    await context?.dispose();
  }
}
