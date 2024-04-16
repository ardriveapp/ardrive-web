// ignore_for_file: library_private_types_in_public_api

import 'package:ardrive/authentication/components/breakpoint_layout_builder.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/svg.dart';

class TilesView extends StatelessWidget {
  const TilesView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width < SMALL_DESKTOP) {
      return _tablet();
    } else if (width < LARGE_DESKTOP) {
      return _smallDesktop();
    } else {
      return _largeDesktop();
    }
  }

  Widget _tablet() {
    return const _RoundContainer(child: _PermanentStorageTile());
  }

  Widget _largeDesktop() {
    return Column(
      children: [
        Flexible(
          child: Row(
            children: [
              const Flexible(
                flex: 2,
                child: Padding(
                  padding:
                      EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 8),
                  child: _RoundContainer(child: _ArDriveIsForEveryOne()),
                ),
              ),
              Flexible(
                child: Padding(
                    padding: const EdgeInsets.only(
                      right: 8,
                      top: 8,
                      bottom: 8,
                    ),
                    child: _RoundContainer(
                      padding: const EdgeInsets.all(0),
                      child: _MilitaryGradeEncryption(),
                    )),
              )
            ],
          ),
        ),
        const Flexible(
          child: Padding(
            padding: EdgeInsets.only(
              left: 8,
              right: 8,
              bottom: 8,
            ),
            child: _RoundContainer(
              child: Row(
                children: [
                  Flexible(flex: 1, child: _PermanentStorageTile()),
                ],
              ),
            ),
          ),
        ),
        const Flexible(
          child: Row(
            children: [
              Flexible(
                flex: 2,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: 8,
                    left: 8,
                  ),
                  child: _Bento5(),
                ),
              ),
              Flexible(
                flex: 3,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 8,
                    bottom: 8,
                    right: 8,
                  ),
                  child: _RoundContainer(
                    child: Center(
                      child: _PriceCalculator(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _smallDesktop() {
    return const Column(
      children: [
        Flexible(
          flex: 1,
          child: Padding(
            padding: EdgeInsets.only(
              left: 8,
              right: 8,
              top: 8,
            ),
            child: _RoundContainer(child: _PermanentStorageTile()),
          ),
        ),
        Flexible(
          flex: 1,
          child: Padding(
            padding: EdgeInsets.only(
              left: 8,
              right: 8,
              top: 8,
              bottom: 8,
            ),
            child: Row(
              children: [
                Flexible(
                  flex: 1,
                  child: Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: _Bento5(),
                  ),
                ),
                Flexible(
                  flex: 1,
                  child: _RoundContainer(child: _PriceCalculator()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MilitaryGradeEncryption extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // TODO: replace with ArDriveTheme .isLight method
    final isLightMode = ArDriveTheme.of(context).themeData.name == 'light';
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(8),
        topRight: Radius.circular(8),
        bottomLeft: Radius.circular(8),
        bottomRight: Radius.circular(8),
      ),
      child: SvgPicture.asset(
        isLightMode
            ? Resources.images.login.bentoBox.bentoBox2LightMode
            : Resources.images.login.bentoBox.bentoBox2DarkMode,
        fit: BoxFit.cover,
        clipBehavior: Clip.antiAliasWithSaveLayer,
      ),
    );
  }
}

class _RoundContainer extends StatefulWidget {
  const _RoundContainer({
    required this.child,
    this.padding,
  });
  final Widget child;
  final EdgeInsets? padding;

  @override
  State<_RoundContainer> createState() => _RoundContainerState();
}

class _RoundContainerState extends State<_RoundContainer> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Container(
        padding: widget.padding ?? const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(
            color: _isHovering
                ? colorTokens.textRed
                : colorTokens.strokeLow.withOpacity(0.08),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: colorTokens.containerL1,
        ),
        child: widget.child,
      ),
    );
  }
}

class _ArDriveIsForEveryOne extends StatefulWidget {
  const _ArDriveIsForEveryOne();

  @override
  State<_ArDriveIsForEveryOne> createState() => __ArDriveIsForEveryOneState();
}

class __ArDriveIsForEveryOneState extends State<_ArDriveIsForEveryOne> {
  _ProfileImageTileModel? _hoveredProfile;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final description = _hoveredProfile != null
        ? _hoveredProfile!.description
        : 'Your permanent hard drive that never forgets.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 0, left: 28),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            child: Row(
              key: ValueKey('FirstRow$_hoveredProfile'),
              children: [
                Text(
                  'ArDrive is for',
                  style: ArDriveTypographyNew.of(context).paragraphXLarge(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colorTokens
                        .textMid
                        .withOpacity(0.5),
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                Text(
                  ' ${_hoveredProfile != null ? _hoveredProfile!.name : 'everyone'}',
                  style: ArDriveTypographyNew.of(context).paragraphXLarge(
                    color: _hoveredProfile != null
                        ? colorTokens.textRed
                        : colorTokens.textMid,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            child: Row(
              key: ValueKey('SecondRow$_hoveredProfile'),
              children: [
                Text(
                  description,
                  textAlign: TextAlign.start,
                  style: ArDriveTypographyNew.of(context).paragraphNormal(
                    color:
                        ArDriveTheme.of(context).themeData.colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
              ],
            ),
          ),
        ),
        Flexible(
          child: CarouselWithGroups(
            onHover: (model) {
              setState(() {
                _hoveredProfile = model;
              });
            },
            onEndHover: () {
              setState(() {
                _hoveredProfile = null;
              });
            },
          ),
        ),
      ],
    );
  }
}

class _ProfileImageTile extends StatefulWidget {
  const _ProfileImageTile({
    required this.model,
    required this.onHover,
    required this.onEndHover,
  });

  final Function(_ProfileImageTileModel) onHover;
  final Function() onEndHover;

  final _ProfileImageTileModel model;

  @override
  State<_ProfileImageTile> createState() => _ProfileImageTileState();
}

class _ProfileImageTileModel {
  final String image;
  final String name;
  final String description;

  _ProfileImageTileModel(this.image, this.name, this.description);
}

class _ProfileImageTileState extends State<_ProfileImageTile> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(8),
        topRight: Radius.circular(8),
      ),
      clipBehavior: Clip.hardEdge,
      child: MouseRegion(
        onHover: (_) {
          setState(() => _isHovering = true);
          widget.onHover(widget.model);
        },
        onExit: (_) {
          setState(() => _isHovering = false);
          widget.onEndHover();
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: colorTokens.strokeLow.withOpacity(0.08),
              width: 1,
            ),
            color: colorTokens.containerL0,
            borderRadius: const BorderRadius.all(
              Radius.circular(8),
            ),
          ),
          padding: const EdgeInsets.all(4),
          height: 106,
          width: 106,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.all(
                  Radius.circular(8),
                ),
                child: ArDriveImage(
                  image: AssetImage(widget.model.image),
                  fit: BoxFit.contain,
                  height: 106,
                  width: 106,
                ),
              ),
              if (!_isHovering)
                Container(
                  height: 106,
                  width: 107,
                  decoration: BoxDecoration(
                    color: colorTokens.containerL0.withOpacity(0.75),
                  ),
                  child: Center(
                    child: Text(
                      widget.model.name,
                      textAlign: TextAlign.center,
                      style: ArDriveTypographyNew.of(context).paragraphNormal(
                        color: colorTokens.textLow,
                        fontWeight: ArFontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermanentStorageTile extends StatefulWidget {
  const _PermanentStorageTile();

  @override
  State<_PermanentStorageTile> createState() => _PermanentStorageTileState();
}

class _PermanentStorageTileState extends State<_PermanentStorageTile> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.all(
              Radius.circular(8),
            ),
            child: ArDriveImage(
              image: AssetImage(
                Resources.images.login.bentoBox.particleSpace,
              ),
              fit: BoxFit.cover,
              color: colorTokens.containerL0,
              colorBlendMode: BlendMode.color,
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: _isHovering ? 1.05 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: SvgPicture.asset(
                    Resources.images.login.bentoBox.dataStorage,
                    height: 133,
                    width: 133,
                  ),
                ),
                const SizedBox(width: 29),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Permanent',
                      style: typography.heading2(
                          color: const Color(0xffDB323B),
                          fontWeight: ArFontWeight.semiBold),
                    ),
                    Text(
                      'data storage',
                      style: typography.heading2(
                        color: colorTokens.textMid,
                        fontWeight: ArFontWeight.semiBold,
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CarouselWithGroups extends StatefulWidget {
  final Function(_ProfileImageTileModel model) onHover;
  final Function() onEndHover;

  const CarouselWithGroups({
    super.key,
    required this.onHover,
    required this.onEndHover,
  });

  @override
  _CarouselWithGroupsState createState() => _CarouselWithGroupsState();
}

class _CarouselWithGroupsState extends State<CarouselWithGroups> {
  final CarouselController _mainCarouselController = CarouselController();

  final List<List<_ProfileImageTileModel>> groupImages = [
    // Group 1 images
    [
      _ProfileImageTileModel(Resources.images.login.bentoBox.profile1,
          'Educators', 'Students and educators can preserve work forever.'),
      _ProfileImageTileModel(
          Resources.images.login.bentoBox.profile2,
          'Journalists',
          'Unleash journalistic freedom with censorship-resistant storage.'),
      _ProfileImageTileModel(
          Resources.images.login.bentoBox.profile3,
          'Podcasters',
          'Store episodes and research reliably and cost-effectively.'),
    ],
    // Group 2 images
    [
      _ProfileImageTileModel(Resources.images.login.bentoBox.profile4,
          'Artists', 'Store and share your art with the world.'),
      _ProfileImageTileModel(Resources.images.login.bentoBox.profile5,
          'Creators', 'Preserve your creations for future generations.'),
      _ProfileImageTileModel(Resources.images.login.bentoBox.profile6,
          'Sound Engineers', 'Store and share your music and sound projects.'),
    ],
  ];

  int _currentGroupIndex = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        CarouselSlider.builder(
          carouselController: _mainCarouselController,
          itemCount: groupImages.length,
          itemBuilder:
              (BuildContext context, int itemIndex, int pageViewIndex) {
            return Row(
              children: groupImages[itemIndex]
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: _ProfileImageTile(
                        model: item,
                        onEndHover: widget.onEndHover,
                        onHover: widget.onHover,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
          options: CarouselOptions(
            height: 125,
            enlargeCenterPage: false,
            viewportFraction: 0.76,
            enableInfiniteScroll: true,
            autoPlayAnimationDuration: const Duration(milliseconds: 300),
            pauseAutoPlayOnManualNavigate: true,
            autoPlayInterval: const Duration(seconds: 10),
            autoPlayCurve: Curves.easeInOut,
            autoPlay: true,
            aspectRatio: 1 / 1,
            onPageChanged: (index, reason) => setState(() {
              _currentGroupIndex = index;
            }),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(groupImages.length, (index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: CustomIndicator(
                index: index,
                currentPage: _currentGroupIndex,
                onPageAnimationEnd: (index) {},
                onClickDot: (index) {
                  _mainCarouselController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              ),
            );
          }),
        ),
      ],
    );
  }
}

class CustomIndicator extends StatefulWidget {
  final int index;
  final int currentPage;
  final Function(int) onPageAnimationEnd;
  final Duration duration;
  final Function(int) onClickDot;

  const CustomIndicator({
    super.key,
    required this.index,
    required this.currentPage,
    required this.onPageAnimationEnd,
    required this.onClickDot,
    this.duration = const Duration(seconds: 10),
  });

  @override
  _CustomIndicatorState createState() => _CustomIndicatorState();
}

class _CustomIndicatorState extends State<CustomIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _animation = Tween<double>(begin: 0.1, end: 1.0).animate(_controller)
      ..addListener(() {
        setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            widget.index == widget.currentPage) {
          widget.onPageAnimationEnd(widget.index);
        }
      });

    if (widget.index == widget.currentPage) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant CustomIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == widget.currentPage &&
        oldWidget.currentPage != widget.currentPage) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ArDriveClickArea(
      child: GestureDetector(
        onTap: () {
          widget.onClickDot(widget.index);
        },
        child: Builder(
          builder: (context) {
            double indicatorWidth =
                widget.index == widget.currentPage ? 48.0 : 9.0;
            final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
            if (widget.index != widget.currentPage) {
              return Container(
                width: indicatorWidth,
                height: 9.0,
                decoration: BoxDecoration(
                  color: const Color(0xffC4C4C4),
                  borderRadius: BorderRadius.circular(4.5),
                ),
              );
            }

            return AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: indicatorWidth,
              height: 9.0,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4.5),
                color: const Color(0xffC4C4C4),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: indicatorWidth * _animation.value,
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorTokens.iconMid,
                        borderRadius: BorderRadius.circular(4.5),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Bento5 extends StatefulWidget {
  const _Bento5();

  @override
  State<_Bento5> createState() => __Bento5State();
}

class __Bento5State extends State<_Bento5> {
  final List<_BentoBox5Model> _bentoBox5Models = [
    _BentoBox5Model(Resources.images.login.bentoBox.noSubscription,
        'No monthly subscriptions.'),
    _BentoBox5Model(Resources.images.login.bentoBox.permanentAccessibleData,
        'Permanently archived'),
    _BentoBox5Model(Resources.images.login.bentoBox.decentralized,
        'Decentralized and open sourced.'),
  ];

  final CarouselController _mainCarouselController = CarouselController();
  int _currentGroupIndex = 0;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    ArDriveTypographyNew.of(context);
    return Container(
      color: colorTokens.containerL0,
      child: _RoundContainer(
        child: Center(
          child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  CarouselSlider.builder(
                    carouselController: _mainCarouselController,
                    itemCount: _bentoBox5Models.length,
                    itemBuilder: (BuildContext context, int itemIndex,
                        int pageViewIndex) {
                      return GestureDetector(
                        onTap: () {
                          _mainCarouselController.nextPage();
                        },
                        child: _Bento5Tile(
                          model: _bentoBox5Models[itemIndex],
                        ),
                      );
                    },
                    options: CarouselOptions(
                      height: 200,
                      enlargeCenterPage: false,
                      viewportFraction: 1,
                      enableInfiniteScroll: true,
                      autoPlayAnimationDuration:
                          const Duration(milliseconds: 300),
                      pauseAutoPlayOnManualNavigate: true,
                      autoPlayInterval: const Duration(seconds: 5),
                      autoPlayCurve: Curves.easeInOut,
                      autoPlay: true,
                      aspectRatio: 1 / 1,
                      onPageChanged: (index, reason) => setState(() {
                        _currentGroupIndex = index;
                      }),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_bentoBox5Models.length, (index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: CustomIndicator(
                          index: index,
                          currentPage: _currentGroupIndex,
                          duration: const Duration(seconds: 5),
                          onPageAnimationEnd: (index) {},
                          onClickDot: (index) {
                            _mainCarouselController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                        ),
                      );
                    }),
                  ),
                ],
              )),
        ),
      ),
    );
  }
}

class _BentoBox5Model {
  final String image;
  final String title;

  _BentoBox5Model(this.image, this.title);
}

class _Bento5Tile extends StatelessWidget {
  const _Bento5Tile({required this.model});

  final _BentoBox5Model model;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return Column(
      children: [
        Text(
          model.title,
          style: typography.heading6(
            color: colorTokens.textLow,
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
        Expanded(
          child: SvgPicture.asset(
            model.image,
            color: colorTokens.textRed,
          ),
        ),
      ],
    );
  }
}

class _PriceCalculator extends StatefulWidget {
  const _PriceCalculator();

  @override
  State<_PriceCalculator> createState() => _PriceCalculatorState();
}

class _PriceCalculatorState extends State<_PriceCalculator> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final color = ArDriveTheme.of(context).themeData.colorTokens.textLow;
    return GestureDetector(
      onTap: () {
        openUrl(url: Resources.priceCalculatorLink);
      },
      child: ArDriveClickArea(
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovering = true),
          onExit: (_) => setState(() => _isHovering = false),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 24.0, right: 24, top: 24),
                child: SvgPicture.asset(
                  Resources.images.login.bentoBox.priceCalculator,
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: ArDriveImage(
                  image: AssetImage(Resources.images.login.bentoBox.dots),
                  fit: BoxFit.cover,
                ),
              ),
              if (_isHovering)
                Center(
                  child: Container(
                    width: double.maxFinite,
                    height: double.maxFinite,
                    color: color.withOpacity(0.1),
                    child: ArDriveIcons.newWindow(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
