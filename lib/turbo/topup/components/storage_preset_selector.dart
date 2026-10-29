import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Preset storage amounts with their display values
class StoragePreset {
  final double value;
  final FileSizeUnit unit;

  const StoragePreset(this.value, this.unit);

  /// Returns the storage size in bytes
  int get bytes {
    switch (unit) {
      case FileSizeUnit.bytes:
        return value.round();
      case FileSizeUnit.kilobytes:
        return (value * 1024).round();
      case FileSizeUnit.megabytes:
        return (value * 1024 * 1024).round();
      case FileSizeUnit.gigabytes:
        return (value * 1024 * 1024 * 1024).round();
    }
  }

  String get displayString {
    final formattedValue =
        value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
    switch (unit) {
      case FileSizeUnit.bytes:
        return '$formattedValue B';
      case FileSizeUnit.kilobytes:
        return '$formattedValue KiB';
      case FileSizeUnit.megabytes:
        return '$formattedValue MiB';
      case FileSizeUnit.gigabytes:
        return '$formattedValue GiB';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoragePreset &&
          runtimeType == other.runtimeType &&
          value == other.value &&
          unit == other.unit;

  @override
  int get hashCode => value.hashCode ^ unit.hashCode;
}

/// Default storage presets: 500 MiB, 1 GiB, 5 GiB, 10 GiB, 100 GiB
const List<StoragePreset> defaultStoragePresets = [
  StoragePreset(500, FileSizeUnit.megabytes),
  StoragePreset(1, FileSizeUnit.gigabytes),
  StoragePreset(5, FileSizeUnit.gigabytes),
  StoragePreset(10, FileSizeUnit.gigabytes),
  StoragePreset(100, FileSizeUnit.gigabytes),
];

/// Selector for storage-based amount selection.
///
/// Shows preset storage sizes and a custom amount input.
class StoragePresetSelector extends StatefulWidget {
  final List<StoragePreset> presets;
  final StoragePreset? selectedPreset;
  final double? customValue;
  final FileSizeUnit customUnit;
  final ValueChanged<StoragePreset> onPresetSelected;
  final void Function(double? value, FileSizeUnit unit) onCustomAmountChanged;
  final void Function(FileSizeUnit unit) onUnitChanged;

  const StoragePresetSelector({
    super.key,
    this.presets = defaultStoragePresets,
    this.selectedPreset,
    this.customValue,
    this.customUnit = FileSizeUnit.gigabytes,
    required this.onPresetSelected,
    required this.onCustomAmountChanged,
    required this.onUnitChanged,
  });

  @override
  State<StoragePresetSelector> createState() => _StoragePresetSelectorState();
}

class _StoragePresetSelectorState extends State<StoragePresetSelector> {
  final TextEditingController _customAmountController = TextEditingController();
  final FocusNode _customAmountFocus = FocusNode();
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    if (widget.customValue != null) {
      _customAmountController.text = widget.customValue.toString();
    }
  }

  @override
  void didUpdateWidget(StoragePresetSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync controller when customValue changes externally, but only if the
    // field is not focused to avoid clobbering in-progress user edits
    if (widget.customValue != oldWidget.customValue &&
        !_customAmountFocus.hasFocus) {
      final newText = widget.customValue?.toString() ?? '';
      if (_customAmountController.text != newText) {
        _customAmountController.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _customAmountController.dispose();
    _customAmountFocus.dispose();
    super.dispose();
  }

  void _onPresetSelected(StoragePreset preset) {
    setState(() {
      _customAmountController.clear();
      _validationMessage = null;
    });
    widget.onPresetSelected(preset);
  }

  void _onCustomAmountChanged(String value) {
    final numValue = double.tryParse(value);
    if (value.isEmpty) {
      setState(() {
        _validationMessage = null;
      });
      // Notify parent that the custom amount was cleared
      widget.onCustomAmountChanged(null, widget.customUnit);
      return;
    }

    if (numValue == null || numValue <= 0) {
      setState(() {
        _validationMessage = 'Please enter a valid amount';
      });
      // Notify parent that the custom amount is invalid (clear selection)
      widget.onCustomAmountChanged(null, widget.customUnit);
      return;
    }

    setState(() {
      _validationMessage = null;
    });

    widget.onCustomAmountChanged(numValue, widget.customUnit);
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Storage amount',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colors.textHigh,
          ),
        ),
        const SizedBox(height: 12),
        // Preset buttons in a responsive grid
        _buildPresetGrid(context),
        const SizedBox(height: 16),
        // Custom amount section
        _buildCustomAmountSection(context),
      ],
    );
  }

  Widget _buildPresetGrid(BuildContext context) {
    // One row at every width: a label shrinks a little on a phone rather than
    // wrapping onto a second row. None is chosen while a custom amount is in
    // use.
    return ArDriveSegmentedControl<StoragePreset>(
      expand: true,
      selected: widget.selectedPreset,
      onSelected: _onPresetSelected,
      segments: [
        for (final preset in widget.presets)
          ArDriveSegment(value: preset, label: preset.displayString),
      ],
    );
  }

  Widget _buildCustomAmountSection(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Or enter custom amount',
          style: typography.paragraphSmall(
            fontWeight: ArFontWeight.semiBold,
            color: colors.textMid,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Custom amount text field
            SizedBox(
              width: 120,
              child: _CustomAmountTextField(
                controller: _customAmountController,
                focusNode: _customAmountFocus,
                onChanged: _onCustomAmountChanged,
              ),
            ),
            const SizedBox(width: 12),
            // Unit dropdown
            _UnitDropdown(
              selectedUnit: widget.customUnit,
              onChanged: (unit) {
                widget.onUnitChanged(unit);
                // Reuse the same validation logic as _onCustomAmountChanged
                final text = _customAmountController.text;
                if (text.isEmpty) {
                  widget.onCustomAmountChanged(null, unit);
                  return;
                }
                final numValue = double.tryParse(text);
                if (numValue == null || numValue <= 0) {
                  // Invalid input - clear the custom amount
                  widget.onCustomAmountChanged(null, unit);
                } else {
                  widget.onCustomAmountChanged(numValue, unit);
                }
              },
            ),
          ],
        ),
        if (_validationMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _validationMessage!,
            style: typography.paragraphSmall(
              color: colors.statusErrorFg,
            ),
          ),
        ],
      ],
    );
  }
}

/// The custom amount, on the standard text field.
class _CustomAmountTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _CustomAmountTextField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ArDriveTextFieldNew(
      controller: controller,
      focusNode: focusNode,
      hintText: '0',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      onChanged: onChanged,
    );
  }
}

class _UnitDropdown extends StatelessWidget {
  final FileSizeUnit selectedUnit;
  final ValueChanged<FileSizeUnit> onChanged;

  const _UnitDropdown({
    required this.selectedUnit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    // Drawn like the standard text field beside it: its fill, edge and
    // radius, and the same height.
    return ArDriveChoiceMenu<FileSizeUnit>(
      value: selectedUnit,
      onSelected: onChanged,
      matchButtonWidth: true,
      alignmentOffset: const Offset(0, 4),
      debugLabel: 'unit',
      choices: [
        for (final unit in FileSizeUnit.values)
          ArDriveChoice(value: unit, label: unit.abbreviation),
      ],
      builder: (context, isOpen, toggle) => ArDriveChoiceButton(
        toggle: toggle,
        semanticValue: selectedUnit.abbreviation,
        builder: (context, hovered, focused) => Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isOpen || focused ? colors.strokeHigh : colors.strokeMid,
            ),
            borderRadius: BorderRadius.circular(ArDriveRadius.control),
            color: colors.inputDefault,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selectedUnit.abbreviation,
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: colors.textHigh,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 18,
                  color: colors.textMid,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
