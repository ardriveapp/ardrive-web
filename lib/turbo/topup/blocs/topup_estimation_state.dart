part of 'topup_estimation_bloc.dart';

abstract class TopupEstimationState extends Equatable {
  const TopupEstimationState();
}

class TopupEstimationInitial extends TopupEstimationState {
  @override
  List<Object?> get props => [];
}

class EstimationInitial extends TopupEstimationState {
  @override
  List<Object?> get props => [];
}

class EstimationLoading extends TopupEstimationState {
  @override
  List<Object?> get props => [];
}

class EstimationLoaded extends TopupEstimationState {
  final BigInt balance;
  final String estimatedStorageForBalance;
  final int selectedAmount;
  final BigInt creditsForSelectedAmount;
  final String estimatedStorageForSelectedAmount;
  final String currencyUnit;
  final FileSizeUnit dataUnit;

  const EstimationLoaded({
    required this.balance,
    required this.estimatedStorageForBalance,
    required this.selectedAmount,
    required this.creditsForSelectedAmount,
    required this.estimatedStorageForSelectedAmount,
    required this.currencyUnit,
    required this.dataUnit,
  });

  @override
  List<Object?> get props => [
        balance,
        estimatedStorageForBalance,
        selectedAmount,
        creditsForSelectedAmount,
        estimatedStorageForSelectedAmount,
        currencyUnit,
        dataUnit,
      ];
}

class FetchEstimationError extends TopupEstimationState {
  @override
  List<Object?> get props => [];
}

class EstimationLoadError extends TopupEstimationState {
  @override
  List<Object?> get props => [];
}
