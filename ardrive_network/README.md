# ArdriveNetwork

Custom ArDrive library to perform network calls for ArDrive Web. It uses Isolates to perform network calls on Dart VM environments and WebWorkers on Web.

### Features

- Standarize network calls
- Support retries
- Use Isolates and WebWorkers to reduce impact on UI process

### Implemented methods

- get()
- getJson()
- getAsBytes()

## Getting started

In order to use this package you need to copy `ardrive-network.js` and `workers.js` to `web` folder so they can be dynamic imported when `ArDriveNetwork` method is called.

## Usage

Simply create a new instance of `ArdriveNetwork` and pass the follow optional params:

- `retries`: amount of retry attempts
- `retryDelayMs`: base retry delay in ms
- `noLogs`: to hide logs

```dart
// Using defaults
final arDriveNetwork = ArdriveNetwork()

// Setting params
// Retry 4 times
// Initial delay of 100ms
// Don't log requests
final arDriveNetwork = ArdriveNetwork(
  retries: 4,
  retryDelayMs: 100,
  noLog: true,
);
```

Call the intended method like:

```dart
// Get raw response
final response = await ArdriveNetwork().get(url: 'https://url');

// Get JSON response
final jsonResponse = await ArdriveNetwork().get(
  url: 'https://url',
  isJson: true,
);
// OR
final getJsonResponse = await ArdriveNetwork().getJson('https://url');

// Get bytes
final bytesResponse = await ArdriveNetwork().get(
  url: 'https://url',
  asBytes: true,
);
// OR
final getBytesResponse = await ArdriveNetwork().getAsBytes('https://url');
```
