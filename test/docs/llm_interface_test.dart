import 'package:scip_server/scip_server.dart';
import 'package:test/test.dart';

void main() {
  group('GeneratedDoc', () {
    test('stores all fields', () {
      const doc = GeneratedDoc(
        content: '# My Doc\n\nSome content.',
        smartSymbols: ['scip://lib/test#'],
        title: 'My Doc',
        summary: 'A short summary.',
      );

      expect(doc.content, contains('# My Doc'));
      expect(doc.smartSymbols, hasLength(1));
      expect(doc.title, 'My Doc');
      expect(doc.summary, 'A short summary.');
    });

    test('allows null title and summary', () {
      const doc = GeneratedDoc(
        content: 'Content',
        smartSymbols: [],
      );

      expect(doc.title, isNull);
      expect(doc.summary, isNull);
    });
  });

  group('FolderDocSummary', () {
    test('stores all fields', () {
      const summary = FolderDocSummary(
        path: 'lib/test',
        content: '# Test folder',
        summary: 'Test folder summary.',
        smartSymbols: ['scip://symbol1#', 'scip://symbol2#'],
      );

      expect(summary.path, 'lib/test');
      expect(summary.content, '# Test folder');
      expect(summary.summary, 'Test folder summary.');
      expect(summary.smartSymbols, hasLength(2));
    });
  });

  group('ModuleDocSummary', () {
    test('stores all fields', () {
      const summary = ModuleDocSummary(
        name: 'auth',
        content: '# Auth Module',
        summary: 'Authentication module.',
        smartSymbols: ['scip://auth#'],
      );

      expect(summary.name, 'auth');
      expect(summary.content, '# Auth Module');
      expect(summary.summary, 'Authentication module.');
      expect(summary.smartSymbols, hasLength(1));
    });
  });

  group('StubDocGenerator', () {
    const generator = StubDocGenerator();

    group('generateFolderDoc', () {
      test('generates doc with title from folder name', () async {
        const context = DocContext(
          current: FolderContext(
            path: 'lib/features/auth',
            files: [],
            internalDeps: {},
            externalDeps: {},
            usedSymbols: {},
          ),
          internalDeps: [],
          externalDeps: [],
          dependents: [],
        );

        final doc = await generator.generateFolderDoc(context);

        expect(doc.title, 'Auth');
        expect(doc.content, contains('# Auth'));
      });

      test('includes files section', () async {
        const context = DocContext(
          current: FolderContext(
            path: 'lib/test',
            files: [
              FileContext(
                path: 'lib/test/service.dart',
                docComments: [],
                publicApi: [
                  ApiSignature(
                    name: 'TestService',
                    kind: 'class',
                    signature: 'class TestService',
                  ),
                ],
                symbols: [],
              ),
            ],
            internalDeps: {},
            externalDeps: {},
            usedSymbols: {},
          ),
          internalDeps: [],
          externalDeps: [],
          dependents: [],
        );

        final doc = await generator.generateFolderDoc(context);

        expect(doc.content, contains('## Files'));
        expect(doc.content, contains('service.dart'));
        expect(doc.content, contains('TestService'));
      });

      test('includes dependencies section', () async {
        const context = DocContext(
          current: FolderContext(
            path: 'lib/test',
            files: [],
            internalDeps: {},
            externalDeps: {},
            usedSymbols: {},
          ),
          internalDeps: [
            FolderSummary(
              path: 'lib/core',
              docSummary: null,
              publicApi: [],
              usedSymbols: ['Helper'],
            ),
          ],
          externalDeps: [
            PackageSummary(
              name: 'http',
              usedSymbols: ['Client'],
            ),
          ],
          dependents: [],
        );

        final doc = await generator.generateFolderDoc(context);

        expect(doc.content, contains('## Dependencies'));
        expect(doc.content, contains('### Internal'));
        expect(doc.content, contains('lib/core'));
        expect(doc.content, contains('### External Packages'));
        expect(doc.content, contains('http'));
      });

      test('generates smart symbols for public API', () async {
        const context = DocContext(
          current: FolderContext(
            path: 'lib/test',
            files: [
              FileContext(
                path: 'lib/test/my_class.dart',
                docComments: [],
                publicApi: [
                  ApiSignature(
                    name: 'MyClass',
                    kind: 'class',
                    signature: 'class MyClass',
                  ),
                ],
                symbols: [],
              ),
            ],
            internalDeps: {},
            externalDeps: {},
            usedSymbols: {},
          ),
          internalDeps: [],
          externalDeps: [],
          dependents: [],
        );

        final doc = await generator.generateFolderDoc(context);

        expect(doc.smartSymbols, contains('scip://lib/test/my_class.dart/MyClass#'));
      });

      test('includes smart symbol definitions in content', () async {
        const context = DocContext(
          current: FolderContext(
            path: 'lib/test',
            files: [
              FileContext(
                path: 'lib/test/api.dart',
                docComments: [],
                publicApi: [
                  ApiSignature(
                    name: 'ApiClient',
                    kind: 'class',
                    signature: 'class ApiClient',
                  ),
                ],
                symbols: [],
              ),
            ],
            internalDeps: {},
            externalDeps: {},
            usedSymbols: {},
          ),
          internalDeps: [],
          externalDeps: [],
          dependents: [],
        );

        final doc = await generator.generateFolderDoc(context);

        expect(doc.content, contains('[apiclient]: scip://lib/test/api.dart/ApiClient#'));
      });

      test('converts snake_case folder to Title Case', () async {
        const context = DocContext(
          current: FolderContext(
            path: 'lib/features/user_profile',
            files: [],
            internalDeps: {},
            externalDeps: {},
            usedSymbols: {},
          ),
          internalDeps: [],
          externalDeps: [],
          dependents: [],
        );

        final doc = await generator.generateFolderDoc(context);

        expect(doc.title, 'User Profile');
      });
    });

    group('generateModuleDoc', () {
      test('generates module doc with title', () async {
        final doc = await generator.generateModuleDoc(
          'authentication',
          [
            const FolderDocSummary(
              path: 'lib/features/auth',
              content: '# Auth',
              summary: 'Auth folder',
              smartSymbols: [],
            ),
          ],
        );

        expect(doc.title, 'Authentication Module');
        expect(doc.content, contains('# Authentication Module'));
      });

      test('lists all folders', () async {
        final doc = await generator.generateModuleDoc(
          'core',
          [
            const FolderDocSummary(
              path: 'lib/core/utils',
              content: '',
              summary: 'Utilities',
              smartSymbols: [],
            ),
            const FolderDocSummary(
              path: 'lib/core/helpers',
              content: '',
              summary: 'Helpers',
              smartSymbols: [],
            ),
          ],
        );

        expect(doc.content, contains('## Components'));
        expect(doc.content, contains('lib/core/utils'));
        expect(doc.content, contains('lib/core/helpers'));
      });

      test('aggregates smart symbols from folders', () async {
        final doc = await generator.generateModuleDoc(
          'test',
          [
            const FolderDocSummary(
              path: 'lib/a',
              content: '',
              summary: null,
              smartSymbols: ['scip://a#'],
            ),
            const FolderDocSummary(
              path: 'lib/b',
              content: '',
              summary: null,
              smartSymbols: ['scip://b#'],
            ),
          ],
        );

        expect(doc.smartSymbols, containsAll(['scip://a#', 'scip://b#']));
      });
    });

    group('generateProjectDoc', () {
      test('generates project doc', () async {
        final doc = await generator.generateProjectDoc(
          'MyApp',
          [
            const ModuleDocSummary(
              name: 'auth',
              content: '',
              summary: 'Auth module',
              smartSymbols: [],
            ),
            const ModuleDocSummary(
              name: 'products',
              content: '',
              summary: 'Products module',
              smartSymbols: [],
            ),
          ],
        );

        expect(doc.title, 'MyApp');
        expect(doc.content, contains('# MyApp'));
        expect(doc.content, contains('## Modules'));
        expect(doc.content, contains('auth'));
        expect(doc.content, contains('products'));
      });

      test('aggregates smart symbols from modules', () async {
        final doc = await generator.generateProjectDoc(
          'Test',
          [
            const ModuleDocSummary(
              name: 'a',
              content: '',
              summary: null,
              smartSymbols: ['scip://mod-a#'],
            ),
            const ModuleDocSummary(
              name: 'b',
              content: '',
              summary: null,
              smartSymbols: ['scip://mod-b#'],
            ),
          ],
        );

        expect(doc.smartSymbols, containsAll(['scip://mod-a#', 'scip://mod-b#']));
      });
    });
  });
}
