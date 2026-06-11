// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppConfig _$AppConfigFromJson(Map<String, dynamic> json) => AppConfig(
      arweaveGatewayUrl: json['defaultArweaveGatewayUrl'] as String?,
      arweaveGatewayForDataRequest:
          json['defaultArweaveGatewayForDataRequest'] == null
              ? const SelectedGateway(
                  label: 'ArDrive Turbo Gateway', url: 'https://ardrive.net')
              : SelectedGateway.fromJson(
                  json['defaultArweaveGatewayForDataRequest']
                      as Map<String, dynamic>),
      useTurboUpload: json['useTurboUpload'] as bool? ?? false,
      useTurboPayment: json['useTurboPayment'] as bool? ?? false,
      defaultTurboUploadUrl: json['defaultTurboUploadUrl'] as String?,
      defaultTurboPaymentUrl: json['defaultTurboPaymentUrl'] as String?,
      allowedDataItemSizeForTurbo: json['allowedDataItemSizeForTurbo'] as int,
      autoSyncIntervalInSeconds:
          json['autoSyncIntervalInSeconds'] as int? ?? 5 * 60,
      enableSyncFromSnapshot: json['enableSyncFromSnapshot'] as bool? ?? true,
      stripePublishableKey: json['stripePublishableKey'] as String,
      autoSync: json['autoSync'] as bool? ?? true,
      uploadThumbnails: json['uploadThumbnails'] as bool? ?? true,
      configVersion: json['configVersion'] as int?,
      solanaRpcUrl: json['solanaRpcUrl'] as String?,
      solanaCoreProgramId: json['solanaCoreProgramId'] as String?,
      solanaGarProgramId: json['solanaGarProgramId'] as String?,
      solanaArnsProgramId: json['solanaArnsProgramId'] as String?,
      solanaAntProgramId: json['solanaAntProgramId'] as String?,
    );

Map<String, dynamic> _$AppConfigToJson(AppConfig instance) => <String, dynamic>{
      'defaultArweaveGatewayUrl': instance.arweaveGatewayUrl,
      'defaultArweaveGatewayForDataRequest':
          instance.arweaveGatewayForDataRequest,
      'useTurboUpload': instance.useTurboUpload,
      'useTurboPayment': instance.useTurboPayment,
      'defaultTurboUploadUrl': instance.defaultTurboUploadUrl,
      'defaultTurboPaymentUrl': instance.defaultTurboPaymentUrl,
      'allowedDataItemSizeForTurbo': instance.allowedDataItemSizeForTurbo,
      'autoSyncIntervalInSeconds': instance.autoSyncIntervalInSeconds,
      'enableSyncFromSnapshot': instance.enableSyncFromSnapshot,
      'stripePublishableKey': instance.stripePublishableKey,
      'autoSync': instance.autoSync,
      'uploadThumbnails': instance.uploadThumbnails,
      'configVersion': instance.configVersion,
      'solanaRpcUrl': instance.solanaRpcUrl,
      'solanaCoreProgramId': instance.solanaCoreProgramId,
      'solanaGarProgramId': instance.solanaGarProgramId,
      'solanaArnsProgramId': instance.solanaArnsProgramId,
      'solanaAntProgramId': instance.solanaAntProgramId,
    };
