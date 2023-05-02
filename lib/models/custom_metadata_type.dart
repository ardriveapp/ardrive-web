import 'dart:collection';

class CustomMetadata extends MapMixin<String, dynamic> {
  final Map<String, dynamic>? _data;

  CustomMetadata(Map<String, dynamic>? initialData) : _data = initialData;

  @override
  dynamic operator [](Object? key) => _data?[key];

  @override
  void operator []=(String key, dynamic value) {
    if (_data == null) {
      throw StateError('CustomMetadata is null');
    }
    _data![key] = value;
  }

  @override
  void clear() {
    _data?.clear();
  }

  @override
  Iterable<String> get keys => _data?.keys ?? [];

  @override
  dynamic remove(Object? key) => _data?.remove(key);

  // CustomMetadata fromJson function
  static CustomMetadata fromJson(Map<String, dynamic>? json) {
    return CustomMetadata(json);
  }

  // CustomMetadata toJson function
  static Map<String, dynamic>? toJson(CustomMetadata customMetadata) {
    return customMetadata._data;
  }
}
