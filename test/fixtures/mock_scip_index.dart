import 'dart:io';

import 'package:path/path.dart' as p;
// ignore: implementation_imports
import 'package:scip_dart/src/gen/scip.pb.dart' as scip;
import 'package:scip_server/scip_server.dart';

/// Helper class for creating mock SCIP indexes for testing.
class MockScipIndex {
  /// Create a basic mock index with a few folders and symbols.
  static ScipIndex basic() {
    final documents = <scip.Document>[];

    // Auth folder
    documents.add(
      scip.Document(
        language: 'Dart',
        relativePath: 'lib/features/auth/auth_service.dart',
        symbols: [
          scip.SymbolInformation(
            symbol: 'scip-dart mock 1.0.0 lib/features/auth/auth_service.dart/AuthService#',
            documentation: ['/// Authentication service.'],
            kind: scip.SymbolInformation_Kind.Class,
            displayName: 'AuthService',
          ),
          scip.SymbolInformation(
            symbol: 'scip-dart mock 1.0.0 lib/features/auth/auth_service.dart/AuthService#login().',
            documentation: ['/// Log in a user.'],
            kind: scip.SymbolInformation_Kind.Method,
            displayName: 'login',
          ),
        ],
        occurrences: [
          scip.Occurrence(
            symbol: 'scip-dart mock 1.0.0 lib/features/auth/auth_service.dart/AuthService#',
            range: [5, 0],
            symbolRoles: scip.SymbolRole.Definition.value,
          ),
        ],
      ),
    );

    // Core folder
    documents.add(
      scip.Document(
        language: 'Dart',
        relativePath: 'lib/core/api_client.dart',
        symbols: [
          scip.SymbolInformation(
            symbol: 'scip-dart mock 1.0.0 lib/core/api_client.dart/ApiClient#',
            documentation: ['/// API client for network requests.'],
            kind: scip.SymbolInformation_Kind.Class,
            displayName: 'ApiClient',
          ),
        ],
        occurrences: [],
      ),
    );

    final rawIndex = scip.Index(
      metadata: scip.Metadata(projectRoot: '/mock/project'),
      documents: documents,
    );

    return ScipIndex.fromScipIndex(rawIndex, projectRoot: '/mock/project');
  }

  /// Create a mock index with cross-folder dependencies.
  static ScipIndex withDependencies() {
    final documents = <scip.Document>[];

    // Core folder with a utility
    documents.add(
      scip.Document(
        language: 'Dart',
        relativePath: 'lib/core/helper.dart',
        symbols: [
          scip.SymbolInformation(
            symbol: 'scip-dart mock 1.0.0 lib/core/helper.dart/Helper#',
            kind: scip.SymbolInformation_Kind.Class,
            displayName: 'Helper',
          ),
        ],
        occurrences: [
          scip.Occurrence(
            symbol: 'scip-dart mock 1.0.0 lib/core/helper.dart/Helper#',
            range: [3, 0],
            symbolRoles: scip.SymbolRole.Definition.value,
            enclosingRange: [3, 0, 10],
          ),
        ],
      ),
    );

    // Auth folder that uses core
    documents.add(
      scip.Document(
        language: 'Dart',
        relativePath: 'lib/features/auth/auth_service.dart',
        symbols: [
          scip.SymbolInformation(
            symbol: 'scip-dart mock 1.0.0 lib/features/auth/auth_service.dart/AuthService#',
            kind: scip.SymbolInformation_Kind.Class,
            displayName: 'AuthService',
          ),
        ],
        occurrences: [
          // Definition
          scip.Occurrence(
            symbol: 'scip-dart mock 1.0.0 lib/features/auth/auth_service.dart/AuthService#',
            range: [5, 0],
            symbolRoles: scip.SymbolRole.Definition.value,
            enclosingRange: [5, 0, 20],
          ),
          // Reference to Helper (inside AuthService's enclosing range)
          scip.Occurrence(
            symbol: 'scip-dart mock 1.0.0 lib/core/helper.dart/Helper#',
            range: [10, 4],
            symbolRoles: 0, // Reference, not definition
          ),
        ],
      ),
    );

    final rawIndex = scip.Index(
      metadata: scip.Metadata(projectRoot: '/mock/project'),
      documents: documents,
    );

    return ScipIndex.fromScipIndex(rawIndex, projectRoot: '/mock/project');
  }

  /// Create a mock index with external package dependencies.
  static ScipIndex withExternalDeps() {
    final documents = <scip.Document>[];

    // Auth folder that uses an external package
    documents.add(
      scip.Document(
        language: 'Dart',
        relativePath: 'lib/features/auth/auth_service.dart',
        symbols: [
          scip.SymbolInformation(
            symbol: 'scip-dart mock 1.0.0 lib/features/auth/auth_service.dart/AuthService#',
            kind: scip.SymbolInformation_Kind.Class,
            displayName: 'AuthService',
          ),
        ],
        occurrences: [
          scip.Occurrence(
            symbol: 'scip-dart mock 1.0.0 lib/features/auth/auth_service.dart/AuthService#',
            range: [5, 0],
            symbolRoles: scip.SymbolRole.Definition.value,
            enclosingRange: [5, 0, 30],
          ),
          // Reference to external Firebase symbol
          scip.Occurrence(
            symbol: 'scip-dart pub firebase_auth 4.0.0 lib/firebase_auth.dart/FirebaseAuth#',
            range: [15, 4],
            symbolRoles: 0,
          ),
        ],
      ),
    );

    // Add external symbol definition
    final rawIndex = scip.Index(
      metadata: scip.Metadata(projectRoot: '/mock/project'),
      documents: documents,
      externalSymbols: [
        scip.SymbolInformation(
          symbol: 'scip-dart pub firebase_auth 4.0.0 lib/firebase_auth.dart/FirebaseAuth#',
          kind: scip.SymbolInformation_Kind.Class,
          displayName: 'FirebaseAuth',
        ),
      ],
    );

    return ScipIndex.fromScipIndex(rawIndex, projectRoot: '/mock/project');
  }

  /// Build a mock index from the sample_flutter_app fixture.
  static Future<ScipIndex> fromFixture() async {
    final fixturePath = p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'sample_flutter_app',
    );

    final documents = <scip.Document>[];
    final libDir = Directory(p.join(fixturePath, 'lib'));

    if (!await libDir.exists()) {
      throw Exception('Fixture lib directory not found: ${libDir.path}');
    }

    await for (final entity in libDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final relativePath = p.relative(entity.path, from: fixturePath);
        final content = await entity.readAsString();

        // Parse class declarations
        final classMatches = RegExp(r'class\s+(\w+)(?:\s+extends\s+(\w+))?')
            .allMatches(content);

        final symbols = <scip.SymbolInformation>[];
        final occurrences = <scip.Occurrence>[];

        for (final match in classMatches) {
          final className = match.group(1)!;
          final parentClass = match.group(2);
          final symbolId = 'scip-dart fixture 1.0.0 $relativePath/$className#';

          // Extract doc comments before the class
          final beforeClass = content.substring(0, match.start);
          final docMatch =
              RegExp(r'((?:///[^\n]*\n)+)\s*$').firstMatch(beforeClass);
          final docs = docMatch != null
              ? docMatch
                  .group(1)!
                  .split('\n')
                  .map((l) => l.replaceFirst('/// ', ''))
                  .toList()
              : <String>[];

          final relationships = <scip.Relationship>[];
          if (parentClass != null) {
            relationships.add(
              scip.Relationship(
                symbol: 'scip-dart flutter 3.0.0 $parentClass#',
                isImplementation: true,
              ),
            );
          }

          symbols.add(
            scip.SymbolInformation(
              symbol: symbolId,
              documentation: docs,
              kind: scip.SymbolInformation_Kind.Class,
              displayName: className,
              relationships: relationships,
            ),
          );

          final lineNumber =
              '\n'.allMatches(content.substring(0, match.start)).length;

          occurrences.add(
            scip.Occurrence(
              symbol: symbolId,
              range: [
                lineNumber,
                match.start - content.lastIndexOf('\n', match.start) - 1,
              ],
              symbolRoles: scip.SymbolRole.Definition.value,
            ),
          );
        }

        documents.add(
          scip.Document(
            language: 'Dart',
            relativePath: relativePath,
            symbols: symbols,
            occurrences: occurrences,
          ),
        );
      }
    }

    final rawIndex = scip.Index(
      metadata: scip.Metadata(
        projectRoot: Uri.file(fixturePath).toString(),
      ),
      documents: documents,
    );

    return ScipIndex.fromScipIndex(rawIndex, projectRoot: fixturePath);
  }
}
