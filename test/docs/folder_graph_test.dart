import 'package:scip_server/src/docs/folder_graph.dart';
import 'package:scip_server/src/index/scip_index.dart';
import 'package:test/test.dart';

void main() {
  group('FolderDependencyGraph', () {
    group('build from ScipIndex', () {
      test('creates empty graph from empty index', () {
        final index = ScipIndex.empty();
        final graph = FolderDependencyGraph.build(index);

        expect(graph.folders, isEmpty);
        expect(graph.stats['folders'], equals(0));
        expect(graph.stats['internalEdges'], equals(0));
      });
    });

    group('forTesting constructor', () {
      test('creates graph with specified folders', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth', 'lib/core', 'lib/ui'},
          internalDeps: {},
        );

        expect(graph.folders, containsAll(['lib/auth', 'lib/core', 'lib/ui']));
        expect(graph.folders.length, equals(3));
      });

      test('creates graph with internal dependencies', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth', 'lib/core'},
          internalDeps: {
            'lib/auth': {'lib/core'},
            'lib/core': {},
          },
        );

        expect(graph.getInternalDependencies('lib/auth'), contains('lib/core'));
        expect(graph.getInternalDependencies('lib/core'), isEmpty);
      });

      test('creates graph with external dependencies', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth'},
          internalDeps: {'lib/auth': {}},
          externalDeps: {
            'lib/auth': {'firebase_auth', 'shared_preferences'},
          },
        );

        expect(
          graph.getExternalDependencies('lib/auth'),
          containsAll(['firebase_auth', 'shared_preferences']),
        );
      });

      test('auto-computes dependents from internal deps', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth', 'lib/core', 'lib/ui'},
          internalDeps: {
            'lib/auth': {'lib/core'},
            'lib/ui': {'lib/auth', 'lib/core'},
            'lib/core': {},
          },
        );

        // lib/core is used by lib/auth and lib/ui
        expect(
          graph.getDependents('lib/core'),
          containsAll(['lib/auth', 'lib/ui']),
        );

        // lib/auth is used by lib/ui
        expect(graph.getDependents('lib/auth'), contains('lib/ui'));

        // lib/ui is not used by anyone
        expect(graph.getDependents('lib/ui'), isEmpty);
      });
    });

    group('getInternalDependencies', () {
      test('returns empty set for unknown folder', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth'},
          internalDeps: {'lib/auth': {}},
        );

        expect(graph.getInternalDependencies('lib/unknown'), isEmpty);
      });

      test('returns direct dependencies only', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/a', 'lib/b', 'lib/c'},
          internalDeps: {
            'lib/a': {'lib/b'},
            'lib/b': {'lib/c'},
            'lib/c': {},
          },
        );

        // lib/a depends on lib/b but not directly on lib/c
        expect(graph.getInternalDependencies('lib/a'), equals({'lib/b'}));
        expect(
            graph.getInternalDependencies('lib/a'), isNot(contains('lib/c')));
      });
    });

    group('getExternalDependencies', () {
      test('returns empty set for unknown folder', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth'},
          internalDeps: {'lib/auth': {}},
        );

        expect(graph.getExternalDependencies('lib/unknown'), isEmpty);
      });

      test('returns all external packages for folder', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth', 'lib/data'},
          internalDeps: {},
          externalDeps: {
            'lib/auth': {'firebase_auth'},
            'lib/data': {'sqflite', 'path'},
          },
        );

        expect(graph.getExternalDependencies('lib/auth'),
            equals({'firebase_auth'}));
        expect(graph.getExternalDependencies('lib/data'),
            containsAll(['sqflite', 'path']));
      });
    });

    group('getDependents', () {
      test('returns empty set for unknown folder', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth'},
          internalDeps: {'lib/auth': {}},
        );

        expect(graph.getDependents('lib/unknown'), isEmpty);
      });

      test('returns all folders that depend on this folder', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth', 'lib/core', 'lib/ui', 'lib/admin'},
          internalDeps: {
            'lib/auth': {'lib/core'},
            'lib/ui': {'lib/core'},
            'lib/admin': {'lib/core'},
            'lib/core': {},
          },
        );

        expect(
          graph.getDependents('lib/core'),
          containsAll(['lib/auth', 'lib/ui', 'lib/admin']),
        );
        expect(graph.getDependents('lib/core').length, equals(3));
      });
    });

    group('dependsOn', () {
      test('returns false for unknown folders', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth'},
          internalDeps: {'lib/auth': {}},
        );

        expect(graph.dependsOn('lib/a', 'lib/b'), isFalse);
      });

      test('returns true for direct dependency', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth', 'lib/core'},
          internalDeps: {
            'lib/auth': {'lib/core'},
            'lib/core': {},
          },
        );

        expect(graph.dependsOn('lib/auth', 'lib/core'), isTrue);
      });

      test('returns false for transitive dependency', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/a', 'lib/b', 'lib/c'},
          internalDeps: {
            'lib/a': {'lib/b'},
            'lib/b': {'lib/c'},
            'lib/c': {},
          },
        );

        // Direct dependency
        expect(graph.dependsOn('lib/a', 'lib/b'), isTrue);
        // Transitive (not direct)
        expect(graph.dependsOn('lib/a', 'lib/c'), isFalse);
      });

      test('returns false for reverse dependency', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth', 'lib/core'},
          internalDeps: {
            'lib/auth': {'lib/core'},
            'lib/core': {},
          },
        );

        // auth depends on core, not the other way around
        expect(graph.dependsOn('lib/core', 'lib/auth'), isFalse);
      });
    });

    group('transitivelyDependsOn', () {
      test('returns false for unknown folders', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth'},
          internalDeps: {'lib/auth': {}},
        );

        expect(graph.transitivelyDependsOn('lib/a', 'lib/b'), isFalse);
      });

      test('returns true for direct dependency', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth', 'lib/core'},
          internalDeps: {
            'lib/auth': {'lib/core'},
            'lib/core': {},
          },
        );

        expect(graph.transitivelyDependsOn('lib/auth', 'lib/core'), isTrue);
      });

      test('returns true for transitive dependency', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/a', 'lib/b', 'lib/c', 'lib/d'},
          internalDeps: {
            'lib/a': {'lib/b'},
            'lib/b': {'lib/c'},
            'lib/c': {'lib/d'},
            'lib/d': {},
          },
        );

        expect(graph.transitivelyDependsOn('lib/a', 'lib/d'), isTrue);
        expect(graph.transitivelyDependsOn('lib/a', 'lib/c'), isTrue);
        expect(graph.transitivelyDependsOn('lib/b', 'lib/d'), isTrue);
      });

      test('returns false when no path exists', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/a', 'lib/b', 'lib/c'},
          internalDeps: {
            'lib/a': {'lib/b'},
            'lib/b': {},
            'lib/c': {},
          },
        );

        expect(graph.transitivelyDependsOn('lib/a', 'lib/c'), isFalse);
      });

      test('handles diamond dependencies', () {
        // Diamond: a -> b -> d
        //          a -> c -> d
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/a', 'lib/b', 'lib/c', 'lib/d'},
          internalDeps: {
            'lib/a': {'lib/b', 'lib/c'},
            'lib/b': {'lib/d'},
            'lib/c': {'lib/d'},
            'lib/d': {},
          },
        );

        expect(graph.transitivelyDependsOn('lib/a', 'lib/d'), isTrue);
      });

      test('handles cycles without infinite loop', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/a', 'lib/b', 'lib/c'},
          internalDeps: {
            'lib/a': {'lib/b'},
            'lib/b': {'lib/c'},
            'lib/c': {'lib/a'}, // Cycle back to a
          },
        );

        // Should not hang - finds b via direct dep
        expect(graph.transitivelyDependsOn('lib/a', 'lib/b'), isTrue);
        // Should find c through the cycle
        expect(graph.transitivelyDependsOn('lib/a', 'lib/c'), isTrue);
      });
    });

    group('internalDependencyGraph', () {
      test('returns the full dependency map', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/a', 'lib/b'},
          internalDeps: {
            'lib/a': {'lib/b'},
            'lib/b': {},
          },
        );

        final depGraph = graph.internalDependencyGraph;
        expect(depGraph['lib/a'], equals({'lib/b'}));
        expect(depGraph['lib/b'], isEmpty);
      });
    });

    group('stats', () {
      test('returns zero counts for empty graph', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {},
          internalDeps: {},
        );

        expect(graph.stats['folders'], equals(0));
        expect(graph.stats['internalEdges'], equals(0));
        expect(graph.stats['externalPackages'], equals(0));
      });

      test('counts folders correctly', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/a', 'lib/b', 'lib/c'},
          internalDeps: {},
        );

        expect(graph.stats['folders'], equals(3));
      });

      test('counts internal edges correctly', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/a', 'lib/b', 'lib/c'},
          internalDeps: {
            'lib/a': {'lib/b', 'lib/c'},
            'lib/b': {'lib/c'},
            'lib/c': {},
          },
        );

        // a->b, a->c, b->c = 3 edges
        expect(graph.stats['internalEdges'], equals(3));
      });

      test('counts unique external packages', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/a', 'lib/b'},
          internalDeps: {},
          externalDeps: {
            'lib/a': {'http', 'json'},
            'lib/b': {'http', 'sqflite'}, // http is shared
          },
        );

        // http, json, sqflite = 3 unique packages
        expect(graph.stats['externalPackages'], equals(3));
      });
    });

    group('toString', () {
      test('formats empty graph', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {},
          internalDeps: {},
        );

        expect(graph.toString(), equals('FolderDependencyGraph(\n)'));
      });

      test('formats graph with dependencies', () {
        final graph = FolderDependencyGraph.forTesting(
          folders: {'lib/auth', 'lib/core'},
          internalDeps: {
            'lib/auth': {'lib/core'},
            'lib/core': {},
          },
          externalDeps: {
            'lib/auth': {'firebase_auth'},
            'lib/core': {},
          },
        );

        final str = graph.toString();
        expect(str, contains('lib/auth:'));
        expect(str, contains('lib/core'));
        expect(str, contains('firebase_auth'));
      });
    });
  });
}
