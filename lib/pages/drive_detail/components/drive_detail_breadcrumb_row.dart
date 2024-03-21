part of '../drive_detail_page.dart';

class BreadCrumbRowInfo {
  final String text;
  final String targetId;

  BreadCrumbRowInfo({
    required this.text,
    required this.targetId,
  });
}

class DriveDetailBreadcrumbRow extends StatelessWidget {
  final List<BreadCrumbRowInfo> _pathSegments;
  final String driveName;
  final String rootFolderId;

  const DriveDetailBreadcrumbRow({
    Key? key,
    required List<BreadCrumbRowInfo> path,
    required this.driveName,
    required this.rootFolderId,
  })  : _pathSegments = path,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    const mobileBreadcrumbCount = 2;
    const desktopBreadcrumbCount = 4;

    return ScreenTypeLayout.builder(
      desktop: (context) => _buildBreadcrumbs(
        desktopBreadcrumbCount,
        context,
      ),
      mobile: (context) => _buildBreadcrumbs(
        mobileBreadcrumbCount,
        context,
      ),
    );
  }

  Widget _buildBreadcrumbs(int breadCrumbcount, BuildContext context) {
    bool isLastSegment(int index) => index == _pathSegments.length - 1;

    final breadCrumbSplit = _pathSegments.length - breadCrumbcount;
    TextStyle segmentStyle(int index) {
      return ArDriveTypography.body
          .captionBold(
            color: isLastSegment(index)
                ? ArDriveTheme.of(context).themeData.colors.themeFgDefault
                : ArDriveTheme.of(context).themeData.colors.themeAccentDisabled,
          )
          .copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          );
    }

    Widget buildSegment(int index) {
      return GestureDetector(
        onTap: () {
          context.read<DriveDetailCubit>().openFolder(
                folderId: _pathSegments[index].targetId,
              );
        },
        child: HoverText(
          text: _pathSegments[index].text,
          style: segmentStyle(index),
        ),
      );
    }

    Widget buildSeparator(bool isDrive) {
      final segmentStyle = ArDriveTypography.body.captionBold(
        color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
      );

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          '/',
          style: segmentStyle.copyWith(
            color:
                ArDriveTheme.of(context).themeData.colors.themeAccentDisabled,
          ),
        ),
      );
    }

    List<Widget> segments = [];

    if (_pathSegments.length >= breadCrumbcount) {
      segments.add(_navigateBackIcon(
        context: context,
        breadCrumbcount: breadCrumbcount,
      ));
      segments.addAll(
        _pathSegments.sublist(breadCrumbSplit).asMap().entries.expand(
              (s) => [
                buildSegment(s.key + breadCrumbSplit),
                if (!isLastSegment(s.key + breadCrumbSplit))
                  buildSeparator(false)
              ],
            ),
      );
    } else {
      segments.addAll(
        [
          GestureDetector(
            onTap: () => context
                .read<DriveDetailCubit>()
                .openFolder(folderId: rootFolderId),
            child: HoverText(
              text: driveName,
              style: segmentStyle(_pathSegments.length).copyWith(
                color: _pathSegments.isEmpty
                    ? ArDriveTheme.of(context).themeData.colors.themeFgDefault
                    : ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeAccentDisabled,
              ),
            ),
          ),
        ],
      );
      if (_pathSegments.isNotEmpty) {
        segments.add(buildSeparator(true));
      }

      segments.addAll(
        _pathSegments.asMap().entries.expand(
              (s) => [
                buildSegment(s.key),
                if (!isLastSegment(s.key)) buildSeparator(false)
              ],
            ),
      );
    }

    return Row(children: segments);
  }

  Widget _navigateBackIcon({
    required BuildContext context,
    required int breadCrumbcount,
  }) {
    final path =
        _pathSegments.sublist(0, _pathSegments.length - breadCrumbcount);
    final items = path.asMap().entries.expand((s) {
      return [
        ArDriveDropdownItem(
          onClick: () => context.read<DriveDetailCubit>().openFolder(
                folderId: s.value.targetId,
              ),
          content: _buildDropdownItemContent(
            context,
            s.value.text,
            false,
          ),
        ),
      ];
    }).toList();
    items.insert(
      0,
      ArDriveDropdownItem(
        onClick: () => context.read<DriveDetailCubit>().openFolder(
              folderId: rootFolderId,
            ),
        content: _buildDropdownItemContent(
          context,
          driveName,
          true,
        ),
      ),
    );
    return ArDriveDropdown(
      items: items,
      child: Padding(
        padding: const EdgeInsets.only(right: 8.0, top: 4),
        child: HoverWidget(
          // cursor: SystemMouseCursors.click,
          child: ArDriveIcons.carretLeft(),
        ),
      ),
    );
  }

  Widget _buildDropdownItemContent(
    BuildContext context,
    String text,
    bool isDrive,
  ) {
    return ArDriveDropdownItemTile(
      name: text,
    );
  }
}

class HoverText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const HoverText({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  // ignore: library_private_types_in_public_api
  _HoverTextState createState() => _HoverTextState();
}

class _HoverTextState extends State<HoverText> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() {
          _isHovering = true;
        });
      },
      onExit: (_) {
        setState(() {
          _isHovering = false;
        });
      },
      child: Text(
        widget.text,
        style: _isHovering
            ? widget.style.copyWith(
                color: ArDriveTheme.of(context).themeData.colors.themeFgDefault)
            : widget.style,
      ),
    );
  }
}
