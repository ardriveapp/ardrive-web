import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

ArNSManagedName _name(String name, int undernames) => ArNSManagedName(
      name: name,
      processId: 'ant-$name',
      role: ArNSRole.owner,
      type: ArNSNameType.permabuy,
      endTimestamp: null,
      undernameLimit: 100,
      records: [
        ArNSNameRecord(
          name: name,
          undername: '@',
          transactionId: 'tx',
          ttlSeconds: 3600,
        ),
        for (var i = 1; i <= undernames; i++)
          ArNSNameRecord(
            name: name,
            undername: 'page-$i',
            transactionId: 'tx',
            ttlSeconds: 3600,
          ),
      ],
    );

List<String> _undernames(ArNSPickerGroup group) =>
    [for (final r in group.undernames) r.undername];

void main() {
  final names = [_name('studio', 12), _name('acme', 2)];

  group('arnsPickerGroups', () {
    test('with no query, a long name lists its first few and hides the rest',
        () {
      final groups = arnsPickerGroups(names, query: '', expanded: {});
      expect(groups, hasLength(2));
      expect(groups[0].undernames, hasLength(arnsPickerUndernamesShown));
      expect(groups[0].hidden, 12 - arnsPickerUndernamesShown);
      expect(groups[1].undernames, hasLength(2));
      expect(groups[1].hidden, 0);
    });

    test('an expanded name lists all its undernames', () {
      final groups = arnsPickerGroups(names, query: '', expanded: {'studio'});
      expect(groups[0].undernames, hasLength(12));
      expect(groups[0].hidden, 0);
    });

    test('the chosen undername stays listed when collapsed', () {
      final groups = arnsPickerGroups(
        names,
        query: '',
        expanded: {},
        choice: const ArNSRecordChoice(name: 'studio', undername: 'page-11'),
      );
      expect(_undernames(groups[0]), contains('page-11'));
      expect(groups[0].hidden, 12 - arnsPickerUndernamesShown - 1);
    });

    test('a query keeps only matching undernames, across names', () {
      final groups = arnsPickerGroups(names, query: 'page-1', expanded: {});
      expect(groups, hasLength(2));
      expect(
          _undernames(groups[0]), ['page-1', 'page-10', 'page-11', 'page-12']);
      expect(_undernames(groups[1]), ['page-1']);
    });

    test('a name with no matching undername is left out', () {
      final groups = arnsPickerGroups(names, query: 'page-12', expanded: {});
      expect(groups, hasLength(1));
      expect(groups[0].name.name, 'studio');
    });

    test('a query matching a name keeps all of it', () {
      final groups = arnsPickerGroups(names, query: 'acme', expanded: {});
      expect(groups, hasLength(1));
      expect(_undernames(groups[0]), ['page-1', 'page-2']);
    });

    test('a query matching nothing lists nothing', () {
      expect(arnsPickerGroups(names, query: 'zzz', expanded: {}), isEmpty);
    });
  });

  test('renew opens the name in the console', () {
    expect(arnsRenewUrlFor('studio'), 'https://console.ar.io/domains/studio');
  });
}
