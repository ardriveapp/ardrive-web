import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/foundation.dart';

class ResponseObject {
  final Map<String, ARNSProcessData> data;

  ResponseObject({required this.data});

  factory ResponseObject.fromJson(Map<String, dynamic> json) {
    final processedData = <String, ARNSProcessData>{};

    for (var entry in json.entries) {
      try {
        processedData[entry.key] = ARNSProcessData.fromJson(entry.value);
      } catch (e) {
        /// Filter out the processData that throws error.
        /// It will avoid breaking the whole response object because of a single processData.
        debugPrint('Error processing ARNSProcessData: $e');
      }
    }

    return ResponseObject(data: processedData);
  }

  Map<String, dynamic> toJson() {
    return data.map((key, value) => MapEntry(key, value.toJson()));
  }
}

class ARNSProcessData {
  final ProcessState state;
  final Map<String, ARNSName> names;

  ARNSProcessData({required this.state, required this.names});

  factory ARNSProcessData.fromJson(Map<String, dynamic> json) {
    return ARNSProcessData(
      state: ProcessState.fromJson(json['state']),
      names: (json['names'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, ARNSName.fromJson(value)),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'state': state.toJson(),
      'names': names.map((key, value) => MapEntry(key, value.toJson())),
    };
  }
}

class ProcessState {
  final int totalSupply;
  final String? sourceCodeTxId;
  final Map<String, int> balances;
  final List<String> controllers;
  final Map<String, ARNSRecord> records;
  final bool initialized;
  final String ticker;
  final String logo;
  final int denomination;
  final String name;
  final String owner;

  ProcessState({
    required this.totalSupply,
    this.sourceCodeTxId,
    required this.balances,
    required this.controllers,
    required this.records,
    required this.initialized,
    required this.ticker,
    required this.logo,
    required this.denomination,
    required this.name,
    required this.owner,
  });

  factory ProcessState.fromJson(Map<String, dynamic> json) {
    return ProcessState(
      totalSupply: json['TotalSupply'],
      sourceCodeTxId: json['Source-Code-TX-ID'],
      balances: Map<String, int>.from(json['Balances']),
      controllers: List<String>.from(json['Controllers']),
      records: (json['Records'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, ARNSRecord.fromJson(value)),
      ),
      initialized: json['Initialized'],
      ticker: json['Ticker'],
      logo: json['Logo'],
      denomination: json['Denomination'],
      name: json['Name'],
      owner: json['Owner'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'TotalSupply': totalSupply,
      'Source-Code-TX-ID': sourceCodeTxId,
      'Balances': balances,
      'Controllers': controllers,
      'Records': records.map((key, value) => MapEntry(key, value.toJson())),
      'Initialized': initialized,
      'Ticker': ticker,
      'Logo': logo,
      'Denomination': denomination,
      'Name': name,
      'Owner': owner,
    };
  }
}

class ARNSName {
  final int? endTimestamp;
  final String processId;
  final int startTimestamp;
  final String type;
  final int purchasePrice;
  final int undernameLimit;

  ARNSName({
    this.endTimestamp,
    required this.processId,
    required this.startTimestamp,
    required this.type,
    required this.purchasePrice,
    required this.undernameLimit,
  });

  factory ARNSName.fromJson(Map<String, dynamic> json) {
    return ARNSName(
      endTimestamp: json['endTimestamp'],
      processId: json['processId'],
      startTimestamp: json['startTimestamp'],
      type: json['type'],
      purchasePrice: json['purchasePrice'],
      undernameLimit: json['undernameLimit'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'endTimestamp': endTimestamp,
      'processId': processId,
      'startTimestamp': startTimestamp,
      'type': type,
      'purchasePrice': purchasePrice,
      'undernameLimit': undernameLimit,
    };
  }
}
