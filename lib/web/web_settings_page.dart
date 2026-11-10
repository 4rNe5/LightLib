// Web settings: sync, the translation language and style, Gemini (the
// only engine the web has).

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/translation/translation_model_store.dart'
    show translationTargetLanguagePref;
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/ui/components/gemini_engine_section.dart';
import 'package:openlib/ui/components/sync_section.dart';

class WebSettingsPage extends StatefulWidget {
  const WebSettingsPage({super.key});

  @override
  State<WebSettingsPage> createState() => _WebSettingsPageState();
}

class _WebSettingsPageState extends State<WebSettingsPage> {
  final _db = MyLibraryDb.instance;
  String _target = translationLanguages.first.code;
  bool _lightNovel = TranslationStyle.lightNovel;

  @override
  void initState() {
    super.initState();
    _db
        .getPreference(translationTargetLanguagePref)
        .catchError((_) => null)
        .then((value) {
      if (value is String && mounted) {
        setState(() => _target = languageForCode(value).code);
      }
    });
  }

  Future<void> _setTarget(String code) async {
    setState(() => _target = code);
    await _db
        .savePreference(translationTargetLanguagePref, code)
        .catchError((_) {});
  }

  Future<void> _setLightNovel(bool on) async {
    setState(() => _lightNovel = on);
    TranslationStyle.lightNovel = on;
    await _db
        .savePreference(translationLightNovelStylePref, on ? 1 : 0)
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SyncSection(),
              const Divider(height: 32),
              Text(l10n.translationTargetLanguage,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                key: const ValueKey('webTranslationTarget'),
                initialValue: _target,
                items: [
                  for (final language in translationLanguages)
                    DropdownMenuItem(
                        value: language.code, child: Text(language.nativeName)),
                ],
                onChanged: (code) {
                  if (code != null) _setTarget(code);
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.auto_stories_outlined),
                title: Text(l10n.translationLightNovelStyle),
                subtitle: Text(l10n.translationLightNovelStyleHint,
                    style: const TextStyle(fontSize: 12)),
                value: _lightNovel,
                onChanged: _setLightNovel,
              ),
              const SizedBox(height: 12),
              GeminiEngineSection(onEngineChanged: () {}),
            ],
          ),
        ),
      ),
    );
  }
}
