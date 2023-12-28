import 'package:ardrive/entities/license_assertion.dart';
import 'package:ardrive/models/license_assertion.dart';
import 'package:ardrive/services/license/license_types.dart';
import 'package:ardrive/services/license/licenses/udl.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:drift/drift.dart';
import 'package:test/test.dart';

void main() {
  const stubFileId = '00000000-0000-0000-0000-000000000000';
  const stubDriveId = 'FFFFFFFF-0000-0000-0000-000000000000';
  const stubLicenseAssertionTxId =
      '0000000000000000000000000000000000000000000';
  const stubDataTxId = '0000000000000000000000000000000000000000001';
  const stubLicenseTxId = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';
  const stubOwner = '8888';
  // final stubCurrentDate = DateTime.now();

  final stubLicenseParams = UdlLicenseParams(
    licenseFeeCurrency: UdlCurrency.u,
    commercialUse: UdlCommercialUse.unspecified,
    derivations: UdlDerivation.unspecified,
  );
  final stubAdditionalTags = stubLicenseParams.toAdditionalTags();
  final stubAdditionalTxTags = stubAdditionalTags.entries.map(
    (entry) => Tag(
      encodeStringToBase64(entry.key),
      encodeStringToBase64(entry.value),
    ),
  );

  final stubLicenseAssertion = LicenseAssertionEntity(
    dataTxId: stubDataTxId,
    licenseTxId: stubLicenseTxId,
    additionalTags: stubAdditionalTags,
  )..txId = stubLicenseAssertionTxId;

  group('LicenseAssertion Tests', () {
    group('asPreparedDataItem method', () {
      test('returns a DataItem with expected Tx Tag', () async {
        final dataItem =
            await stubLicenseAssertion.asPreparedDataItem(owner: stubOwner);

        expect(dataItem.tags, containsAll(stubAdditionalTxTags));
      });
    });

    group('toLicenseAssertionsCompanion method', () {
      test('returns a companion with expected fields', () async {
        final companion = stubLicenseAssertion.toLicenseAssertionsCompanion(
          driveId: stubDriveId,
          fileId: stubFileId,
          licenseType: LicenseType.udl,
        );

        expect(companion.fileId, equals(const Value(stubFileId)));
        expect(companion.driveId, equals(const Value(stubDriveId)));
        expect(companion.licenseType, equals(Value(LicenseType.udl.name)));
        expect(companion.dataTxId, equals(const Value(stubDataTxId)));
        expect(companion.licenseAssertionTxId,
            equals(const Value(stubLicenseAssertionTxId)));
        expect(companion.bundledIn, equals(const Value.absent()));
      });
    });
  });
}
