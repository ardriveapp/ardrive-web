part of '../drive_detail_page.dart';

class DriveDetailBreadcrumbRow extends StatelessWidget {
  final List<String> _pathSegments;

  DriveDetailBreadcrumbRow({required String path})
      : _pathSegments = path.split('/').where((s) => s != '').toList();

  @override
  Widget build(BuildContext context) {
    final mobileBreadcrumbCount = 2;
    final desktopBreadcrumbCount = 4;

    final theme = Theme.of(context);
    final segmentButtonPadding = const EdgeInsets.symmetric(vertical: 16);

    final selectedSegmentTheme = TextButton.styleFrom(
      primary: kOnSurfaceBodyTextColor,
      padding: segmentButtonPadding,
    );
    Row _buildBreadcrumbs(int breadCrumbcount) {
      final breadCrumbSplit = _pathSegments.length - breadCrumbcount;
      return Row(
        children: [
          if (_pathSegments.length >= breadCrumbcount) ...[
            PopupMenuButton(
              icon: Icon(Icons.navigate_before),
              itemBuilder: (context) {
                return <PopupMenuItem>[
                  PopupMenuItem(
                    child: TextButton(
                      style:
                          _pathSegments.isEmpty ? selectedSegmentTheme : null,
                      onPressed: () => context
                          .read<DriveDetailCubit>()
                          .openFolder(path: rootPath),
                      child: Text(
                        AppLocalizations.of(context)!.driveRoot,
                      ),
                    ),
                  ),
                  ..._pathSegments
                      .sublist(0, (_pathSegments.length - breadCrumbcount))
                      .asMap()
                      .entries
                      .expand((s) {
                    return [
                      PopupMenuItem(
                        child: TextButton(
                          onPressed: () => context
                              .read<DriveDetailCubit>()
                              .openFolder(
                                  path:
                                      '/${_pathSegments.sublist(0, s.key + 1).join('/')}'),
                          child: Text(s.value),
                        ),
                      ),
                    ];
                  })
                ];
              },
            ),
            ..._pathSegments
                .sublist(breadCrumbSplit)
                .asMap()
                .entries
                .expand((s) {
              final isLastSegment =
                  s.key + breadCrumbSplit == _pathSegments.length - 1;

              return [
                TextButton(
                  style: isLastSegment ? selectedSegmentTheme : null,
                  onPressed: () => context.read<DriveDetailCubit>().openFolder(
                      path:
                          '/${_pathSegments.sublist(0, s.key + breadCrumbSplit + 1).join('/')}'),
                  child: Text(s.value),
                ),
                if (!isLastSegment)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('/'),
                  ),
              ];
            })
          ] else ...[
            TextButton(
              style: _pathSegments.isEmpty ? selectedSegmentTheme : null,
              onPressed: () =>
                  context.read<DriveDetailCubit>().openFolder(path: rootPath),
              child: Text(
                AppLocalizations.of(context)!.driveRoot,
              ),
            ),
            if (_pathSegments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('/'),
              ),
            ..._pathSegments.asMap().entries.expand((s) {
              final isLastSegment = s.key == _pathSegments.length - 1;

              return [
                TextButton(
                  style: isLastSegment ? selectedSegmentTheme : null,
                  onPressed: () => context.read<DriveDetailCubit>().openFolder(
                      path:
                          '/${_pathSegments.sublist(0, s.key + 1).join('/')}'),
                  child: Text(s.value),
                ),
                if (!isLastSegment)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('/'),
                  ),
              ];
            })
          ]
        ],
      );
    }

    return Theme(
      data: theme.copyWith(
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              textStyle: theme.textTheme.subtitle1,
              primary: Colors.black54,
              padding: segmentButtonPadding),
        ),
      ),
      child: ScreenTypeLayout(
          desktop: _buildBreadcrumbs(desktopBreadcrumbCount),
          mobile: _buildBreadcrumbs(mobileBreadcrumbCount)),
    );
  }
}
