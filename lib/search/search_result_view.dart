import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The icon a search result is listed with: the file's type, a folder, or the
/// drive's privacy.
Widget searchResultIcon(
  SearchResult searchResult,
  ArDriveColorTokens colorTokens, {
  double size = 24,
}) {
  final result = searchResult.result;

  if (result is FileEntry) {
    return getIconForContentType(
      result.dataContentType ?? ContentType.octetStream,
      size: size,
      color: colorTokens.textHigh,
    );
  } else if (result is FolderEntry) {
    return ArDriveIcons.folderOutline(
      size: size,
      color: colorTokens.textHigh,
    );
  } else if (result is Drive) {
    // Its kind is in the line under its name.
    return ArDriveIcons.drive(size: size, color: colorTokens.iconHigh);
  }

  return Icon(Icons.error, size: size);
}

/// Where a result is: the drive, and the folder when it is not the drive's
/// top level. For a drive, what kind of drive it is.
String searchResultLocation(BuildContext context, SearchResult searchResult) {
  final result = searchResult.result;

  if (result is Drive) {
    return appLocalizationsOf(context).searchDriveResult(result.privacy);
  }

  final parentFolder = searchResult.parentFolder;

  return parentFolder == null
      ? searchResult.drive.name
      : '${searchResult.drive.name} / ${parentFolder.name}';
}

/// Whether a result is hidden, or sits in a hidden drive.
bool searchResultIsHidden(SearchResult searchResult) {
  final result = searchResult.result;

  if (result is FileEntry && result.isHidden) return true;
  if (result is FolderEntry && result.isHidden) return true;
  if (result is Drive) return result.isHidden;

  return searchResult.drive.isHidden;
}

/// A name with the part that matches [query] in bold, so the reader sees why
/// it is listed. Plain when the query does not appear in it as typed, which a
/// LIKE wildcard (`%` or `_`) in the query can cause.
class SearchMatchText extends StatelessWidget {
  const SearchMatchText({
    super.key,
    required this.text,
    required this.query,
    required this.style,
    required this.matchStyle,
  });

  final String text;
  final String query;
  final TextStyle style;
  final TextStyle matchStyle;

  @override
  Widget build(BuildContext context) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    // Lowercasing can change a string's length ("İ" becomes two code units),
    // and then a position in the lowercased name is not one in the name.
    final at = query.isEmpty ||
            lowerText.length != text.length ||
            lowerQuery.length != query.length
        ? -1
        : lowerText.indexOf(lowerQuery);

    if (at < 0) {
      return Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final end = at + query.length;

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, at)),
          TextSpan(text: text.substring(at, end), style: matchStyle),
          TextSpan(text: text.substring(end)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
