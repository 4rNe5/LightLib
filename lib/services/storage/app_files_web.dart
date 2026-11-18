// Web: AppFiles in the browser's IndexedDB.

// Package imports:
import 'package:idb_shim/idb_browser.dart';

// Project imports:
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/storage/idb_app_files.dart';

AppFiles createAppFiles() => IdbAppFiles(idbFactoryBrowser);
