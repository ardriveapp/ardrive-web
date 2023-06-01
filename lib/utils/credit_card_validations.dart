import 'package:credit_card_validator/credit_card_validator.dart';

import 'logger/logger.dart';

bool validateCreditCardNumber(String ccNum) {
  CreditCardValidator ccValidator = CreditCardValidator();

  var ccNumResults = ccValidator.validateCCNum(ccNum);

  logger.d('ccNumResults: ${ccNumResults.isValid}');

  return ccNumResults.isValid;
}

bool validateCreditCardExpiryDate(String expiryDate) {
  CreditCardValidator ccValidator = CreditCardValidator();

  var ccExpResults = ccValidator.validateExpDate(expiryDate);

  logger.d('ccExpResults: ${ccExpResults.isValid}');

  return ccExpResults.isValid;
}

bool validateCreditCardCVC(String cvc, String ccNum) {
  CreditCardValidator ccValidator = CreditCardValidator();

  final creditType = ccValidator.validateCCNum(ccNum).ccType;

  var ccCVCResults = ccValidator.validateCVV(cvc, creditType);

  logger.d('ccCVCResults: ${ccCVCResults.isValid}');

  return ccCVCResults.isValid;
}
