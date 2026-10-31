import 'package:ardrive/components/list_page/list_page_layout.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The centred, width-capped card a list page shows in place of its table:
/// while it waits, and when it could not read what it lists.
///
/// The table's own ground and edges, so the card is exactly as wide as the
/// table it stands in for and the title row above already leaves the gap the
/// table has.
class ListPageStateCard extends StatelessWidget {
  const ListPageStateCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            // Fills the height it is given; given none, as tall as its words.
            constraints: BoxConstraints(
              minHeight:
                  constraints.hasBoundedHeight ? constraints.maxHeight : 0,
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: listPageSectionGap),
              child: Container(
                // The ground every other full-panel state sits on. These were
                // drawn straight onto the page, so the words floated on black
                // while the same states in the explorer had a card behind
                // them.
                decoration: BoxDecoration(
                  color: ArDriveTheme.of(context)
                      .themeData
                      .tableTheme
                      .backgroundColor,
                  borderRadius: BorderRadius.circular(cardDefaultBorderRadius),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(listPageSectionGap),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: children,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A list page waiting on something it cannot measure: one heading and the
/// large spinner under it.
///
/// One layout for every wait on the drives page, so "Loading your drives" and
/// "Setting up My files", which follow each other for a new account, read as
/// one wait rather than two screens.
class ListPageWaiting extends StatelessWidget {
  const ListPageWaiting({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return ListPageStateCard(
      children: [
        Text(
          title,
          // Tabular figures, so "2 of 4" doesn't shift as it counts.
          style: typography
              .heading4(
            color: colorTokens.textHigh,
            fontWeight: ArFontWeight.bold,
          )
              .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: listPageSectionGap),
        // Nothing to measure, so nothing is claimed: it moves and says no
        // more than that. 32, the spinner's size on its own (README, Loaders).
        const ArDriveSpinner(size: ArDriveSpinnerSize.large),
      ],
    );
  }
}
