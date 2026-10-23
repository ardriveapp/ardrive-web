import 'dart:math';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/library/domain/library_mode.dart';
import 'package:ardrive/search/domain/bloc/search_bloc.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive/search/search_coverage_notice.dart';
import 'package:ardrive/search/search_modal.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive/search/search_result_navigator.dart';
import 'package:ardrive/search/search_result_view.dart';
import 'package:ardrive/search/search_scope.dart';
import 'package:ardrive/search/search_text_field.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_portal/flutter_portal.dart';

/// How many results the dropdown lists. The rest are one row away, under
/// "See all results".
const searchBoxMaxResults = 8;

/// The id of the "See all results" row, among the results' own ids.
const _seeAllRowId = '#see-all';

/// The search box at the top of a page, with results in a dropdown as you
/// type.
///
/// Behaves the way search boxes do elsewhere:
/// - typing lists the best matches under the box after a short pause
/// - Down and Up move through them, and the mouse picks one by moving over it
/// - Enter goes to the highlighted result, or with none highlighted opens
///   every result in the search dialog
/// - Esc or a click elsewhere closes the dropdown; typing or Down reopens it,
///   and Esc again with it closed empties the field
///
/// The text and the search belong to the session ([SearchSession]), not to
/// this widget, which the explorer rebuilds whenever the drive on screen
/// changes state.
class SearchBox extends StatefulWidget {
  const SearchBox({super.key, this.onNavigateToFolder});

  /// See [SearchResultNavigator.onNavigateToFolder].
  final void Function(String driveId, String folderId, {String? itemId})?
      onNavigateToFolder;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'SearchBox',
    onKeyEvent: _onKeyEvent,
  );

  late final SearchSession _session;

  /// Closed by Esc or a click elsewhere, while the field keeps its text and
  /// may keep focus. Typing, Down or focusing the field again reopens it.
  bool _dismissed = false;

  /// The highlighted row: a result's [SearchResult.uniqueId], or
  /// [_seeAllRowId]. By id rather than position, because the rows are replaced
  /// as results arrive and after a sync, and Enter must not open whatever has
  /// moved into the place the reader picked.
  String? _highlighted;

  String _text = '';

  /// Set once the box gives up focus on purpose, to open a result or the
  /// dialog, so the page that replaces it does not take focus back.
  bool _letGo = false;

  final _rowKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();

    _session = context.read<SearchSession>();
    _text = _session.controller.text;
    _session.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);

    if (_session.restoreBoxFocus) {
      _session.restoreBoxFocus = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void deactivate() {
    // Taken down with focus, not let go of: the page was rebuilt under the
    // reader, as the explorer does when a sync started from this dropdown
    // brings the drive on screen into view. See [SearchSession.restoreBoxFocus].
    if (_focusNode.hasFocus && !_letGo) {
      _session.restoreBoxFocus = true;
    }

    super.deactivate();
  }

  @override
  void dispose() {
    _session.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isOpen =>
      _focusNode.hasFocus && _session.query.isNotEmpty && !_dismissed;

  void _onTextChanged() {
    final text = _session.controller.text;

    // Moving the caret notifies too, and is not an edit.
    if (text == _text) {
      return;
    }

    setState(() {
      _text = text;
      _dismissed = false;
      _highlighted = null;
    });
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _letGo = false;
    }

    setState(() {
      _dismissed = false;

      if (!_focusNode.hasFocus) {
        _highlighted = null;
      }
    });
  }

  /// The results the dropdown lists, which are what the reader can pick.
  List<SearchResult> _listed(SearchState state) {
    if (state.status == SearchStatus.empty) {
      return const [];
    }

    return state.results.take(searchBoxMaxResults).toList();
  }

  List<String> _rowIds(SearchState state) {
    final listed = _listed(state);

    return [
      for (final result in listed) result.uniqueId,
      if (listed.isNotEmpty) _seeAllRowId,
    ];
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // An input method is still composing: these keys are its, not ours.
    if (_session.controller.value.composing.isValid) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      if (_session.query.isEmpty) {
        return KeyEventResult.ignored;
      }

      if (!_isOpen) {
        setState(() => _dismissed = false);
        return KeyEventResult.handled;
      }

      _moveHighlight(1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (!_isOpen) {
        return KeyEventResult.ignored;
      }

      _moveHighlight(-1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape && _isOpen) {
      setState(() {
        _dismissed = true;
        _highlighted = null;
      });
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape &&
        _session.controller.text.isNotEmpty) {
      _session.clear();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Down from the last row, and Up from the first, go back to the field with
  /// nothing highlighted, where Enter opens every result.
  void _moveHighlight(int step) {
    final ids = _rowIds(_session.bloc.state);

    if (ids.isEmpty) {
      return;
    }

    final current = ids.indexOf(_highlighted ?? '');
    final int next;

    if (step > 0) {
      next = current + 1 >= ids.length ? -1 : current + 1;
    } else {
      next = current == -1 ? ids.length - 1 : current - 1;
    }

    final id = next == -1 ? null : ids[next];

    setState(() => _highlighted = id);

    if (id != null) {
      _announceHighlighted(id);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final rowContext = _rowKeys[id]?.currentContext;

        if (rowContext != null && rowContext.mounted) {
          Scrollable.ensureVisible(
            rowContext,
            alignmentPolicy: step > 0
                ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
                : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          );
        }
      });
    }
  }

  void _announceHighlighted(String id) {
    final String label;

    if (id == _seeAllRowId) {
      label = _seeAllLabel(context, _session.bloc.state);
    } else {
      final result = _listed(_session.bloc.state)
          .where((result) => result.uniqueId == id)
          .firstOrNull;

      if (result == null) {
        return;
      }

      label =
          '${searchResultName(result)}, ${searchResultLocation(context, result)}';
    }

    SemanticsService.announce(label, Directionality.of(context));
  }

  /// Enter. Handled here and nowhere else: on the web the browser's own Enter
  /// also arrives as a submit, and acting on the key event as well would do
  /// two things for one press.
  void _onSubmitted(String _) {
    if (_session.query.isEmpty) {
      return;
    }

    final highlighted = _highlighted;

    if (_isOpen && highlighted != null && highlighted != _seeAllRowId) {
      final result = _listed(_session.bloc.state)
          .where((result) => result.uniqueId == highlighted)
          .firstOrNull;

      if (result != null) {
        _openResult(result);
        return;
      }
    }

    _openAllResults();
  }

  /// Closes the dropdown and lets go of the field before anything opens over
  /// it or replaces the page. Left focused, the field took focus back when the
  /// dialog closed, and the dropdown reopened over wherever the reader had
  /// gone.
  void _close() {
    _highlighted = null;
    _letGo = true;
    _focusNode.unfocus();
  }

  void _openResult(SearchResult result) {
    final navigator = SearchResultNavigator(
      drivesCubit: context.read<DrivesCubit>(),
      driveDetailCubit: context.read<DriveDetailCubit>(),
      onNavigateToFolder: widget.onNavigateToFolder,
    );

    _close();
    _session.clear();
    navigator.open(result);
  }

  void _openAllResults() {
    _close();

    showSearchModalDesktop(
      context: context,
      driveDetailCubit: context.read<DriveDetailCubit>(),
      drivesCubit: context.read<DrivesCubit>(),
      onNavigateToFolder: widget.onNavigateToFolder,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SearchBloc, SearchState>(
      listenWhen: (previous, current) =>
          (current.status == SearchStatus.success ||
              current.status == SearchStatus.empty) &&
          (previous.status != current.status ||
              previous.results != current.results),
      listener: (context, state) {
        if (!_isOpen) {
          return;
        }

        SemanticsService.announce(
          appLocalizationsOf(context).searchResultCount(
            state.status == SearchStatus.empty ? 0 : state.results.length,
          ),
          Directionality.of(context),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fieldWidth =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
          // Wider than a narrow field, so names and their folders fit, but
          // never wider than the window.
          final width = min(
            max(fieldWidth, 440.0),
            max(fieldWidth, MediaQuery.sizeOf(context).width - 32),
          );

          return PortalTarget(
            visible: _isOpen,
            anchor: const Aligned(
              follower: Alignment.topLeft,
              target: Alignment.bottomLeft,
              offset: Offset(0, 8),
            ),
            portalFollower: TextFieldTapRegion(
              child: SizedBox(
                width: width,
                child: BlocBuilder<SearchBloc, SearchState>(
                  builder: (context, state) => _SearchDropdown(
                    state: state,
                    query: _session.query,
                    listed: _listed(state),
                    highlighted: _rowIds(state).contains(_highlighted)
                        ? _highlighted
                        : null,
                    rowKeys: _rowKeys,
                    onHighlight: (id) => setState(() => _highlighted = id),
                    onOpenResult: _openResult,
                    onSeeAll: _openAllResults,
                  ),
                ),
              ),
            ),
            child: SearchTextField(
              controller: _session.controller,
              focusNode: _focusNode,
              hintText: LibraryMode.isOn
                  ? appLocalizationsOf(context).librarySearchHint
                  : appLocalizationsOf(context).searchBoxHint,
              // Present, so Enter leaves focus in the field: a box that
              // closed itself on every Enter could not be typed on into.
              onEditingComplete: () {},
              onFieldSubmitted: _onSubmitted,
            ),
          );
        },
      ),
    );
  }
}

/// The last row's label: how many results there are when the dropdown lists
/// only some, so the reader knows whether more are worth opening.
String _seeAllLabel(BuildContext context, SearchState state) {
  final localizations = appLocalizationsOf(context);

  return state.results.length > searchBoxMaxResults
      ? localizations.searchSeeAllResultsCount(state.results.length)
      : localizations.searchSeeAllResults;
}

class _SearchDropdown extends StatelessWidget {
  const _SearchDropdown({
    required this.state,
    required this.query,
    required this.listed,
    required this.highlighted,
    required this.rowKeys,
    required this.onHighlight,
    required this.onOpenResult,
    required this.onSeeAll,
  });

  final SearchState state;

  /// The text in the field now, which [state] might not have caught up with.
  final String query;
  final List<SearchResult> listed;
  final String? highlighted;
  final Map<String, GlobalKey> rowKeys;
  final void Function(String id) onHighlight;
  final void Function(SearchResult result) onOpenResult;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final dropdownTheme = ArDriveTheme.of(context).themeData.dropdownTheme;
    final localizations = appLocalizationsOf(context);

    // Under the bar the box sits in, and never past the bottom of the window.
    final maxHeight =
        min(600.0, max(160.0, MediaQuery.sizeOf(context).height - 140));

    final Widget body;

    if (listed.isNotEmpty) {
      // While a newer query loads, the last results stay rather than blank.
      body = Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            for (final result in listed)
              _ResultRow(
                key: rowKeys.putIfAbsent(result.uniqueId, GlobalKey.new),
                result: result,
                query: state.query,
                highlighted: highlighted == result.uniqueId,
                onHighlight: () => onHighlight(result.uniqueId),
                onTap: () => onOpenResult(result),
              ),
          ],
        ),
      );
    } else {
      final noMatches =
          state.status == SearchStatus.empty && state.query == query;

      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Text(
          noMatches
              ? localizations.searchNoMatches(state.query)
              : localizations.searchSearching,
          style: typography.paragraphNormal(
            color: colorTokens.textMid,
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
      );
    }

    return ArDriveCard(
      backgroundColor: dropdownTheme.backgroundColor,
      boxShadow: BoxShadowCard.shadow80,
      contentPadding: EdgeInsets.zero,
      border: Border.all(color: colorTokens.strokeLow),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.query.isNotEmpty && !state.coverage.isComplete) ...[
              const SearchCoverageNotice(compact: true),
              Divider(height: 1, color: colorTokens.strokeLow),
            ],
            body,
            if (listed.isNotEmpty) ...[
              Divider(height: 1, color: colorTokens.strokeLow),
              _SeeAllRow(
                key: rowKeys.putIfAbsent(_seeAllRowId, GlobalKey.new),
                label: _seeAllLabel(context, state),
                highlighted: highlighted == _seeAllRowId,
                onHighlight: () => onHighlight(_seeAllRowId),
                onTap: onSeeAll,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Highlights on pointer movement only. A row that appears under a pointer
/// that has not moved gets an enter event, and highlighting on that would
/// turn "Enter with nothing picked opens every result" into "Enter opens
/// whatever the mouse happened to be resting on".
class _HoverRow extends StatelessWidget {
  const _HoverRow({
    required this.highlighted,
    required this.onHighlight,
    required this.onTap,
    required this.semanticsLabel,
    required this.child,
  });

  final bool highlighted;
  final VoidCallback onHighlight;
  final VoidCallback onTap;
  final String semanticsLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dropdownTheme = ArDriveTheme.of(context).themeData.dropdownTheme;
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Semantics(
      button: true,
      selected: highlighted,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (_) {
          if (!highlighted) {
            onHighlight();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ColoredBox(
            color: highlighted ? dropdownTheme.hoverColor : Colors.transparent,
            // A bar down the edge as well as the shade, which alone was hard
            // to see in the light theme.
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    width: 3,
                    color: highlighted
                        ? colorTokens.containerRed
                        : Colors.transparent,
                  ),
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.result,
    required this.query,
    required this.highlighted,
    required this.onHighlight,
    required this.onTap,
  });

  final SearchResult result;
  final String query;
  final bool highlighted;
  final VoidCallback onHighlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final name = searchResultName(result);
    final location = searchResultLocation(context, result);

    return _HoverRow(
      highlighted: highlighted,
      onHighlight: onHighlight,
      onTap: onTap,
      semanticsLabel: '$name, $location',
      child: ConstrainedBox(
        // A minimum, so the row grows with the reader's text size.
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              searchResultIcon(result, colorTokens, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SearchMatchText(
                      text: name,
                      query: query,
                      style: typography.paragraphNormal(
                        color: colorTokens.textMid,
                        fontWeight: ArFontWeight.book,
                      ),
                      matchStyle: typography.paragraphNormal(
                        color: colorTokens.textHigh,
                        fontWeight: ArFontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typography.paragraphSmall(
                        color: colorTokens.textLow,
                      ),
                    ),
                  ],
                ),
              ),
              if (searchResultIsHidden(result)) ...[
                const SizedBox(width: 8),
                ArDriveIcons.eyeClosed(size: 16, color: colorTokens.iconLow),
              ],
              if (result.hasArNSName ?? false) ...[
                const SizedBox(width: 8),
                ArDriveIcons.arnsName(size: 16, color: colorTokens.iconLow),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SeeAllRow extends StatelessWidget {
  const _SeeAllRow({
    super.key,
    required this.label,
    required this.highlighted,
    required this.onHighlight,
    required this.onTap,
  });

  final String label;
  final bool highlighted;
  final VoidCallback onHighlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return _HoverRow(
      highlighted: highlighted,
      onHighlight: onHighlight,
      onTap: onTap,
      semanticsLabel: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: typography.paragraphNormal(
                    color: colorTokens.textHigh,
                    fontWeight: ArFontWeight.bold,
                  ),
                ),
              ),
              ArDriveIcons.arrowRightOutline(
                size: 16,
                color: colorTokens.iconMid,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
