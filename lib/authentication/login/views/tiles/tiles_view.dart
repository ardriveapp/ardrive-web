import 'package:ardrive/authentication/components/breakpoint_layout_builder.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class TilesView extends StatelessWidget {
  const TilesView({
    Key? key,
  }) : super(key: key);

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
    return const _PermanentStorageTile();
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
                      padding: const EdgeInsets.only(
                          left: 8, right: 8, top: 8, bottom: 8),
                      child: _RoundContainer(child: _ArDriveIsForEveryOne()))),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(
                    right: 8,
                    top: 8,
                    bottom: 8,
                  ),
                  child: _MilitareGradeEncryption(),
                ),
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
        Flexible(
          child: Row(
            children: [
              const Flexible(
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
                  padding: const EdgeInsets.only(
                    left: 8,
                    bottom: 8,
                    right: 8,
                  ),
                  child: _RoundContainer(
                    child: Center(child: _PriceCalculator()),
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
    return Column(
      children: [
        const Flexible(
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
            padding: const EdgeInsets.only(
              left: 8,
              right: 8,
              top: 8,
              bottom: 8,
            ),
            child: Row(
              children: [
                const Flexible(
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

class _MilitareGradeEncryption extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    ArDriveTypographyNew.of(context);

    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Military-grade encryption',
          style: ArDriveTypographyNew.of(context).paragraphXLarge(
            color: ArDriveTheme.of(context).themeData.colorTokens.textLow,
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: SvgPicture.asset(
            Resources.images.login.bento2,
            fit: BoxFit.cover,
            height: 120,
            width: 120,
          ),
        ),
        const SizedBox.shrink(),
      ],
    );
  }
}

class _RoundContainer extends StatelessWidget {
  const _RoundContainer({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(
          color: colorTokens.strokeLow.withOpacity(0.08),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _ArDriveIsForEveryOne extends StatefulWidget {
  const _ArDriveIsForEveryOne({super.key});

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
          padding: const EdgeInsets.only(top: 8.0, left: 28),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
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
                  ),
                ),
                Text(
                  ' ${_hoveredProfile != null ? _hoveredProfile!.name : 'everyone'}',
                  style: ArDriveTypographyNew.of(context).paragraphXLarge(
                    color: _hoveredProfile != null
                        ? colorTokens.textRed.withOpacity(0.5)
                        : colorTokens.textMid,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8.0, left: 28),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
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
    super.key,
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
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(8),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      widget.model.name,
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

class _PermanentStorageTile extends StatelessWidget {
  const _PermanentStorageTile({super.key});

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Stack(
      fit: StackFit.expand,
      children: [
        Stack(
          fit: StackFit.expand,
          children: [
            ArDriveImage(
              image: AssetImage(
                Resources.images.login.particleSpace,
              ),
              fit: BoxFit.cover,
            ),
            Opacity(
              opacity: 0.5,
              child: Container(color: const Color(0xff141414)),
            )
          ],
        ),
        Align(
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SvgPicture.asset(
                Resources.images.login.dataStorage,
                height: 133,
                width: 133,
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
                      color: colorTokens.textOnPrimary,
                      fontWeight: ArFontWeight.semiBold,
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ],
    );
  }
}

class CarouselWithGroups extends StatefulWidget {
  final Function(_ProfileImageTileModel) onHover;
  final Function() onEndHover;

  const CarouselWithGroups({
    Key? key,
    required this.onHover,
    required this.onEndHover,
  }) : super(key: key);

  @override
  _CarouselWithGroupsState createState() => _CarouselWithGroupsState();
}

class _CarouselWithGroupsState extends State<CarouselWithGroups> {
  final CarouselController _mainCarouselController = CarouselController();

  final List<List<_ProfileImageTileModel>> groupImages = [
    // Group 1 images
    [
      _ProfileImageTileModel(
          Resources.images.login.bentoBox.profile1,
          'Educators',
          'Educators can store their educational content on ArDrive.'),
      _ProfileImageTileModel(
          Resources.images.login.bentoBox.profile2,
          'Journalists',
          'Journalists can store their articles and research on ArDrive.'),
      _ProfileImageTileModel(Resources.images.login.bentoBox.profile3,
          'Podcasters', 'Podcasters can store their podcasts on ArDrive.'),
    ],
    // Group 2 images
    [
      _ProfileImageTileModel(Resources.images.login.bentoBox.profile4,
          'Artists', 'Artists can store their art on ArDrive.'),
      _ProfileImageTileModel(Resources.images.login.bentoBox.profile5,
          'Creators', 'Creators can store their creations on ArDrive.'),
      _ProfileImageTileModel(
          Resources.images.login.bentoBox.profile6,
          'Sound Engineers',
          'Sound engineers can store their music on ArDrive.'),
    ],
  ];

  int _currentGroupIndex = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
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
                      padding: const EdgeInsets.all(8.0),
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
            viewportFraction: 0.9,
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
                onPageAnimationEnd: (index) {
                  // _mainCarouselController.animateToPage(index);
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

  const CustomIndicator({
    Key? key,
    required this.index,
    required this.currentPage,
    required this.onPageAnimationEnd,
    this.duration = const Duration(seconds: 10),
  }) : super(key: key);

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
    double indicatorWidth = widget.index == widget.currentPage ? 48.0 : 9.0;
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    if (widget.index != widget.currentPage) {
      return Container(
        width: indicatorWidth,
        height: 9.0,
        decoration: BoxDecoration(
          color: const Color(0xff3D3D3D),
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
        color: const Color(0xff3D3D3D),
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
                color: colorTokens.textLow,
                borderRadius: BorderRadius.circular(4.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bento5 extends StatefulWidget {
  const _Bento5({super.key});

  @override
  State<_Bento5> createState() => __Bento5State();
}

class __Bento5State extends State<_Bento5> {
  final List<_BentoBox5Model> _bentoBox5Models = [
    _BentoBox5Model(Resources.images.login.bentoBox.noSubscription,
        'No monthly subscriptions.'),
    _BentoBox5Model(Resources.images.login.bentoBox.permanentAccessibleData,
        'Permanently accessible data.'),
    _BentoBox5Model(Resources.images.login.bentoBox.decentralized,
        'Decentralized and open sourced.'),
  ];

  final CarouselController _mainCarouselController = CarouselController();
  int _currentGroupIndex = 0;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return _RoundContainer(
      child: Center(
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CarouselSlider.builder(
                  carouselController: _mainCarouselController,
                  itemCount: _bentoBox5Models.length,
                  itemBuilder:
                      (BuildContext context, int itemIndex, int pageViewIndex) {
                    return _Bento5Tile(
                      model: _bentoBox5Models[itemIndex],
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
                        onPageAnimationEnd: (index) {
                          // _mainCarouselController.animateToPage(index);
                        },
                      ),
                    );
                  }),
                ),
              ],
            )),
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
  const _Bento5Tile({super.key, required this.model});

  final _BentoBox5Model model;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return Column(
      children: [
        Text(model.title,
            style: typography.heading6(
              color: colorTokens.textLow,
              fontWeight: ArFontWeight.semiBold,
            )),
        Expanded(
          child: SvgPicture.asset(
            model.image,
            color: colorTokens.textRed,
          ),
        ),
        // SvgPicture.asset(
        //   Resources.images.login.bentoBox.bg,
        //   height: 100,
        //   width: 100,
        // ),
      ],
    );
  }
}

class _PriceCalculator extends StatefulWidget {
  _PriceCalculator({super.key});

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
        openUrl(url: 'https://ardrive.io/pricing');
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
