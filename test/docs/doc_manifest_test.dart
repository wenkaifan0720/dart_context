import 'dart:io';

import 'package:scip_server/src/docs/doc_manifest.dart';
import 'package:test/test.dart';

void main() {
  group('DocManifest', () {
    group('fromJson/toJson', () {
      test('round-trips empty manifest', () {
        final manifest = DocManifest();
        final json = manifest.toJson();
        final restored = DocManifest.fromJson(json);

        expect(restored.version, equals(manifest.version));
        expect(restored.folders, isEmpty);
        expect(restored.modules, isEmpty);
        expect(restored.project, isNull);
      });

      test('round-trips manifest with folder state', () {
        final manifest = DocManifest(
          folders: {
            'lib/auth': FolderDocState(
              structureHash: 'abc123',
              docHash: 'def456',
              generatedAt: DateTime(2025, 1, 12),
              internalDeps: ['lib/core'],
              externalDeps: ['firebase_auth'],
              smartSymbols: ['scip://lib/auth/service.dart/AuthService#'],
            ),
          },
        );

        final json = manifest.toJson();
        final restored = DocManifest.fromJson(json);

        expect(restored.folders.length, equals(1));
        expect(restored.folders['lib/auth']!.structureHash, equals('abc123'));
        expect(restored.folders['lib/auth']!.docHash, equals('def456'));
        expect(restored.folders['lib/auth']!.internalDeps, contains('lib/core'));
        expect(
          restored.folders['lib/auth']!.externalDeps,
          contains('firebase_auth'),
        );
      });

      test('round-trips manifest with module state', () {
        final manifest = DocManifest(
          modules: {
            'auth': ModuleDocState(
              docHash: 'abc123',
              generatedAt: DateTime(2025, 1, 12),
              childFolders: ['lib/features/auth', 'lib/services/auth'],
              folderDocHashes: {
                'lib/features/auth': 'hash1',
                'lib/services/auth': 'hash2',
              },
            ),
          },
        );

        final json = manifest.toJson();
        final restored = DocManifest.fromJson(json);

        expect(restored.modules.length, equals(1));
        expect(restored.modules['auth']!.docHash, equals('abc123'));
        expect(
          restored.modules['auth']!.childFolders,
          containsAll(['lib/features/auth', 'lib/services/auth']),
        );
      });

      test('round-trips manifest with project state', () {
        final manifest = DocManifest(
          project: ProjectDocState(
            docHash: 'projhash',
            generatedAt: DateTime(2025, 1, 12),
            moduleDocHashes: {'auth': 'authhash', 'products': 'prodhash'},
          ),
        );

        final json = manifest.toJson();
        final restored = DocManifest.fromJson(json);

        expect(restored.project, isNotNull);
        expect(restored.project!.docHash, equals('projhash'));
        expect(restored.project!.moduleDocHashes['auth'], equals('authhash'));
      });
    });

    group('isFolderDirty', () {
      test('returns true for unknown folder', () {
        final manifest = DocManifest();
        expect(manifest.isFolderDirty('lib/auth', 'anyhash'), isTrue);
      });

      test('returns true when structure hash changed', () {
        final manifest = DocManifest(
          folders: {
            'lib/auth': FolderDocState(
              structureHash: 'oldhash',
              docHash: 'dochash',
              generatedAt: DateTime.now(),
            ),
          },
        );

        expect(manifest.isFolderDirty('lib/auth', 'newhash'), isTrue);
      });

      test('returns false when structure hash unchanged', () {
        final manifest = DocManifest(
          folders: {
            'lib/auth': FolderDocState(
              structureHash: 'samehash',
              docHash: 'dochash',
              generatedAt: DateTime.now(),
            ),
          },
        );

        expect(manifest.isFolderDirty('lib/auth', 'samehash'), isFalse);
      });
    });

    group('isModuleDirty', () {
      test('returns true for unknown module', () {
        final manifest = DocManifest();
        expect(manifest.isModuleDirty('auth', ['lib/auth']), isTrue);
      });

      test('returns true when child folder missing', () {
        final manifest = DocManifest(
          modules: {
            'auth': ModuleDocState(
              docHash: 'modhash',
              generatedAt: DateTime.now(),
              childFolders: ['lib/auth'],
              folderDocHashes: {'lib/auth': 'oldhash'},
            ),
          },
        );

        // Child folder not in folders map
        expect(manifest.isModuleDirty('auth', ['lib/auth']), isTrue);
      });

      test('returns true when child folder doc hash changed', () {
        final manifest = DocManifest(
          folders: {
            'lib/auth': FolderDocState(
              structureHash: 'struct',
              docHash: 'newhash', // Changed
              generatedAt: DateTime.now(),
            ),
          },
          modules: {
            'auth': ModuleDocState(
              docHash: 'modhash',
              generatedAt: DateTime.now(),
              childFolders: ['lib/auth'],
              folderDocHashes: {'lib/auth': 'oldhash'}, // Old hash
            ),
          },
        );

        expect(manifest.isModuleDirty('auth', ['lib/auth']), isTrue);
      });

      test('returns false when child folder doc hash unchanged', () {
        final manifest = DocManifest(
          folders: {
            'lib/auth': FolderDocState(
              structureHash: 'struct',
              docHash: 'samehash',
              generatedAt: DateTime.now(),
            ),
          },
          modules: {
            'auth': ModuleDocState(
              docHash: 'modhash',
              generatedAt: DateTime.now(),
              childFolders: ['lib/auth'],
              folderDocHashes: {'lib/auth': 'samehash'},
            ),
          },
        );

        expect(manifest.isModuleDirty('auth', ['lib/auth']), isFalse);
      });
    });

    group('isProjectDirty', () {
      test('returns true when no project state', () {
        final manifest = DocManifest();
        expect(manifest.isProjectDirty(['auth']), isTrue);
      });

      test('returns true when module doc hash changed', () {
        final manifest = DocManifest(
          modules: {
            'auth': ModuleDocState(
              docHash: 'newhash',
              generatedAt: DateTime.now(),
              childFolders: [],
            ),
          },
          project: ProjectDocState(
            docHash: 'projhash',
            generatedAt: DateTime.now(),
            moduleDocHashes: {'auth': 'oldhash'},
          ),
        );

        expect(manifest.isProjectDirty(['auth']), isTrue);
      });
    });

    group('getDirtyFolders', () {
      test('returns all folders when manifest is empty', () {
        final manifest = DocManifest();
        final hashes = {
          'lib/auth': 'hash1',
          'lib/core': 'hash2',
        };

        final dirty = manifest.getDirtyFolders(hashes);

        expect(dirty, containsAll(['lib/auth', 'lib/core']));
      });

      test('returns only changed folders', () {
        final manifest = DocManifest(
          folders: {
            'lib/auth': FolderDocState(
              structureHash: 'unchanged',
              docHash: 'doc',
              generatedAt: DateTime.now(),
            ),
            'lib/core': FolderDocState(
              structureHash: 'oldhash',
              docHash: 'doc',
              generatedAt: DateTime.now(),
            ),
          },
        );

        final hashes = {
          'lib/auth': 'unchanged',
          'lib/core': 'newhash',
        };

        final dirty = manifest.getDirtyFolders(hashes);

        expect(dirty, equals(['lib/core']));
      });
    });

    group('pruneRemovedFolders', () {
      test('removes folders not in existing set', () {
        final manifest = DocManifest(
          folders: {
            'lib/auth': FolderDocState(
              structureHash: 'hash',
              docHash: 'doc',
              generatedAt: DateTime.now(),
            ),
            'lib/removed': FolderDocState(
              structureHash: 'hash',
              docHash: 'doc',
              generatedAt: DateTime.now(),
            ),
          },
        );

        manifest.pruneRemovedFolders({'lib/auth'});

        expect(manifest.folders.keys, equals(['lib/auth']));
      });
    });

    group('load/save', () {
      test('loads empty manifest from non-existent file', () async {
        final manifest = await DocManifest.load('/nonexistent/path.json');
        expect(manifest.folders, isEmpty);
      });

      test('round-trips through file', () async {
        final tempDir = await Directory.systemTemp.createTemp('manifest_test');
        final path = '${tempDir.path}/manifest.json';

        try {
          final original = DocManifest(
            folders: {
              'lib/auth': FolderDocState(
                structureHash: 'abc',
                docHash: 'def',
                generatedAt: DateTime(2025, 1, 12),
              ),
            },
          );

          await original.save(path);
          final loaded = await DocManifest.load(path);

          expect(loaded.folders['lib/auth']!.structureHash, equals('abc'));
          expect(loaded.folders['lib/auth']!.docHash, equals('def'));
        } finally {
          await tempDir.delete(recursive: true);
        }
      });

      test('handles corrupted file gracefully', () async {
        final tempDir = await Directory.systemTemp.createTemp('manifest_test');
        final path = '${tempDir.path}/manifest.json';

        try {
          await File(path).writeAsString('not valid json');
          final manifest = await DocManifest.load(path);
          expect(manifest.folders, isEmpty);
        } finally {
          await tempDir.delete(recursive: true);
        }
      });
    });
  });
}
