import 'package:flutter_test/flutter_test.dart';
import 'package:dearcocoa/config/app_config.dart';
import 'package:dearcocoa/config/app_flavor.dart';
import 'package:dearcocoa/domain/models/llm_config.dart';

void main() {
  group('AppConfig.availableProviders', () {
    test('includes DeepSeek in global flavor', () {
      AppFlavor.init('global');

      expect(AppConfig.availableProviders, contains(LLMConfig.typeDeepSeek));
    });

    test('excludes Memex proxy service from manual providers', () {
      AppFlavor.init('global');

      expect(
          AppConfig.availableProviders, isNot(contains(LLMConfig.typeMemex)));
      expect(AppConfig.enableMemexModelService, isTrue);
    });

    test('includes DeepSeek in CN flavor', () {
      AppFlavor.init('cn');

      expect(AppConfig.availableProviders, contains(LLMConfig.typeDeepSeek));
    });
  });
}
