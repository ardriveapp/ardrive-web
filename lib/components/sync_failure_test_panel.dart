import 'package:ardrive/sync/domain/sync_failure_simulator.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Debug panel for testing sync failure scenarios
/// Only visible in debug mode
class SyncFailureTestPanel extends StatefulWidget {
  const SyncFailureTestPanel({super.key});

  @override
  State<SyncFailureTestPanel> createState() => _SyncFailureTestPanelState();
}

class _SyncFailureTestPanelState extends State<SyncFailureTestPanel> {
  final _simulator = SyncFailureSimulator.instance;
  FailureMode _selectedMode = FailureMode.none;
  double _failureRate = 0.5;
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    // Only show in debug mode
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }

    final themeData = ArDriveTheme.of(context).themeData;

    return Positioned(
      bottom: 20,
      right: 20,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _isExpanded ? 360 : 56,
        child: ArDriveCard(
          backgroundColor: themeData.colorTokens.containerL0,
          contentPadding: EdgeInsets.zero,
          content: _isExpanded
              ? _buildExpandedPanel(context)
              : _buildCollapsedPanel(context),
          boxShadow: BoxShadowCard.shadow80,
        ),
      ),
    );
  }

  Widget _buildCollapsedPanel(BuildContext context) {
    final themeData = ArDriveTheme.of(context).themeData;
    return SizedBox(
      height: 40,
      child: Center(
        child: IconButton(
          icon: Icon(
            Icons.bug_report,
            color: _simulator.isEnabled
                ? themeData.colorTokens.statusErrorFg
                : themeData.colorTokens.textHigh,
            size: 24,
          ),
          onPressed: () => setState(() => _isExpanded = true),
          tooltip: 'Sync Failure Simulator',
        ),
      ),
    );
  }

  Widget _buildExpandedPanel(BuildContext context) {
    final themeData = ArDriveTheme.of(context).themeData;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with red accent line
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: _simulator.isEnabled
                ? themeData.colorTokens.statusErrorFg
                : themeData.colorTokens.textMid,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
        ),

        // Title Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: themeData.colorTokens.containerL1,
            border: Border(
              bottom: BorderSide(
                color: themeData.colorTokens.strokeMid,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.bug_report,
                color: _simulator.isEnabled
                    ? themeData.colorTokens.statusErrorFg
                    : themeData.colorTokens.textHigh,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sync Failure Simulator',
                  style: typography.heading6(
                    fontWeight: ArFontWeight.semiBold,
                    color: themeData.colorTokens.textHigh,
                  ),
                ),
              ),
              IconButton(
                icon: ArDriveIcons.x(
                  size: 16,
                  color: themeData.colorTokens.textMid,
                ),
                onPressed: () => setState(() => _isExpanded = false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),

        // Content
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Enable/Disable Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: themeData.colorTokens.containerL2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: themeData.colorTokens.strokeMid,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Simulator Status',
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                          color: themeData.colorTokens.textHigh,
                        ),
                      ),
                    ),
                    ArDriveToggleSwitch(
                      text: '',
                      value: _simulator.isEnabled,
                      onChanged: (value) {
                        setState(() {
                          if (value) {
                            _simulator.enable(_selectedMode,
                                failureRate: _failureRate);
                          } else {
                            _simulator.disable();
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _simulator.isEnabled
                            ? themeData.colorTokens.statusErrorContainer
                            : themeData.colorTokens.containerL2,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _simulator.isEnabled
                              ? themeData.colorTokens.statusErrorFg
                              : themeData.colorTokens.strokeMid,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _simulator.isEnabled ? 'ON' : 'OFF',
                        style: typography.paragraphSmall(
                          color: _simulator.isEnabled
                              ? themeData.colorTokens.statusErrorFg
                              : themeData.colorTokens.textMid,
                          fontWeight: ArFontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Failure Mode Selection
              Text(
                'Failure Mode',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: themeData.colorTokens.textHigh,
                ),
              ),
              const SizedBox(height: 8),

              Container(
                decoration: BoxDecoration(
                  color: themeData.colorTokens.containerL2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: themeData.colorTokens.strokeMid,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: FailureMode.values.map((mode) {
                    final isSelected = _selectedMode == mode;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedMode = mode;
                          if (_simulator.isEnabled) {
                            _simulator.enable(_selectedMode,
                                failureRate: _failureRate);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? themeData.colorTokens.buttonSecondaryHover
                              : Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(ArDriveRadius.control),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? themeData
                                          .colorTokens.buttonPrimaryDefault
                                      : themeData.colorTokens.strokeMid,
                                  width: 2,
                                ),
                              ),
                              child: isSelected
                                  ? Center(
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: themeData
                                              .colorTokens.buttonPrimaryDefault,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _getModeLabel(mode),
                              style: typography.paragraphSmall(
                                color: themeData.colorTokens.textHigh,
                                fontWeight: isSelected
                                    ? ArFontWeight.semiBold
                                    : ArFontWeight.book,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Failure Rate Slider (only for random mode)
              if (_selectedMode == FailureMode.randomFailures) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: themeData.colorTokens.containerL2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: themeData.colorTokens.strokeMid,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Failure Rate',
                            style: typography.paragraphNormal(
                              fontWeight: ArFontWeight.semiBold,
                              color: themeData.colorTokens.textHigh,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: themeData.colorTokens.containerL0,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: themeData.colorTokens.strokeMid,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '${(_failureRate * 100).toInt()}%',
                              style: typography.paragraphSmall(
                                fontWeight: ArFontWeight.bold,
                                color: themeData.colorTokens.textHigh,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor:
                              themeData.colorTokens.buttonPrimaryDefault,
                          inactiveTrackColor: themeData.colorTokens.strokeMid,
                          thumbColor:
                              themeData.colorTokens.buttonPrimaryDefault,
                          overlayColor: themeData
                              .colorTokens.buttonPrimaryDefault
                              .withOpacity(0.2),
                        ),
                        child: Slider(
                          value: _failureRate,
                          min: 0.0,
                          max: 1.0,
                          divisions: 10,
                          onChanged: (value) {
                            setState(() {
                              _failureRate = value;
                              if (_simulator.isEnabled) {
                                _simulator.enable(_selectedMode,
                                    failureRate: _failureRate);
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Test Actions
              Text(
                'Quick Actions',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: themeData.colorTokens.textHigh,
                ),
              ),
              const SizedBox(height: 8),

              // Trigger Sync Button
              ArDriveButtonNew(
                maxWidth: double.infinity,
                text: 'Trigger Sync Now',
                onPressed: () {
                  context.read<SyncCubit>().startSync();
                  setState(() => _isExpanded = false);
                },
                variant: ButtonVariant.primary,
                typography: typography,
              ),

              const SizedBox(height: 8),

              // Cancel Sync Button
              BlocBuilder<SyncCubit, SyncState>(
                builder: (context, state) {
                  final canCancel = state is SyncInProgress;
                  return ArDriveButtonNew(
                    maxWidth: double.infinity,
                    text: 'Cancel Current Sync',
                    onPressed: canCancel
                        ? () {
                            context.read<SyncCubit>().cancelSync();
                            setState(() => _isExpanded = false);
                          }
                        : null,
                    variant: ButtonVariant.secondary,
                    typography: typography,
                    isDisabled: !canCancel,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getModeLabel(FailureMode mode) {
    switch (mode) {
      case FailureMode.none:
        return 'No Failures';
      case FailureMode.allFail:
        return 'All Drives Fail';
      case FailureMode.firstDriveFails:
        return 'First Drive Fails';
      case FailureMode.randomFailures:
        return 'Random Failures';
      case FailureMode.alternatingFailures:
        return 'Alternating Failures';
    }
  }
}
