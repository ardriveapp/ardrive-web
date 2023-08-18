import 'package:ardrive/utils/data_size.dart';

// FIXME: need address size limits per browser (500 MiB for Chrome, 2 Gb for Firefox, 300 MiB for mobile)
final publicDownloadSizeLimit = const MiB(500).size;
final privateDownloadSizeLimit = const MiB(500).size;
