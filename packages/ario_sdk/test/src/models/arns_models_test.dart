import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArNSNameData.fromJson', () {
    test('reads a lease with its end', () {
      final name = ArNSNameData.fromJson({
        'name': 'forever-loved',
        'processId': 'EH9PsyfwJBk9KLMpZ2C5nUjWQfXsNTHaUzTqFa4BpbQj',
        'type': 'lease',
        'startTimestamp': 1762985225000,
        'endTimestamp': 1794521225000,
        'undernameLimit': 110,
      });

      expect(name.type, ArNSNameType.lease);
      expect(name.endTimestamp, 1794521225000);
      expect(name.undernameLimit, 110);
    });

    test('reads a permanent name without an end', () {
      final name = ArNSNameData.fromJson({
        'name': 'turbo',
        'processId': 'CBsEKdomKa9nwF4fMiV5iFerfQPT73Et2ZKWpdCLHHsv',
        'type': 'permabuy',
        'startTimestamp': 1740009600000,
        'endTimestamp': null,
        'undernameLimit': 100,
      });

      expect(name.type, ArNSNameType.permabuy);
      expect(name.endTimestamp, isNull);
    });
  });

  test('ANTSummary.fromJson reads owner, controllers and apex record', () {
    final summary = ANTSummary.fromJson({
      'processId': 'ant',
      'name': 'ArDrive',
      'ticker': 'ANT',
      'owner': 'owner',
      'controllers': ['c1', 'c2'],
      'apexRecord': {
        'undername': '@',
        'transactionId': 'tx',
        'ttlSeconds': 3600,
      },
    });

    expect(summary.owner, 'owner');
    expect(summary.controllers, ['c1', 'c2']);
    expect(summary.apexRecord!.undername, '@');
    expect(
      summary.apexRecord!.record,
      const ARNSRecord(transactionId: 'tx', ttlSeconds: 3600),
    );
  });

  test('the default cache time is 5 minutes', () {
    expect(ARNSRecord.defaultTtlSeconds, 300);
  });
}
