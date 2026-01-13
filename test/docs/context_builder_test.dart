import 'package:scip_server/scip_server.dart';
import 'package:test/test.dart';

import '../fixtures/mock_scip_index.dart';

void main() {
  group('ContextBuilder', () {
    group('with dependency index', () {
      late ScipIndex index;
      late FolderDependencyGraph graph;
      late ContextBuilder builder;

      setUp(() {
        index = MockScipIndex.withDependencies();
        graph = FolderDependencyGraph.build(index);
        builder = ContextBuilder(
          index: index,
          graph: graph,
          projectRoot: '/mock/project',
        );
      });

      test('builds context for folder', () async {
        final context = await builder.buildForFolder('lib/features/auth');

        expect(context.current.path, 'lib/features/auth');
        expect(context.current.files, isNotEmpty);
      });

      test('includes internal dependency summaries', () async {
        final context = await builder.buildForFolder('lib/features/auth');

        // Auth depends on core
        expect(
          context.internalDeps.any((d) => d.path == 'lib/core'),
          isTrue,
        );
      });

      test('includes used symbols in dependency summary', () async {
        final context = await builder.buildForFolder('lib/features/auth');

        final coreDep = context.internalDeps.firstWhere(
          (d) => d.path == 'lib/core',
          orElse: () => throw Exception('Core dep not found'),
        );

        expect(coreDep.usedSymbols, contains('Helper'));
      });
    });

    group('with external deps index', () {
      late ScipIndex index;
      late FolderDependencyGraph graph;
      late ContextBuilder builder;

      setUp(() {
        index = MockScipIndex.withExternalDeps();
        graph = FolderDependencyGraph.build(index);
        builder = ContextBuilder(
          index: index,
          graph: graph,
          projectRoot: '/mock/project',
        );
      });

      test('includes external package summaries', () async {
        final context = await builder.buildForFolder('lib/features/auth');

        expect(
          context.externalDeps.any((d) => d.name == 'firebase_auth'),
          isTrue,
        );
      });

      test('includes used symbols from external packages', () async {
        final context = await builder.buildForFolder('lib/features/auth');

        final firebaseDep = context.externalDeps.firstWhere(
          (d) => d.name == 'firebase_auth',
          orElse: () => throw Exception('Firebase dep not found'),
        );

        expect(firebaseDep.usedSymbols, contains('FirebaseAuth'));
      });
    });
  });

  group('FolderSummary', () {
    test('toJson includes all fields', () {
      const summary = FolderSummary(
        path: 'lib/core',
        docSummary: 'Core utilities for the app.',
        publicApi: ['class Helper', 'class Utils'],
        usedSymbols: ['Helper', 'formatDate'],
      );

      final json = summary.toJson();

      expect(json['path'], 'lib/core');
      expect(json['docSummary'], 'Core utilities for the app.');
      expect(json['publicApi'], hasLength(2));
      expect(json['usedSymbols'], hasLength(2));
    });

    test('toJson omits null docSummary', () {
      const summary = FolderSummary(
        path: 'lib/core',
        docSummary: null,
        publicApi: [],
        usedSymbols: [],
      );

      final json = summary.toJson();

      expect(json.containsKey('docSummary'), isFalse);
    });
  });

  group('PackageSummary', () {
    test('toJson includes all fields', () {
      const summary = PackageSummary(
        name: 'http',
        version: '1.2.0',
        docSummary: 'HTTP client for Dart.',
        usedSymbols: ['Client', 'Response'],
      );

      final json = summary.toJson();

      expect(json['name'], 'http');
      expect(json['version'], '1.2.0');
      expect(json['docSummary'], 'HTTP client for Dart.');
      expect(json['usedSymbols'], hasLength(2));
    });

    test('toJson omits optional fields when null', () {
      const summary = PackageSummary(
        name: 'http',
        usedSymbols: ['Client'],
      );

      final json = summary.toJson();

      expect(json['name'], 'http');
      expect(json.containsKey('version'), isFalse);
      expect(json.containsKey('docSummary'), isFalse);
    });
  });

  group('DependentUsage', () {
    test('toJson includes all fields', () {
      const usage = DependentUsage(
        path: 'lib/ui/home',
        usedSymbols: ['HomeBloc', 'HomeState'],
      );

      final json = usage.toJson();

      expect(json['path'], 'lib/ui/home');
      expect(json['usedSymbols'], hasLength(2));
    });
  });

  group('DocContext', () {
    test('toJson produces complete structure', () {
      const context = DocContext(
        current: FolderContext(
          path: 'lib/test',
          files: [],
          internalDeps: {},
          externalDeps: {},
          usedSymbols: {},
        ),
        internalDeps: [],
        externalDeps: [],
        dependents: [],
      );

      final json = context.toJson();

      expect(json['current'], isA<Map>());
      expect(json['internalDeps'], isEmpty);
      expect(json['externalDeps'], isEmpty);
      expect(json['dependents'], isEmpty);
    });
  });
}
