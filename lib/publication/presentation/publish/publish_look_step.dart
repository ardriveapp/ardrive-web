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
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 680;
      if (!wide) {
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_Form(), SizedBox(height: 24), _Previews()],
        );
      }
      return const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 11, child: _Form()),
          SizedBox(width: 24),
          Expanded(flex: 9, child: _Previews()),
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
        const SizedBox(height: 16),
        const _Licence(),
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
                  decoration: BoxDecoration(
                    color: colors.containerL2,
                    borderRadius: BorderRadius.circular(16),
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
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final cubit = context.read<PublishCubit>();
    final licence = context.select((PublishCubit c) => c.state.licence);
    final border = OutlineInputBorder(
      borderSide: BorderSide(color: colors.strokeMid),
      borderRadius: BorderRadius.circular(4),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(strings.publishLicenceLabel),
        DropdownButtonFormField<LicenseMeta?>(
          value: licence?.meta,
          isExpanded: true,
          dropdownColor: colors.containerL1,
          decoration: InputDecoration(
            enabledBorder: border,
            focusedBorder: border,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: [
            DropdownMenuItem<LicenseMeta?>(
              value: null,
              child: Text(strings.publishLicenceNone,
                  style: typography.paragraphNormal(color: colors.textHigh)),
            ),
            for (final meta in _choices)
              DropdownMenuItem<LicenseMeta?>(
                value: meta,
                child: Text(meta.nameWithShortName,
                    overflow: TextOverflow.ellipsis,
                    style: typography.paragraphNormal(color: colors.textHigh)),
              ),
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
                borderRadius: BorderRadius.circular(6),
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
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ArDriveButtonNew(
                    text: strings.publishUpload,
                    typography: typography,
                    variant: ButtonVariant.outline,
                    maxHeight: 36,
                    onPressed: () => _upload(cubit),
                  ),
                  ArDriveButtonNew(
                    text: strings.publishFromDrive,
                    typography: typography,
                    variant: ButtonVariant.outline,
                    maxHeight: 36,
                    onPressed: () => _fromDrive(context, cubit),
                  ),
                  if (picked != null)
                    ArDriveButtonNew(
                      text: strings.publishRemove,
                      typography: typography,
                      variant: ButtonVariant.outline,
                      maxHeight: 36,
                      onPressed: () => cubit.removeImage(slot),
                    ),
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
          ..where((f) =>
              f.driveId.equals(driveId) &
              f.isHidden.equals(false) &
              f.dataContentType.like('image/%') &
              f.size.isSmallerOrEqualValue(publicationImageMaxBytes))
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
      backgroundColor: colors.containerL1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(strings.publishChooseImageTitle,
                        style:
                            typography.heading5(fontWeight: ArFontWeight.bold)),
                  ),
                  ArDriveIconButton(
                    icon: ArDriveIcons.x(color: colors.iconMid),
                    tooltip: strings.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<List<FileEntry>>(
                future: _images(),
                builder: (context, snapshot) {
                  final files = snapshot.data;
                  if (files == null) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (files.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Text(strings.publishNoImagesInDrive,
                          style: typography.paragraphNormal(
                              color: colors.textMid)),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: files.length,
                    itemBuilder: (context, i) {
                      final file = files[i];
                      return ListTile(
                        leading: ArDriveIcons.image(color: colors.iconMid),
                        title: Text(
                          truncateString(file.name,
                              offsetStart: 24, offsetEnd: 12),
                          style: typography.paragraphNormal(
                              color: colors.textHigh),
                        ),
                        subtitle: Text(filesize(file.size),
                            style: typography.paragraphSmall(
                                color: colors.textLow)),
                        onTap: () => Navigator.of(context).pop(file),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
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
    final owner = state.ownerName.trim().isNotEmpty
        ? state.ownerName.trim()
        : truncateString(context.read<PublishCubit>().drive.ownerAddress,
            offsetStart: 6, offsetEnd: 4);
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
                    borderRadius: BorderRadius.circular(6),
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
                      Text(
                        [
                          strings.publicationBy(owner),
                          if (summary != null)
                            strings.publishFileCount(summary.fileCount),
                          if (state.licence != null)
                            state.licence!.meta.shortName,
                        ].join(' • '),
                        style: typography.paragraphSmall(color: colors.textMid),
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
