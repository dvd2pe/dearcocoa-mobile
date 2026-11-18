import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dearcocoa/data/services/local_server_service.dart';
import 'package:dearcocoa/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  test('OAuth missing-code page uses unknownError', () {
    expect(oauthMissingCodePage(), UserStorage.l10n.unknownError);
  });
}
