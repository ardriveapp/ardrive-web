import 'package:artemis/artemis.dart';
import 'package:gql/ast.dart';
import 'package:gql_dedupe_link/gql_dedupe_link.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_http_link/gql_http_link.dart';
import 'package:gql_link/gql_link.dart';
import 'package:http/http.dart' as http;

/// An [ArtemisClient] that sends every query with its fragments written out
/// as plain fields.
///
/// Built like `ArtemisClient(url)` - a [DedupeLink] in front of an [HttpLink]
/// - with [FragmentFreeLink] between them.
///
/// Why: an ar.io gateway (turbo-gateway.com, measured 2026-10-16) answers a
/// transaction query whose range reaches more than a few hundred blocks back
/// in about 8 seconds when its fields come through any fragment, named or
/// inline, and in about 0.35 seconds when the same fields are written out.
/// Same filters, same fields, same answer. Every sync query spreads
/// `...TransactionCommon`, so a drive's first sync, the walk after a drive
/// state artifact and any sync of a drive not synced for a day paid those 8
/// seconds per page.
ArtemisClient fragmentFreeArtemisClient(String graphQLEndpoint,
    {http.Client? httpClient}) {
  final httpLink = HttpLink(graphQLEndpoint, httpClient: httpClient);
  return _FragmentFreeArtemisClient(
    httpLink,
    Link.from([DedupeLink(), FragmentFreeLink(), httpLink]),
  );
}

class _FragmentFreeArtemisClient extends ArtemisClient {
  _FragmentFreeArtemisClient(this._httpLink, Link link) : super.fromLink(link);

  final HttpLink _httpLink;

  /// What `ArtemisClient(url)` disposes; `fromLink` alone would dispose
  /// nothing.
  @override
  void dispose() => _httpLink.dispose();
}

/// Rewrites each request's document with [withoutFragments] before passing
/// it on.
class FragmentFreeLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    final document = request.operation.document;
    final rewritten = withoutFragments(document);
    return forward!(
      identical(rewritten, document)
          ? request
          : Request(
              operation: Operation(
                document: rewritten,
                operationName: request.operation.operationName,
              ),
              variables: request.variables,
              context: request.context,
            ),
    );
  }
}

/// [document] with every fragment spread replaced by the fragment's own
/// selections, and the fragment definitions dropped.
///
/// A spread and the fields it names select the same thing, so the answer
/// comes back in the same shape and the generated parsers read it unchanged.
/// That holds when the fragment's type is the type at the spread, which is
/// true of every spread in this app (`TransactionCommon on Transaction`,
/// spread on transactions only); `fragment_free_graphql_test.dart` checks it
/// for every generated document, so a new fragment on another type fails a
/// test rather than a query.
///
/// Returns [document] itself, unchanged, when it has no fragments, or when a
/// spread names a fragment the document does not define or carries a
/// directive. Those are sent as they always were.
DocumentNode withoutFragments(DocumentNode document) {
  final fragments = {
    for (final d in document.definitions.whereType<FragmentDefinitionNode>())
      d.name.value: d,
  };
  if (fragments.isEmpty) return document;

  try {
    return DocumentNode(
      definitions: [
        for (final d in document.definitions)
          if (d is OperationDefinitionNode)
            OperationDefinitionNode(
              type: d.type,
              name: d.name,
              variableDefinitions: d.variableDefinitions,
              directives: d.directives,
              selectionSet: _expand(d.selectionSet, fragments, const {}),
            )
          else if (d is! FragmentDefinitionNode)
            d,
      ],
    );
  } on _CannotExpand {
    return document;
  }
}

SelectionSetNode _expand(
  SelectionSetNode selectionSet,
  Map<String, FragmentDefinitionNode> fragments,
  Set<String> expanding,
) =>
    SelectionSetNode(
      selections: [
        for (final selection in selectionSet.selections)
          ..._expandSelection(selection, fragments, expanding),
      ],
    );

List<SelectionNode> _expandSelection(
  SelectionNode selection,
  Map<String, FragmentDefinitionNode> fragments,
  Set<String> expanding,
) {
  if (selection is FragmentSpreadNode) {
    final name = selection.name.value;
    final fragment = fragments[name];
    if (fragment == null ||
        selection.directives.isNotEmpty ||
        expanding.contains(name)) {
      throw const _CannotExpand();
    }
    return _expand(fragment.selectionSet, fragments, {...expanding, name})
        .selections;
  }
  if (selection is FieldNode && selection.selectionSet != null) {
    return [
      FieldNode(
        alias: selection.alias,
        name: selection.name,
        arguments: selection.arguments,
        directives: selection.directives,
        selectionSet: _expand(selection.selectionSet!, fragments, expanding),
      ),
    ];
  }
  if (selection is InlineFragmentNode) {
    // Kept as written: dropping its type condition would change what it
    // selects. None of this app's queries has one.
    return [
      InlineFragmentNode(
        typeCondition: selection.typeCondition,
        directives: selection.directives,
        selectionSet: _expand(selection.selectionSet, fragments, expanding),
      ),
    ];
  }
  return [selection];
}

class _CannotExpand implements Exception {
  const _CannotExpand();
}
