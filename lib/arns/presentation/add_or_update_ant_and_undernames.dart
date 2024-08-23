import 'package:ardrive/arns/presentation/assign_name_bloc/assign_name_bloc.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SetARNSExperiment extends StatefulWidget {
  const SetARNSExperiment({super.key, required this.file});

  final FileDataTableItem file;

  @override
  State<SetARNSExperiment> createState() => _SetARNSExperimentState();
}

class _SetARNSExperimentState extends State<SetARNSExperiment> {
  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return BlocConsumer<AssignNameBloc, AssignNameState>(
      listener: (previous, current) {
        if (current is SelectionConfirmed) {
          showArDriveDialog(
            context,
            content: ArDriveStandardModalNew(
              width: 400,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ArDriveIcons.checkCirle(
                    size: 50,
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeSuccessDefault,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      'ArNS name added',
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
                                text: current.address,
                                style: typography.paragraphNormal(
                                  fontWeight: ArFontWeight.bold,
                                  color: colorTokens.textLow,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    openUrl(url: current.address);
                                  },
                              ),
                            ],
                          ),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 28),
                  ArDriveButtonNew(
                    text: 'Ok',
                    typography: typography,
                    variant: ButtonVariant.primary,
                    onPressed: () {
                      final cubit = context.read<SyncCubit>();
                      Future.delayed(const Duration(milliseconds: 500), () {
                        cubit.startSync();
                      });
                      Navigator.of(context).pop();
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'It can take up to 15 minutes to reflect',
                    style: typography.paragraphSmall(),
                  ),
                  Text(
                    'You can check the status of the assignment in the ARNS tab',
                    style: typography.paragraphSmall(),
                  ),
                ],
              ),
            ),
          );
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
        final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
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

        return ArDriveStandardModalNew(
          hasCloseButton: true,
          title:
              state is ReviewingSelection ? 'Review' : 'Assign Existing Name',
          width: (state is! NamesLoaded && state is! UndernamesLoaded)
              ? null
              : kLargeDialogWidth,
          content: Builder(
            builder: (context) {
              if (state is LoadingNames) {
                return const Center(child: CircularProgressIndicator());
              } else if (state is NamesLoaded) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose an existing ArNS name to assign to this file. Assigning an under_name is optional.',
                      style: typography.paragraphNormal(),
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    _NameSelectorDropdown<ARNSRecord>(
                      label: 'ArNS name',
                      names: state.names,
                      hintText: 'Choose ArNS name',
                      selectedName: state.selectedName,
                      onSelected: (name) {
                        context
                            .read<AssignNameBloc>()
                            .add(SelectName(name, true));
                        context
                            .read<AssignNameBloc>()
                            .add(const LoadUndernames());
                      },
                    ),
                    const SizedBox(
                      height: 40,
                    ),
                    // NameDropdownMenu(
                    //   label: 'Select a name',
                    //   itemsTextStyle: typography.paragraphLarge(),
                    //   items: state.names.map((e) => NameItem('Text')).toList(),
                    //   buildSelectedItem: (item) => const Text('Text'),
                    //   backgroundColor: colorTokens.containerL2,
                    // ),
                    // ListView.builder(
                    //   itemCount: state.names.length,
                    //   shrinkWrap: true,
                    //   itemBuilder: (context, index) {
                    //     final isSelected = state.selectedName != null &&
                    //         state.selectedName!.domain ==
                    //             state.names[index].domain;
                    //     return HoverWidget(
                    //       hoverScale: 1,
                    //       child: ListTile(
                    //         title: Text(
                    //           state.names[index].domain,
                    //           style: typography.paragraphLarge(
                    //             color: isSelected
                    //                 ? colorTokens.textHigh
                    //                 : colorTokens.textMid,
                    //             fontWeight:
                    //                 isSelected ? ArFontWeight.bold : null,
                    //           ),
                    //         ),
                    //         onTap: () {
                    //           context
                    //               .read<AssignNameBloc>()
                    //               .add(SelectName(state.names[index], false));
                    //         },
                    //       ),
                    //     );
                    //   },
                    // ),
                    // if (state.selectedName != null)
                    //   Padding(
                    //     padding: const EdgeInsets.only(top: 16.0),
                    //     child: ArDriveButtonNew(
                    //       variant: ButtonVariant.outline,
                    //       text: 'Do you want to assign an undername?',
                    //       typography: typography,
                    //       maxHeight: 32,
                    //       onPressed: () {
                    //         context
                    //             .read<AssignNameBloc>()
                    //             .add(const LoadUndernames());
                    //       },
                    //     ),
                    //   ),
                    BlocBuilder<AssignNameBloc, AssignNameState>(
                        builder: (context, state) {
                      if (state is LoadingUndernames) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 8.0),
                          child: LinearProgressIndicator(),
                        );
                      } else if (state is NamesLoaded) {
                        return _NameSelectorDropdown<ARNSRecord>(
                          names: state.names,
                          label: 'under_name',
                          hintText: 'Select undername',
                          onSelected: (name) {},
                        );
                      }

                      return const SizedBox();
                    }),
                  ],
                );
              } else if (state is UndernamesLoaded) {
                return ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose an existing ArNS name to assign to this file. Assigning an under_name is optional.',
                        style: typography.paragraphNormal(),
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      _NameSelectorDropdown<ARNSRecord>(
                        selectedName: state.selectedName,
                        label: 'ArNS name',
                        names: state.names,
                        hintText: 'Choose ArNS name',
                        onSelected: (name) {
                          context
                              .read<AssignNameBloc>()
                              .add(SelectName(name, true));
                          context
                              .read<AssignNameBloc>()
                              .add(const LoadUndernames());
                        },
                      ),
                      const SizedBox(
                        height: 40,
                      ),
                      _NameSelectorDropdown<ARNSUndername>(
                        label: 'under_name',
                        names: state.undernames,
                        selectedName: state.selectedUndername,
                        hintText: 'Select undername',
                        onSelected: (name) {
                          context.read<AssignNameBloc>().add(SelectUndername(
                              undername: name, txId: widget.file.dataTxId));
                          // context
                          //     .read<AssignNameBloc>()
                          //     .add(const LoadUndernames());
                        },
                      ),
                      // Text('Your names', style: typography.paragraphLarge()),
                      // Flexible(
                      //   child: ListView.builder(
                      //     itemCount: state.names.length,
                      //     shrinkWrap: true,
                      //     itemBuilder: (context, index) {
                      //       final isSelected = state.selectedName.domain ==
                      //           state.names[index].domain;
                      //       return HoverWidget(
                      //         hoverScale: 1,
                      //         child: ListTile(
                      //           title: Text(
                      //             state.names[index].domain,
                      //             style: typography.paragraphLarge(
                      //               color: isSelected
                      //                   ? colorTokens.textHigh
                      //                   : colorTokens.textMid,
                      //               fontWeight:
                      //                   isSelected ? ArFontWeight.bold : null,
                      //             ),
                      //           ),
                      //           onTap: () {
                      //             context.read<AssignNameBloc>().add(
                      //                 SelectName(state.names[index], false));
                      //           },
                      //         ),
                      //       );
                      //     },
                      //   ),
                      // ),
                      // Text('Undernames', style: typography.paragraphLarge()),
                      // Flexible(
                      //   child: ListView.builder(
                      //     itemCount: state.undernames.length,
                      //     shrinkWrap: true,
                      //     itemBuilder: (context, index) {
                      //       final isSelected = state.selectedUndernames
                      //           .contains(state.undernames[index]);

                      //       return HoverWidget(
                      //         hoverScale: 1,
                      //         child: ListTile(
                      //           title: Text(
                      //             state.undernames[index].name,
                      //             style: typography.paragraphLarge(
                      //               color: isSelected
                      //                   ? colorTokens.textHigh
                      //                   : colorTokens.textMid,
                      //               fontWeight: isSelected
                      //                   ? ArFontWeight.bold
                      //                   : ArFontWeight.book,
                      //             ),
                      //           ),
                      //           onTap: () {
                      //             context.read<AssignNameBloc>().add(
                      //                   SelectUndername(
                      //                     undername: state.undernames[index],
                      //                     txId: widget.file.dataTxId,
                      //                   ),
                      //                 );
                      //           },
                      //         ),
                      //       );
                      //     },
                      //   ),
                      // ),
                    ],
                  ),
                );
              } else if (state is ReviewingSelection) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      'File',
                      style: typography.heading6(
                        fontWeight: ArFontWeight.semiBold,
                      ),
                    ),
                    Text(
                      widget.file.name,
                      style: typography.paragraphLarge(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Name:',
                      style: typography.heading6(
                        fontWeight: ArFontWeight.semiBold,
                      ),
                    ),
                    Text(
                      state.domain,
                      style: typography.paragraphLarge(),
                    ),
                    const SizedBox(height: 16),
                    // if (state.undername ) ...[
                    Text(
                      'Undernames:',
                      style: typography.heading6(
                        fontWeight: ArFontWeight.semiBold,
                      ),
                    ),
                    // for (var undername in state.undernames!)
                    Text(
                      state.undername.name,
                      style: typography.paragraphLarge(),
                    ),
                    // ]
                  ],
                );
              } else if (state is ConfirmingSelection) {
                return const Center(child: CircularProgressIndicator());
              }
              return const SizedBox();
            },
          ),
          actions: [
            if (isButtonEnabled)
              ModalAction(
                action: () {
                  context.read<AssignNameBloc>().add(ConfirmSelection());
                },
                title: 'Add',
                // isEnable: isButtonEnabled,
              ),
          ],
        );
      },
    );
  }
}

class _NameSelectorDropdown<T> extends StatefulWidget {
  const _NameSelectorDropdown({
    required this.names,
    required this.onSelected,
    this.selectedName,
    required this.label,
    required this.hintText,
    super.key,
  });

  final List<T> names;
  final Function(T) onSelected;
  final T? selectedName;
  final String label;
  final String hintText;

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
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    double maxHeight;

    if (48 * widget.names.length.toDouble() > 240) {
      maxHeight = 240;
    } else {
      maxHeight = 48 * widget.names.length.toDouble();
    }

    return ArDriveDropdown(
      hasBorder: false,
      hasDivider: false,
      anchor: const Aligned(
        follower: Alignment.topRight,
        target: Alignment.bottomRight,
        offset: Offset(0, 10),
      ),
      showScrollbars: true,
      maxHeight: maxHeight,
      items: _buildList(widget.names),
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
              width: 500,
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
    // return ArDriveOverlay(
    //   anchor: const Aligned(
    //     follower: Alignment.topRight,
    //     target: Alignment.bottomRight,
    //     offset: Offset(0, 18),
    //   ),
    //   visible: isVisible,
    //   content: Container(
    //     width: 576,
    //     decoration: BoxDecoration(
    //       color: ArDriveTheme.of(context).themeData.colorTokens.containerL0,
    //       borderRadius: BorderRadius.circular(5),
    //       boxShadow: [],
    //     ),
    //     child: Column(
    //       mainAxisSize: MainAxisSize.min,
    //       children: [
    //         for (var name in widget.names)
    // Container(
    //   alignment: Alignment.centerLeft,
    //   height: 48,
    //   child: Padding(
    //     padding: const EdgeInsets.symmetric(horizontal: 8.0),
    //     child: Text(
    //       name.domain,
    //       style: typography.paragraphLarge(),
    //     ),
    //   ),
    // ),
    //       ],
    //     ),
    //   ),
    //   child: Container(
    //     width: 576,
    //     decoration: BoxDecoration(
    //       color: ArDriveTheme.of(context).themeData.colorTokens.containerL2,
    //       borderRadius: BorderRadius.circular(5),
    //       boxShadow: [],
    //     ),
    //     child: Column(
    //       children: [
    //         GestureDetector(
    //             onTap: () {
    //               setState(() {
    //                 isVisible = !isVisible;
    //               });
    //             },
    //             child: const _NameDropdownItem()),
    //       ],
    //     ),
    //   ),
    // );
  }

  String _getName(T item) {
    String name;

    if (item is ARNSRecord) {
      name = item.domain;
    } else if (item is ARNSUndername) {
      name = item.name;
    } else {
      throw Exception('Unknown type');
    }

    return name;
  }

  List<ArDriveDropdownItem> _buildList(List<T> items) {
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
            width: 500,
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                _getName(item),
                style: ArDriveTypographyNew.of(context).paragraphLarge(),
              ),
            ),
          ),
        ),
      );
    }
    return list;
  }
}

class _NameDropdownItem extends StatelessWidget {
  const _NameDropdownItem({super.key});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Container(
      width: 576,
      color: colorTokens.containerL2,
      height: 48,
      alignment: Alignment.center,
      child: Text('text',
          style: ArDriveTypographyNew.of(context).paragraphLarge()),
    );
  }
}

//
