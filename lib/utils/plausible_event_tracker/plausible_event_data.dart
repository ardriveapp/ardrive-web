class PlausibleEventData {
  final String name;
  final Uri url;
  String? referrer;
  Map<String, dynamic>? props;

  PlausibleEventData({
    required this.name,
    required this.url,
    this.referrer,
    this.props,
  });
}
