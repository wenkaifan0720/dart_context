import 'package:scip_server/src/docs/folder_graph.dart';
import 'package:scip_server/src/index/scip_index.dart';
import 'package:test/test.dart';

void main() {
  group('FolderDependencyGraph', () {
    group('build', () {
      test('creates empty graph from empty index', () {
        final index = ScipIndex.empty();
        final graph = FolderDependencyGraph.build(index);

        expect(graph.folders, isEmpty);
      });
    });

    group('getInternalDependencies', () {
      test('returns empty set for unknown folder', () {
        final index = ScipIndex.empty();
        final graph = FolderDependencyGraph.build(index);

        expect(graph.getInternalDependencies('unknown'), isEmpty);
      });
    });

    group('getExternalDependencies', () {
      test('returns empty set for unknown folder', () {
        final index = ScipIndex.empty();
        final graph = FolderDependencyGraph.build(index);

        expect(graph.getExternalDependencies('unknown'), isEmpty);
      });
    });

    group('getDependents', () {
      test('returns empty set for unknown folder', () {
        final index = ScipIndex.empty();
        final graph = FolderDependencyGraph.build(index);

        expect(graph.getDependents('unknown'), isEmpty);
      });
    });

    group('dependsOn', () {
      test('returns false for unknown folders', () {
        final index = ScipIndex.empty();
        final graph = FolderDependencyGraph.build(index);

        expect(graph.dependsOn('a', 'b'), isFalse);
      });
    });

    group('transitivelyDependsOn', () {
      test('returns false for unknown folders', () {
        final index = ScipIndex.empty();
        final graph = FolderDependencyGraph.build(index);

        expect(graph.transitivelyDependsOn('a', 'b'), isFalse);
      });
    });

    group('stats', () {
      test('returns zero counts for empty graph', () {
        final index = ScipIndex.empty();
        final graph = FolderDependencyGraph.build(index);

        expect(graph.stats['folders'], equals(0));
        expect(graph.stats['internalEdges'], equals(0));
        expect(graph.stats['externalPackages'], equals(0));
      });
    });

    group('_extractPackageName', () {
      test('extracts package name from SCIP symbol', () {
        // The static method is private, but we can test via the graph behavior
        // For unit testing the extraction, we'd need to make it testable
      });
    });
  });
}
