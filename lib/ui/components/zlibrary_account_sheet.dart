// Settings: the reader's Z-Library account. Signed out: an email and a
// password (or the browser, when that does not go through). Signed in:
// who, how many downloads are used today, sign out.

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/search_manager.dart' show ZlibraryProvider;
import 'package:openlib/services/zlibrary_account.dart';
import 'package:openlib/ui/zlibrary_login_page.dart';

typedef ZlibSignIn = Future<({ZlibrarySession? session, String? error})>
    Function(String email, String password);
typedef ZlibLimits = Future<({ZlibraryLimits? limits, bool signedOut})>
    Function();

Future<void> showZlibraryAccountSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: const ZlibraryAccountSheet(),
      ),
    );

class ZlibraryAccountSheet extends StatefulWidget {
  const ZlibraryAccountSheet({
    super.key,
    this.account,
    this.signIn,
    this.limits,
    this.browserSignIn,
    this.browserSignOut,
  });

  /// Replaceable in tests (no network, no web view there).
  final ZlibraryAccount? account;
  final ZlibSignIn? signIn;
  final ZlibLimits? limits;
  final Future<ZlibrarySession?> Function(BuildContext context)? browserSignIn;
  final Future<void> Function()? browserSignOut;

  @override
  State<ZlibraryAccountSheet> createState() => _ZlibraryAccountSheetState();
}

class _ZlibraryAccountSheetState extends State<ZlibraryAccountSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final ZlibraryAccount _account =
      widget.account ?? ZlibraryAccount.instance;
  late final ZlibraryProvider _provider = ZlibraryProvider(account: _account);

  bool _busy = false;
  String? _error;
  Future<({ZlibraryLimits? limits, bool signedOut})>? _limits;

  @override
  void initState() {
    super.initState();
    unawaited(_account.load().then((_) {
      if (mounted && _account.signedIn) setState(_askLimits);
    }));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _askLimits() {
    _limits = (widget.limits ?? _provider.accountLimits)()
        .catchError((_) => (limits: null as ZlibraryLimits?, signedOut: false));
  }

  Future<void> _signIn() async {
    final l10n = AppLocalizations.of(context);
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    ({ZlibrarySession? session, String? error}) result;
    try {
      result = await (widget.signIn ?? _provider.signIn)(email, password);
    } catch (_) {
      result = (session: null, error: null);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.session != null) {
        _password.clear();
        _askLimits();
      } else {
        _error = result.error ?? l10n.zlibSignInFailed;
      }
    });
  }

  Future<void> _browser() async {
    final session = await (widget.browserSignIn ?? _openBrowser)(context);
    if (session == null || !mounted) return;
    await _account.signIn(session);
    if (mounted) setState(_askLimits);
  }

  Future<ZlibrarySession?> _openBrowser(BuildContext context) async {
    final mirrors = await _provider.mirrors();
    if (mirrors.isEmpty || !context.mounted) return null;
    return Navigator.push<ZlibrarySession>(
        context,
        MaterialPageRoute(
            builder: (_) => ZlibraryLoginPage(mirror: mirrors.first)));
  }

  Future<void> _signOut() async {
    await _account.signOut();
    unawaited((widget.browserSignOut ??
            () async => zlibraryBrowserSignOut(await _provider.mirrors()))()
        .catchError((_) {}));
    if (mounted) setState(() => _limits = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: _account,
      builder: (context, _) {
        final session = _account.session;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.zlibAccountTitle,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(l10n.zlibAccountWhy,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              if (session == null) ...[
                TextField(
                  key: const ValueKey('zlibEmail'),
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(labelText: l10n.zlibEmail),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('zlibPassword'),
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(labelText: l10n.zlibPassword),
                  onSubmitted: (_) => _signIn(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      key: const ValueKey('zlibError'),
                      style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('zlibSignIn'),
                  onPressed: _busy ? null : _signIn,
                  child: Text(_busy ? l10n.zlibSigningIn : l10n.zlibSignIn),
                ),
                TextButton(
                  key: const ValueKey('zlibBrowser'),
                  onPressed: _busy ? null : _browser,
                  child: Text(l10n.zlibSignInBrowser),
                ),
              ] else ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(session.label,
                      key: const ValueKey('zlibSignedIn'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: FutureBuilder(
                    future: _limits,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      final data = snap.data;
                      if (data?.signedOut == true) {
                        return Text(l10n.zlibSessionExpired,
                            key: const ValueKey('zlibExpired'),
                            style: TextStyle(color: scheme.error));
                      }
                      final limits = data?.limits;
                      return Text(
                          limits == null
                              ? l10n.zlibLimitsUnknown
                              : l10n.zlibLimits(limits.today, limits.limit),
                          key: const ValueKey('zlibLimits'));
                    },
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('zlibSignOut'),
                  onPressed: _signOut,
                  child: Text(l10n.zlibSignOut),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
