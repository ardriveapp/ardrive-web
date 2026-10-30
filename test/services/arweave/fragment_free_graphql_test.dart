import 'dart:io';

import 'package:ardrive/services/arweave/fragment_free_graphql.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:test/test.dart';

/// Every query the app sends, as generated.
final _documents = <String, DocumentNode>{
  'ALL_FILE_ENTITIES_WITH_ID_QUERY_DOCUMENT':
      ALL_FILE_ENTITIES_WITH_ID_QUERY_DOCUMENT,
  'DRIVE_ACTIVITY_PROBE_QUERY_DOCUMENT': DRIVE_ACTIVITY_PROBE_QUERY_DOCUMENT,
  'DRIVE_ENTITY_HISTORY_QUERY_DOCUMENT': DRIVE_ENTITY_HISTORY_QUERY_DOCUMENT,
  'DRIVE_ENTITY_HISTORY_WITHOUT_ENTITY_TYPE_FILTER_QUERY_DOCUMENT':
      DRIVE_ENTITY_HISTORY_WITHOUT_ENTITY_TYPE_FILTER_QUERY_DOCUMENT,
  'DRIVE_SIGNATURE_FOR_DRIVE_QUERY_DOCUMENT':
      DRIVE_SIGNATURE_FOR_DRIVE_QUERY_DOCUMENT,
  'FIRST_DRIVE_ENTITY_WITH_ID_OWNER_QUERY_DOCUMENT':
      FIRST_DRIVE_ENTITY_WITH_ID_OWNER_QUERY_DOCUMENT,
  'FIRST_FILE_ENTITY_WITH_ID_OWNER_QUERY_DOCUMENT':
      FIRST_FILE_ENTITY_WITH_ID_OWNER_QUERY_DOCUMENT,
  'FIRST_TX_BLOCK_HEIGHT_FOR_WALLET_QUERY_DOCUMENT':
      FIRST_TX_BLOCK_HEIGHT_FOR_WALLET_QUERY_DOCUMENT,
  'ACCOUNT_RECORDS_QUERY_DOCUMENT': ACCOUNT_RECORDS_QUERY_DOCUMENT,
  'FIRST_TX_FOR_WALLET_QUERY_DOCUMENT': FIRST_TX_FOR_WALLET_QUERY_DOCUMENT,
  'INFO_OF_TRANSACTIONS_TO_BE_PINNED_QUERY_DOCUMENT':
      INFO_OF_TRANSACTIONS_TO_BE_PINNED_QUERY_DOCUMENT,
  'INFO_OF_TRANSACTION_TO_BE_PINNED_QUERY_DOCUMENT':
      INFO_OF_TRANSACTION_TO_BE_PINNED_QUERY_DOCUMENT,
  'LATEST_DRIVE_ENTITY_WITH_ID_QUERY_DOCUMENT':
      LATEST_DRIVE_ENTITY_WITH_ID_QUERY_DOCUMENT,
  'LATEST_FILE_ENTITY_WITH_ID_QUERY_DOCUMENT':
      LATEST_FILE_ENTITY_WITH_ID_QUERY_DOCUMENT,
  'LICENSE_ASSERTIONS_QUERY_DOCUMENT': LICENSE_ASSERTIONS_QUERY_DOCUMENT,
  'LICENSE_COMPOSED_QUERY_DOCUMENT': LICENSE_COMPOSED_QUERY_DOCUMENT,
  'PENDING_DRIVE_ENTITIES_QUERY_DOCUMENT':
      PENDING_DRIVE_ENTITIES_QUERY_DOCUMENT,
  'PENDING_TX_FEES_QUERY_DOCUMENT': PENDING_TX_FEES_QUERY_DOCUMENT,
  'TRANSACTION_DETAILS_QUERY_DOCUMENT': TRANSACTION_DETAILS_QUERY_DOCUMENT,
  'SNAPSHOT_ENTITY_HISTORY_QUERY_DOCUMENT':
      SNAPSHOT_ENTITY_HISTORY_QUERY_DOCUMENT,
  'TRANSACTIONS_AT_HEIGHT_QUERY_DOCUMENT':
      TRANSACTIONS_AT_HEIGHT_QUERY_DOCUMENT,
  'TRANSACTION_STATUSES_QUERY_DOCUMENT': TRANSACTION_STATUSES_QUERY_DOCUMENT,
  'USER_DRIVE_ENTITIES_QUERY_DOCUMENT': USER_DRIVE_ENTITIES_QUERY_DOCUMENT,
  'TRANSACTION_DETAILS_WITH_SIGNATURE_QUERY_DOCUMENT':
      TRANSACTION_DETAILS_WITH_SIGNATURE_QUERY_DOCUMENT,
  'DRIVE_STATE_ENTITY_HISTORY_QUERY_DOCUMENT':
      DRIVE_STATE_ENTITY_HISTORY_QUERY_DOCUMENT,
  'WALLET_AR_DRIVE_FEES_QUERY_DOCUMENT': WALLET_AR_DRIVE_FEES_QUERY_DOCUMENT,
  'OWNER_PUBLICATIONS_QUERY_DOCUMENT': OWNER_PUBLICATIONS_QUERY_DOCUMENT,
};

/// What [selectionSet] selects, as one path per field: the path of aliases or
/// names from the root, each with its arguments. Fragments are resolved by
/// looking them up, independently of [withoutFragments], so the two can be
/// compared.
Set<String> _paths(
  SelectionSetNode selectionSet,
  Map<String, FragmentDefinitionNode> fragments, [
  String prefix = '',
]) {
  final paths = <String>{};
  for (final selection in selectionSet.selections) {
    if (selection is FieldNode) {
      final arguments = selection.arguments.map(printNode).join(',');
      final path =
          '$prefix/${selection.alias?.value ?? selection.name.value}($arguments)';
      paths.add(path);
      if (selection.selectionSet != null) {
        paths.addAll(_paths(selection.selectionSet!, fragments, path));
      }
    } else if (selection is FragmentSpreadNode) {
      paths.addAll(_paths(
          fragments[selection.name.value]!.selectionSet, fragments, prefix));
    } else if (selection is InlineFragmentNode) {
      paths.addAll(_paths(selection.selectionSet, fragments, prefix));
    }
  }
  return paths;
}

Map<String, FragmentDefinitionNode> _fragmentsOf(DocumentNode document) => {
      for (final d in document.definitions.whereType<FragmentDefinitionNode>())
        d.name.value: d,
    };

Set<String> _operationPaths(DocumentNode document) => {
      for (final operation
          in document.definitions.whereType<OperationDefinitionNode>())
        ..._paths(operation.selectionSet, _fragmentsOf(document),
            operation.name?.value ?? ''),
    };

/// The spreads in [selectionSet], each with the name of the field it sits in.
Iterable<(String, String)> _spreads(
    SelectionSetNode selectionSet, String parent) sync* {
  for (final selection in selectionSet.selections) {
    if (selection is FragmentSpreadNode) {
      yield (selection.name.value, parent);
    } else if (selection is FieldNode && selection.selectionSet != null) {
      yield* _spreads(selection.selectionSet!, selection.name.value);
    } else if (selection is InlineFragmentNode) {
      yield* _spreads(selection.selectionSet, parent);
    }
  }
}

/// The gateway answers a query over an old range in about 8 seconds when its
/// fields come through a fragment, and in about 0.35 seconds when they are
/// written out (fragment_free_graphql.dart). These tests hold the rewrite to
/// selecting exactly what the generated query selects.
void main() {
  test('covers every query in the .graphql files', () {
    final declared = Directory('lib/services/arweave/graphql/queries')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.graphql'))
        .expand((f) => f.readAsLinesSync())
        .where((line) => RegExp(r'^\s*query \w').hasMatch(line))
        .length;
    expect(_documents, hasLength(declared),
        reason: 'a query missing here is a query these tests do not check');
  });

  for (final MapEntry(key: name, value: document) in _documents.entries) {
    group(name, () {
      final rewritten = withoutFragments(document);

      test('is sent with no fragment of any kind', () {
        final printed = printNode(rewritten);
        expect(printed, isNot(contains('...')));
        expect(printed, isNot(contains('fragment ')));
      });

      test('selects exactly the fields the generated query selects', () {
        expect(_operationPaths(rewritten), _operationPaths(document));
      });

      test('keeps its operations, names and variables', () {
        final before =
            document.definitions.whereType<OperationDefinitionNode>().toList();
        final after =
            rewritten.definitions.whereType<OperationDefinitionNode>().toList();
        expect(
            after.map((o) => o.name?.value), before.map((o) => o.name?.value));
        expect(after.map((o) => o.type), before.map((o) => o.type));
        expect(
          after.map((o) => o.variableDefinitions.map(printNode).toList()),
          before.map((o) => o.variableDefinitions.map(printNode).toList()),
        );
      });

      // Writing a spread out is exact only where the fragment's type is the
      // type at the spread. A fragment on another type, or spread somewhere
      // else, needs that rule revisited before it ships.
      test('spreads only Transaction fragments, only on transactions', () {
        final fragments = _fragmentsOf(document);
        for (final fragment in fragments.values) {
          expect(fragment.typeCondition.on.name.value, 'Transaction',
              reason: '${fragment.name.value} is on another type');
        }
        for (final operation
            in document.definitions.whereType<OperationDefinitionNode>()) {
          for (final (fragment, parent)
              in _spreads(operation.selectionSet, '')) {
            expect(fragments, contains(fragment));
            expect(parent, anyOf('node', 'transaction'),
                reason: '...$fragment is spread inside $parent');
          }
        }
      });
    });
  }

  group('leaves a document as it is', () {
    test('when it has no fragments', () {
      final document = parseString('query Q { a { b } }');
      expect(identical(withoutFragments(document), document), isTrue);
    });

    test('when a spread names a fragment the document does not define', () {
      final document =
          parseString('query Q { a { ...Missing } } fragment F on T { b }');
      expect(identical(withoutFragments(document), document), isTrue);
    });

    test('when a spread carries a directive', () {
      final document =
          parseString('query Q(\$x: Boolean!) { a { ...F @include(if: \$x) } } '
              'fragment F on T { b }');
      expect(identical(withoutFragments(document), document), isTrue);
    });

    test('when fragments spread each other in a cycle', () {
      final document = parseString('query Q { a { ...F } } '
          'fragment F on T { b ...G } fragment G on T { c ...F }');
      expect(identical(withoutFragments(document), document), isTrue);
    });
  });

  test('writes out nested fragments', () {
    final document = parseString('query Q { a { ...F } } '
        'fragment F on T { b ...G } fragment G on T { c { d } }');
    expect(
        printNode(withoutFragments(document)).replaceAll(RegExp(r'\s+'), ' '),
        'query Q { a { b c { d } } }');
  });

  test('the link sends the rewritten document and nothing else changed',
      () async {
    Request? sent;
    final link = Link.from([
      FragmentFreeLink(),
      Link.function((request, [forward]) {
        sent = request;
        return Stream.value(const Response(response: {}));
      }),
    ]);
    final request = Request(
      operation: Operation(
        document: DRIVE_ENTITY_HISTORY_QUERY_DOCUMENT,
        operationName: 'DriveEntityHistory',
      ),
      variables: const {'driveId': 'a-drive'},
    );

    await link.request(request).first;

    expect(printNode(sent!.operation.document), isNot(contains('...')));
    expect(sent!.operation.operationName, 'DriveEntityHistory');
    expect(sent!.variables, {'driveId': 'a-drive'});
    expect(sent!.context, request.context);
  });
}
