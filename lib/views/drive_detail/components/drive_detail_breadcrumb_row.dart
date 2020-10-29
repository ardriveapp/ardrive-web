import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DriveDetailBreadcrumbRow extends StatelessWidget {
  final List<String> _pathSegments;

  DriveDetailBreadcrumbRow({String path})
      : _pathSegments = path.split('/').where((s) => s != '').toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segmentButtonPadding = const EdgeInsets.symmetric(vertical: 16);

    final selectedSegmentTheme = TextButton.styleFrom(
      primary: kOnSurfaceBodyTextColor,
      padding: segmentButtonPadding,
    );

    return Theme(
      data: theme.copyWith(
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              textStyle: theme.textTheme.subtitle1,
              primary: Colors.black54,
              padding: segmentButtonPadding),
        ),
      ),
      child: Row(
        children: [
          TextButton(
            style: _pathSegments.isEmpty ? selectedSegmentTheme : null,
            onPressed: () =>
                context.bloc<DriveDetailCubit>().openFolderAtPath(''),
            child: Text(
              'Drive Root',
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
                onPressed: () => context
                    .bloc<DriveDetailCubit>()
                    .openFolderAtPath(
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
        ],
      ),
    );
  }
}
