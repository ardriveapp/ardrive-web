// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

String? readLibraryMetaContent() => html.document
    .querySelector('meta[name="ardrive-library"]')
    ?.getAttribute('content');
