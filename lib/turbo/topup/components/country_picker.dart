import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Picks a country by typing: a standard text field whose list narrows as
/// you type, with the arrow keys, Enter and Escape working as expected.
///
/// It replaces a menu of some 200 names in a 275 px box with no way to
/// search. [onChanged] reports a country only when one is chosen or typed in
/// full, and null otherwise, so a form can stay incomplete until it is.
class CountryPicker extends StatefulWidget {
  const CountryPicker({
    super.key,
    required this.countries,
    required this.onChanged,
    this.label = 'Country',
    this.isRequired = true,
  });

  /// The countries, in the order to offer them when nothing is typed.
  final List<String> countries;

  final ValueChanged<String?> onChanged;
  final String label;
  final bool isRequired;

  /// How many options show before the list scrolls.
  static const visibleOptions = 6;

  static const optionHeight = 40.0;

  /// The countries matching [query]: those starting with it first, then
  /// those containing it, each in [countries] order, ignoring case.
  static List<String> filter(List<String> countries, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return countries;

    final starts = <String>[];
    final contains = <String>[];
    for (final country in countries) {
      final name = country.toLowerCase();
      if (name.startsWith(q)) {
        starts.add(country);
      } else if (name.contains(q)) {
        contains.add(country);
      }
    }
    return [...starts, ...contains];
  }

  @override
  State<CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<CountryPicker> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _chosen;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _report(String? country) {
    if (country == _chosen) return;
    _chosen = country;
    widget.onChanged(country);
  }

  /// A country typed in full counts as chosen; anything else clears it.
  void _onTextChanged(String text) {
    final typed = text.trim().toLowerCase();
    String? match;
    for (final country in widget.countries) {
      if (country.toLowerCase() == typed) {
        match = country;
        break;
      }
    }
    _report(match);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<String>(
        textEditingController: _controller,
        focusNode: _focusNode,
        optionsBuilder: (value) =>
            CountryPicker.filter(widget.countries, value.text),
        onSelected: _report,
        // The list opens under the field's box. The standard field fills
        // any height it is given, so it is held to its own here.
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
            UnconstrainedBox(
          constrainedAxis: Axis.horizontal,
          child: ArDriveTextFieldNew(
            controller: controller,
            focusNode: focusNode,
            label: widget.label,
            isFieldRequired: widget.isRequired,
            hintText: 'Search countries',
            autofillHints: const [AutofillHints.countryName],
            onChanged: _onTextChanged,
            onFieldSubmitted: (_) => onSubmitted(),
          ),
        ),
        optionsViewBuilder: (context, onSelected, options) => _Options(
          width: constraints.maxWidth,
          options: options.toList(),
          onSelected: onSelected,
        ),
      ),
    );
  }
}

class _Options extends StatelessWidget {
  const _Options({
    required this.width,
    required this.options,
    required this.onSelected,
  });

  final double width;
  final List<String> options;
  final AutocompleteOnSelected<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final highlighted = AutocompleteHighlightedOption.of(context);

    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Material(
          color: colors.containerRaised,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ArDriveRadius.md),
            side: BorderSide(color: colors.strokeMid),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: width,
              maxHeight:
                  CountryPicker.optionHeight * CountryPicker.visibleOptions,
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                final isHighlighted = index == highlighted;

                return Builder(builder: (context) {
                  if (isHighlighted) {
                    // Keeps the keyboard's option in view as it moves.
                    SchedulerBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) {
                        Scrollable.ensureVisible(context, alignment: 0.5);
                      }
                    });
                  }

                  return Semantics(
                    button: true,
                    selected: isHighlighted,
                    child: InkWell(
                      onTap: () => onSelected(option),
                      hoverColor: colors.buttonSecondaryHover,
                      child: Container(
                        height: CountryPicker.optionHeight,
                        color: isHighlighted
                            ? colors.buttonSecondaryDefault
                            : null,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          option,
                          style: typography.paragraphNormal(
                            color: colors.textHigh,
                          ),
                        ),
                      ),
                    ),
                  );
                });
              },
            ),
          ),
        ),
      ),
    );
  }
}
