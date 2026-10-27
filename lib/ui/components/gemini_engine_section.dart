// Settings: which engine translates (the phone or Gemini), Gemini's key,
// model, safety filters, what happens when it cannot translate, and
// today's use against the limits the API reported.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/translation/gemini/gemini_api.dart';
import 'package:openlib/services/translation/gemini/gemini_client.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';

class GeminiEngineSection extends StatefulWidget {
  const GeminiEngineSection({super.key, required this.onEngineChanged});

  /// The engine, the key or the model changed: translation starts over
  /// with them.
  final VoidCallback onEngineChanged;

  @override
  State<GeminiEngineSection> createState() => _GeminiEngineSectionState();
}

enum _Test { none, running, ok, badKey, failed }

class _GeminiEngineSectionState extends State<GeminiEngineSection> {
  final _settings = GeminiSettings.instance;
  final _keyField = TextEditingController();
  _Test _test = _Test.none;
  String _testError = '';

  @override
  void initState() {
    super.initState();
    _settings.load();
  }

  @override
  void dispose() {
    _keyField.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final key = _keyField.text.trim().isNotEmpty
        ? _keyField.text.trim()
        : _settings.apiKey;
    if (key.isEmpty) return;
    setState(() => _test = _Test.running);
    try {
      await GeminiClient.shared.test(apiKey: key);
      await _settings.setKey(key);
      _keyField.clear();
      if (mounted) setState(() => _test = _Test.ok);
      widget.onEngineChanged();
    } on GeminiError catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.kind == GeminiErrorKind.badKey) {
          _test = _Test.badKey;
        } else if (e.kind == GeminiErrorKind.quotaExhausted ||
            e.kind == GeminiErrorKind.rateLimited) {
          // The key works; only today's quota is gone.
          _test = _Test.ok;
          _settings.setKey(key);
        } else {
          _test = _Test.failed;
          _testError = e.message;
        }
      });
    }
  }

  String _blockLabel(AppLocalizations l10n, GeminiBlock b) => switch (b) {
        GeminiBlock.off => l10n.geminiBlockOff,
        GeminiBlock.onlyHigh => l10n.geminiBlockOnlyHigh,
        GeminiBlock.mediumAndAbove => l10n.geminiBlockMedium,
        GeminiBlock.lowAndAbove => l10n.geminiBlockLow,
      };

  String _harmLabel(AppLocalizations l10n, GeminiHarm h) => switch (h) {
        GeminiHarm.harassment => l10n.geminiHarmHarassment,
        GeminiHarm.hate => l10n.geminiHarmHate,
        GeminiHarm.sexual => l10n.geminiHarmSexual,
        GeminiHarm.dangerous => l10n.geminiHarmDangerous,
      };

  static String _tokens(int n) => n >= 1000000
      ? '${(n / 1e6).toStringAsFixed(2)}M'
      : n >= 1000
          ? '${(n / 1000).toStringAsFixed(1)}K'
          : '$n';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        final gemini = _settings.useGemini;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.translationEngine, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              key: const ValueKey('translationEngine'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.smartphone_outlined),
                    label: Text(l10n.translationEngineDevice)),
                ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.cloud_outlined),
                    label: Text(l10n.translationEngineGemini)),
              ],
              selected: {gemini},
              onSelectionChanged: (v) async {
                await _settings.setUseGemini(v.first);
                widget.onEngineChanged();
              },
            ),
            if (gemini) ...[
              const SizedBox(height: 6),
              Text(l10n.translationEngineGeminiHint, style: small),
              const SizedBox(height: 12),
              _keyInput(l10n, small),
              const SizedBox(height: 12),
              _modelPicker(l10n, small),
              const SizedBox(height: 12),
              if (_settings.hasKey) _usageCard(l10n, theme, small),
              const SizedBox(height: 12),
              Text(l10n.geminiSafety, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(l10n.geminiSafetyHint, style: small),
              for (final h in GeminiHarm.values)
                Row(
                  children: [
                    Expanded(child: Text(_harmLabel(l10n, h))),
                    DropdownButton<GeminiBlock>(
                      key: ValueKey('geminiSafety-${h.name}'),
                      value: _settings.safety[h],
                      items: [
                        for (final b in GeminiBlock.values)
                          DropdownMenuItem(
                              value: b, child: Text(_blockLabel(l10n, b))),
                      ],
                      onChanged: (b) {
                        if (b != null) _settings.setSafety(h, b);
                      },
                    ),
                  ],
                ),
              SwitchListTile(
                key: const ValueKey('geminiDeviceFallback'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.geminiDeviceFallback),
                subtitle: Text(l10n.geminiDeviceFallbackHint,
                    style: const TextStyle(fontSize: 12)),
                value: _settings.deviceFallback,
                onChanged: _settings.setDeviceFallback,
              ),
              Row(
                children: [
                  Expanded(child: Text(l10n.geminiConcurrency)),
                  DropdownButton<int>(
                    key: const ValueKey('geminiConcurrency'),
                    value: _settings.concurrency,
                    items: [
                      for (final n in const [1, 2, 3, 4, 5])
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (n) {
                      if (n != null) _settings.setConcurrency(n);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(child: Text(l10n.geminiPrivacyNote, style: small)),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _keyInput(AppLocalizations l10n, TextStyle small) {
    final scheme = Theme.of(context).colorScheme;
    final status = switch (_test) {
      _Test.none || _Test.running => null,
      _Test.ok => (Icons.check_circle, scheme.secondary, l10n.geminiTestOk),
      _Test.badKey => (
          Icons.error_outline,
          scheme.error,
          l10n.geminiTestBadKey
        ),
      _Test.failed => (
          Icons.error_outline,
          scheme.error,
          l10n.geminiTestFailed(_testError)
        ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('geminiKey'),
          controller: _keyField,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: l10n.geminiKey,
            hintText: _settings.hasKey
                ? l10n.geminiKeySaved(_settings.keyHint)
                : 'AIza…',
            isDense: true,
          ),
        ),
        const SizedBox(height: 4),
        Text(l10n.geminiKeyHint, style: small),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonal(
              key: const ValueKey('geminiTest'),
              onPressed: _test == _Test.running ? null : _saveAndTest,
              child: _test == _Test.running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.geminiTest),
            ),
            TextButton.icon(
              onPressed: () => launchUrl(
                  Uri.parse('https://aistudio.google.com/apikey'),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(l10n.geminiGetKey),
            ),
          ],
        ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(status.$1, size: 16, color: status.$2),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(status.$3,
                        key: const ValueKey('geminiTestStatus'),
                        style: TextStyle(fontSize: 12, color: status.$2))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _modelPicker(AppLocalizations l10n, TextStyle small) {
    final m = _settings.model;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('geminiModel'),
          initialValue: m.id,
          decoration:
              InputDecoration(labelText: l10n.geminiModel, isDense: true),
          items: [
            for (final model in geminiModels)
              DropdownMenuItem(value: model.id, child: Text(model.label)),
          ],
          onChanged: (id) async {
            if (id == null) return;
            await _settings.setModel(geminiModelFor(id));
            widget.onEngineChanged();
          },
        ),
        const SizedBox(height: 4),
        Text(
            l10n.geminiModelInfo(m.freeRpd, m.inputPrice.toStringAsFixed(2),
                m.outputPrice.toStringAsFixed(2)),
            style: small),
      ],
    );
  }

  Widget _usageCard(AppLocalizations l10n, ThemeData theme, TextStyle small) {
    final scheme = theme.colorScheme;
    final u = _settings.usage;
    final m = _settings.model;
    final reset = quotaResetAt(DateTime.now());
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(reset));
    final tier = switch (u.freeTier) {
      true => l10n.geminiTierFree,
      false => l10n.geminiTierPaid,
      null => l10n.geminiTierUnknown,
    };
    final cost = m.cost(u.promptTokens, u.outputTokens);
    final limit = u.dailyLimit;
    final share = (limit ?? m.freeRpd) > 0
        ? (u.requests / (limit ?? m.freeRpd)).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      key: const ValueKey('geminiUsage'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(l10n.geminiUsageTitle,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700))),
              Text(tier, style: small),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            limit != null
                ? l10n.geminiUsageRequests(u.requests, limit)
                : l10n.geminiUsageRequestsEstimate(u.requests, m.freeRpd),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 5,
              color: u.exhausted ? scheme.error : scheme.secondary,
              backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(height: 6),
          Text(l10n.geminiUsageResets(time), style: small),
          const SizedBox(height: 6),
          Text(l10n.geminiUsageTokens(
              _tokens(u.promptTokens), _tokens(u.outputTokens))),
          Text(l10n.geminiUsageParagraphs(u.paragraphs)),
          Text(l10n.geminiUsageBlocked(u.blockedSafety, u.blockedProhibited)),
          if (u.onDevice > 0) Text(l10n.geminiUsageOnDevice(u.onDevice)),
          Text(l10n.geminiCost('\$${cost.toStringAsFixed(cost < 1 ? 3 : 2)}'),
              style: small),
          if (u.exhausted)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(l10n.geminiExhausted,
                  key: const ValueKey('geminiExhausted'),
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            ),
        ],
      ),
    );
  }
}
