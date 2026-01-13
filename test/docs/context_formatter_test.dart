import 'package:scip_server/scip_server.dart';
import 'package:test/test.dart';

void main() {
  group('ContextFormatter', () {
    const formatter = ContextFormatter();

    test('formats basic DocContext as YAML', () {
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

      final yaml = formatter.formatAsYaml(context);

      expect(yaml, contains('# Documentation Context for: lib/features/auth'));
      expect(yaml, contains('CURRENT FOLDER'));
      expect(yaml, contains('folder:'));
      expect(yaml, contains('path: lib/features/auth'));
    });

    test('formats files with public API', () {
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
                  docComment: 'A test service.',
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

      final yaml = formatter.formatAsYaml(context);

      expect(yaml, contains('lib/test/service.dart'));
      expect(yaml, contains('public_api:'));
      expect(yaml, contains('class TestService'));
    });

    test('formats internal dependencies', () {
      const context = DocContext(
        current: FolderContext(
          path: 'lib/features/auth',
          files: [],
          internalDeps: {},
          externalDeps: {},
          usedSymbols: {},
        ),
        internalDeps: [
          FolderSummary(
            path: 'lib/core',
            docSummary: 'Core utilities.',
            publicApi: ['class Helper'],
            usedSymbols: ['Helper'],
          ),
        ],
        externalDeps: [],
        dependents: [],
      );

      final yaml = formatter.formatAsYaml(context);

      expect(yaml, contains('INTERNAL DEPENDENCIES'));
      expect(yaml, contains('internal_dependencies:'));
      expect(yaml, contains('lib/core'));
      expect(yaml, contains('Core utilities.'));
      expect(yaml, contains('used_symbols:'));
      expect(yaml, contains('Helper'));
    });

    test('formats external dependencies', () {
      const context = DocContext(
        current: FolderContext(
          path: 'lib/features/auth',
          files: [],
          internalDeps: {},
          externalDeps: {},
          usedSymbols: {},
        ),
        internalDeps: [],
        externalDeps: [
          PackageSummary(
            name: 'firebase_auth',
            version: '4.0.0',
            usedSymbols: ['FirebaseAuth', 'UserCredential'],
          ),
        ],
        dependents: [],
      );

      final yaml = formatter.formatAsYaml(context);

      expect(yaml, contains('EXTERNAL PACKAGES'));
      expect(yaml, contains('external_dependencies:'));
      expect(yaml, contains('firebase_auth'));
      expect(yaml, contains('FirebaseAuth'));
    });

    test('formats dependents', () {
      const context = DocContext(
        current: FolderContext(
          path: 'lib/core',
          files: [],
          internalDeps: {},
          externalDeps: {},
          usedSymbols: {},
        ),
        internalDeps: [],
        externalDeps: [],
        dependents: [
          DependentUsage(
            path: 'lib/features/auth',
            usedSymbols: ['Helper', 'formatDate'],
          ),
        ],
      );

      final yaml = formatter.formatAsYaml(context);

      expect(yaml, contains('DEPENDENTS'));
      expect(yaml, contains('dependents:'));
      expect(yaml, contains('lib/features/auth'));
      expect(yaml, contains('uses:'));
      expect(yaml, contains('Helper'));
    });

    test('formats symbols with relationships', () {
      const context = DocContext(
        current: FolderContext(
          path: 'lib/test',
          files: [
            FileContext(
              path: 'lib/test/child.dart',
              docComments: [],
              publicApi: [],
              symbols: [
                SymbolSummary(
                  id: 'scip://lib/test/child.dart/Child#',
                  name: 'Child',
                  kind: 'class',
                  relationships: [
                    SymbolRelationship(
                      targetId: 'scip://lib/test/parent.dart/Parent#',
                      targetName: 'Parent',
                      kind: 'implements',
                    ),
                  ],
                ),
              ],
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

      final yaml = formatter.formatAsYaml(context);

      expect(yaml, contains('symbols:'));
      expect(yaml, contains('name: Child'));
      expect(yaml, contains('relationships:'));
      expect(yaml, contains('implements: Parent'));
    });

    test('escapes special YAML characters', () {
      const context = DocContext(
        current: FolderContext(
          path: 'lib/test',
          files: [
            FileContext(
              path: 'lib/test/special.dart',
              docComments: [],
              publicApi: [
                ApiSignature(
                  name: 'Special',
                  kind: 'class',
                  signature: 'class Special<T extends Base>',
                  docComment: 'Has "quotes" and: colons',
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

      final yaml = formatter.formatAsYaml(context);

      // Should escape special characters
      expect(yaml, contains('Special<T extends Base>'));
      expect(yaml, contains(r'\"quotes\"'));
    });

    test('omits empty sections', () {
      const context = DocContext(
        current: FolderContext(
          path: 'lib/standalone',
          files: [],
          internalDeps: {},
          externalDeps: {},
          usedSymbols: {},
        ),
        internalDeps: [],
        externalDeps: [],
        dependents: [],
      );

      final yaml = formatter.formatAsYaml(context);

      // Should not include sections for empty lists
      expect(yaml, isNot(contains('internal_dependencies:')));
      expect(yaml, isNot(contains('external_dependencies:')));
      expect(yaml, isNot(contains('dependents:')));
    });
  });
}
