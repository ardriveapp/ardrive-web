import 'dart:convert';

import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/turbo_utils.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart';
import 'package:uuid/uuid.dart';

class PaymentService {
  final bool useTurboPayment = true;
  final Uri turboPaymentUri;

  ArDriveHTTP httpClient;

  PaymentService({
    required this.turboPaymentUri,
    required this.httpClient,
  });

  Future<BigInt> getPriceForBytes({
    required int byteSize,
  }) async {
    final acceptedStatusCodes = [200, 202, 204];
    final result = await httpClient.get(
      url: '$turboPaymentUri/v1/price/bytes/$byteSize',
    );
    if (!acceptedStatusCodes.contains(result.statusCode)) {
      throw Exception(
        'Turbo price fetch failed with status code ${result.statusCode}',
      );
    }
    final price = BigInt.parse((json.decode(result.data)['winc']));

    return price;
  }

  Future<BigInt> getPriceForFiat({
    required int amount,
    required String currency,
  }) async {
    final acceptedStatusCodes = [200, 202, 204];

    final result = await httpClient.get(
      url: '$turboPaymentUri/v1/price/$currency/$amount',
    );

    if (!acceptedStatusCodes.contains(result.statusCode)) {
      throw Exception(
        'Turbo price fetch failed with status code ${result.statusCode}',
      );
    }

    final price = BigInt.parse((json.decode(result.data)['winc']));

    return price;
  }

  Future<BigInt> getBalance({
    required Wallet wallet,
  }) async {
    final nonce = const Uuid().v4();
    final publicKey = await wallet.getOwner();
    final signature = await signNonceAndData(
      nonce: nonce,
      wallet: wallet,
    );
    final result = await httpClient.get(
      url: '$turboPaymentUri/v1/balance',
      headers: {
        'x-nonce': nonce,
        'x-signature': signature,
        'x-public-key': publicKey,
      },
    ).onError((ArDriveHTTPException error, stackTrace) {
      logger.e('Error getting balance', error, stackTrace);

      if (error.statusCode == 404) {
        throw TurboUserNotFound();
      }

      throw error;
    });

    final price = BigInt.parse((json.decode(result.data)['winc']));

    return price;
  }

  Future<PaymentModel> getPaymentIntent({
    required Wallet wallet,
    required int amount,
    String currency = 'usd',
  }) async {
    final nonce = const Uuid().v4();
    final walletAddress = await wallet.getAddress();
    final publicKey = await wallet.getOwner();
    final signature = await signNonceAndData(
      nonce: nonce,
      wallet: wallet,
    );

    final result = await httpClient.get(
      url:
          '$turboPaymentUri/v1/top-up/payment-intent/$walletAddress/$currency/$amount',
      headers: {
        'x-nonce': nonce,
        'x-signature': signature,
        'x-public-key': publicKey,
      },
    );

    return PaymentModel.fromJson(jsonDecode(result.data));
  }

  Future<List<String>> getSupportedCountries() async {
    // final result = await httpClient.get(
    //   url: '$turboPaymentUri/v1/countries',
    // );

    // final countries = jsonDecode(result.data) as List<dynamic>;

    await Future.delayed(Duration(seconds: 1));

    return _recognizedCountries;
  }
}

class DontUsePaymentService implements PaymentService {
  @override
  late ArDriveHTTP httpClient;

  @override
  Future<BigInt> getPriceForBytes({required int byteSize}) =>
      throw UnimplementedError();

  @override
  Future<BigInt> getBalance({required Wallet wallet}) =>
      throw UnimplementedError();

  @override
  Future<PaymentModel> getPaymentIntent({
    required Wallet wallet,
    required int amount,
    String currency = 'usd',
  }) async {
    throw UnimplementedError();
  }

  @override
  Uri get turboPaymentUri => throw UnimplementedError();

  @override
  bool get useTurboPayment => false;

  @override
  Future<BigInt> getPriceForFiat({
    required int amount,
    required String currency,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<String>> getSupportedCountries() {
    // TODO: implement getSupportedCountries
    throw UnimplementedError();
  }
}

class TurboUserNotFound implements Exception {
  TurboUserNotFound();
}

List<String> _recognizedCountries = [
  'Afghanistan',
  'Albania',
  'Algeria',
  'Andorra',
  'Angola',
  'Antigua and Barbuda',
  'Argentina',
  'Armenia',
  'Australia',
  'Austria',
  'Azerbaijan',
  'Bahamas',
  'Bahrain',
  'Bangladesh',
  'Barbados',
  'Belarus',
  'Belgium',
  'Belize',
  'Benin',
  'Bhutan',
  'Bolivia',
  'Bosnia and Herzegovina',
  'Botswana',
  'Brazil',
  'Brunei',
  'Bulgaria',
  'Burkina Faso',
  'Burundi',
  'Cabo Verde',
  'Cambodia',
  'Cameroon',
  'Canada',
  'Central African Republic',
  'Chad',
  'Chile',
  'China',
  'Colombia',
  'Comoros',
  'Congo',
  'Costa Rica',
  'Cote d\'Ivoire',
  'Croatia',
  'Cyprus',
  'Czech Republic',
  'Democratic Republic of the Congo',
  'Denmark',
  'Djibouti',
  'Dominica',
  'Dominican Republic',
  'East Timor',
  'Ecuador',
  'Egypt',
  'El Salvador',
  'Equatorial Guinea',
  'Eritrea',
  'Estonia',
  'Eswatini',
  'Ethiopia',
  'Fiji',
  'Finland',
  'France',
  'Gabon',
  'Gambia',
  'Georgia',
  'Germany',
  'Ghana',
  'Greece',
  'Grenada',
  'Guatemala',
  'Guinea',
  'Guinea-Bissau',
  'Guyana',
  'Haiti',
  'Honduras',
  'Hungary',
  'Iceland',
  'India',
  'Indonesia',
  'Iraq',
  'Ireland',
  'Israel',
  'Italy',
  'Jamaica',
  'Japan',
  'Jordan',
  'Kazakhstan',
  'Kenya',
  'Kiribati',
  'Kuwait',
  'Kyrgyzstan',
  'Laos',
  'Latvia',
  'Lebanon',
  'Lesotho',
  'Liberia',
  'Libya',
  'Liechtenstein',
  'Lithuania',
  'Luxembourg',
  'Madagascar',
  'Malawi',
  'Malaysia',
  'Maldives',
  'Mali',
  'Malta',
  'Marshall Islands',
  'Mauritania',
  'Mauritius',
  'Mexico',
  'Micronesia',
  'Moldova',
  'Monaco',
  'Mongolia',
  'Montenegro',
  'Morocco',
  'Mozambique',
  'Myanmar',
  'Namibia',
  'Nauru',
  'Nepal',
  'Netherlands',
  'New Zealand',
  'Nicaragua',
  'Niger',
  'Nigeria',
  'North Macedonia',
  'Norway',
  'Oman',
  'Pakistan',
  'Palau',
  'Palestine',
  'Panama',
  'Papua New Guinea',
  'Paraguay',
  'Peru',
  'Philippines',
  'Poland',
  'Portugal',
  'Qatar',
  'Romania',
  'Russia',
  'Rwanda',
  'Saint Kitts and Nevis',
  'Saint Lucia',
  'Saint Vincent and the Grenadines',
  'Samoa',
  'San Marino',
  'Sao Tome and Principe',
  'Saudi Arabia',
  'Senegal',
  'Serbia',
  'Seychelles',
  'Sierra Leone',
  'Singapore',
  'Slovakia',
  'Slovenia',
  'Solomon Islands',
  'Somalia',
  'South Africa',
  'South Korea',
  'South Sudan',
  'Spain',
  'Sri Lanka',
  'Sudan',
  'Suriname',
  'Sweden',
  'Switzerland',
  'Taiwan',
  'Tajikistan',
  'Tanzania',
  'Thailand',
  'Togo',
  'Tonga',
  'Trinidad and Tobago',
  'Tunisia',
  'Turkey',
  'Turkmenistan',
  'Tuvalu',
  'Uganda',
  'Ukraine',
  'United Arab Emirates',
  'United Kingdom',
  'United States',
  'Uruguay',
  'Uzbekistan',
  'Vanuatu',
  'Vatican City',
  'Venezuela',
  'Vietnam',
  'Yemen',
  'Zambia',
  'Zimbabwe',
];
