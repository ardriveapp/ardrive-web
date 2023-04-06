part of '../drive_detail_page.dart';

class DriveDetailBreadcrumbRow extends StatelessWidget {
  final List<String> _pathSegments;
  final String driveName;

  DriveDetailBreadcrumbRow({
    Key? key,
    required String path,
    required this.driveName,
  })  : _pathSegments = path.split('/').where((s) => s != '').toList(),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    const mobileBreadcrumbCount = 2;
    const desktopBreadcrumbCount = 4;

    return ScreenTypeLayout(
      desktop: _buildBreadcrumbs(
        desktopBreadcrumbCount,
        context,
      ),
      mobile: _buildBreadcrumbs(
        mobileBreadcrumbCount,
        context,
      ),
    );
  }

  Widget _buildBreadcrumbs(int breadCrumbcount, BuildContext context) {
    final breadCrumbSplit = _pathSegments.length - breadCrumbcount;
    final segmentStyle = ArDriveTypography.body.captionBold(
      color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
    );

    bool isLastSegment(int index) => index == _pathSegments.length - 1;

    Widget buildSegment(int index) {
      return TextButton(
        onPressed: () {
          final path = _pathSegments.sublist(0, index + 1).join('/');
          context.read<DriveDetailCubit>().openFolder(path: '/$path');
        },
        child: Text(_pathSegments[index], style: segmentStyle),
      );
    }

    Widget buildSeparator(bool isDrive) {
      final segmentStyle = ArDriveTypography.body.captionBold(
        color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
      );

      return Text(
        '/',
        style: isDrive
            ? segmentStyle.copyWith(
                color: ArDriveTheme.of(context)
                    .themeData
                    .colors
                    .themeAccentDisabled,
              )
            : segmentStyle,
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
          TextButton(
            onPressed: () => context
                .read<DriveDetailCubit>()
                .openFolder(path: entities.rootPath),
            child: Text(
              driveName,
              style: segmentStyle.copyWith(
                color: ArDriveTheme.of(context)
                    .themeData
                    .colors
                    .themeAccentDisabled,
                decoration: TextDecoration.underline,
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
                path: '/${path.sublist(0, s.key + 1).join('/')}',
              ),
          content: _buildDropdownItemContent(
            context,
            s.value,
            false,
          ),
        ),
      ];
    }).toList();
    items.insert(
      0,
      ArDriveDropdownItem(
        onClick: () => context.read<DriveDetailCubit>().openFolder(
              path: entities.rootPath,
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
        padding: const EdgeInsets.only(right: 8.0),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: ArDriveIcons.chevronLeft(
            color: Colors.white,
            size: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownItemContent(
    BuildContext context,
    String text,
    bool isDrive,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 8.0),
        child: Text(
          text,
          style: ArDriveTypography.body.captionBold(
            color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }
}
