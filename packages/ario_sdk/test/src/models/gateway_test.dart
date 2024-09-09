import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Gateway Model Tests', () {
    test('Gateway serialization and deserialization', () {
      final gateway = Gateway(
        operatorStake: 1000,
        gatewayAddress: 'gatewayAddress',
        observerAddress: 'observerAddress',
        settings: Settings(
          port: 8080,
          protocol: 'https',
          allowDelegatedStaking: true,
          fqdn: 'example.com',
          delegateRewardShareRatio: 50,
          properties: 'some properties',
          note: 'some note',
          minDelegatedStake: 500,
          label: 'test label',
          autoStake: false,
        ),
        startTimestamp: 1622519735,
        endTimestamp: 1622529735,
        totalDelegatedStake: 2000,
        stats: Stats(
          failedConsecutiveEpochs: 1,
          observedEpochCount: 10,
          passedConsecutiveEpochs: 5,
          totalEpochCount: 20,
          prescribedEpochCount: 15,
          passedEpochCount: 15,
          failedEpochCount: 5,
        ),
        status: 'active',
      );

      final json = gateway.toJson();
      final deserializedGateway = Gateway.fromJson(json);

      expect(deserializedGateway.operatorStake, gateway.operatorStake);
      expect(deserializedGateway.gatewayAddress, gateway.gatewayAddress);
      expect(deserializedGateway.observerAddress, gateway.observerAddress);
      expect(deserializedGateway.settings.toJson(), gateway.settings.toJson());
      expect(deserializedGateway.startTimestamp, gateway.startTimestamp);
      expect(deserializedGateway.endTimestamp, gateway.endTimestamp);
      expect(
          deserializedGateway.totalDelegatedStake, gateway.totalDelegatedStake);
      expect(deserializedGateway.stats.toJson(), gateway.stats.toJson());
      expect(deserializedGateway.status, gateway.status);
    });

    test('Vault serialization and deserialization', () {
      final vault = Vault(
        balance: 1000,
        startTimestamp: 1622519735,
        endTimestamp: 1622529735,
      );

      final json = vault.toJson();
      final deserializedVault = Vault.fromJson(json);

      expect(deserializedVault.balance, vault.balance);
      expect(deserializedVault.startTimestamp, vault.startTimestamp);
      expect(deserializedVault.endTimestamp, vault.endTimestamp);
    });

    test('Settings serialization and deserialization', () {
      final settings = Settings(
        port: 8080,
        protocol: 'https',
        allowDelegatedStaking: true,
        fqdn: 'example.com',
        delegateRewardShareRatio: 50,
        properties: 'some properties',
        note: 'some note',
        minDelegatedStake: 500,
        label: 'test label',
        autoStake: false,
      );

      final json = settings.toJson();
      final deserializedSettings = Settings.fromJson(json);

      expect(deserializedSettings.port, settings.port);
      expect(deserializedSettings.protocol, settings.protocol);
      expect(deserializedSettings.allowDelegatedStaking,
          settings.allowDelegatedStaking);
      expect(deserializedSettings.fqdn, settings.fqdn);
      expect(deserializedSettings.delegateRewardShareRatio,
          settings.delegateRewardShareRatio);
      expect(deserializedSettings.properties, settings.properties);
      expect(deserializedSettings.note, settings.note);
      expect(
          deserializedSettings.minDelegatedStake, settings.minDelegatedStake);
      expect(deserializedSettings.label, settings.label);
      expect(deserializedSettings.autoStake, settings.autoStake);
    });

    test('Stats serialization and deserialization', () {
      final stats = Stats(
        failedConsecutiveEpochs: 1,
        observedEpochCount: 10,
        passedConsecutiveEpochs: 5,
        totalEpochCount: 20,
        prescribedEpochCount: 15,
        passedEpochCount: 15,
        failedEpochCount: 5,
      );

      final json = stats.toJson();
      final deserializedStats = Stats.fromJson(json);

      expect(deserializedStats.failedConsecutiveEpochs,
          stats.failedConsecutiveEpochs);
      expect(deserializedStats.observedEpochCount, stats.observedEpochCount);
      expect(deserializedStats.passedConsecutiveEpochs,
          stats.passedConsecutiveEpochs);
      expect(deserializedStats.totalEpochCount, stats.totalEpochCount);
      expect(
          deserializedStats.prescribedEpochCount, stats.prescribedEpochCount);
      expect(deserializedStats.passedEpochCount, stats.passedEpochCount);
      expect(deserializedStats.failedEpochCount, stats.failedEpochCount);
    });

    test('Delegate serialization and deserialization', () {
      final vault1 = Vault(
        balance: 1000,
        startTimestamp: 1622519735,
        endTimestamp: 1622529735,
      );

      final vault2 = Vault(
        balance: 1500,
        startTimestamp: 1622539735,
        endTimestamp: 1622549735,
      );

      final delegate = Delegate(
        vaults: [vault1, vault2],
        delegatedStake: 2000,
        startTimestamp: 1622519735,
      );

      final json = delegate.toJson();
      final deserializedDelegate = Delegate.fromJson(json);

      expect(deserializedDelegate.delegatedStake, delegate.delegatedStake);
      expect(deserializedDelegate.startTimestamp, delegate.startTimestamp);
      expect(deserializedDelegate.vaults.length, delegate.vaults.length);
      expect(
          deserializedDelegate.vaults[0].toJson(), delegate.vaults[0].toJson());
      expect(
          deserializedDelegate.vaults[1].toJson(), delegate.vaults[1].toJson());
    });
  });
}
