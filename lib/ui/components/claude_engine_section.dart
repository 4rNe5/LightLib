// Settings, when Claude is the engine: its key (and the workspace a key
// not tied to one is used in), model, how much it thinks, what happens
// when it cannot translate, and what today's requests cost.

// Flutter imports:
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Package imports:
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/translation/claude/claude_api.dart';
import 'package:openlib/services/translation/claude/claude_client.dart';
import 'package:openlib/services/translation/claude/claude_settings.dart';
import 'package:openlib/services/translation/gemini/gemini_api.dart';

class ClaudeEngineBody extends StatefulWidget {
  const ClaudeEngineBody(
      {super.key, required this.onEngineChanged, this.client});

  /// The key or the model changed: translation starts over with them.
  final VoidCallback onEngineChanged;

  /// What checks a key (the shared client unless a test gives its own).
  final ClaudeClient? client;

  @override
  State<ClaudeEngineBody> createState() => _ClaudeEngineBodyState();
}

enum _Test { none, running, ok, badKey, noCredit, failed }

class _ClaudeEngineBodyState extends State<ClaudeEngineBody> {
  final _settings = ClaudeSettings.instance;
  final _keyField = TextEditingController();
  final _workspaceField = TextEditingController();
  _Test _test = _Test.none;
  String _testError = '';

  @override
  void initState() {
    super.initState();
    _workspaceField.text = _settings.workspace;
    _settings.load().then((_) {
      if (mounted && _workspaceField.text.isEmpty) {
        _workspaceField.text = _settings.workspace;
      }
    });
  }

  @override
  void dispose() {
    _keyField.dispose();
    _workspaceField.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final key = _keyField.text.trim().isNotEmpty
        ? _keyField.text.trim()
        : _settings.apiKey;
    final workspace = _workspaceField.text.trim();
    if (key.isEmpty) return;
    setState(() => _test = _Test.running);
    Future<void> keep() async {
      await _settings.setKey(key, workspace: workspace);
      _keyField.clear();
    }

    try {
      await (widget.client ?? ClaudeClient.shared)
          .test(apiKey: key, workspace: workspace);
      await keep();
      if (mounted) setState(() => _test = _Test.ok);
      widget.onEngineChanged();
    } on GeminiError catch (e) {
      switch (e.kind) {
        case GeminiErrorKind.quotaExhausted:
          // The key is right; its account has no credit.
          await keep();
          _settings.recordLimit(e);
          if (mounted) setState(() => _test = _Test.noCredit);
        case GeminiErrorKind.rateLimited:
          await keep();
          if (mounted) setState(() => _test = _Test.ok);
          widget.onEngineChanged();
        case GeminiErrorKind.badKey:
          if (!mounted) return;
          setState(() {
            _test = _Test.badKey;
            _testError = e.message;
          });
        default:
          if (!mounted) return;
          setState(() {
            _test = _Test.failed;
            _testError = e.message;
          });
      }
    }
  }

  static String _tokens(int n) => n >= 1000000
      ? '${(n / 1e6).toStringAsFixed(2)}M'
      : n >= 1000
          ? '${(n / 1000).toStringAsFixed(1)}K'
          : '$n';

  static String _dollars(double cost) =>
      '\$${cost.toStringAsFixed(cost < 1 ? 3 : 2)}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          Text(l10n.translationEngineClaudeHint, style: small),
          const SizedBox(height: 12),
          _keyInput(l10n, small),
          const SizedBox(height: 12),
          _modelPicker(l10n, small),
          const SizedBox(height: 12),
          Text(l10n.geminiThinking, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<GeminiThinking>(
            key: const ValueKey('claudeThinking'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: GeminiThinking.speed,
                  label: Text(l10n.geminiThinkingSpeed)),
              ButtonSegment(
                  value: GeminiThinking.balanced,
                  label: Text(l10n.geminiThinkingBalanced)),
              ButtonSegment(
                  value: GeminiThinking.quality,
                  label: Text(l10n.geminiThinkingQuality)),
            ],
            selected: {_settings.thinking},
            onSelectionChanged: (v) => _settings.setThinking(v.first),
          ),
          const SizedBox(height: 4),
          Text(l10n.claudeThinkingHint, style: small),
          const SizedBox(height: 12),
          if (_settings.hasKey) _usageCard(l10n, theme, small),
          // (The web has no model of its own.)
          if (!kIsWeb)
          SwitchListTile(
            key: const ValueKey('claudeDeviceFallback'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.geminiDeviceFallback),
            subtitle: Text(l10n.claudeDeviceFallbackHint,
                style: const TextStyle(fontSize: 12)),
            value: _settings.deviceFallback,
            onChanged: _settings.setDeviceFallback,
          ),
          SwitchListTile(
            key: const ValueKey('claudePolish'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.geminiPolish),
            subtitle: Text(l10n.claudePolishHint,
                style: const TextStyle(fontSize: 12)),
            value: _settings.polish,
            onChanged: _settings.setPolish,
          ),
          Row(
            children: [
              Expanded(child: Text(l10n.geminiConcurrency)),
              DropdownButton<int>(
                key: const ValueKey('claudeConcurrency'),
                value: _settings.concurrency,
                items: [
                  for (final n in const [1, 2, 3, 4, 5, 6, 7, 8])
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
              Expanded(child: Text(l10n.claudePrivacyNote, style: small)),
            ],
          ),
        ],
      ),
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
          l10n.claudeTestBadKey(_testError)
        ),
      _Test.noCredit => (
          Icons.error_outline,
          scheme.error,
          l10n.claudeExhausted
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
          key: const ValueKey('claudeKey'),
          controller: _keyField,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: l10n.geminiKey,
            hintText: _settings.hasKey
                ? l10n.geminiKeySaved(_settings.keyHint)
                : 'sk-ant-…',
            isDense: true,
          ),
        ),
        const SizedBox(height: 4),
        Text(l10n.claudeKeyHint, style: small),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('claudeWorkspace'),
          controller: _workspaceField,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: l10n.claudeWorkspace,
            hintText: 'wrkspc_…',
            isDense: true,
          ),
        ),
        const SizedBox(height: 4),
        Text(l10n.claudeWorkspaceHint, style: small),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonal(
              key: const ValueKey('claudeTest'),
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
                  Uri.parse('https://platform.claude.com/settings/keys'),
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
                        key: const ValueKey('claudeTestStatus'),
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
          key: const ValueKey('claudeModel'),
          initialValue: m.id,
          decoration:
              InputDecoration(labelText: l10n.geminiModel, isDense: true),
          items: [
            for (final model in claudeModels)
              DropdownMenuItem(value: model.id, child: Text(model.label)),
          ],
          onChanged: (id) async {
            if (id == null) return;
            await _settings.setModel(claudeModelFor(id));
            widget.onEngineChanged();
          },
        ),
        const SizedBox(height: 4),
        Text(
            l10n.claudeModelInfo(m.inputPrice.toStringAsFixed(2),
                m.outputPrice.toStringAsFixed(2)),
            key: const ValueKey('claudeModelInfo'),
            style: small),
      ],
    );
  }

  Widget _usageCard(AppLocalizations l10n, ThemeData theme, TextStyle small) {
    final scheme = theme.colorScheme;
    final u = _settings.usage;
    final m = _settings.model;
    return Container(
      key: const ValueKey('claudeUsage'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Whose use this is: each model has its own count and price.
          Text('${l10n.geminiUsageTitle} · ${m.label}',
              key: const ValueKey('claudeUsageModel'),
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(l10n.claudeUsageRequests(u.requests),
              style: const TextStyle(fontSize: 13)),
          Text(l10n.geminiUsageTokens(
              _tokens(u.promptTokens), _tokens(u.outputTokens))),
          Text(l10n.geminiUsageParagraphs(u.paragraphs)),
          if (u.blockedSafety + u.blockedProhibited > 0)
            Text(
                l10n.claudeUsageRefused(u.blockedSafety + u.blockedProhibited)),
          if (u.onDevice > 0) Text(l10n.geminiUsageOnDevice(u.onDevice)),
          const SizedBox(height: 4),
          Text(l10n.claudeCostToday(_dollars(_settings.costOf(m))),
              key: const ValueKey('claudeCost'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (u.exhausted)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(l10n.claudeExhausted,
                  key: const ValueKey('claudeExhausted'),
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            ),
          // What the other models cost today: theirs, not this model's.
          for (final MapEntry(key: other, value: used)
              in _settings.otherModelsToday.entries)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  l10n.claudeUsageOther(other.label, used.requests,
                      _dollars(_settings.costOf(other))),
                  key: ValueKey('claudeUsageOther-${other.id}'),
                  style: small),
            ),
        ],
      ),
    );
  }
}
