import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SharedFileSideSheet extends StatefulWidget {
  final List<FileRevision> revisions;
  final Privacy privacy;
  const SharedFileSideSheet({
    Key? key,
    required this.revisions,
    required this.privacy,
  }) : super(key: key);

  @override
  State<SharedFileSideSheet> createState() => _SharedFileSideSheetState();
}

class _SharedFileSideSheetState extends State<SharedFileSideSheet> {
  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          TabBar(
            tabs: [
              Tab(
                text: appLocalizationsOf(context).itemDetailsEmphasized,
              ),
              Tab(
                text: appLocalizationsOf(context).itemActivityEmphasized,
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildInfoTable(context, widget.revisions),
                    _buildTxTable(context, widget.revisions),
                  ],
                ),
                _buildActivityTab(context, widget.revisions),
              ],
            ),
          )
        ],
      ));

  Widget _buildInfoTable(BuildContext context, List<FileRevision> revisions) =>
      DataTable(
        // Hide the data table header.
        headingRowHeight: 0,
        dataTextStyle: Theme.of(context).textTheme.subtitle2,
        columns: const [
          DataColumn(label: Text('')),
          DataColumn(label: Text('')),
        ],
        rows: [
          ...{
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).fileID)),
              DataCell(
                CopyIconButton(
                  tooltip: appLocalizationsOf(context).copyFileID,
                  value: revisions.last.fileId,
                ),
              ),
            ]),
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).fileSize)),
              DataCell(
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(filesize(revisions.first.size)),
                ),
              )
            ]),
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).lastModified)),
              DataCell(
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    yMMdDateFormatter.format(revisions.last.lastModifiedDate),
                  ),
                ),
              )
            ]),
          },
          DataRow(cells: [
            DataCell(Text(appLocalizationsOf(context).dateCreated)),
            DataCell(
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  yMMdDateFormatter.format(revisions.first.dateCreated),
                ),
              ),
            ),
          ]),
        ],
      );

  Widget _buildTxTable(BuildContext context, List<FileRevision> revisions) =>
      DataTable(
        // Hide the data table header.

        headingRowHeight: 0,
        dataTextStyle: Theme.of(context).textTheme.subtitle2,
        columns: const [
          DataColumn(label: Text('')),
          DataColumn(label: Text('')),
        ],
        rows: [
          ...{
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).metadataTxID)),
              DataCell(
                CopyIconButton(
                  tooltip: appLocalizationsOf(context).copyMetadataTxID,
                  value: revisions.last.metadataTxId,
                ),
              ),
            ]),
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).dataTxID)),
              DataCell(
                CopyIconButton(
                  tooltip: appLocalizationsOf(context).copyDataTxID,
                  value: revisions.last.dataTxId,
                ),
              ),
            ]),
            if (revisions.first.bundledIn != null)
              DataRow(cells: [
                DataCell(Text(appLocalizationsOf(context).bundleTxID)),
                DataCell(
                  CopyIconButton(
                    tooltip: appLocalizationsOf(context).copyBundleTxID,
                    value: revisions.first.bundledIn!,
                  ),
                ),
              ]),
          },
        ],
      );

  Widget _buildActivityTab(
          BuildContext context, List<FileRevision> revisions) =>
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Builder(
          builder: (context) {
            if (revisions.isNotEmpty) {
              return ListView.separated(
                itemBuilder: (BuildContext context, int index) {
                  final revision = revisions[index];

                  late Widget content;
                  late Widget dateCreatedSubtitle;

                  {
                    final previewOrDownloadButton = InkWell(
                      onTap: () {
                        // downloadOrPreviewRevision(
                        //   drivePrivacy: revision.,
                        //   context: context,
                        //   revision: revision,
                        // );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: widget.privacy == DrivePrivacy.private
                              ? [
                                  Text(appLocalizationsOf(context).download),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.download),
                                ]
                              : [
                                  Text(appLocalizationsOf(context).preview),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.open_in_new)
                                ],
                        ),
                      ),
                    );

                    switch (revision.action) {
                      case RevisionAction.create:
                        content = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appLocalizationsOf(context)
                                  .fileWasCreatedWithName(revision.name),
                            ),
                            previewOrDownloadButton,
                          ],
                        );
                        break;
                      case RevisionAction.rename:
                        content = Text(appLocalizationsOf(context)
                            .fileWasRenamed(revision.name));
                        break;
                      case RevisionAction.move:
                        content =
                            Text(appLocalizationsOf(context).fileWasMoved);
                        break;
                      case RevisionAction.uploadNewVersion:
                        content = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(appLocalizationsOf(context)
                                .fileHadANewRevision),
                            previewOrDownloadButton,
                          ],
                        );
                        break;
                      default:
                        content =
                            Text(appLocalizationsOf(context).fileWasModified);
                    }

                    dateCreatedSubtitle =
                        Text(yMMdDateFormatter.format(revision.dateCreated));
                  }

                  return ListTile(
                    title: DefaultTextStyle(
                      style: Theme.of(context).textTheme.subtitle2!,
                      child: content,
                    ),
                    subtitle: DefaultTextStyle(
                      style: Theme.of(context).textTheme.caption!,
                      child: dateCreatedSubtitle,
                    ),
                  );
                },
                separatorBuilder: (context, index) => const Divider(),
                itemCount: revisions.length,
              );
            } else {
              return Center(
                  child: Text(appLocalizationsOf(context).itemIsBeingProcesed));
            }
          },
        ),
      );
}

void downloadOrPreviewRevision({
  required String drivePrivacy,
  required BuildContext context,
  required FileRevision revision,
}) {
  if (drivePrivacy == DrivePrivacy.private) {
    promptToDownloadProfileFile(
      context: context,
      driveId: revision.driveId,
      fileId: revision.fileId,
      dataTxId: revision.dataTxId,
    );
  } else {
    context.read<DriveDetailCubit>().launchPreview(revision.dataTxId);
  }
}

class CopyIconButton extends StatelessWidget {
  final String value;
  final String tooltip;

  const CopyIconButton({
    Key? key,
    required this.value,
    required this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.centerRight,
        child: IconButton(
          icon: const Icon(Icons.copy, color: Colors.black54),
          tooltip: tooltip,
          onPressed: () => Clipboard.setData(ClipboardData(text: value)),
        ),
      );
}
