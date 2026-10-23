import 'package:ardrive/library/domain/library_config.dart';
import 'package:ardrive/library/presentation/library_loader/library_loader_cubit.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// What a library page shows until its library is open: the loading screen
/// and the error screens (docs/LIBRARY_PAGES.md, "Loading screen", "Error
/// screens"). One frame, centred on the page background: the library's icon
/// and title once `library.json` has been read, then a progress line or a
/// heading, a sentence and one action.
class LibraryLoaderPage extends StatelessWidget {
  const LibraryLoaderPage({super.key});

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
              child: BlocBuilder<LibraryLoaderCubit, LibraryLoaderState>(
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

  final LibraryLoaderState state;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final config = _configOf(state);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LibraryIcon(config: config, size: 64),
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
          LibraryFailed(:final failure) => _Failure(failure: failure),
          // Private libraries open in phase 3; until then this build cannot
          // open one, which is exactly what this screen says.
          LibraryNeedsKey() =>
            const _Failure(failure: LibraryFailure.needsNewerViewer),
          _ => _Progress(state: state),
        },
      ],
    );
  }

  static LibraryConfig? _configOf(LibraryLoaderState state) => switch (state) {
        LibraryNeedsKey(:final config) => config,
        LibraryLoadingSnapshot(:final config) => config,
        LibraryImporting(:final config) => config,
        LibraryReady(:final config) => config,
        LibraryFailed(:final config) => config,
        LibraryLoadingSettings() => null,
      };
}

class _Progress extends StatelessWidget {
  const _Progress({required this.state});

  final LibraryLoaderState state;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final strings = appLocalizationsOf(context);

    final (String line, double? value) = switch (state) {
      LibraryLoadingSnapshot(:final received, :final total)
          when total != null && total > 0 =>
        (
          strings.libraryLoadingFilesOf(filesize(received), filesize(total)),
          received / total,
        ),
      LibraryLoadingSnapshot() => (strings.libraryLoadingFiles, null),
      LibraryImporting() || LibraryReady() => (
          strings.libraryAlmostThere,
          null
        ),
      _ => (strings.libraryOpening, null),
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

  final LibraryFailure failure;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final strings = appLocalizationsOf(context);

    final (heading, sentence) = switch (failure) {
      LibraryFailure.settingsUnreadable => (
          strings.libraryCantBeOpened,
          strings.librarySettingsDamaged,
        ),
      LibraryFailure.snapshotUnavailable => (
          strings.libraryCantLoadNow,
          strings.libraryGatewayDidntReturnFiles,
        ),
      LibraryFailure.snapshotRejected => (
          strings.libraryCantBeOpened,
          strings.libraryDataFailedChecks,
        ),
      LibraryFailure.needsNewerViewer => (
          strings.libraryNeedsNewerArDrive,
          strings.libraryAskOwnerToRepublish,
        ),
    };
    final retry = failure == LibraryFailure.snapshotUnavailable;

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
          text: retry ? strings.tryAgain : strings.libraryOpenArDrive,
          typography: typography,
          variant: ButtonVariant.primary,
          maxWidth: 240,
          onPressed: retry
              ? () => context.read<LibraryLoaderCubit>().retry()
              : () => openUrl(url: LibraryLoaderPage.ardriveUrl),
        ),
      ],
    );
  }
}

/// The library's icon from its own manifest, or ArDrive's when it has none
/// or it does not load.
class LibraryIcon extends StatelessWidget {
  const LibraryIcon({super.key, required this.config, required this.size});

  final LibraryConfig? config;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(
      Resources.images.login.ardriveLogoOnboarding,
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
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
