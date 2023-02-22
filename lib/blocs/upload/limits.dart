import 'package:ardrive/utils/data_size.dart';

const privateFileSizeLimit = 104857600;
const publicFileSizeLimit =
    1288490189 * 100; // TODO: Decide a sane limit for stream transctions
const mobilePrivateFileSizeLimit = 1073741823;
// 5GiB
final publicFileSafeSizeLimit = const GiB(5).size;
