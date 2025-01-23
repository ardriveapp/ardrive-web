import 'package:ardrive/arns/presentation/assign_name_bloc/assign_name_bloc.dart';
import 'package:ario_sdk/ario_sdk.dart' as sdk;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../user/name/presentation/bloc/profile_name_bloc_test.dart';

void main() {
  late MockArDriveAuth auth;
  late MockARNSRepository arnsRepository;

  setUpAll(() {
    auth = MockArDriveAuth();
    arnsRepository = MockARNSRepository();

    registerFallbackValue(
      const sdk.ANTRecord(
        domain: 'test-domain',
        processId: 'test-process-id',
      ),
    );
  });

  group('AssignNameBloc', () {
    group('LoadNames', () {
      blocTest<AssignNameBloc, AssignNameState>(
        'emits [LoadingNames, NamesLoaded] when names are loaded successfully',
        setUp: () {
          when(() => auth.getWalletAddress())
              .thenAnswer((_) async => 'test-wallet-address');
          when(() =>
                  arnsRepository.getAntRecordsForWallet(any(), update: false))
              .thenAnswer((_) async => [
                    const sdk.ANTRecord(
                      domain: 'test.ar',
                      processId: 'process-id',
                    )
                  ]);
          when(() => arnsRepository.getARNSNameModelsForWallet(any()))
              .thenAnswer((_) async => [
                    const sdk.ArNSNameModel(
                      name: 'test.ar',
                      processId: 'process-id',
                      records: 1,
                      undernameLimit: 100,
                    )
                  ]);
        },
        build: () => AssignNameBloc(
          auth: auth,
          arnsRepository: arnsRepository,
        ),
        act: (bloc) => bloc.add(const LoadNames()),
        expect: () => [
          isA<LoadingNames>(),
          isA<NamesLoaded>().having(
            (state) => state.nameModels.first.name,
            'name',
            'test.ar',
          ),
        ],
      );

      blocTest<AssignNameBloc, AssignNameState>(
        'emits [LoadingNames, AssignNameEmptyState] when no names are found',
        setUp: () {
          when(() => auth.getWalletAddress())
              .thenAnswer((_) async => 'test-wallet-address');
          when(() =>
                  arnsRepository.getAntRecordsForWallet(any(), update: false))
              .thenAnswer((_) async => []);
          when(() => arnsRepository.getARNSNameModelsForWallet(any()))
              .thenAnswer((_) async => []);
        },
        build: () => AssignNameBloc(
          auth: auth,
          arnsRepository: arnsRepository,
        ),
        act: (bloc) => bloc.add(const LoadNames()),
        expect: () => [
          isA<LoadingNames>(),
          isA<AssignNameEmptyState>(),
        ],
      );

      blocTest<AssignNameBloc, AssignNameState>(
        'emits [LoadingNames, LoadingNamesFailed] when error occurs',
        setUp: () {
          when(() => auth.getWalletAddress())
              .thenThrow(Exception('Failed to get wallet address'));
        },
        build: () => AssignNameBloc(
          auth: auth,
          arnsRepository: arnsRepository,
        ),
        act: (bloc) => bloc.add(const LoadNames()),
        expect: () => [
          isA<LoadingNames>(),
          isA<LoadingNamesFailed>(),
        ],
      );
    });

    group('SelectName', () {
      setUp(() {
        when(() => auth.getWalletAddress())
            .thenAnswer((_) async => 'test-wallet-address');
        when(() => arnsRepository.getAntRecordsForWallet(any(), update: false))
            .thenAnswer((_) async => [
                  const sdk.ANTRecord(
                    domain: 'test.ar',
                    processId: 'process-id',
                  )
                ]);

        when(() => arnsRepository.getARNSNameModelsForWallet(any()))
            .thenAnswer((_) async => [
                  const sdk.ArNSNameModel(
                    name: 'test.ar',
                    processId: 'process-id',
                    records: 1,
                    undernameLimit: 100,
                  )
                ]);
      });
      blocTest<AssignNameBloc, AssignNameState>(
        'emits [LoadingNames, NamesLoaded] when loading names succeeds',
        build: () => AssignNameBloc(
          auth: auth,
          arnsRepository: arnsRepository,
        )..add(const LoadNames()),
        act: (bloc) async {
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(
            const SelectName(
              sdk.ArNSNameModel(
                name: 'test.ar',
                processId: 'process-id',
                records: 1,
                undernameLimit: 100,
              ),
            ),
          );
        },
        expect: () => [
          isA<LoadingNames>(),
          isA<NamesLoaded>(),
          isA<NamesLoaded>().having(
            (state) => state.selectedName?.name,
            'name',
            'test.ar',
          ),
        ],
      );

      blocTest<AssignNameBloc, AssignNameState>(
        'emits [LoadingNames, NamesLoaded, LoadingUndernames, UndernamesLoaded] when loading undernames succeeds',
        build: () => AssignNameBloc(
          auth: auth,
          arnsRepository: arnsRepository,
        )..add(const LoadNames()),
        setUp: () {
          when(() => arnsRepository.getARNSUndernames(any()))
              .thenAnswer((_) async => [
                    const sdk.ARNSUndername(
                      domain: 'test.ar',
                      name: 'test.ar',
                      record: sdk.ARNSRecord(
                        transactionId: 'transaction-id',
                        ttlSeconds: 100,
                      ),
                    )
                  ]);
        },
        act: (bloc) async {
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(
            const SelectName(
              sdk.ArNSNameModel(
                name: 'test.ar',
                processId: 'process-id',
                records: 1,
                undernameLimit: 100,
              ),
            ),
          );
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(const LoadUndernames());
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(
            const SelectName(
              sdk.ArNSNameModel(
                name: 'test.ar',
                processId: 'process-id',
                records: 1,
                undernameLimit: 100,
              ),
            ),
          );
        },
        expect: () => [
          isA<LoadingNames>(),
          isA<NamesLoaded>(),
          isA<NamesLoaded>(),
          isA<LoadingUndernames>(),
          isA<UndernamesLoaded>(),
          isA<NamesLoaded>().having(
            (state) => state.selectedName?.name,
            'name',
            'test.ar',
          ),
        ],
      );
    });
  });
}
