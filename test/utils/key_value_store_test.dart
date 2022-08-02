import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  group('LocalKeyValueStore class', () {
    late KeyValueStore store;

    setUp(() async {
      Map<String, Object> values = <String, Object>{
        'isItTrue': false,
        'aStringValue': 'IM THE STRING!',
      };
      SharedPreferences.setMockInitialValues(values);
      final fakePrefs = await SharedPreferences.getInstance();
      store = await LocalKeyValueStore.getInstance(prefs: fakePrefs);
    });

    group('putBool method', () {
      test('replaces the previous value', () async {
        var currentValue = store.getBool('isItTrue');
        expect(currentValue, false);
        await store.putBool('isItTrue', true);
        currentValue = store.getBool('isItTrue');
        expect(currentValue, true);
      });
    });

    group('putString method', () {
      test('replaces the previous value', () async {
        var currentValue = store.getString('aStringValue');
        expect(currentValue, 'IM THE STRING!');
        await store.putString('aStringValue', 'DIFFERENT STRING!');
        currentValue = store.getString('aStringValue');
        expect(currentValue, 'DIFFERENT STRING!');
      });
    });

    group('remove method', () {
      test(
        'returns true when sucessfully removed and the value turns null',
        () async {
          final successBoolean = await store.remove('isItTrue');
          final successString = await store.remove('aStringValue');
          expect(successBoolean, true);
          expect(successString, true);
          var currentBoolValue = store.getBool('isItTrue');
          var currentStringValue = store.getBool('aStringValue');
          expect(currentBoolValue, null);
          expect(currentStringValue, null);
        },
      );
    });

    group('getBool method', () {
      test('returns null if the key is not present', () async {
        var currentValue = store.getBool('isItTrue');
        expect(currentValue, null);
      });
    });

    group('getString method', () {
      test('returns null if the key is not present', () async {
        var currentValue = store.getString('aStringValue');
        expect(currentValue, null);
      });
    });
  });
}
