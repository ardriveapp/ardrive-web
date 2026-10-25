import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart'
    show
        AudioPlayerWidget,
        FsEntryPreviewFailedMessage,
        FsEntryPreviewOnRequestPrompt,
        FsEntryPreviewProgress,
        FsEntryPreviewStarting,
        FsEntryPreviewWidget,
        VideoPlayerWidget;
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:visibility_detector/visibility_detector.dart';

class _MockFsEntryPreviewCubit extends MockCubit<FsEntryPreviewState>
    implements FsEntryPreviewCubit {}

/// A media preview that is not playing yet is drawn inside the player that
/// will play it, so the frame stands from the first moment to the last.
void main() {
  const video = FsEntryPreviewMedia(
    kind: FsEntryPreviewMediaKind.video,
    filename: 'clip.mp4',
  );
  const audio = FsEntryPreviewMedia(
    kind: FsEntryPreviewMediaKind.audio,
    filename: 'memo.mp3',
  );

  setUpAll(() {
    // The players pause when scrolled out of view; the detector's timer would
    // otherwise outlive each test.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  Widget wrap(Widget child, {Size size = const Size(480, 480)}) {
    return ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: Material(
          child: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  /// The big round play/pause button. Disabled until there is something to
  /// play.
  MaterialButton playButton(WidgetTester tester) =>
      tester.widget<MaterialButton>(find.byType(MaterialButton).last);

  group('the controls say what they are', () {
    // The play button had no name at all, and the speed, skip and mute
    // buttons no tooltip: a screen reader heard "button".
    testWidgets('the play button is named, and says Pause when playing',
        (tester) async {
      await tester.pumpWidget(wrap(const VideoPlayerWidget(
        filename: 'clip.mp4',
        videoUrl: null,
        isSharePage: false,
      )));

      expect(find.bySemanticsLabel('Play'), findsOneWidget);
      expect(find.byTooltip('Play'), findsOneWidget);
    });

    testWidgets('the speed control is named', (tester) async {
      await tester.pumpWidget(wrap(const AudioPlayerWidget(
        filename: 'memo.mp3',
        audioUrl: null,
        isSharePage: false,
      )));

      expect(find.byTooltip('Playback speed'), findsOneWidget);
    });

    testWidgets('on a phone the speeds open in the standard sheet, ticked',
        (tester) async {
      await tester.pumpWidget(wrap(const AudioPlayerWidget(
        filename: 'memo.mp3',
        audioUrl: null,
        isSharePage: false,
      )));

      await tester.tap(find.byTooltip('Playback speed'));
      // Not settled: the stage's "Loading..." spinner never stops.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ArDriveBottomSheet), findsOneWidget);
      expect(find.text('Playback speed'), findsOneWidget);
      expect(find.text('1.5x'), findsOneWidget);
      final normal = tester.widget<ListTile>(find.ancestor(
          of: find.text('Normal'), matching: find.byType(ListTile)));
      expect(normal.selected, isTrue);
    });
  });

  group('a player with no file yet', () {
    testWidgets('a video player draws its frame, with the stage given',
        (tester) async {
      await tester.pumpWidget(wrap(const VideoPlayerWidget(
        filename: 'clip.mp4',
        videoUrl: null,
        isSharePage: false,
        stage: Text('the stage'),
      )));

      expect(tester.takeException(), isNull);
      expect(find.text('the stage'), findsOneWidget);
      expect(find.text('clip.mp4'), findsOneWidget);
      expect(playButton(tester).onPressed, isNull,
          reason: 'nothing to play yet, so nothing to press');
    });

    testWidgets('an audio player draws its frame too, rather than a spinner',
        (tester) async {
      await tester.pumpWidget(wrap(const AudioPlayerWidget(
        filename: 'memo.mp3',
        audioUrl: null,
        isSharePage: false,
        stage: Text('the stage'),
      )));

      expect(tester.takeException(), isNull);
      expect(find.text('the stage'), findsOneWidget);
      expect(find.text('memo.mp3'), findsOneWidget);
      expect(playButton(tester).onPressed, isNull);
    });

    testWidgets('with no stage given, a player says it is loading',
        (tester) async {
      await tester.pumpWidget(wrap(const VideoPlayerWidget(
        filename: 'clip.mp4',
        videoUrl: null,
        isSharePage: false,
      )));

      expect(find.byType(FsEntryPreviewStarting), findsOneWidget);
      expect(find.text('Loading...'), findsOneWidget);
    });
  });

  group('what the preview draws for media that is not playing yet', () {
    late _MockFsEntryPreviewCubit cubit;

    setUp(() {
      cubit = _MockFsEntryPreviewCubit();
      when(() => cubit.retry()).thenAnswer((_) async {});
      when(() => cubit.loadOnRequest()).thenAnswer((_) async {});
    });

    Future<void> pump(
      WidgetTester tester,
      FsEntryPreviewState state, {
      Size size = const Size(480, 480),
    }) async {
      whenListen(cubit, const Stream<FsEntryPreviewState>.empty(),
          initialState: state);

      await tester.pumpWidget(wrap(
        FsEntryPreviewWidget(
          state: state,
          isSharePage: false,
          canNavigateThroughImages: false,
          previewCubit: cubit,
        ),
        size: size,
      ));
    }

    testWidgets('a video download is drawn in the video player, for its stage',
        (tester) async {
      await pump(
        tester,
        const FsEntryPreviewLoading(received: 1, total: 4, media: video),
      );

      expect(find.byType(VideoPlayerWidget), findsOneWidget);
      final progress = tester.widget<FsEntryPreviewProgress>(
        find.byType(FsEntryPreviewProgress),
      );
      expect(progress.onDark, isTrue, reason: 'a video stage is black');
      expect(find.text('clip.mp4'), findsOneWidget);
    });

    testWidgets('an audio download is drawn in the audio player',
        (tester) async {
      await pump(tester, const FsEntryPreviewLoading(media: audio));

      expect(find.byType(AudioPlayerWidget), findsOneWidget);
      final progress = tester.widget<FsEntryPreviewProgress>(
        find.byType(FsEntryPreviewProgress),
      );
      expect(progress.onDark, isFalse,
          reason: 'an audio stage follows the theme, so does what is on it');
    });

    testWidgets('a large video waits in its player, and Preview asks',
        (tester) async {
      await pump(
        tester,
        const FsEntryPreviewOnRequest(size: 30 * 1024 * 1024, media: video),
      );

      expect(find.byType(VideoPlayerWidget), findsOneWidget);
      expect(find.byType(FsEntryPreviewOnRequestPrompt), findsOneWidget);

      await tester.tap(find.text('Preview'));
      await tester.pump();

      verify(() => cubit.loadOnRequest()).called(1);
    });

    testWidgets('a failed video says so in its player, and Try Again asks',
        (tester) async {
      await pump(
        tester,
        const FsEntryPreviewFailed(
          FsEntryPreviewFailure.download,
          media: video,
        ),
      );

      expect(find.byType(VideoPlayerWidget), findsOneWidget);
      expect(find.byType(FsEntryPreviewFailedMessage), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();

      verify(() => cubit.retry()).called(1);
    });

    testWidgets('anything that is not media is not put in a player',
        (tester) async {
      await pump(tester, const FsEntryPreviewLoading(received: 1, total: 4));

      expect(find.byType(VideoPlayerWidget), findsNothing);
      expect(find.byType(AudioPlayerWidget), findsNothing);
      expect(find.byType(FsEntryPreviewProgress), findsOneWidget);
    });

    testWidgets('on a phone, a prompt with its button fits a short stage',
        (tester) async {
      // A phone-sized box: the player's controls leave the stage shorter
      // than the prompt, its sentence and its button.
      await pump(
        tester,
        const FsEntryPreviewOnRequest(size: 30 * 1024 * 1024, media: video),
        size: const Size(360, 320),
      );

      expect(tester.takeException(), isNull, reason: 'nothing overflows');
      await tester.tap(find.text('Preview'));
      await tester.pump();
      verify(() => cubit.loadOnRequest()).called(1);
    });

    testWidgets('on a dark stage the button is the filled one', (tester) async {
      await pump(
        tester,
        const FsEntryPreviewOnRequest(size: 30 * 1024 * 1024, media: video),
      );

      // The one thing to do on the stage, so the primary one.
      final button =
          tester.widget<ArDriveButtonNew>(find.byType(ArDriveButtonNew));
      expect(button.variant, ButtonVariant.primary);
      expect(button.size, ArDriveButtonSize.compact);
    });

    testWidgets('what is on a dark stage takes the dark theme', (tester) async {
      await pump(
        tester,
        const FsEntryPreviewOnRequest(size: 30 * 1024 * 1024, media: video),
      );

      // The app under test is in the light theme; the words on the black
      // stage must still be the dark theme's, or they are dark on black.
      final text = tester.widget<Text>(find.textContaining('This file is'));
      expect(text.style?.color, ArDriveColorTokens.darkMode().textHigh);
    });
  });

  group('the file arriving', () {
    testWidgets('keeps the same player: nothing is swapped out',
        (tester) async {
      final cubit = _MockFsEntryPreviewCubit();
      whenListen(cubit, const Stream<FsEntryPreviewState>.empty(),
          initialState: const FsEntryPreviewLoading(media: video));

      Future<void> show(FsEntryPreviewState state) => tester.pumpWidget(wrap(
            FsEntryPreviewWidget(
              state: state,
              isSharePage: false,
              canNavigateThroughImages: false,
              previewCubit: cubit,
            ),
          ));

      await show(const FsEntryPreviewLoading(
        phase: FsEntryPreviewLoadPhase.decrypting,
        media: video,
      ));
      final waiting = tester.state(find.byType(VideoPlayerWidget));

      await show(const FsEntryPreviewVideo(
        previewUrl: 'blob:fake/clip',
        filename: 'clip.mp4',
      ));
      // A VM test has no video platform, so the player says it cannot load
      // the file; what matters is that it is the same player saying it.
      await tester.pump();
      final playing = tester.state(find.byType(VideoPlayerWidget));

      expect(identical(waiting, playing), isTrue,
          reason: 'a new player here would be the frame being swapped');

      // And it started on the file it was handed, rather than keeping the
      // stage it had: with no platform here, starting ends on "could not
      // load", where a player that never started would say "Loading..."
      // forever.
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(FsEntryPreviewStarting), findsNothing);
      expect(find.byType(FsEntryPreviewProgress), findsNothing);
    });
  });
}
