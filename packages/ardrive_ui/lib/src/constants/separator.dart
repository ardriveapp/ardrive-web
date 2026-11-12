/// The dot between the facts of a line: "3 files • 2.43 MiB".
///
/// Not U+00B7 (the middle dot). Wavehaus draws that glyph on the baseline, 170
/// units tall, so in the app's type it reads as a full stop; the bullet sits
/// at mid-height. Text that holds a middle dot (a localized string, say) goes
/// through [withSeparatorDots].
const String arDriveSeparator = '•';

/// [text] with each middle dot replaced by [arDriveSeparator].
String withSeparatorDots(String text) => text.replaceAll('·', arDriveSeparator);
