// ignore_for_file: unnecessary_string_escapes, unused_element

import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/arns/presentation/assign_name_bloc/assign_name_bloc.dart';
import 'package:ardrive/arns/presentation/create_undername.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> showAssignArNSNameModal(
  BuildContext context, {
  FileDataTableItem? file,
  required DriveDetailCubit driveDetailCubit,
  bool justSelectName = false,
  Function(SelectionConfirmed)? onSelectionConfirmed,
  bool updateARNSRecords = true,
  String? customLoadingText,
  String? customNameSelectionTitle,
}) {
  return showArDriveDialog(
    context,
    barrierDismissible: false,
    content: AssignArNSNameModal(
      file: file,
      driveDetailCubit: driveDetailCubit,
      justSelectName: justSelectName,
      onSelectionConfirmed: onSelectionConfirmed,
      updateARNSRecords: updateARNSRecords,
      customLoadingText: customLoadingText,
      customNameSelectionTitle: customNameSelectionTitle,
    ),
  );
}

class AssignArNSNameModal extends StatelessWidget {
  const AssignArNSNameModal({
    super.key,
    this.file,
    required this.driveDetailCubit,
    required this.justSelectName,
    this.onSelectionConfirmed,
    this.updateARNSRecords = true,
    this.customLoadingText,
    this.customNameSelectionTitle,
    this.onEmptySelection,
    this.canClose = true,
  });

  final FileDataTableItem? file;
  final DriveDetailCubit driveDetailCubit;
  final Function(SelectionConfirmed)? onSelectionConfirmed;
  final Function(EmptySelection)? onEmptySelection;
  final bool canClose;
  final bool justSelectName;
  final bool updateARNSRecords;
  final String? customLoadingText;
  final String? customNameSelectionTitle;

  @override
  Widget build(BuildContext context) {
    logger.d('AssignArNSNameModal build');

    return BlocProvider(
      create: (context) => AssignNameBloc(
          auth: context.read<ArDriveAuth>(),
          fileDataTableItem: file,
          arnsRepository: context.read<ARNSRepository>())
        ..add(
          LoadNames(updateARNSRecords: updateARNSRecords),
        ),
      child: _AssignArNSNameModal(
        file: file,
        justSelectName: justSelectName,
        driveDetailCubit: driveDetailCubit,
        onSelectionConfirmed: onSelectionConfirmed,
        customLoadingText: customLoadingText,
        customNameSelectionTitle: customNameSelectionTitle,
        onEmptySelection: onEmptySelection,
        canClose: canClose,
      ),
    );
  }
}

class _AssignArNSNameModal extends StatefulWidget {
  const _AssignArNSNameModal({
    super.key,
    this.file,
    required this.justSelectName,
    required this.driveDetailCubit,
    this.onSelectionConfirmed,
    this.customLoadingText,
    this.customNameSelectionTitle,
    this.onEmptySelection,
    this.canClose = true,
  });

  final DriveDetailCubit driveDetailCubit;
  final bool justSelectName;
  final FileDataTableItem? file;
  final Function(SelectionConfirmed)? onSelectionConfirmed;
  final Function(EmptySelection)? onEmptySelection;
  final String? customLoadingText;
  final String? customNameSelectionTitle;
  final bool canClose;

  @override
  State<_AssignArNSNameModal> createState() => _AssignArNSNameModalState();
}

class _AssignArNSNameModalState extends State<_AssignArNSNameModal> {
  @override
  dispose() {
    super.dispose();
    logger.d('AssignArNSNameModal dispose');
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return BlocConsumer<AssignNameBloc, AssignNameState>(
      listener: (previous, current) {
        if (current is NameAssignedWithSuccess) {
          showArDriveDialog(
            context,
            content: _ArNSAssignmentConfirmationModal(
              arAddress: current.arAddress,
              address: current.address,
              onOkPressed: () {
                widget.driveDetailCubit.refreshDriveDataTable();
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
            ),
          );
        }

        if (current is SelectionConfirmed) {
          widget.onSelectionConfirmed?.call(current);
        }

        if (current is EmptySelection) {
          widget.onEmptySelection?.call(current);
        }
      },
      buildWhen: (previous, current) {
        if (current is LoadingUndernames) {
          return false;
        } else {
          return true;
        }
      },
      builder: (context, state) {
        return ArDriveStandardModalNew(
          hasCloseButton: state is! ConfirmingSelection,
          title: _getTitle(state),
          close: widget.canClose
              ? null
              : () {
                  logger.d('Closing assign name modal');
                  context.read<AssignNameBloc>().add(CloseAssignName());
                },
          width: (state is! NamesLoaded &&
                  state is! UndernamesLoaded &&
                  state is! LoadingNames)
              ? null
              : kLargeDialogWidth,
          content: Builder(
            builder: (_) {
              if (state is LoadingNames || state is AssignNameInitial) {
                return const SizedBox(
                  height: 275,
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              } else if (state is NamesLoaded) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose one of your ArNS names to assign to this file.',
                      style: typography.paragraphNormal(),
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    _NameSelectorDropdown<ArNSNameModel>(
                      label: 'ArNS name',
                      names: state.nameModels,
                      hintText: 'Choose ArNS name',
                      selectedName: state.selectedName,
                      onSelected: (name) {
                        context.read<AssignNameBloc>().add(SelectName(name));
                        context
                            .read<AssignNameBloc>()
                            .add(const LoadUndernames());
                      },
                    ),
                    const SizedBox(
                      height: 40,
                    ),
                    BlocBuilder<AssignNameBloc, AssignNameState>(
                        builder: (context, state) {
                      if (state is LoadingUndernames) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 8.0),
                          child: LinearProgressIndicator(),
                        );
                      } else if (state is NamesLoaded) {
                        return _NameSelectorDropdown<ARNSUndername>(
                          names: const [],
                          label: 'under_name (optional)',
                          hintText: 'Select under_name',
                          onSelected: (name) {},
                        );
                      }

                      return const SizedBox();
                    }),
                  ],
                );
              } else if (state is UndernamesLoaded) {
                final undernamesPurchased = state.undernames
                    .where((element) => element.name != '@')
                    .length;

                return ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose one of your ArNS names to assign to this file.',
                        style: typography.paragraphNormal(),
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      _NameSelectorDropdown<ArNSNameModel>(
                        selectedName: state.selectedName,
                        label: 'ArNS name',
                        names: state.nameModels,
                        hintText: 'Choose ArNS name',
                        onSelected: (name) {
                          context.read<AssignNameBloc>().add(SelectName(name));
                          context
                              .read<AssignNameBloc>()
                              .add(const LoadUndernames());
                        },
                      ),
                      const SizedBox(
                        height: 40,
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _NameSelectorDropdown<ARNSUndername>(
                            label: 'under_name (optional)',
                            names: state.undernames,
                            selectedName: state.selectedUndername,
                            hintText: 'Select undername',
                            onSelected: (name) {
                              logger.d('Selecting undername');
                              context
                                  .read<AssignNameBloc>()
                                  .add(SelectUndername(undername: name));
                            },
                            records: undernamesPurchased,
                            undernameLimit: state.selectedName?.undernameLimit,
                            key: ValueKey(state.selectedName?.name),
                            onCreateNewUndername: () {
                              if (state.undernames.length ==
                                  state.selectedName?.undernameLimit) {
                                return;
                              }

                              showArDriveDialog(
                                context,
                                content: BlocProvider.value(
                                  value: context.read<AssignNameBloc>(),
                                  child: CreateUndernameModal(
                                    nameModel: state.selectedName!,
                                    driveId: widget.file!.driveId,
                                    fileId: widget.file!.id,
                                    transactionId: widget.file!.dataTxId,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 30.0),
                            child: ArDriveIconButton(
                              tooltip: undernamesPurchased ==
                                      state.selectedName?.undernameLimit
                                  ? 'You can\'t create more undernames $undernamesPurchased of ${state.selectedName?.undernameLimit} in use'
                                  : 'Add new undername $undernamesPurchased of ${state.selectedName?.undernameLimit} in use',
                              icon: ArDriveIcons.addArnsName(
                                size: 30,
                                color: undernamesPurchased ==
                                        state.selectedName?.undernameLimit
                                    ? ArDriveTheme.of(context)
                                        .themeData
                                        .colorTokens
                                        .buttonDisabled
                                    : ArDriveTheme.of(context)
                                        .themeData
                                        .colorTokens
                                        .textHigh,
                              ),
                              onPressed: () {
                                if (undernamesPurchased ==
                                    state.selectedName?.undernameLimit) {
                                  return;
                                }

                                showArDriveDialog(
                                  context,
                                  content: BlocProvider.value(
                                    value: context.read<AssignNameBloc>(),
                                    child: CreateUndernameModal(
                                      nameModel: state.selectedName!,
                                      driveId: widget.file!.driveId,
                                      fileId: widget.file!.id,
                                      transactionId: widget.file!.dataTxId,
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        ],
                      ),
                    ],
                  ),
                );
              } else if (state is ConfirmingSelection) {
                return const Center(child: CircularProgressIndicator());
              } else if (state is AssignNameEmptyState) {
                return const _AssignNameEmptyState();
              } else if (state is SelectionFailed) {
                final colorTokens =
                    ArDriveTheme.of(context).themeData.colorTokens;
                return Center(
                  child: Text(
                    'Error assigning ArNS name. Please try again later',
                    style: typography.paragraphLarge(
                      color: colorTokens.textMid,
                    ),
                  ),
                );
              } else if (state is LoadingNamesFailed) {
                final colorTokens =
                    ArDriveTheme.of(context).themeData.colorTokens;
                return Center(
                  child: Text(
                    'Error fetching ArNS names. Please try again later',
                    style: typography.paragraphLarge(
                      color: colorTokens.textMid,
                    ),
                  ),
                );
              }

              return const SizedBox();
            },
          ),
          actions: _getActions(state),
        );
      },
    );
  }

  String _getTitle(AssignNameState state) {
    if (state is AssignNameEmptyState) {
      return 'Add ArNS Name';
    } else if (state is LoadingNames) {
      return widget.customLoadingText ?? 'Loading ArNS Names';
    } else if (state is ConfirmingSelection) {
      return 'Assigning ArNS Name';
    } else {
      return widget.customNameSelectionTitle ?? 'Assign ArNS Name';
    }
  }

  List<ModalAction> _getActions(AssignNameState state) {
    if (state is AssignNameEmptyState) {
      return [];
    }

    if (state is LoadingNamesFailed) {
      return [
        ModalAction(
          action: () {
            Navigator.of(context).pop();
          },
          title: 'Cancel',
        ),
        ModalAction(
          action: () {
            context
                .read<AssignNameBloc>()
                .add(const LoadNames(updateARNSRecords: true));
          },
          title: 'Try again',
        ),
      ];
    }

    if (state is SelectionFailed) {
      return [
        ModalAction(
          action: () {
            Navigator.of(context).pop();
          },
          title: 'Cancel',
        ),
        ModalAction(
          action: () {
            context.read<AssignNameBloc>().add(ConfirmSelectionAndUpload());
          },
          title: 'Try again',
        ),
      ];
    }

    late final bool isButtonEnabled;

    if (state is NamesLoaded && state.selectedName != null) {
      isButtonEnabled = true;
    } else {
      if (state is UndernamesLoaded) {
        isButtonEnabled = true;
      } else {
        isButtonEnabled = false;
      }
    }

    return [
      if (isButtonEnabled) ...[
        ModalAction(
          action: () {
            if (widget.justSelectName) {
              context.read<AssignNameBloc>().add(ConfirmSelection());
            } else {
              context.read<AssignNameBloc>().add(ConfirmSelectionAndUpload());
            }
          },
          title: 'Add',
        ),
      ]
    ];
  }
}

class _AssignNameEmptyState extends StatelessWidget {
  const _AssignNameEmptyState();

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return Column(
      children: [
        Text(_title,
            style:
                typography.paragraphNormal(fontWeight: ArFontWeight.semiBold)),
        const SizedBox(height: 16),
        Text(
          _subtitle,
          style: typography.paragraphNormal(fontWeight: ArFontWeight.semiBold),
        ),
        const SizedBox(height: 32),
        Align(
          alignment: Alignment.centerLeft,
          child: ArDriveButtonNew(
            variant: ButtonVariant.primary,
            maxWidth: 165,
            maxHeight: 45,
            text: 'Go to ArNS',
            rightIcon: ArDriveIcons.newWindow(
              color: colorTokens.textOnPrimary,
              size: 18,
            ),
            onPressed: () {
              openUrl(url: Resources.arnsLink);
            },
            typography: typography,
          ),
        ),
      ],
    );
  }

  static const String _title =
      'The Arweave Name System (ArNS) works similarly to traditional domain name systems - but with ArNS, the registry is decentralized, permanent, and stored on Arweave. It\’s a simple way to name, and help you find your data.';
  static const String _subtitle =
      'There are no existing names associated with your wallet address, but you can buy one via the ArNS app.';
}

class _NameSelectorDropdown<T> extends StatefulWidget {
  const _NameSelectorDropdown({
    required this.names,
    required this.onSelected,
    this.selectedName,
    required this.label,
    required this.hintText,
    this.records,
    this.undernameLimit,
    this.onCreateNewUndername,
    super.key,
  });

  final List<T> names;
  final Function(T) onSelected;
  final Function()? onCreateNewUndername;
  final T? selectedName;
  final String label;
  final String hintText;
  final int? records;
  final int? undernameLimit;

  @override
  State<_NameSelectorDropdown<T>> createState() =>
      __NameSelectorDropdownState<T>();
}

class __NameSelectorDropdownState<T> extends State<_NameSelectorDropdown<T>> {
  bool isVisible = false;
  T? selectedName;

  @override
  initState() {
    super.initState();
    selectedName = widget.selectedName;
    logger.d('Selected name: ${widget.selectedName}');
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    double maxHeight;
    double maxWidth = 500;
    if (48 * widget.names.length.toDouble() > 240) {
      maxHeight = 240;
    } else if (widget.names.isEmpty) {
      maxHeight = 48;
    } else {
      maxHeight = 48 * widget.names.length.toDouble();
    }

    if (widget.onCreateNewUndername != null) {
      maxHeight = maxHeight + 48;
    }

    if (maxWidth >= MediaQuery.of(context).size.width) {
      maxWidth = MediaQuery.of(context).size.width - 32;
    }

    if (widget.onCreateNewUndername != null) {
      maxWidth = maxWidth - 48;
    }

    return ArDriveDropdown(
      hasBorder: false,
      hasDivider: false,
      anchor: const Aligned(
        follower: Alignment.topRight,
        target: Alignment.bottomRight,
        offset: Offset(0, 10),
      ),
      maxHeight: maxHeight,
      items: _buildList(widget.names, maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: typography.paragraphLarge(
              color: colorTokens.textMid,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
          const SizedBox(height: 8),
          ArDriveClickArea(
            child: Container(
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: colorTokens.inputDisabled,
                border: Border.all(
                  color: colorTokens.textXLow,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorTokens.containerL3,
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
              width: maxWidth,
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  selectedName != null
                      ? _getName(selectedName as T)
                      : widget.hintText,
                  style: typography.paragraphLarge(
                    fontWeight: ArFontWeight.semiBold,
                    color: selectedName != null
                        ? colorTokens.textHigh
                        : colorTokens.textLow,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getName(T item) {
    String name;

    if (item is ArNSNameModel) {
      name = item.name;
    } else if (item is ARNSUndername) {
      name = item.name;
    } else {
      throw Exception('Unknown type');
    }

    if (name == '@') {
      return 'No undername';
    }

    return name;
  }

  List<ArDriveDropdownItem> _buildList(List<T> items, double maxWidth) {
    List<ArDriveDropdownItem> list = [];

    for (var item in items) {
      list.add(
        ArDriveDropdownItem(
          onClick: () {
            widget.onSelected(item);
            setState(() {
              selectedName = item;
            });
          },
          content: Container(
            alignment: Alignment.centerLeft,
            width: maxWidth,
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                _getName(item),
                style: ArDriveTypographyNew.of(context).paragraphLarge(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }

    if (widget.onCreateNewUndername != null) {
      // add create new undername button
      final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

      list.add(
        ArDriveDropdownItem(
          onClick: () {
            widget.onCreateNewUndername?.call();
          },
          content: Container(
            alignment: Alignment.centerLeft,
            width: maxWidth,
            color: colorTokens.containerL3,
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Create new undername. ${widget.records} of ${widget.undernameLimit} in use',
                style: ArDriveTypographyNew.of(context).paragraphLarge(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }

    return list;
  }
}

class _ArNSAssignmentConfirmationModal extends StatelessWidget {
  final String arAddress;
  final String address;
  final VoidCallback onOkPressed;

  const _ArNSAssignmentConfirmationModal({
    required this.arAddress,
    required this.address,
    required this.onOkPressed,
  });

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return ArDriveStandardModalNew(
      width: 400,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ArDriveIcons.checkCirle(
            size: 50,
            color:
                ArDriveTheme.of(context).themeData.colors.themeSuccessDefault,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.center,
            child: Text(
              'ArNS name assigned',
              style: typography.heading3(
                fontWeight: ArFontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Address: ',
                        style: typography.paragraphNormal(
                          color: colorTokens.textLow,
                        ),
                      ),
                      TextSpan(
                        text: arAddress,
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.bold,
                          color: colorTokens.textLow,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            openUrl(url: address);
                          },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ArDriveTooltip(
                message: 'Learn more',
                child: ArDriveClickArea(
                  child: GestureDetector(
                    onTap: () {
                      openUrl(url: Resources.arnsArcssLink);
                    },
                    child: Transform(
                      transform: Matrix4.translationValues(0.0, 2.0, 0.0),
                      child: ArDriveIcons.info(
                        size: 18,
                        color: colorTokens.textLow,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          ArDriveButtonNew(
            text: 'Ok',
            typography: typography,
            variant: ButtonVariant.primary,
            onPressed: onOkPressed,
          ),
          const SizedBox(height: 28),
          Text(
            'Changes may take several minutes or more to propagate.',
            style: typography.paragraphSmall(),
          ),
          Text(
            'You can check the ArNS app for more details.',
            style: typography.paragraphSmall(),
          ),
        ],
      ),
    );
  }
}
