import 'dart:io';

import 'package:code_context/code_context.dart';
import 'package:test/test.dart';

void main() {
  group('DartBinding', () {
    late DartBinding binding;

    setUp(() {
      binding = DartBinding();
    });

    test('has correct languageId', () {
      expect(binding.languageId, 'dart');
    });

    test('has correct extensions', () {
      expect(binding.extensions, contains('.dart'));
    });

    test('has correct packageFile', () {
      expect(binding.packageFile, 'pubspec.yaml');
    });

    test('supports incremental indexing', () {
      expect(binding.supportsIncremental, isTrue);
    });

    test('globalCachePath is non-empty', () {
      expect(binding.globalCachePath, isNotEmpty);
    });

    group('discoverPackages', () {
      late Directory tempDir;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('dart_binding_test_');
      });

      tearDown(() async {
        await tempDir.delete(recursive: true);
      });

      test('returns empty list for empty directory', () async {
        final packages = await binding.discoverPackages(tempDir.path);
        expect(packages, isEmpty);
      });

      test('discovers single package', () async {
        // Create a minimal Dart package
        await File('${tempDir.path}/pubspec.yaml').writeAsString('''
name: test_package
environment:
  sdk: ^3.0.0
''');

        final packages = await binding.discoverPackages(tempDir.path);

        expect(packages, hasLength(1));
        expect(packages.first.name, 'test_package');
        expect(packages.first.path, tempDir.path);
      });

      test('discovers multiple packages in monorepo', () async {
        // Create monorepo structure
        await File('${tempDir.path}/pubspec.yaml').writeAsString('''
name: root_package
environment:
  sdk: ^3.0.0
''');

        final packagesDir = Directory('${tempDir.path}/packages');
        await packagesDir.create();

        await Directory('${packagesDir.path}/pkg_a').create();
        await File('${packagesDir.path}/pkg_a/pubspec.yaml').writeAsString('''
name: pkg_a
environment:
  sdk: ^3.0.0
''');

        await Directory('${packagesDir.path}/pkg_b').create();
        await File('${packagesDir.path}/pkg_b/pubspec.yaml').writeAsString('''
name: pkg_b
environment:
  sdk: ^3.0.0
''');

        final packages = await binding.discoverPackages(tempDir.path);

        expect(packages, hasLength(3));
        expect(packages.map((p) => p.name), containsAll(['root_package', 'pkg_a', 'pkg_b']));
      });
    });

    group('createIndexer', () {
      late Directory tempDir;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('dart_binding_indexer_test_');

        // Create a minimal Dart package
        await File('${tempDir.path}/pubspec.yaml').writeAsString('''
name: test_package
environment:
  sdk: ^3.0.0
''');

        final libDir = Directory('${tempDir.path}/lib');
        await libDir.create();

        final dartToolDir = Directory('${tempDir.path}/.dart_tool');
        await dartToolDir.create();

        await File('${dartToolDir.path}/package_config.json').writeAsString('''
{
  "configVersion": 2,
  "packages": [
    {"name": "test_package", "rootUri": "../", "packageUri": "lib/"}
  ]
}
''');

        await File('${libDir.path}/example.dart').writeAsString('''
class Example {
  void hello() => print('hello');
}
''');
      });

      tearDown(() async {
        await tempDir.delete(recursive: true);
      });

      test('creates indexer and returns PackageIndexer', () async {
        final indexer = await binding.createIndexer(tempDir.path, useCache: false);

        expect(indexer, isA<PackageIndexer>());
        expect(indexer.index, isNotNull);
        expect(indexer.index.files, isNotEmpty);

        await indexer.dispose();
      });

      test('indexer finds symbols in project', () async {
        final indexer = await binding.createIndexer(tempDir.path, useCache: false);

        final symbols = indexer.index.findSymbols('Example');
        expect(symbols, isNotEmpty);
        expect(symbols.first.name, 'Example');

        await indexer.dispose();
      });
    });
  });

  group('LanguageBinding interface', () {
    test('DartBinding implements LanguageBinding', () {
      final binding = DartBinding();
      expect(binding, isA<LanguageBinding>());
    });

    test('DiscoveredPackage has required fields', () {
      final pkg = DiscoveredPackage(
        name: 'test_pkg',
        path: '/path/to/pkg',
        version: '1.0.0',
      );

      expect(pkg.name, 'test_pkg');
      expect(pkg.path, '/path/to/pkg');
      expect(pkg.version, '1.0.0');
    });
  });

  group('PackageIndexer interface', () {
    test('DartPackageIndexer has updates stream', () async {
      final tempDir = await Directory.systemTemp.createTemp('pkg_indexer_test_');

      try {
        // Create minimal package
        await File('${tempDir.path}/pubspec.yaml').writeAsString('''
name: test_package
environment:
  sdk: ^3.0.0
''');

        final libDir = Directory('${tempDir.path}/lib');
        await libDir.create();

        final dartToolDir = Directory('${tempDir.path}/.dart_tool');
        await dartToolDir.create();

        await File('${dartToolDir.path}/package_config.json').writeAsString('''
{"configVersion": 2, "packages": [{"name": "test_package", "rootUri": "../", "packageUri": "lib/"}]}
''');

        await File('${libDir.path}/test.dart').writeAsString('class Test {}');

        final binding = DartBinding();
        final indexer = await binding.createIndexer(tempDir.path, useCache: false);

        expect(indexer.updates, isNotNull);

        await indexer.dispose();
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}

