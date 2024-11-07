import 'package:ardrive/models/database/database.dart';
import 'package:drift/web.dart';

Database getIntegrationTestDatabase() {
  return Database(WebDatabase('integration_test'));
}
//
