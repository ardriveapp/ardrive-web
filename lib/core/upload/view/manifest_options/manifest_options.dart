import 'package:ardrive/components/components.dart';
import 'package:ardrive/core/upload/view/blocs/upload_manifest_options_bloc.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ManifestOptions extends StatelessWidget {
  const ManifestOptions({super.key, this.scrollable = true});

  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UploadManifestOptionsBloc, UploadManifestOptionsState>(
      builder: (context, state) {
        if (state is UploadManifestOptionsReady) {
          final selectedManifestIds = state.selectedManifestIds;
          final manifestFiles = state.manifestFiles;

          return Padding(
            padding: const EdgeInsets.only(bottom: 42.0),
            child: ListView.separated(
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              physics: scrollable
                  ? const ScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: manifestFiles.length,
              itemBuilder: (context, index) {
                final file = manifestFiles.elementAt(index).manifest;
                final isSelected = selectedManifestIds.contains(file.id);

                logger.d('Is selected: $isSelected');

                return _ManifestOptionTile(
                  manifestSelection: manifestFiles.elementAt(index),
                  isSelected: isSelected,
                  onSelect: () {
                    if (isSelected) {
                      context
                          .read<UploadManifestOptionsBloc>()
                          .add(DeselectManifest(manifest: file));
                    } else {
                      context
                          .read<UploadManifestOptionsBloc>()
                          .add(SelectManifest(manifest: file));
                    }
                  },
                );
              },
            ),
          );
        }

        return const SizedBox();
      },
    );
  }
}

class _ManifestOptionTile extends StatefulWidget {
  final ManifestSelection manifestSelection;
  final bool isSelected;
  final VoidCallback onSelect;

  const _ManifestOptionTile({
    required this.manifestSelection,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  State<_ManifestOptionTile> createState() => __ManifestOptionTileState();
}

class __ManifestOptionTileState extends State<_ManifestOptionTile> {
  @override
  Widget build(BuildContext context) {
    final state = context.read<UploadManifestOptionsBloc>().state;

    if (state is UploadManifestOptionsReady) {
      final isExpanded = state.showingArNSSelection
          .contains(widget.manifestSelection.manifest.id);
      final file = widget.manifestSelection.manifest;

      final hiddenColor =
          ArDriveTheme.of(context).themeData.colors.themeFgDisabled;
      final typography = ArDriveTypographyNew.of(context);
      final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
      final showingName = !isExpanded &&
          (widget.manifestSelection.antRecord != null ||
              widget.manifestSelection.undername != null);
      final hasSelectedAnt = widget.manifestSelection.antRecord != null;

      return SingleChildScrollView(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: colorTokens.containerL2,
            borderRadius: BorderRadius.circular(5),
          ),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          height: isExpanded
              ? 168
              : showingName
                  ? 70
                  : 50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  ArDriveCheckBox(
                    key: ValueKey(widget.isSelected),
                    checked: widget.isSelected,
                    onChange: (value) {
                      if (value) {
                        context
                            .read<UploadManifestOptionsBloc>()
                            .add(SelectManifest(manifest: file));
                      } else {
                        context
                            .read<UploadManifestOptionsBloc>()
                            .add(DeselectManifest(manifest: file));
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        ArDriveIcons.manifest(
                            size: 16,
                            color: file.isHidden ? hiddenColor : null),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            file.name,
                            style: typography.paragraphNormal(
                              color: file.isHidden ? hiddenColor : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (file.isHidden) ...[
                          const SizedBox(width: 8),
                          Text('(hidden)',
                              style: typography.paragraphNormal(
                                color: hiddenColor,
                              ))
                        ]
                      ],
                    ),
                  ),
                  ArDriveTooltip(
                    message: (state.arnsNamesLoaded && state.ants!.isEmpty)
                        ? 'No ArNS names found for your wallet'
                        : '',
                    child: ArDriveButtonNew(
                      text: !state.arnsNamesLoaded
                          ? 'Loading Names...'
                          : hasSelectedAnt
                              ? 'Change ArNS Name'
                              : 'Add ArNS Name',
                      typography: typography,
                      isDisabled: isExpanded ||
                          !widget.isSelected ||
                          !state.arnsNamesLoaded ||
                          (state.arnsNamesLoaded && state.ants!.isEmpty),
                      fontStyle: typography.paragraphSmall(),
                      variant: ButtonVariant.primary,
                      maxWidth: state.arnsNamesLoaded ? 140 : 160,
                      maxHeight: 30,
                      onPressed: () {
                        context
                            .read<UploadManifestOptionsBloc>()
                            .add(ShowArNSSelection(manifest: file));
                      },
                    ),
                  )
                ],
              ),
              if (showingName) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    ArDriveIcons.arnsName(
                      size: 16,
                      color: colorTokens.textHigh,
                    ),
                    const SizedBox(width: 18),
                    Flexible(
                      child: Text(
                        getLiteralArNSName(widget.manifestSelection.antRecord!,
                            widget.manifestSelection.undername),
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (isExpanded) ...[
                const SizedBox(height: 8),
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 34),
                    child: AntSelector(
                      manifestSelection: widget.manifestSelection,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return const SizedBox();
  }
}

class AntSelector extends StatefulWidget {
  final ManifestSelection manifestSelection;

  const AntSelector({super.key, required this.manifestSelection});

  @override
  State<AntSelector> createState() => _AntSelectorState();
}

class _AntSelectorState extends State<AntSelector> {
  ANTRecord? _selectedAnt;
  ARNSUndername? _selectedUndername;

  List<ARNSUndername> _arnsUndernames = [];
  bool _loadingUndernames = false;

  Future<void> loadARNSUndernames(
    ANTRecord ant,
  ) async {
    setState(() {
      _loadingUndernames = true;
    });

    _arnsUndernames =
        await context.read<UploadManifestOptionsBloc>().getARNSUndernames(ant);
    _arnsUndernames.removeWhere((e) => e.name == '@');

    setState(() {
      _loadingUndernames = false;
    });
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _selectedAnt = widget.manifestSelection.antRecord;
    _selectedUndername = widget.manifestSelection.undername;
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return BlocBuilder<UploadManifestOptionsBloc, UploadManifestOptionsState>(
      builder: (context, state) {
        if (state is UploadManifestOptionsReady) {
          final reservedNames =
              context.read<UploadManifestOptionsBloc>().reservedNames;

          bool isNameAlreadyInUse = reservedNames[_selectedAnt?.domain]
                  ?.contains(_selectedUndername?.name ?? '@') ??
              false;

          return Column(
            children: [
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: colorTokens.inputDisabled,
                  border: Border.all(
                    color: colorTokens.textXLow,
                    width: 1,
                  ),
                ),
                child: ArDriveDropdown(
                  height: 45,
                  maxHeight: (state.ants!.length > 6) ? 45 * 6 : null,
                  items: state.ants!
                      .map((ant) => _buildDropdownItem(context, ant))
                      .toList(),
                  child: ArDriveClickArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(child: _buildSelectedItem(context)),
                        ArDriveIcons.chevronDown(),
                      ],
                    ),
                  ),
                ),
              ),
              if (_loadingUndernames) const CircularProgressIndicator(),
              if (_selectedUndername != null ||
                  (!_loadingUndernames && _arnsUndernames.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    alignment: Alignment.centerLeft,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      color: colorTokens.inputDisabled,
                      border: Border.all(
                        color: colorTokens.textXLow,
                        width: 1,
                      ),
                    ),
                    child: ArDriveDropdown(
                      maxHeight: (_arnsUndernames.length > 6) ? 45 * 6 : null,
                      height: 45,
                      items: _arnsUndernames
                          .map((undername) =>
                              _buildDropdownItemUndername(context, undername))
                          .toList(),
                      child: ArDriveClickArea(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                _buildSelectedItemUndername(context),
                              ],
                            ),
                            ArDriveIcons.chevronDown(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(
                  top: 8,
                  left: 8,
                  bottom: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isNameAlreadyInUse &&
                        widget.manifestSelection.antRecord?.domain !=
                            _selectedAnt?.domain)
                      Expanded(
                        child: Text(
                          'Name already in use, please choose another name or select a undername',
                          style: typography.paragraphSmall(
                            fontWeight: ArFontWeight.semiBold,
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ArDriveButtonNew(
                        text: 'Add',
                        typography: typography,
                        fontStyle: typography.paragraphSmall(),
                        variant: ButtonVariant.primary,
                        maxWidth: 80,
                        maxHeight: 30,
                        isDisabled: isNameAlreadyInUse || _selectedAnt == null,
                        onPressed: () {
                          context
                              .read<UploadManifestOptionsBloc>()
                              .add(LinkManifestToUndername(
                                manifest: widget.manifestSelection.manifest,
                                antRecord: _selectedAnt!,
                                undername: _selectedUndername,
                              ));
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return const SizedBox();
      },
    );
  }

  Widget _buildSelectedItem(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return Text(
      _selectedAnt?.domain ?? 'Choose ArNS name',
      style: typography.paragraphSmall(
        fontWeight: ArFontWeight.semiBold,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildSelectedItemUndername(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return Text(
      _selectedUndername?.name ?? 'under_name (optional)',
      style: typography.paragraphSmall(
        fontWeight: ArFontWeight.semiBold,
      ),
    );
  }

  ArDriveDropdownItem _buildDropdownItem(BuildContext context, ANTRecord ant) {
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveDropdownItem(
      content: SizedBox(
        width: 235,
        height: 45,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  ant.domain,
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
              ),
              if (ant.domain == _selectedAnt?.domain)
                ArDriveIcons.checkmark(
                  size: 16,
                )
            ],
          ),
        ),
      ),
      onClick: () {
        setState(() {
          _selectedAnt = ant;

          _arnsUndernames = [];
          _selectedUndername = null;
          loadARNSUndernames(ant);
        });
      },
    );
  }

  ArDriveDropdownItem _buildDropdownItemUndername(
      BuildContext context, ARNSUndername undername) {
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveDropdownItem(
      content: SizedBox(
        width: 235,
        height: 45,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  undername.name,
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
              ),
              if (undername.name == _selectedUndername?.name)
                ArDriveIcons.checkmark(
                  size: 16,
                )
            ],
          ),
        ),
      ),
      onClick: () {
        setState(() {
          _selectedUndername = undername;
        });
      },
    );
  }
}
