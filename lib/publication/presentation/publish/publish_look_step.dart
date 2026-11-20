import 'dart:ui' as ui;

import 'package:ardrive/components/license/udl_params_form.dart';
import 'package:ardrive/models/forms/cc.dart';
import 'package:ardrive/models/forms/udl.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/domain/publication_images.dart';
import 'package:ardrive/authentication/password/new_password.dart';
import 'package:ardrive/authentication/password/new_password_fields.dart';
import 'package:ardrive/publication/domain/publication_social_card.dart';
import 'package:ardrive/publication/presentation/publication_chrome.dart';
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
          isFieldRequired: !state.isPrivatePage,
          initialValue: state.title,
          maxLength: publicationTitleMax,
          onChanged: cubit.setTitle,
        ),
        // A private page's words are the only part of it everyone sees.
        if (state.isPrivatePage) _Hint(strings.publishPrivateTitleHint),
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
        if (state.isPrivatePage) ...[
          const SizedBox(height: 24),
          const _Password(),
        ],
        const SizedBox(height: 24),
        // The pictures come right after the words, in view without a scroll.
        _ImageField(
          slot: PublicationImageSlot.cover,
          label: strings.publishCoverLabel,
          hint: strings.publishCoverHint,
          aspect: 4,
        ),
        const SizedBox(height: ArDriveSpacing.lg),
        _ImageField(
          slot: PublicationImageSlot.icon,
          label: strings.publishIconLabel,
          hint: strings.publishIconHint,
          aspect: 1,
        ),
        const SizedBox(height: ArDriveSpacing.lg),
        _MoreOptions(
          initiallyOpen: state.ownerName.trim().isNotEmpty ||
              state.keywords.isNotEmpty ||
              state.social != null ||
              state.licence != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                slot: PublicationImageSlot.social,
                label: strings.publishSocialLabel,
                hint: strings.publishSocialHint,
                aspect: 1200 / 630,
              ),
              // Last: the page comes first, then the terms it is shared
              // under.
              const SizedBox(height: 24),
              const _Licence(),
            ],
          ),
        ),
      ],
    );
  }
}

/// The settings most pages leave alone, folded under one line, as the upload
/// dialog folds its options. Open from the start when one already has a
/// value, as on an update. Closed, the fields stay built (and keep what was
/// typed) but are not shown.
class _MoreOptions extends StatefulWidget {
  const _MoreOptions({required this.initiallyOpen, required this.child});

  final bool initiallyOpen;
  final Widget child;

  @override
  State<_MoreOptions> createState() => _MoreOptionsState();
}

class _MoreOptionsState extends State<_MoreOptions> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    void toggle() => setState(() => _open = !_open);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: ArDriveFocusable(
            onActivate: toggle,
            child: ArDriveClickArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: toggle,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    (_open
                        ? ArDriveIcons.carretDown
                        : ArDriveIcons.carretRight)(
                      size: 16,
                      color: colors.textMid,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      appLocalizationsOf(context).publishMoreOptions,
                      style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold,
                        color: colors.textHigh,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Visibility(
          visible: _open,
          maintainState: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// A private page's optional password: set when publishing or added in an
/// update, never changed or removed (docs/PUBLICATIONS.md, "Private
/// publications").
class _Password extends StatefulWidget {
  const _Password();

  @override
  State<_Password> createState() => _PasswordState();
}

class _PasswordState extends State<_Password> {
  late final TextEditingController _controller;
  String? _suggested;

  /// Counts the owner's edits and asks for a suggestion: a suggestion that
  /// loads after either is dropped, so it never overwrites what they typed.
  int _edits = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: context.read<PublishCubit>().state.password);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    final asked = ++_edits;
    final words = await loadPassphraseWords(DefaultAssetBundle.of(context));
    if (!mounted || asked != _edits) return;
    final phrase = suggestPassphrase(words);
    _controller.text = phrase;
    context.read<PublishCubit>().setPassword(phrase);
    setState(() => _suggested = phrase);
  }

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final cubit = context.read<PublishCubit>();
    final state = context.watch<PublishCubit>().state;
    if (state.hasPassword) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(strings.publishPasswordLabel),
          Text(strings.publishPasswordExisting,
              style: typography.paragraphNormal(color: colors.textMid)),
        ],
      );
    }
    final password = state.password;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ArDriveTextFieldNew(
          label: strings.publishPasswordLabel,
          controller: _controller,
          obscureText: _suggested == null,
          showObfuscationToggle: true,
          autocorrect: false,
          onChanged: (value) {
            _edits++;
            if (_suggested != null && value != _suggested) {
              setState(() => _suggested = null);
            }
            cubit.setPassword(value);
          },
        ),
        _Hint(strings.publishPasswordHint),
        if (password.isNotEmpty) ...[
          const SizedBox(height: 8),
          PasswordStrengthMeter(strength: assessNewPassword(password)),
          _Hint(strings.publishPasswordPermanent, color: colors.textMid),
        ],
        if (state.passwordIsWeak) ...[
          const SizedBox(height: 8),
          ArDriveCheckBox(
            // A new box for each password: ticking covers the one typed.
            key: ValueKey(password),
            title: strings.publishWeakPasswordAccept,
            checked: state.weakPasswordAccepted,
            onChange: cubit.acceptWeakPassword,
            titleStyle: typography.paragraphNormal(color: colors.textMid),
          ),
        ],
        if (_suggested != null) ...[
          const SizedBox(height: 8),
          SuggestedPassphrase(phrase: _suggested!, onAnother: _suggest),
        ] else ...[
          const SizedBox(height: 6),
          ArDriveClickArea(
            child: GestureDetector(
              onTap: _suggest,
              child: Text(
                strings.newPasswordSuggest,
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
            spacing: ArDriveSpacing.xs,
            runSpacing: ArDriveSpacing.xs,
            children: [
              for (final keyword in keywords)
                Container(
                  padding: const EdgeInsets.fromLTRB(
                      ArDriveSpacing.xs,
                      ArDriveSpacing.xxs,
                      ArDriveSpacing.xxs,
                      ArDriveSpacing.xxs),
                  // Outlined, as input chips are: on the light dialog the
                  // fill alone matched the background.
                  decoration: BoxDecoration(
                    color: colors.containerL2,
                    borderRadius: BorderRadius.circular(ArDriveRadius.lg),
                    border: Border.all(color: colors.strokeMid),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(keyword,
                          style: typography.paragraphSmall(
                              color: colors.textHigh,
                              fontWeight: ArFontWeight.semiBold)),
                      const SizedBox(width: ArDriveSpacing.xxs),
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
                borderRadius: BorderRadius.circular(ArDriveRadius.md),
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
                      // A private drive's images can't go on a public page.
                      if (!cubit.isPrivateFile && !cubit.state.isPrivatePage)
                        publishButton(
                          context,
                          strings.publishFromDrive,
                          onPressed: () => _fromDrive(cubit),
                        ),
                    ],
                  ),
                  // A link under the buttons rather than a third button,
                  // which wrapped onto a line of its own beside a cover.
                  if (picked != null) ...[
                    const SizedBox(height: ArDriveSpacing.xs),
                    ArDriveLink(
                      text: strings.publishRemove,
                      onTap: () => cubit.removeImage(slot),
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
        // A private page never gets a generated card.
        else if (slot == PublicationImageSlot.social &&
            picked == null &&
            !context.read<PublishCubit>().state.isPrivatePage)
          _Hint('$hint ${strings.publishSocialGenerated}')
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

  void _fromDrive(PublishCubit cubit) => cubit.openImageChooser(slot);
}

/// The drive's images, newest first, to choose one for [slot]: shown in the
/// publish dialog in place of the look, so no second dialog opens over it.
/// Picking one returns to the look with the picture used.
class ImageFromDriveChooser extends StatefulWidget {
  const ImageFromDriveChooser({
    super.key,
    required this.slot,
    @visibleForTesting this.loadImages,
  });

  final PublicationImageSlot slot;

  /// Stands in for the drive's images in a test.
  final Future<List<FileEntry>> Function()? loadImages;

  @override
  State<ImageFromDriveChooser> createState() => _ImageFromDriveChooserState();
}

class _ImageFromDriveChooserState extends State<ImageFromDriveChooser> {
  // Read once: the dialog rebuilds on every state change while this shows,
  // and a new query each time would flash the spinner and query again.
  late final Future<List<FileEntry>> _files = widget.loadImages?.call() ??
      _images(context.read<DriveDao>(), context.read<PublishCubit>().drive.id);

  Future<List<FileEntry>> _images(DriveDao driveDao, String driveId) async {
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

  Future<void> _pick(BuildContext context, FileEntry file) async {
    final cubit = context.read<PublishCubit>();
    final repository = context.read<PublicationRepository>();
    // A second press before the chooser has gone must not pick again.
    if (cubit.state.choosingSlot == null) return;
    cubit.closeImageChooser();
    try {
      final bytes = await repository.readData(file.dataTxId);
      await cubit.pickImage(widget.slot, bytes);
    } catch (_) {
      await cubit.pickImage(widget.slot, Uint8List(0));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return SizedBox(
      height: _chooserHeight,
      child: FutureBuilder<List<FileEntry>>(
        future: _files,
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
                    style: typography.paragraphSmall(color: colors.textLow)),
                onTap: () => _pick(context, file),
              );
            },
          );
        },
      ),
    );
  }
}

/// The chooser's list height, so the dialog does not jump while it loads.
const _chooserHeight = 320.0;

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
        // A private page shares a card only when its owner picked one.
        if (!context.read<PublishCubit>().state.isPrivatePage ||
            context.watch<PublishCubit>().state.social != null) ...[
          const SizedBox(height: ArDriveSpacing.lg),
          _Label(strings.publishLinkPreview),
          const _CardPreview(),
        ],
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
    final cubit = context.read<PublishCubit>();
    final summary = state.summary;
    // The page always shows the address, beside a name when there is one.
    final address = shortenId(context.read<PublishCubit>().drive.ownerAddress);
    final name = state.ownerName.trim();
    final bylineStyle = typography.paragraphSmall(color: colors.textMid);
    // The rest of the byline, after the owner; no-break spaces keep a wrapped
    // line from starting with a middle dot, as on the page.
    final rest = [
      if (summary != null) strings.publishFileCount(summary.fileCount),
      if (state.licence != null) state.licence!.meta.shortName,
    ].map((part) => '\u00a0$arDriveSeparator $part').join();
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.title.trim().isEmpty
              ? (state.isPrivatePage ? strings.publicationPrivatePage : ' ')
              : state.title.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: typography.paragraphLarge(
              color: colors.textHigh, fontWeight: ArFontWeight.bold),
        ),
        const SizedBox(height: ArDriveSpacing.xxs),
        // A name in the body face and the address beside it in monospace
        // after a wallet icon, as on the published page.
        Text.rich(
          TextSpan(
            style: bylineStyle,
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: PublicationOwnerLabel(
                  name: name.isEmpty ? null : name,
                  address: address,
                  style: bylineStyle,
                  idStyle: typography.code(
                    color: colors.textLow,
                    fontSize: 11,
                  ),
                ),
              ),
              if (rest.isNotEmpty) TextSpan(text: rest),
            ],
          ),
        ),
        if (state.description.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            state.description.trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: typography.paragraphSmall(color: colors.textMid),
          ),
        ],
      ],
    );
    final cover = state.cover != null
        ? AspectRatio(
            aspectRatio: 4,
            child: RawImage(image: state.cover!.preview, fit: BoxFit.cover),
          )
        : AspectRatio(
            aspectRatio: 4,
            child: Container(color: colors.containerL2),
          );
    final icon = state.icon;
    // The same layout as the page's head at a smaller scale: the icon cut into
    // the cover's bottom-left edge, the title beside it.
    final head = icon != null
        ? PublicationCoverLayout(
            cover: cover,
            icon: SizedBox(
              width: 40,
              height: 40,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(ArDriveRadius.md),
                child: RawImage(image: icon.preview, fit: BoxFit.cover),
              ),
            ),
            iconSize: 40,
            ringWidth: 3,
            ringColor: colors.containerL0,
            inset: 12,
            iconRadius: ArDriveRadius.control,
            gap: 12,
            bodyTop: ArDriveSpacing.xs,
            beside: true,
            body: Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 12),
              child: title,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cover,
              Padding(padding: const EdgeInsets.all(12), child: title),
            ],
          );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.containerL0,
        borderRadius: BorderRadius.circular(ArDriveRadius.md),
        border: Border.all(color: colors.strokeLow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          head,
          // A file page shows its file under the header: what a visitor
          // opens and downloads. A private file's name stays hidden until
          // the key opens it.
          if (cubit.isFile)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _FilePreview(
                name: cubit.isPrivateFile
                    ? strings.sharedFileEncryptedFileTitle
                    : cubit.scopeName,
              ),
            ),
        ],
      ),
    );
  }
}

/// The file's card on a file page, small: its icon, its name and Download.
class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.name});

  /// The file's name, or "Encrypted file" for a private one.
  final String name;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: ArDriveSpacing.sm, vertical: ArDriveSpacing.xs),
      decoration: BoxDecoration(
        color: colors.containerL1,
        borderRadius: BorderRadius.circular(ArDriveRadius.md),
        border: Border.all(color: colors.strokeLow),
      ),
      child: Row(
        children: [
          // The locked share page's own icon, private or not.
          ArDriveIcons.file(size: 16, color: colors.iconMid),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typography.paragraphSmall(
                  color: colors.textHigh, fontWeight: ArFontWeight.semiBold),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: ArDriveSpacing.xs, vertical: ArDriveSpacing.xxs),
            decoration: BoxDecoration(
              color: colors.buttonPrimaryDefault,
              borderRadius: BorderRadius.circular(ArDriveRadius.md),
            ),
            child: Text(
              appLocalizationsOf(context).download,
              style: typography.paragraphSmall(
                  color: colors.textOnPrimary,
                  fontWeight: ArFontWeight.semiBold),
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
        borderRadius: BorderRadius.circular(ArDriveRadius.md),
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
                      // A file page lists no files, and its card says none.
                      fileCount: context.read<PublishCubit>().isFile
                          ? ''
                          : strings
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
