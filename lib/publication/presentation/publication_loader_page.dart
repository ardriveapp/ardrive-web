import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/presentation/publication_loader/publication_loader_cubit.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// What a publication shows until its publication is open: the loading screen
/// and the error screens (docs/PUBLICATIONS.md, "Loading screen", "Error
/// screens"). One frame, centred on the page background: the publication's icon
/// and title once `publication.json` has been read, then a progress line or a
/// heading, a sentence and one action.
class PublicationLoaderPage extends StatelessWidget {
  const PublicationLoaderPage({super.key});

  /// Where "Open ArDrive" goes.
  static const ardriveUrl = 'https://app.ardrive.io';

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Scaffold(
      backgroundColor: colors.containerL0,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child:
                  BlocBuilder<PublicationLoaderCubit, PublicationLoaderState>(
                builder: (context, state) => _Frame(state: state),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.state});

  final PublicationLoaderState state;

  @override
  Widget build(BuildContext context) {
    // ArDrive's mark is fetched like any image on the web: ask for it now, so
    // it is there when a publication without its own icon needs it.
    precacheImage(AssetImage(Resources.images.brand.logo1), context);

    // Until publication.json is read there is no icon or title to show, only a
    // slot where one will be. That small request is quick; the page's
    // background alone covers it.
    if (state is PublicationLoadingSettings) return const SizedBox.shrink();

    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final config = _configOf(state);

    // A refused page is not trusted for anything it says about itself, the
    // window's name included: the publisher wrote it into <title>.
    if (state
        case PublicationFailed(failure: PublicationFailure.snapshotRejected)) {
      return Title(
        title: 'ArDrive',
        color: const Color(0xFF000000),
        child: _column(context, null, typography, colors),
      );
    }
    return _column(context, config, typography, colors);
  }

  Widget _column(
    BuildContext context,
    PublicationConfig? config,
    ArdriveTypographyNew typography,
    ArDriveColorTokens colors,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PublicationIcon(config: config, size: 64),
        if (config != null) ...[
          const SizedBox(height: 16),
          Text(
            config.title,
            textAlign: TextAlign.center,
            style: typography.heading4(
              color: colors.textHigh,
              fontWeight: ArFontWeight.bold,
            ),
          ),
        ],
        const SizedBox(height: 24),
        switch (state) {
          PublicationFailed(:final failure) => _Failure(failure: failure),
          // Private publications open in phase 3; until then this build cannot
          // open one, which is exactly what this screen says.
          PublicationNeedsKey() =>
            const _Failure(failure: PublicationFailure.needsNewerViewer),
          _ => _Progress(state: state),
        },
      ],
    );
  }

  static PublicationConfig? _configOf(PublicationLoaderState state) =>
      switch (state) {
        PublicationNeedsKey(:final config) => config,
        PublicationLoadingSnapshot(:final config) => config,
        PublicationImporting(:final config) => config,
        PublicationReady(:final config) => config,
        PublicationFailed(:final config) => config,
        PublicationLoadingSettings() => null,
      };
}

class _Progress extends StatelessWidget {
  const _Progress({required this.state});

  final PublicationLoaderState state;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final strings = appLocalizationsOf(context);

    final (String line, double? value) = switch (state) {
      // A browser that decodes a compressed body can count past the total
      // the gateway gave, which was of the compressed bytes.
      PublicationLoadingSnapshot(:final received, :final total)
          when total != null && total > 0 && received <= total =>
        (
          strings.publicationLoadingFilesOf(
              filesize(received), filesize(total)),
          received / total,
        ),
      PublicationLoadingSnapshot() => (strings.publicationLoadingFiles, null),
      PublicationImporting() || PublicationReady() => (
          strings.publicationAlmostThere,
          null
        ),
      _ => (strings.publicationLoadingFiles, null),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 240,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 3,
              backgroundColor: colors.containerL2,
              color: colors.textHigh,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          line,
          textAlign: TextAlign.center,
          style: typography.paragraphNormal(color: colors.textLow),
        ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.failure});

  final PublicationFailure failure;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final strings = appLocalizationsOf(context);

    final (heading, sentence) = switch (failure) {
      PublicationFailure.settingsUnreadable => (
          strings.publicationCantBeOpened,
          strings.publicationSettingsDamaged,
        ),
      PublicationFailure.snapshotUnavailable => (
          strings.publicationCantLoadNow,
          strings.publicationGatewayDidntReturnFiles,
        ),
      PublicationFailure.snapshotRejected => (
          strings.publicationCantBeOpened,
          strings.publicationDataFailedChecks,
        ),
      PublicationFailure.needsNewerViewer => (
          strings.publicationNeedsNewerArDrive,
          strings.publicationAskOwnerToRepublish,
        ),
    };
    final retry = failure == PublicationFailure.snapshotUnavailable;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          heading,
          textAlign: TextAlign.center,
          style: typography.heading5(
            color: colors.textHigh,
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          sentence,
          textAlign: TextAlign.center,
          style: typography.paragraphNormal(color: colors.textLow),
        ),
        const SizedBox(height: 24),
        ArDriveButtonNew(
          size: ArDriveButtonSize.large,
          text: retry ? strings.tryAgain : strings.publicationOpenArDrive,
          typography: typography,
          variant: ButtonVariant.primary,
          maxWidth: 240,
          onPressed: retry
              ? () => context.read<PublicationLoaderCubit>().retry()
              : () => openUrl(url: PublicationLoaderPage.ardriveUrl),
        ),
      ],
    );
  }
}

/// The publication's icon from its own manifest, or ArDrive's mark when it has
/// none or it does not load. A plain square holds its place while it loads.
class PublicationIcon extends StatelessWidget {
  const PublicationIcon({super.key, required this.config, required this.size});

  final PublicationConfig? config;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(
      Resources.images.brand.logo1,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
    final icon = config?.images.icon;
    if (icon == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 6),
      child: Image.network(
        Uri.base.resolve(icon).toString(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        frameBuilder: (context, image, frame, wasSynchronouslyLoaded) =>
            frame != null || wasSynchronouslyLoaded
                ? image
                : PublicationImagePlaceholder(width: size, height: size),
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

/// Where a publication's own image will be, until it has loaded.
class PublicationImagePlaceholder extends StatelessWidget {
  const PublicationImagePlaceholder({super.key, this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        color: ArDriveTheme.of(context).themeData.colorTokens.containerL2,
      );
}
