@TestOn('browser')
library;

// The same cases, in the browser. A Unix-Time outside what DateTime can hold
// throws a RangeError on the VM and a plain ArgumentError on the web, and CI
// runs only `@TestOn('browser')` files in Chrome, so without this the web
// behaviour - the one users run - would go untested.
import 'package:flutter_test/flutter_test.dart';

import 'unique_user_drive_entity_txs_test.dart' as cases;

void main() => cases.main();
