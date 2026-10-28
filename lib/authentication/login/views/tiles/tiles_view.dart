import 'dart:async';
import 'dart:math' as math;

import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';

/// The brand red and the warm highlight it fades from, as in the art.
const _brandRed = Color(0xFFD31721);
const _brandPeach = Color(0xFFF4BE8C);

/// The bento beside the sign-in panel: what ArDrive is, in five tiles.
///
/// Every width keeps all five. Wide, they sit in three columns; narrower, two;
/// on a phone, below the sign-in panel, one. Which one is decided by the
/// bento's own width, and an unbounded height (inside a scroll view) means the
/// stacked phone column.
class TilesView extends StatelessWidget {
  const TilesView({super.key, this.loadPricePerGb});

  /// The price of 1 GB in USD; null when it can't be found. Defaults to
  /// Turbo's, read from [PaymentService].
  final Future<double?> Function()? loadPricePerGb;

  /// From here the bento has three columns.
  static const threeColumnsFrom = 600.0;

  /// From here, and with a bounded height, it has two.
  static const twoColumnsFrom = 400.0;

  @override
  Widget build(BuildContext context) {
    final loadPrice =
        loadPricePerGb ?? () => turboPricePerGb(context.read<PaymentService>());
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (!constraints.hasBoundedHeight || width < twoColumnsFrom) {
        return _Stacked(loadPrice: loadPrice);
      }
      if (width < threeColumnsFrom) {
        return _TwoColumns(loadPrice: loadPrice);
      }
      return _ThreeColumns(width: width, loadPrice: loadPrice);
    });
  }
}

/// The price of 1 GB in USD from Turbo: the credits a gigabyte costs, against
/// the credits ten dollars buy (Turbo's fees included, as a buyer pays them). Read once per session; null when Turbo can't
/// be reached, and the tile then leaves the price out.
Future<double?> turboPricePerGb(PaymentService payments) =>
    _pricePerGb ??= () async {
      try {
        final perGb = await payments.getPriceForBytes(byteSize: 1000000000);
        final perTenDollars = await payments.getPriceForFiat(
          wallet: null,
          // In cents, as Turbo takes it.
          amount: 1000,
          currency: 'usd',
        );
        if (perTenDollars.winc == BigInt.zero) return null;
        return perGb / perTenDollars.winc * 10;
      } catch (e) {
        logger.w('[bento] could not read the price of 1 GB: $e');
        _pricePerGb = null;
        return null;
      }
    }();
Future<double?>? _pricePerGb;

class _ThreeColumns extends StatelessWidget {
  const _ThreeColumns({required this.width, required this.loadPrice});

  final double width;
  final Future<double?> Function() loadPrice;

  @override
  Widget build(BuildContext context) {
    // The publishing tile is as wide as its one-line title needs; the slides
    // as wide as their art.
    final webWidth = (width * 0.4).clamp(268.0, 300.0);
    final slidesWidth = (width * 0.4).clamp(240.0, 280.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: _PeopleTile()),
              const SizedBox(width: 8),
              SizedBox(width: webWidth, child: const _OnlineTile()),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Expanded(child: _HeroTile()),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: slidesWidth, child: const _FeatureSlides()),
              const SizedBox(width: 8),
              Expanded(
                child: _CostTile(loadPrice: loadPrice, showEquivalents: true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TwoColumns extends StatelessWidget {
  const _TwoColumns({required this.loadPrice});

  final Future<double?> Function() loadPrice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Expanded(flex: 10, child: _PeopleTile()),
        const SizedBox(height: 8),
        const Expanded(flex: 6, child: _HeroTile(compact: true)),
        const SizedBox(height: 8),
        const Expanded(flex: 6, child: _OnlineTile()),
        const SizedBox(height: 8),
        // The price tile is the tallest of these; the page is never shorter
        // than 832, so at least 816 is shared out.
        Expanded(
          flex: 9,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: _FeatureSlides()),
              const SizedBox(width: 8),
              Expanded(
                child: _CostTile(loadPrice: loadPrice, showEquivalents: false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stacked extends StatelessWidget {
  const _Stacked({required this.loadPrice});

  final Future<double?> Function() loadPrice;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PeopleTile(),
        const SizedBox(height: 8),
        const SizedBox(height: 128, child: _HeroTile(compact: true)),
        const SizedBox(height: 8),
        const SizedBox(height: 200, child: _OnlineTile()),
        const SizedBox(height: 8),
        const SizedBox(height: 260, child: _FeatureSlides()),
        const SizedBox(height: 8),
        _CostTile(loadPrice: loadPrice, showEquivalents: false),
      ],
    );
  }
}

/// [child] takes the room that is left when there is a bounded height to share,
/// and its own height in the phone column, where there is none.
class _FlexIfBounded extends StatelessWidget {
  const _FlexIfBounded({required this.bounded, required this.child});

  final bool bounded;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      bounded ? Flexible(child: child) : child;
}

/// Whether the viewer asked for less motion: nothing then moves on its own.
bool _still(BuildContext context) => MediaQuery.of(context).disableAnimations;

bool _isLight(BuildContext context) =>
    ArDriveTheme.of(context).themeData.name == 'light';

/// One tile: a large panel, radius 12, on the panel surface. A tile that is a
/// link lifts a little under the pointer; the others don't react.
class _Tile extends StatefulWidget {
  const _Tile({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.onTap,
    this.semanticsLabel,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final lifted = widget.onTap != null && _hovering;
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      transform: Matrix4.translationValues(0, lifted ? -2 : 0, 0),
      padding: widget.padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.containerL1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: lifted ? colors.strokeHigh : colors.strokeLow,
        ),
      ),
      child: widget.child,
    );
    if (widget.onTap == null) return tile;
    return Semantics(
      link: true,
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (mounted) setState(() => _hovering = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovering = false);
        },
        child: GestureDetector(onTap: widget.onTap, child: tile),
      ),
    );
  }
}

/// Dots under a slider: the current one is a bar that fills over [interval],
/// like a progress bar. Each dot is a 24 px target that a keyboard reaches.
class _ProgressDots extends StatefulWidget {
  const _ProgressDots({
    required this.count,
    required this.index,
    required this.interval,
    required this.labels,
    required this.groupLabel,
    required this.onPick,
    this.running = true,
  });

  final int count;
  final int index;
  final Duration interval;
  final List<String> labels;
  final String groupLabel;
  final ValueChanged<int> onPick;

  /// False while paused or under reduced motion: the bar shows full.
  final bool running;

  @override
  State<_ProgressDots> createState() => _ProgressDotsState();
}

class _ProgressDotsState extends State<_ProgressDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fill =
      AnimationController(vsync: this, duration: widget.interval);

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant _ProgressDots old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index || old.running != widget.running) {
      _restart();
    }
  }

  void _restart() {
    if (widget.running) {
      _fill.forward(from: 0);
    } else {
      _fill.value = 1;
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Semantics(
      label: widget.groupLabel,
      container: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < widget.count; i++)
            Semantics(
              button: true,
              selected: i == widget.index,
              label: widget.labels[i],
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('bentoDot-${widget.groupLabel}-$i'),
                onTap: () => widget.onPick(i),
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(
                  dimension: 24,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == widget.index ? 28 : 8,
                      height: 8,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: colors.strokeHigh,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: i == widget.index
                          ? AnimatedBuilder(
                              animation: _fill,
                              builder: (context, _) => FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: _fill.value,
                                child: ColoredBox(color: colors.iconMid),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A timer that steps an index, unless reduced motion is on or it is held.
mixin _Stepper<T extends StatefulWidget> on State<T> {
  Timer? _timer;
  int index = 0;
  bool held = false;

  int get length;
  Duration get interval;

  void startStepping() {
    _timer?.cancel();
    if (_still(context)) return;
    _timer = Timer.periodic(interval, (_) {
      if (!held && mounted) setState(() => index = (index + 1) % length);
    });
  }

  void pick(int i) {
    setState(() => index = i);
    // Picking restarts the count, so the chosen one gets its full time.
    startStepping();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    startStepping();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _Person {
  const _Person(this.image, this.name, this.line);
  final String image;
  final String name;
  final String line;
}

class _PeopleTile extends StatefulWidget {
  const _PeopleTile();

  @override
  State<_PeopleTile> createState() => _PeopleTileState();
}

class _PeopleTileState extends State<_PeopleTile> with _Stepper {
  _Person? _hovered;

  @override
  int get length => 2;

  @override
  Duration get interval => const Duration(seconds: 10);

  List<List<_Person>> _groups(BuildContext context) {
    final s = appLocalizationsOf(context);
    final images = Resources.images.login.bentoBox;
    return [
      [
        _Person(images.profile1, s.bentoEducators, s.bentoEducatorsLine),
        _Person(images.profile2, s.bentoJournalists, s.bentoJournalistsLine),
        _Person(images.profile3, s.bentoPodcasters, s.bentoPodcastersLine),
      ],
      [
        _Person(images.profile4, s.bentoArtists, s.bentoArtistsLine),
        _Person(images.profile5, s.bentoCreators, s.bentoCreatorsLine),
        _Person(
            images.profile6, s.bentoSoundEngineers, s.bentoSoundEngineersLine),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final groups = _groups(context);
    final hovered = _hovered;
    return _Tile(
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // Heading at the top, dots at the bottom, the people centred
          // between them, however tall the tile.
          mainAxisSize: constraints.hasBoundedHeight
              ? MainAxisSize.max
              : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${s.bentoIsFor} '),
                    TextSpan(
                      text: hovered?.name ?? s.bentoEveryone,
                      style: TextStyle(
                        color: hovered == null ? colors.textHigh : _brandRed,
                      ),
                    ),
                  ]),
                  key: const Key('bentoPeopleHeading'),
                  style: type.heading6(
                    color: colors.textHigh,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hovered?.line ?? s.bentoEveryoneLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.paragraphNormal(color: colors.textMid),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _FlexIfBounded(
              bounded: constraints.hasBoundedHeight,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: Row(
                  key: ValueKey('bentoPeople-$index'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, person) in groups[index].indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _PersonPicture(
                          person: person,
                          onHover: (on) {
                            if (!mounted) return;
                            setState(() {
                              _hovered = on ? person : null;
                              held = on;
                            });
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _ProgressDots(
              count: groups.length,
              index: index,
              interval: interval,
              running: !held && !_still(context),
              groupLabel: s.bentoPeopleDots,
              labels: [
                for (final g in groups) g.map((p) => p.name).join(', '),
              ],
              onPick: pick,
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonPicture extends StatelessWidget {
  const _PersonPicture({required this.person, required this.onHover});

  final _Person person;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 140),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.strokeLow),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(person.image, fit: BoxFit.cover),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xB8000000)],
                      ),
                    ),
                    child: Text(
                      person.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // White on the photo's dark fade, in both themes.
                      style: type.paragraphSmall(
                        color: const Color(0xFFFFFFFF),
                        fontWeight: ArFontWeight.semiBold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Put it online, for good": an example address types itself out, holds,
/// and gives way to the next. Every name is an example.
class _OnlineTile extends StatefulWidget {
  const _OnlineTile();

  @override
  State<_OnlineTile> createState() => _OnlineTileState();
}

class _OnlineTileState extends State<_OnlineTile> {
  static const _names = ['maya', 'recipes', 'my-band', 'thesis'];
  static const _typeEvery = Duration(milliseconds: 120);

  /// Ticks a finished name is held before it is deleted.
  static const _holdTicks = 14;

  Timer? _typer;
  Timer? _blink;
  int _example = 0;
  int _chars = 0;
  int _held = 0;
  bool _deleting = false;
  bool _caretOn = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _typer?.cancel();
    _blink?.cancel();
    if (_still(context)) {
      _chars = _names[_example].length;
      return;
    }
    _typer = Timer.periodic(_typeEvery, (_) => _tick());
    _blink = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _caretOn = !_caretOn);
    });
  }

  void _tick() {
    if (!mounted) return;
    final name = _names[_example];
    setState(() {
      if (!_deleting) {
        if (_chars < name.length) {
          _chars++;
        } else if (++_held > _holdTicks) {
          _held = 0;
          _deleting = true;
        }
      } else if (_chars > 0) {
        _chars--;
      } else {
        _deleting = false;
        _example = (_example + 1) % _names.length;
      }
    });
  }

  @override
  void dispose() {
    _typer?.cancel();
    _blink?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final labels = [
      s.bentoExamplePortfolio,
      s.bentoExampleRecipes,
      s.bentoExampleBand,
      s.bentoExampleResearch,
    ];
    final still = _still(context);
    final address = type.heading3(fontWeight: ArFontWeight.semiBold);
    return _Tile(
      child: Stack(
        children: [
          const Positioned.fill(child: _Sparkles()),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.bentoOnlineTitle,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: type.heading6(
                  color: colors.textHigh,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                s.bentoOnlineBody,
                style: type.paragraphNormal(color: colors.textMid),
              ),
              Expanded(
                child: Center(
                  // Shrinks rather than overflows, for a narrow tile or a
                  // longer translation of the label.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          label: '${_names[_example]}.ar.io',
                          excludeSemantics: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ShaderMask(
                                blendMode: BlendMode.srcIn,
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [_brandPeach, _brandRed],
                                  stops: [0, 0.45],
                                ).createShader(bounds),
                                child: Text(
                                  _names[_example].substring(0, _chars),
                                  key: const Key('bentoTypedName'),
                                  style: address,
                                ),
                              ),
                              Opacity(
                                opacity: !still && _caretOn ? 1 : 0,
                                child: Container(
                                  width: 2,
                                  height: 24,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 1),
                                  color: _brandRed,
                                ),
                              ),
                              Text(
                                '.ar.io',
                                style: address.copyWith(color: colors.textLow),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          child: Text(
                            labels[_example],
                            key: ValueKey(_example),
                            style: type.paragraphSmall(
                              color: colors.textLow,
                              fontWeight: ArFontWeight.semiBold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The art's sparkles and dots, drawn behind a tile that has no picture.
class _Sparkles extends StatelessWidget {
  const _Sparkles();

  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: CustomPaint(painter: _SparklePainter()));
}

class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    void sparkle(double x, double y, double r, double opacity) {
      final c = Offset(size.width * x, size.height * y);
      final path = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
        ..close();
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _brandPeach.withOpacity(opacity),
            _brandRed.withOpacity(opacity),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawPath(path, paint);
    }

    void dot(double x, double y, double r, double opacity) => canvas.drawCircle(
        Offset(size.width * x, size.height * y),
        r,
        Paint()..color = const Color(0xFF93161D).withOpacity(opacity));

    // In the lower half, around the address, clear of the title and text.
    sparkle(0.1, 0.72, 12, 0.7);
    sparkle(0.9, 0.86, 6, 0.5);
    dot(0.9, 0.62, 3, 0.3);
    dot(0.2, 0.92, 2, 0.4);
    dot(0.72, 0.95, 2, 0.2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The large tile: "Permanent web publishing and data storage", over a field
/// of particles that drifts very slowly.
class _HeroTile extends StatefulWidget {
  const _HeroTile({this.compact = false});

  /// Narrow layouts: a smaller picture and heading.
  final bool compact;

  @override
  State<_HeroTile> createState() => _HeroTileState();
}

class _HeroTileState extends State<_HeroTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final heading = widget.compact
        ? type.heading5(fontWeight: ArFontWeight.bold)
        : type.heading2(fontWeight: ArFontWeight.bold);
    final picture = widget.compact ? 64.0 : 128.0;
    return _Tile(
      padding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _drift,
              builder: (context, child) {
                final t = _drift.value * 2 * math.pi;
                return Transform.translate(
                  offset: Offset(math.sin(t) * 10, math.cos(t) * 6),
                  child: Transform.scale(scale: 1.08, child: child),
                );
              },
              child: Opacity(
                opacity: _isLight(context) ? 0.35 : 0.55,
                child: Image.asset(
                  Resources.images.login.bentoBox.particleSpace,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  Resources.images.login.bentoBox.dataStorage,
                  height: picture,
                  width: picture,
                ),
                const SizedBox(width: 24),
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: '${s.bentoHeroAccent}\n',
                        style: const TextStyle(color: _brandRed),
                      ),
                      TextSpan(text: s.bentoHeroRest),
                    ]),
                    style: heading.copyWith(color: colors.textMid),
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

class _Slide {
  const _Slide(this.title, this.art);
  final String title;
  final String art;
}

class _FeatureSlides extends StatefulWidget {
  const _FeatureSlides();

  @override
  State<_FeatureSlides> createState() => _FeatureSlidesState();
}

class _FeatureSlidesState extends State<_FeatureSlides> with _Stepper {
  @override
  int get length => 5;

  @override
  Duration get interval => const Duration(seconds: 5);

  List<_Slide> _slides(BuildContext context) {
    final s = appLocalizationsOf(context);
    final light = _isLight(context);
    String art(String name) =>
        Resources.images.login.bentoBox.featureArt(name, light: light);
    return [
      _Slide(s.bentoPrivate, art('encrypted_key')),
      _Slide(s.bentoUnchangeable, art('cant_be_changed')),
      _Slide(s.bentoProofOfTime, art('proof_of_time')),
      _Slide(s.bentoShareLink, art('share_link')),
      _Slide(s.bentoOpenSource, art('open_source')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final slides = _slides(context);
    final slide = slides[index];
    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => held = true);
      },
      onExit: (_) {
        if (mounted) setState(() => held = false);
      },
      child: _Tile(
        child: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: Column(
                  key: ValueKey(index),
                  children: [
                    Text(
                      slide.title,
                      key: const Key('bentoSlideTitle'),
                      textAlign: TextAlign.center,
                      style: type.heading6(
                        color: colors.textHigh,
                        fontWeight: ArFontWeight.semiBold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ExcludeSemantics(
                        child: SvgPicture.asset(slide.art, fit: BoxFit.contain),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _ProgressDots(
              count: slides.length,
              index: index,
              interval: interval,
              running: !held && !_still(context),
              groupLabel: s.bentoSlideDots,
              labels: [for (final x in slides) x.title],
              onPick: pick,
            ),
          ],
        ),
      ),
    );
  }
}

/// "What it costs": the live price of 1 GB, paid once. Opens the pricing page.
class _CostTile extends StatefulWidget {
  const _CostTile({required this.loadPrice, required this.showEquivalents});

  final Future<double?> Function() loadPrice;

  /// What a gigabyte holds, where there is room for it.
  final bool showEquivalents;

  @override
  State<_CostTile> createState() => _CostTileState();
}

class _CostTileState extends State<_CostTile> {
  /// The width the price and the list need side by side.
  static const _equivalentsFrom = 340.0;

  late final Future<double?> _price = widget.loadPrice();

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final body = type.paragraphNormal(color: colors.textMid);

    final price = FutureBuilder<double?>(
      future: _price,
      builder: (context, snapshot) {
        // A fixed-height line, so the tile doesn't move when the price lands.
        const height = 36.0;
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            height: height,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                key: const Key('bentoPriceLoading'),
                width: 120,
                height: 20,
                decoration: BoxDecoration(
                  color: colors.strokeMid,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          );
        }
        final usd = snapshot.data;
        if (usd == null) return const SizedBox.shrink();
        return SizedBox(
          height: height,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '\$${usd.toStringAsFixed(2)} ',
                style: type
                    .heading2(
                  color: colors.textHigh,
                  fontWeight: ArFontWeight.light,
                )
                    .copyWith(fontFeatures: const [
                  FontFeature.tabularFigures(),
                ]),
              ),
              TextSpan(
                text: 'USD',
                style: type.paragraphNormal(
                  color: colors.textMid,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
            ]),
            key: const Key('bentoPrice'),
          ),
        );
      },
    );

    Widget equivalent(ArDriveIcon icon, String text) => Row(
          children: [
            icon,
            const SizedBox(width: 8),
            Text(text, style: body),
          ],
        );

    return _Tile(
      onTap: () => openUrl(url: Resources.priceCalculatorLink),
      semanticsLabel: '${s.bentoCostTitle}. ${s.bentoSeePrices}',
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.bentoCostTitle,
              style: type.heading6(
                color: colors.textHigh,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
            const SizedBox(height: 16),
            _FlexIfBounded(
              bounded: constraints.hasBoundedHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(s.bentoCostAmount, style: body),
                        const SizedBox(height: 4),
                        price,
                        const SizedBox(height: 4),
                        Text(s.bentoCostPaidOnce, style: body),
                      ],
                    ),
                  ),
                  if (widget.showEquivalents &&
                      constraints.maxWidth >= _equivalentsFrom) ...[
                    const SizedBox(width: 24),
                    Container(
                      padding: const EdgeInsets.only(left: 24),
                      decoration: BoxDecoration(
                        border:
                            Border(left: BorderSide(color: colors.strokeLow)),
                      ),
                      child: Column(
                        key: const Key('bentoEquivalents'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          equivalent(
                            ArDriveIcons.image(size: 16, color: colors.iconMid),
                            s.bentoPictures,
                          ),
                          const SizedBox(height: 8),
                          equivalent(
                            ArDriveIcons.file(size: 16, color: colors.iconMid),
                            s.bentoDocuments,
                          ),
                          const SizedBox(height: 8),
                          equivalent(
                            ArDriveIcons.video(size: 16, color: colors.iconMid),
                            s.bentoVideos,
                          ),
                          const SizedBox(height: 8),
                          equivalent(
                            ArDriveIcons.music(size: 16, color: colors.iconMid),
                            s.bentoSongs,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.bentoSeePrices,
                  style: type
                      .paragraphNormal(
                        color: colors.textLink,
                        fontWeight: ArFontWeight.semiBold,
                      )
                      .copyWith(decoration: TextDecoration.underline),
                ),
                const SizedBox(width: 4),
                ArDriveIcons.newWindow(size: 14, color: colors.textLink),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
