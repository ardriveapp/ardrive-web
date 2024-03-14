import 'package:ardrive/entities/license_assertion.dart';
import 'package:ardrive/models/license.dart';
import 'package:ardrive/services/license/license_service.dart';
import 'package:ardrive/services/license/license_state.dart';
import 'package:ardrive/services/license/licenses/udl.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:drift/drift.dart';
import 'package:test/test.dart';

Tag createTag(MapEntry<String, String> entry) {
  return Tag(
    encodeStringToBase64(entry.key),
    encodeStringToBase64(entry.value),
  );
}

void main() {
  // Mock AppInfo
  final appInfo = AppInfo(
    version: '2.22.0',
    platform: 'FlutterTest',
    arfsVersion: '0.14',
    appName: 'ardrive',
  );

  const stubFileId = '00000000-0000-0000-0000-000000000000';
  const stubDriveId = 'FFFFFFFF-0000-0000-0000-000000000000';
  const stubLicenseDefinitionTxId =
      'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';
  const stubLicenseAssertionTxId =
      '0000000000000000000000000000000000000000000';
  const stubDataTxId = '0000000000000000000000000000000000000000001';
  const stubOwner = '8888';
  const stubBundledInTxId = '0000000000000000000000000000000000000000123';
  // final stubCurrentDate = DateTime.now();

  final stubLicenseParams = UdlLicenseParams(
    licenseFeeCurrency: UdlCurrency.u,
    commercialUse: UdlCommercialUse.unspecified,
    derivations: UdlDerivation.unspecified,
  );
  final stubAdditionalTags = stubLicenseParams.toAdditionalTags();
  final stubAdditionalTxTags = stubAdditionalTags.entries.map(createTag);

  final stubLicenseAssertion = LicenseAssertionEntity(
    dataTxId: stubDataTxId,
    licenseDefinitionTxId: stubLicenseDefinitionTxId,
    additionalTags: stubAdditionalTags,
  )
    ..txId = stubLicenseAssertionTxId
    ..bundledIn = stubBundledInTxId;

  group('LicenseAssertion Tests', () {
    group('asPreparedDataItem method', () {
      test('returns a DataItem with expected Tx Tag', () async {
        final dataItem = await stubLicenseAssertion.asPreparedDataItem(
            owner: stubOwner, appInfo: appInfo);

        expect(
          dataItem.tags,
          containsAll({
            'App-Name': 'License-Assertion',
            'Original': stubDataTxId,
            'License': stubLicenseDefinitionTxId,
          }.entries.map(createTag)),
        );
        expect(dataItem.tags, containsAll(stubAdditionalTxTags));
      });
    });

    group('toLicenseAssertionsCompanion method', () {
      test('returns a companion with expected fields', () async {
        final companion = stubLicenseAssertion.toCompanion(
          driveId: stubDriveId,
          fileId: stubFileId,
          licenseType: LicenseType.udl,
        );

        expect(companion.fileId, equals(const Value(stubFileId)));
        expect(companion.driveId, equals(const Value(stubDriveId)));
        expect(companion.licenseType, equals(Value(LicenseType.udl.name)));
        expect(companion.dataTxId, equals(const Value(stubDataTxId)));
        expect(companion.licenseTxType,
            equals(Value(LicenseTxType.assertion.name)));
        expect(companion.licenseTxId,
            equals(const Value(stubLicenseAssertionTxId)));
        expect(companion.bundledIn, equals(const Value(stubBundledInTxId)));
      });
    });
  });
}
