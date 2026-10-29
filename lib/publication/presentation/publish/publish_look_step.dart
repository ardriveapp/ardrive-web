import 'dart:ui' as ui;

import 'package:ardrive/components/license/udl_params_form.dart';
import 'package:ardrive/models/forms/cc.dart';
import 'package:ardrive/models/forms/udl.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/domain/publication_images.dart';
import 'package:ardrive/publication/domain/publication_social_card.dart';
import 'package:ardrive/publication/presentation/publish/publish_cubit.dart';
import 'package:ardrive/publication/presentation/publish_to_web.dart'
    show publishButton;
import 'package:ardrive/services/license/license.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

/// The look (docs/PUBLICATIONS.md, "Step 3 · Look"): what the page says and
/// shows, beside a live preview of its header and its link preview.
class PublishLookStep extends StatelessWidget {
  const PublishLookStep({super.key});

  @override
  Widget build(BuildContext context) {
    final heading = Text(
      appLocalizationsOf(context).publishLook,
      style: ArDriveTypographyNew.of(context)
          .heading5(fontWeight: ArFontWeight.bold),
    );
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 680;
      if (!wide) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            const SizedBox(height: 16),
            const _Form(),
            const SizedBox(height: 24),
            const _Previews(),
          ],
        );
      }
      // The form scrolls on its own and the previews stay in view, so a
      // picture shows on the page the moment it is picked. The height leaves
      // the dialog's title, step and actions room on the screen. Each side
      // shows that it scrolls (a scrollbar, and a divider while more is
      // below).
      final height =
          (MediaQuery.sizeOf(context).height * 0.8 - 250).clamp(320.0, 620.0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: 16),
          SizedBox(
            height: height,
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 11,
                  child: ArDriveScrollArea(
                    padding: EdgeInsetsDirectional.only(end: 16),
                    child: _Form(),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  flex: 9,
                  child: ArDriveScrollArea(
                    padding: EdgeInsetsDirectional.only(end: 16),
                    child: _Previews(),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _Form extends StatelessWidget {
  const _Form();

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final cubit = context.read<PublishCubit>();
    final state = context.read<PublishCubit>().state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ArDriveTextFieldNew(
          label: strings.publishTitleLabel,
          isFieldRequired: true,
          initialValue: state.title,
          maxLength: publicationTitleMax,
          onChanged: cubit.setTitle,
        ),
        const SizedBox(height: 16),
        ArDriveTextFieldNew(
          label: strings.publishDescriptionLabel,
          initialValue: state.description,
          maxLength: publicationDescriptionMax,
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          onChanged: cubit.setDescription,
        ),
        const SizedBox(height: 16),
        ArDriveTextFieldNew(
          label: strings.publishDisplayNameLabel,
          initialValue: state.ownerName,
          maxLength: publicationOwnerNameMax,
          onChanged: cubit.setOwnerName,
        ),
        _Hint(strings.publishDisplayNameHint),
        const SizedBox(height: 16),
        const _Keywords(),
        const SizedBox(height: 24),
        _ImageField(
          slot: PublicationImageSlot.icon,
          label: strings.publishIconLabel,
          hint: strings.publishIconHint,
          aspect: 1,
        ),
        const SizedBox(height: 20),
        _ImageField(
          slot: PublicationImageSlot.cover,
          label: strings.publishCoverLabel,
          hint: strings.publishCoverHint,
          aspect: 4,
        ),
        const SizedBox(height: 20),
        _ImageField(
          slot: PublicationImageSlot.social,
          label: strings.publishSocialLabel,
          hint: strings.publishSocialHint,
          aspect: 1200 / 630,
        ),
        // Last: the page comes first, then the terms it is shared under.
        const SizedBox(height: 24),
        const _Licence(),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text,
          style: typography.paragraphSmall(color: color ?? colors.textLow)),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: typography.paragraphNormal(
              color: colors.textMid, fontWeight: ArFontWeight.semiBold)),
    );
  }
}

class _Keywords extends StatefulWidget {
  const _Keywords();

  @override
  State<_Keywords> createState() => _KeywordsState();
}

class _KeywordsState extends State<_Keywords> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(PublishCubit cubit) {
    for (final part in _controller.text.split(',')) {
      cubit.addKeyword(part);
    }
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final cubit = context.read<PublishCubit>();
    final keywords = context.select((PublishCubit c) => c.state.keywords);
    final full = keywords.length >= publicationMaxKeywords;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!full)
          ArDriveTextFieldNew(
            label: strings.publishKeywordsLabel,
            controller: _controller,
            focusNode: _focus,
            hintText: strings.publishKeywordsHint,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _add(cubit),
          )
        else
          _Label(strings.publishKeywordsLabel),
        if (keywords.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final keyword in keywords)
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                  // Outlined, as input chips are: on the light dialog the
                  // fill alone matched the background.
                  decoration: BoxDecoration(
                    color: colors.containerL2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.strokeMid),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(keyword,
                          style: typography.paragraphSmall(
                              color: colors.textHigh,
                              fontWeight: ArFontWeight.semiBold)),
                      const SizedBox(width: 2),
                      ArDriveIconButton(
                        icon: ArDriveIcons.x(size: 14, color: colors.iconMid),
                        tooltip: strings.publishRemove,
                        onPressed: () => cubit.removeKeyword(keyword),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A licence for the whole publication: none, a Creative Commons licence, or
/// the UDL with its terms.
class _Licence extends StatefulWidget {
  const _Licence();

  @override
  State<_Licence> createState() => _LicenceState();
}

class _LicenceState extends State<_Licence> {
  FormGroup? _udl;

  static final _choices = [...ccLicensesEnabled, udlLicenseMetaV2];

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final cubit = context.read<PublishCubit>();
    final licence = context.select((PublishCubit c) => c.state.licence);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(strings.publishLicenseLabel),
        ArDriveSelectField<LicenseMeta?>(
          value: licence?.meta,
          choices: [
            ArDriveChoice(value: null, label: strings.publishLicenseNone),
            for (final meta in _choices)
              ArDriveChoice(value: meta, label: meta.nameWithShortName),
          ],
          onChanged: (meta) {
            if (meta == null) {
              setState(() => _udl = null);
              cubit.setLicence(null);
            } else if (meta.licenseType == LicenseType.udlV2) {
              final form = _udl ??= createUdlParamsForm();
              setState(() {});
              _setUdl(cubit, form);
            } else {
              setState(() => _udl = null);
              cubit.setLicence(PublicationLicence(meta));
            }
          },
        ),
        if (_udl case final form?) ...[
          const SizedBox(height: 12),
          UdlParamsForm(
            formGroup: form,
            onChangeLicenseFee: () => _setUdl(cubit, form),
          ),
          ReactiveFormConsumer(
            builder: (context, form, _) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _setUdl(cubit, form));
              return const SizedBox.shrink();
            },
          ),
        ],
      ],
    );
  }

  void _setUdl(PublishCubit cubit, FormGroup form) {
    final params = form.valid
        ? udlFormToLicenseParams(form).toAdditionalTags()
        : const <String, String>{};
    final licence = PublicationLicence(udlLicenseMetaV2, params);
    if (cubit.state.licence != licence) cubit.setLicence(licence);
  }
}

/// An image field: its thumbnail, Upload and From this drive, Remove, and
/// what size to use.
class _ImageField extends StatelessWidget {
  const _ImageField({
    required this.slot,
    required this.label,
    required this.hint,
    required this.aspect,
  });

  final PublicationImageSlot slot;
  final String label;
  final String hint;
  final double aspect;

  PickedImage? _picked(PublishState s) => switch (slot) {
        PublicationImageSlot.icon => s.icon,
        PublicationImageSlot.cover => s.cover,
        PublicationImageSlot.social => s.social,
      };

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final cubit = context.read<PublishCubit>();
    final picked = context.select((PublishCubit c) => _picked(c.state));
    final error = context.select((PublishCubit c) =>
        c.state.imageError?.slot == slot ? c.state.imageError!.problem : null);
    const thumbHeight = 64.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(label),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              height: thumbHeight,
              width: (thumbHeight * aspect).clamp(thumbHeight, 160),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.containerL2,
                borderRadius: BorderRadius.circular(ArDriveRadius.control),
                border: Border.all(color: colors.strokeLow),
              ),
              child: picked != null
                  ? RawImage(image: picked.preview, fit: BoxFit.cover)
                  : Center(
                      child:
                          ArDriveIcons.image(size: 20, color: colors.iconLow),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      publishButton(
                        context,
                        strings.publishUpload,
                        onPressed: () => _upload(cubit),
                      ),
                      publishButton(
                        context,
                        strings.publishFromDrive,
                        onPressed: () => _fromDrive(context, cubit),
                      ),
                    ],
                  ),
                  // A link under the buttons rather than a third button,
                  // which wrapped onto a line of its own beside a cover.
                  if (picked != null) ...[
                    const SizedBox(height: 6),
                    ArDriveClickArea(
                      child: GestureDetector(
                        onTap: () => cubit.removeImage(slot),
                        child: Text(
                          strings.publishRemove,
                          style: typography
                              .paragraphNormal(
                                fontWeight: ArFontWeight.semiBold,
                                color: colors.textMid,
                              )
                              .copyWith(decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (error != null)
          _Hint(
            error == PublicationImageProblem.tooLarge
                ? strings.publishImageTooLarge
                : strings.publishImageNotImage,
            color: colors.textRed,
          )
        else if (picked?.isSmall ?? false)
          _Hint(strings.publishImageSmall, color: colors.textMid)
        else if (slot == PublicationImageSlot.social && picked == null)
          _Hint('${strings.publishSocialGenerated} $hint')
        else
          _Hint(hint),
      ],
    );
  }

  Future<void> _upload(PublishCubit cubit) async {
    try {
      final file = await ArDriveIO().pickFile(
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
        fileSource: FileSource.fileSystem,
      );
      await cubit.pickImage(slot, await file.readAsBytes());
    } catch (_) {
      // Closed without choosing.
    }
  }

  Future<void> _fromDrive(BuildContext context, PublishCubit cubit) async {
    final repository = context.read<PublicationRepository>();
    final file = await showDialog<FileEntry>(
      context: context,
      builder: (_) => _ChooseImage(
        driveId: cubit.drive.id,
        driveDao: context.read<DriveDao>(),
      ),
    );
    if (file == null) return;
    try {
      final bytes = await repository.readData(file.dataTxId);
      await cubit.pickImage(slot, bytes);
    } catch (_) {
      await cubit.pickImage(slot, Uint8List(0));
    }
  }
}

/// The drive's images, newest first, to choose one from.
class _ChooseImage extends StatelessWidget {
  const _ChooseImage({required this.driveId, required this.driveDao});

  final String driveId;
  final DriveDao driveDao;

  Future<List<FileEntry>> _images() {
    final db = driveDao.attachedDatabase;
    return (db.select(db.fileEntries)
          ..where((f) {
            // Older uploads may carry no content type; their name says it.
            final name = f.name.lower();
            final isImage = f.dataContentType.like('image/%') |
                name.like('%.png') |
                name.like('%.jpg') |
                name.like('%.jpeg') |
                name.like('%.webp') |
                name.like('%.gif');
            return f.driveId.equals(driveId) &
                f.isHidden.equals(false) &
                isImage &
                f.size.isSmallerOrEqualValue(publicationImageMaxBytes);
          })
          ..orderBy([(f) => OrderingTerm.desc(f.lastUpdated)])
          ..limit(200))
        .get();
  }

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ArDriveStandardModalNew(
        title: strings.publishChooseImageTitle,
        width: 440,
        content: SizedBox(
          height: 320,
          child: FutureBuilder<List<FileEntry>>(
            future: _images(),
            builder: (context, snapshot) {
              final files = snapshot.data;
              if (files == null) {
                return const Center(
                  child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
                );
              }
              if (files.isEmpty) {
                return Text(strings.publishNoImagesInDrive,
                    style: typography.paragraphNormal(color: colors.textMid));
              }
              return ListView.builder(
                itemCount: files.length,
                itemBuilder: (context, i) {
                  final file = files[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ArDriveIcons.image(color: colors.iconMid),
                    title: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typography.paragraphNormal(color: colors.textHigh),
                    ),
                    subtitle: Text(filesize(file.size),
                        style:
                            typography.paragraphSmall(color: colors.textLow)),
                    onTap: () => Navigator.of(context).pop(file),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          ModalAction.dismiss(
            title: strings.cancel,
            action: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// The page's header and its link preview, as the owner types.
class _Previews extends StatelessWidget {
  const _Previews();

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(strings.publishPagePreview),
        const _HeaderPreview(),
        const SizedBox(height: 20),
        _Label(strings.publishLinkPreview),
        const _CardPreview(),
      ],
    );
  }
}

class _HeaderPreview extends StatelessWidget {
  const _HeaderPreview();

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final strings = appLocalizationsOf(context);
    final state = context.watch<PublishCubit>().state;
    final summary = state.summary;
    // The page always shows the address, beside a name when there is one.
    final address = truncateString(
        context.read<PublishCubit>().drive.ownerAddress,
        offsetStart: 6,
        offsetEnd: 4);
    final hasName = state.ownerName.trim().isNotEmpty;
    final owner = hasName ? '${state.ownerName.trim()} $address' : address;
    final bylineStyle = typography.paragraphSmall(color: colors.textMid);
    final byline = [
      strings.publicationBy(owner),
      if (summary != null) strings.publishFileCount(summary.fileCount),
      if (state.licence != null) state.licence!.meta.shortName,
    ].join(' • ');
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.containerL0,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.strokeLow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4,
            child: state.cover != null
                ? RawImage(image: state.cover!.preview, fit: BoxFit.cover)
                : Container(color: colors.containerL2),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.icon != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(ArDriveRadius.control),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: RawImage(
                          image: state.icon!.preview, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.title.trim().isEmpty ? ' ' : state.title.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: typography.paragraphLarge(
                            color: colors.textHigh,
                            fontWeight: ArFontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      // A name in the body face; with no name, the address
                      // in monospace, as on the published page.
                      Text.rich(
                        TextSpan(
                          style: bylineStyle,
                          children: hasName
                              ? [TextSpan(text: byline)]
                              : ArDriveIdText.spansIn(
                                  byline,
                                  owner,
                                  idStyle: typography.code(
                                    color: colors.textMid,
                                    fontSize: 11,
                                  ),
                                ),
                        ),
                      ),
                      if (state.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          state.description.trim(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style:
                              typography.paragraphSmall(color: colors.textMid),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardPreview extends StatelessWidget {
  const _CardPreview();

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final strings = appLocalizationsOf(context);
    final cubit = context.read<PublishCubit>();
    final state = context.watch<PublishCubit>().state;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.strokeLow),
      ),
      child: AspectRatio(
        aspectRatio: PublicationSocialCard.width / PublicationSocialCard.height,
        child: state.social != null
            ? RawImage(image: state.social!.preview, fit: BoxFit.cover)
            : FutureBuilder<ui.Image>(
                future: cubit.mark(),
                builder: (context, mark) {
                  if (!mark.hasData) {
                    return Container(color: colors.containerL2);
                  }
                  return CustomPaint(
                    painter: PublicationSocialCardPainter(PublicationSocialCard(
                      title: state.title,
                      description: state.description,
                      fileCount: strings
                          .publishFileCount(state.summary?.fileCount ?? 0),
                      cover: state.cover?.preview,
                      icon: state.icon?.preview,
                      iconTint: state.iconTint,
                      mark: mark.data!,
                    )),
                  );
                },
              ),
      ),
    );
  }
}
