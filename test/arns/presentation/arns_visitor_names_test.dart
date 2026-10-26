import 'package:ardrive/arns/data/arns_name_verifier.dart';
import 'package:ardrive/arns/presentation/item/arns_item_names.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _MockConfigService extends Mock implements ConfigService {}

const _fileTx = 'FWswWiH1FMFnuzLFzpqzdgxOBlMS8L7DiP5MxUnWODE';
const _otherTx = 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0c';

/// A visitor's Activity tab: a name from the file's metadata is a hint, so
/// it is named only once the gateway confirms it (docs/NAMES.md, Q6).
void main() {
  setUp(() {
    // old_dapp now resolves somewhere else; blog_acme to the file.
    ArNSNameVerifier.session = ArNSNameVerifier(
      gatewayUrl: () => 'https://ar-io.dev',
      client: MockClient((request) async => http.Response('', 200, headers: {
            'x-arns-resolved-id':
                request.url.host.startsWith('blog_acme') ? _fileTx : _otherTx,
          })),
    );
  });

  tearDown(() => ArNSNameVerifier.session = null);

  Future<void> pump(
    WidgetTester tester, {
    required List<String> names,
    required bool isOwner,
  }) async {
    final config = _MockConfigService();
    when(() => config.config).thenReturn(AppConfig(
      stripePublishableKey: '',
      allowedDataItemSizeForTurbo: 100,
      enableArNS: true,
    ));
    await tester.pumpWidget(
      RepositoryProvider<ConfigService>.value(
        value: config,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ArNSNameActivity(
              names: names,
              dataTxIds: const {_fileTx},
              isOwner: isOwner,
              builder: (context, title) => Text(title),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  testWidgets('a visitor never sees a name the gateway does not confirm',
      (tester) async {
    await pump(tester, names: ['old_dapp'], isOwner: false);

    expect(find.textContaining('old_dapp'), findsNothing);
    expect(find.text('This file was modified.'), findsOneWidget);
  });

  testWidgets('a visitor sees a confirmed name', (tester) async {
    await pump(tester, names: ['blog_acme'], isOwner: false);

    expect(find.text('Name set to blog_acme.ar.io'), findsOneWidget);
  });

  testWidgets('the owner sees the name the revision wrote', (tester) async {
    await pump(tester, names: ['old_dapp'], isOwner: true);

    expect(find.text('Name set to old_dapp.ar.io'), findsOneWidget);
  });
}
