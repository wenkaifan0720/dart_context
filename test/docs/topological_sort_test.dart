import 'package:scip_server/src/docs/topological_sort.dart';
import 'package:test/test.dart';

void main() {
  group('TopologicalSort', () {
    group('findSCCs', () {
      test('finds single-node components', () {
        final graph = {
          'a': <String>{},
          'b': <String>{},
          'c': <String>{},
        };

        final sccs = TopologicalSort.findSCCs(graph);

        expect(sccs.length, equals(3));
        expect(sccs.every((scc) => scc.length == 1), isTrue);
      });

      test('finds two-node cycle', () {
        final graph = {
          'a': {'b'},
          'b': {'a'},
        };

        final sccs = TopologicalSort.findSCCs(graph);

        expect(sccs.length, equals(1));
        expect(sccs.first, containsAll(['a', 'b']));
      });

      test('finds three-node cycle', () {
        final graph = {
          'a': {'b'},
          'b': {'c'},
          'c': {'a'},
        };

        final sccs = TopologicalSort.findSCCs(graph);

        expect(sccs.length, equals(1));
        expect(sccs.first, containsAll(['a', 'b', 'c']));
      });

      test('separates independent cycles', () {
        final graph = {
          'a': {'b'},
          'b': {'a'},
          'c': {'d'},
          'd': {'c'},
        };

        final sccs = TopologicalSort.findSCCs(graph);

        expect(sccs.length, equals(2));
        expect(sccs.any((scc) => scc.containsAll(['a', 'b'])), isTrue);
        expect(sccs.any((scc) => scc.containsAll(['c', 'd'])), isTrue);
      });

      test('handles DAG (no cycles)', () {
        final graph = {
          'a': {'b', 'c'},
          'b': {'d'},
          'c': {'d'},
          'd': <String>{},
        };

        final sccs = TopologicalSort.findSCCs(graph);

        expect(sccs.length, equals(4));
        expect(sccs.every((scc) => scc.length == 1), isTrue);
      });
    });

    group('hasCycles', () {
      test('returns false for DAG', () {
        final graph = {
          'a': {'b'},
          'b': {'c'},
          'c': <String>{},
        };

        expect(TopologicalSort.hasCycles(graph), isFalse);
      });

      test('returns true for graph with cycle', () {
        final graph = {
          'a': {'b'},
          'b': {'a'},
        };

        expect(TopologicalSort.hasCycles(graph), isTrue);
      });

      test('returns false for empty graph', () {
        final graph = <String, Set<String>>{};

        expect(TopologicalSort.hasCycles(graph), isFalse);
      });
    });

    group('getCycles', () {
      test('returns empty list for DAG', () {
        final graph = {
          'a': {'b'},
          'b': <String>{},
        };

        expect(TopologicalSort.getCycles(graph), isEmpty);
      });

      test('returns cycles only', () {
        final graph = {
          'a': {'b'},
          'b': {'a'},
          'c': <String>{},
        };

        final cycles = TopologicalSort.getCycles(graph);

        expect(cycles.length, equals(1));
        expect(cycles.first, containsAll(['a', 'b']));
      });
    });

    group('sort', () {
      // sort requires FolderDependencyGraph, which needs ScipIndex
      // These tests would need integration with the full pipeline
    });
  });
}
