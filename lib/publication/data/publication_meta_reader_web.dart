// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

String? readPublicationMetaContent() => html.document
    .querySelector('meta[name="ardrive-publication"]')
    ?.getAttribute('content');

String? readPageTitle() => html.document.title;
