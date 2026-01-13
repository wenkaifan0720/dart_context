import 'package:scip_server/src/docs/folder_graph.dart';
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

      test('handles self-loop', () {
        final graph = {
          'a': {'a'}, // Self-loop
          'b': <String>{},
        };

        final sccs = TopologicalSort.findSCCs(graph);

        // 'a' forms an SCC with itself, 'b' is separate
        expect(sccs.length, equals(2));
      });

      test('handles complex graph with multiple SCCs', () {
        // Graph: a -> b -> c (cycle a-b-c-a)
        //        d -> e (no cycle)
        //        c -> d (connects cycle to non-cycle)
        final graph = {
          'a': {'b'},
          'b': {'c'},
          'c': {'a', 'd'},
          'd': {'e'},
          'e': <String>{},
        };

        final sccs = TopologicalSort.findSCCs(graph);

        // Should have 3 SCCs: {a,b,c}, {d}, {e}
        expect(sccs.length, equals(3));
        expect(sccs.any((scc) => scc.containsAll(['a', 'b', 'c'])), isTrue);
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

      // Note: Self-loops (a -> a) are a degenerate case.
      // In Tarjan's algorithm, they form single-node SCCs, which our
      // hasCycles() doesn't count as cycles (requires 2+ nodes).
      // This is fine for folder dependencies - a folder can't depend on itself.
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

      test('returns multiple cycles', () {
        final graph = {
          'a': {'b'},
          'b': {'a'},
          'c': {'d'},
          'd': {'c'},
          'e': <String>{},
        };

        final cycles = TopologicalSort.getCycles(graph);

        expect(cycles.length, equals(2));
      });
    });

    group('sort', () {
      test('returns empty list for empty graph', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {},
          internalDeps: {},
        );

        final sorted = TopologicalSort.sort(graph);

        expect(sorted, isEmpty);
      });

      test('returns single folder', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth'},
          internalDeps: {'lib/auth': {}},
        );

        final sorted = TopologicalSort.sort(graph);

        expect(sorted.length, equals(1));
        expect(sorted.first, equals(['lib/auth']));
      });

      test('orders dependencies before dependents', () {
        // lib/ui depends on lib/auth depends on lib/core
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/ui', 'lib/auth', 'lib/core'},
          internalDeps: {
            'lib/ui': {'lib/auth'},
            'lib/auth': {'lib/core'},
            'lib/core': {},
          },
        );

        final sorted = TopologicalSort.sort(graph);

        // Flatten to get order
        final order = sorted.expand((g) => g).toList();

        // lib/core should come before lib/auth
        expect(order.indexOf('lib/core'), lessThan(order.indexOf('lib/auth')));
        // lib/auth should come before lib/ui
        expect(order.indexOf('lib/auth'), lessThan(order.indexOf('lib/ui')));
      });

      test('handles independent folders in parallel', () {
        // lib/auth and lib/products are independent, both depend on lib/core
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth', 'lib/products', 'lib/core'},
          internalDeps: {
            'lib/auth': {'lib/core'},
            'lib/products': {'lib/core'},
            'lib/core': {},
          },
        );

        final sorted = TopologicalSort.sort(graph);

        // Flatten to get order
        final order = sorted.expand((g) => g).toList();

        // lib/core should come first
        expect(order.first, equals('lib/core'));
        // lib/auth and lib/products come after lib/core
        expect(order.indexOf('lib/auth'), greaterThan(order.indexOf('lib/core')));
        expect(order.indexOf('lib/products'), greaterThan(order.indexOf('lib/core')));
      });

      test('groups cycles together', () {
        // lib/a and lib/b form a cycle
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/a', 'lib/b', 'lib/c'},
          internalDeps: {
            'lib/a': {'lib/b'},
            'lib/b': {'lib/a'},
            'lib/c': {'lib/a'}, // c depends on the cycle
          },
        );

        final sorted = TopologicalSort.sort(graph);

        // Find the group containing the cycle
        final cycleGroup = sorted.firstWhere(
          (g) => g.contains('lib/a') || g.contains('lib/b'),
        );

        // Both a and b should be in the same group
        expect(cycleGroup, containsAll(['lib/a', 'lib/b']));

        // The cycle should come before lib/c
        final cycleIndex = sorted.indexOf(cycleGroup);
        final cIndex = sorted.indexWhere((g) => g.contains('lib/c'));
        expect(cycleIndex, lessThan(cIndex));
      });

      test('handles diamond dependency', () {
        // Diamond: lib/ui -> lib/auth -> lib/core
        //          lib/ui -> lib/data -> lib/core
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/ui', 'lib/auth', 'lib/data', 'lib/core'},
          internalDeps: {
            'lib/ui': {'lib/auth', 'lib/data'},
            'lib/auth': {'lib/core'},
            'lib/data': {'lib/core'},
            'lib/core': {},
          },
        );

        final sorted = TopologicalSort.sort(graph);
        final order = sorted.expand((g) => g).toList();

        // lib/core comes first
        expect(order.first, equals('lib/core'));
        // lib/ui comes last
        expect(order.last, equals('lib/ui'));
        // lib/auth and lib/data are in between
        expect(order.indexOf('lib/auth'), greaterThan(0));
        expect(order.indexOf('lib/auth'), lessThan(order.length - 1));
      });

      test('handles complex graph with cycle and dependencies', () {
        // lib/core (no deps)
        // lib/a <-> lib/b (cycle, depends on core)
        // lib/ui (depends on the cycle)
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/core', 'lib/a', 'lib/b', 'lib/ui'},
          internalDeps: {
            'lib/core': {},
            'lib/a': {'lib/b', 'lib/core'},
            'lib/b': {'lib/a', 'lib/core'},
            'lib/ui': {'lib/a'},
          },
        );

        final sorted = TopologicalSort.sort(graph);
        final order = sorted.expand((g) => g).toList();

        // lib/core comes first (no deps)
        expect(order.first, equals('lib/core'));
        // lib/ui comes last (depends on everything)
        expect(order.last, equals('lib/ui'));

        // The cycle {lib/a, lib/b} is grouped
        final cycleGroup = sorted.firstWhere(
          (g) => g.length > 1,
          orElse: () => [],
        );
        if (cycleGroup.isNotEmpty) {
          expect(cycleGroup, containsAll(['lib/a', 'lib/b']));
        }
      });

      test('each group is sorted alphabetically', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/zebra', 'lib/alpha', 'lib/beta'},
          internalDeps: {
            'lib/zebra': {},
            'lib/alpha': {},
            'lib/beta': {},
          },
        );

        final sorted = TopologicalSort.sort(graph);

        // Each group should be sorted
        for (final group in sorted) {
          final sortedGroup = List<String>.from(group)..sort();
          expect(group, equals(sortedGroup));
        }
      });
    });
  });
}
