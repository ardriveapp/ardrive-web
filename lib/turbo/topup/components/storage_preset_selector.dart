import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:responsive_builder/responsive_builder.dart';

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
        return '$formattedValue KB';
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
  final void Function(double value, FileSizeUnit unit) onCustomAmountChanged;
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
      return;
    }

    if (numValue == null || numValue <= 0) {
      setState(() {
        _validationMessage = 'Please enter a valid amount';
      });
      return;
    }

    setState(() {
      _validationMessage = null;
    });

    widget.onCustomAmountChanged(numValue, widget.customUnit);
  }

  bool get _isCustomSelected =>
      widget.selectedPreset == null &&
      widget.customValue != null &&
      widget.customValue! > 0;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Storage Amount',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colors.themeFgDefault,
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
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return ScreenTypeLayout.builder(
      mobile: (context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: widget.presets.map((preset) {
          final isSelected = widget.selectedPreset == preset;
          return _PresetButton(
            label: preset.displayString,
            isSelected: isSelected,
            onTap: () => _onPresetSelected(preset),
            colors: colors,
            typography: typography,
          );
        }).toList(),
      ),
      desktop: (context) {
        final presetsList = widget.presets.toList();
        return Row(
          children: List.generate(presetsList.length, (index) {
            final preset = presetsList[index];
            final isSelected = widget.selectedPreset == preset;
            final isFirst = index == 0;
            final isLast = index == presetsList.length - 1;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: isFirst ? 0 : 4,
                  right: isLast ? 0 : 4,
                ),
                child: _PresetButton(
                  label: preset.displayString,
                  isSelected: isSelected,
                  onTap: () => _onPresetSelected(preset),
                  colors: colors,
                  typography: typography,
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildCustomAmountSection(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Or enter custom amount',
          style: typography.paragraphSmall(
            fontWeight: ArFontWeight.semiBold,
            color: colors.themeFgMuted,
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
                isSelected: _isCustomSelected,
                onChanged: _onCustomAmountChanged,
              ),
            ),
            const SizedBox(width: 12),
            // Unit dropdown
            _UnitDropdown(
              selectedUnit: widget.customUnit,
              onChanged: (unit) {
                widget.onUnitChanged(unit);
                if (_customAmountController.text.isNotEmpty) {
                  final numValue =
                      double.tryParse(_customAmountController.text);
                  if (numValue != null) {
                    widget.onCustomAmountChanged(numValue, unit);
                  }
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
              color: colors.themeErrorDefault,
            ),
          ),
        ],
      ],
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ArDriveColors colors;
  final ArdriveTypographyNew typography;

  const _PresetButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
    required this.typography,
  });

  @override
  Widget build(BuildContext context) {
    return ArDriveButton(
      backgroundColor:
          isSelected ? colors.themeFgMuted : colors.themeBorderDefault,
      style: ArDriveButtonStyle.primary,
      maxHeight: 44,
      fontStyle: typography.paragraphSmall(
        fontWeight: ArFontWeight.bold,
        color: isSelected ? colors.themeBgSurface : colors.themeFgMuted,
      ),
      text: label,
      onPressed: onTap,
    );
  }
}

class _CustomAmountTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSelected;
  final ValueChanged<String> onChanged;

  const _CustomAmountTextField({
    required this.controller,
    required this.focusNode,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isSelected ? colors.themeFgMuted : colors.themeBorderDefault,
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: colors.themeBgCanvas,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
        ],
        style: typography.paragraphNormal(
          fontWeight: ArFontWeight.semiBold,
          color: colors.themeFgDefault,
        ),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: InputBorder.none,
          hintText: '0',
          hintStyle: typography.paragraphNormal(
            color: colors.themeFgDisabled,
          ),
        ),
        onChanged: onChanged,
      ),
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
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.themeBorderDefault),
        borderRadius: BorderRadius.circular(8),
        color: colors.themeBgCanvas,
      ),
      child: PopupMenuButton<FileSizeUnit>(
        initialValue: selectedUnit,
        onSelected: onChanged,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        itemBuilder: (context) => FileSizeUnit.values.map((unit) {
          return PopupMenuItem<FileSizeUnit>(
            value: unit,
            child: Text(
              unit.abbreviation,
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.semiBold,
                color: colors.themeFgDefault,
              ),
            ),
          );
        }).toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                selectedUnit.abbreviation,
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colors.themeFgDefault,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: colors.themeFgMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
