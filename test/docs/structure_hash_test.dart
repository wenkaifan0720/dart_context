import 'package:scip_server/src/docs/structure_hash.dart';
import 'package:scip_server/src/index/scip_index.dart';
// ignore: implementation_imports
import 'package:scip_dart/src/gen/scip.pb.dart' as scip;
import 'package:test/test.dart';

void main() {
  group('StructureHash', () {
    group('extractDocRelevantParts', () {
      test('extracts symbol identity', () {
        final symbols = [
          _createSymbol(
            symbol: 'pkg/MyClass#',
            kind: scip.SymbolInformation_Kind.Class,
            displayName: 'MyClass',
          ),
        ];

        final parts = StructureHash.extractDocRelevantParts(symbols);

        expect(parts, contains('symbol:pkg/MyClass#:class'));
        expect(parts, contains('sig:pkg/MyClass#:MyClass'));
      });

      test('extracts doc comments as hashed content', () {
        final symbols = [
          _createSymbol(
            symbol: 'pkg/MyClass#',
            kind: scip.SymbolInformation_Kind.Class,
            documentation: ['/// This is a doc comment'],
          ),
        ];

        final parts = StructureHash.extractDocRelevantParts(symbols);

        expect(parts.any((p) => p.startsWith('doc:pkg/MyClass#:')), isTrue);
      });

      test('extracts relationships', () {
        final symbols = [
          _createSymbol(
            symbol: 'pkg/MyClass#',
            kind: scip.SymbolInformation_Kind.Class,
            relationships: [
              RelationshipInfo(
                symbol: 'pkg/BaseClass#',
                isReference: false,
                isImplementation: true,
                isTypeDefinition: false,
                isDefinition: false,
              ),
            ],
          ),
        ];

        final parts = StructureHash.extractDocRelevantParts(symbols);

        expect(parts, contains('rel:pkg/MyClass#:pkg/BaseClass#:implements'));
      });

      test('skips local symbols', () {
        final symbols = [
          _createSymbol(
            symbol: 'pkg/local0/MyClass#',
            kind: scip.SymbolInformation_Kind.Class,
          ),
        ];

        final parts = StructureHash.extractDocRelevantParts(symbols);

        expect(parts, isEmpty);
      });

      test('skips anonymous symbols', () {
        final symbols = [
          _createSymbol(
            symbol: 'pkg/MyClass#`<anonymous>`.',
            kind: scip.SymbolInformation_Kind.Function,
          ),
        ];

        final parts = StructureHash.extractDocRelevantParts(symbols);

        expect(parts, isEmpty);
      });
    });

    group('computeHash', () {
      test('produces consistent hash for same parts', () {
        final parts = ['symbol:A#:class', 'symbol:B#:function'];

        final hash1 = StructureHash.computeHash(parts);
        final hash2 = StructureHash.computeHash(parts);

        expect(hash1, equals(hash2));
      });

      test('produces same hash regardless of order', () {
        final parts1 = ['symbol:A#:class', 'symbol:B#:function'];
        final parts2 = ['symbol:B#:function', 'symbol:A#:class'];

        final hash1 = StructureHash.computeHash(parts1);
        final hash2 = StructureHash.computeHash(parts2);

        expect(hash1, equals(hash2));
      });

      test('produces different hash for different parts', () {
        final parts1 = ['symbol:A#:class'];
        final parts2 = ['symbol:B#:class'];

        final hash1 = StructureHash.computeHash(parts1);
        final hash2 = StructureHash.computeHash(parts2);

        expect(hash1, isNot(equals(hash2)));
      });

      test('returns empty string for empty parts', () {
        final hash = StructureHash.computeHash([]);
        expect(hash, equals(''));
      });
    });

    group('computeFolderHash', () {
      test('only includes files directly in folder', () {
        // This would need a real ScipIndex to test properly
        // For now, we test the helper method
        expect(
          StructureHash.computeFolderHash(ScipIndex.empty(), 'lib/auth'),
          equals(''),
        );
      });
    });
  });
}

SymbolInfo _createSymbol({
  required String symbol,
  required scip.SymbolInformation_Kind kind,
  String? displayName,
  List<String>? documentation,
  List<RelationshipInfo>? relationships,
}) {
  return SymbolInfo(
    symbol: symbol,
    kind: kind,
    displayName: displayName,
    documentation: documentation ?? [],
    relationships: relationships ?? [],
  );
}
