# Ario SDK for Dart

This SDK facilitates interaction with the Ario network by providing Dart APIs for retrieving gateways and IO token balances. Currently, it supports web platforms only.

## Table of Contents

- [Ario SDK for Dart](#ario-sdk-for-dart)
  - [Table of Contents](#table-of-contents)
  - [Installation](#installation)
  - [Getting Started](#getting-started)
  - [Usage](#usage)
    - [Creating an Instance](#creating-an-instance)
    - [Fetching Gateways](#fetching-gateways)
    - [Fetching IO Token Balance](#fetching-io-token-balance)
    - [Fetching Primary Name](#fetching-primary-name)
  - [Models](#models)
  - [Platform Support](#platform-support)

## Installation

Add the `ario_sdk` package to your `pubspec.yaml`:

```yaml
dependencies:
  ario_sdk: ^1.0.0
```

Then, run the following command:

```bash
flutter pub get
```

## Getting Started

To use the Ario SDK, first, import the package:

```dart
import 'package:ario_sdk/ario_sdk.dart';
```

The SDK can be used only on web platforms. Attempting to use it on other platforms will result in an `UnsupportedError`.

## Usage

### Creating an Instance

Use the `ArioSDKFactory` to create an instance of the SDK:

```dart
final arioSDK = ArioSDKFactory().create();
```

### Fetching Gateways

Retrieve the list of available gateways:

```dart
Future<void> fetchGateways() async {
  final gateways = await arioSDK.getGateways();
  print('Gateways: $gateways');
}
```

### Fetching IO Token Balance

Fetch the IO token balance for a specific address:

```dart
Future<void> fetchIOTokens(String address) async {
  final balance = await arioSDK.getIOTokens(address);
  print('IO Token Balance: $balance');
}
```

### Fetching Primary Name

Fetch the primary name for a specific wallet address:

```dart
Future<void> fetchPrimaryName(String address) async {
  final primaryName = await arioSDK.getPrimaryName(address);
  print('Primary Name: $primaryName');
}
```

Throws a [PrimaryNameNotFoundException] if the primary name is not found.

## Models

The SDK include the Gateway model that represent the data structures used by the Ario network:

- `Gateway`: Represents a gateway in the Ario network.

These models are JSON-serializable, making it easy to work with network responses.

## Platform Support

The Ario SDK currently supports only web platforms. It will throw an `UnsupportedError` if used on other platforms.

To check if the platform is supported, you can use:

```dart
bool isSupported = isArioSDKSupportedOnPlatform();
if (isSupported) {
  // Proceed with using the SDK
} else {
  // Handle unsupported platform
}
```
