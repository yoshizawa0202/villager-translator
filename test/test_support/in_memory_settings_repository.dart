import 'dart:io';

import 'package:villager_translator/domain/settings/app_settings.dart';
import 'package:villager_translator/infrastructure/settings/settings_repository.dart';

class InMemorySettingsRepository extends SettingsRepository {
  InMemorySettingsRepository({AppSettings? initialSettings})
    : _settings = initialSettings ?? AppSettings.defaults(),
      super(File('in_memory_settings_repository.json'));

  AppSettings _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
  }
}