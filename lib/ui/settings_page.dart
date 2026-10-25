// Dart imports:
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:openlib/services/backup_service.dart';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/files.dart';
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/services/update_checker.dart';
import 'package:permission_handler/permission_handler.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/search_manager.dart';
import 'package:openlib/services/webview_challenge_solver.dart';
import 'package:openlib/services/search_history.dart';
import 'package:openlib/ui/components/library_tiles.dart'
    show modernSurfaceTheme;
import 'package:openlib/ui/components/page_title_widget.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';
import 'package:openlib/ui/about_page.dart';
import 'package:openlib/ui/instances_page.dart';
import 'package:openlib/ui/onboarding/onboarding_page.dart';
import 'package:openlib/ui/translation_settings_page.dart';
import 'package:openlib/ui/reader_font_settings_page.dart';
import 'package:openlib/ui/release_history_page.dart';

import 'package:openlib/state/state.dart'
    show
        themeModeProvider,
        fontSizeScaleProvider,
        openPdfWithExternalAppProvider,
        openEpubWithExternalAppProvider,
        showManualDownloadButtonProvider,
        backgroundVerificationProvider,
        donationKeyProvider,
        myLibraryProvider,
        searchProviderToggles,
        localeOverrideProvider;

// Scans a directory for book files (epub, pdf) and imports them to the library database
Future<void> scanAndImportBooks(
    String directoryPath, MyLibraryDb database, WidgetRef ref) async {
  try {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return;

    final files = directory.listSync(recursive: false);
    int importedCount = 0;

    for (var entity in files) {
      if (entity is File) {
        final fileName = entity.path.split('/').last;
        final extension = fileName.split('.').last.toLowerCase();

        // Only process epub and pdf files
        if (extension == 'epub' || extension == 'pdf') {
          // Extract the md5 hash from the filename (the part before the extension)
          final parts = fileName.split('.');
          if (parts.length >= 2) {
            final md5 = parts.sublist(0, parts.length - 1).join('.');

            // Check if this book already exists in the database
            final exists = await database.checkIdExists(md5);
            if (!exists) {
              // Create a minimal book entry for the imported file
              final book = MyBook(
                id: md5,
                title:
                    md5, // Use filename as title since we don't have metadata
                author: "Unknown",
                thumbnail: "",
                link: "",
                publisher: "",
                info: "",
                description: "",
                format: extension,
              );
              await database.insert(book);
              importedCount++;
            }
          }
        }
      }
    }

    // Refresh the library provider to show new books
    if (importedCount > 0) {
      // ignore: unused_result
      ref.refresh(myLibraryProvider);
    }
  } catch (e) {
    // Silently fail - don't interrupt user flow
  }
}

Future<void> requestStoragePermission() async {
  // Desktop platforms don't require runtime storage permissions
  if (PlatformUtils.isDesktop) return;

  // Storage permission exists up to Android 10; from 11 on a folder is
  // usable or not by where it is (see canWriteDirectory). All-files
  // access is not asked for: security scanners flag sideloaded apps that
  // hold it together with the right to install updates.
  DeviceInfoPlugin plugin = DeviceInfoPlugin();
  AndroidDeviceInfo android = await plugin.androidInfo;
  if (android.version.sdkInt < 30) {
    if (await Permission.storage.request().isPermanentlyDenied) {
      await openAppSettings();
    }
  }
}

// ---------------------------------------------------------------------------
// Shared building blocks: grouped, inset cards (one per section) whose
// rows share a coloured icon badge, title/subtitle and trailing element.
// ---------------------------------------------------------------------------

/// Badge colours, one per section, so sections read apart at a glance.
class _Hue {
  static const search = Color(0xFF3B82F6);
  static const history = Color(0xFF6366F1);
  static const library = Color(0xFF0EA5E9);
  static const appearance = Color(0xFFA855F7);
  static const general = Color(0xFF14B8A6);
  static const reader = Color(0xFFF59E0B);
  static const advanced = Color(0xFF64748B);
  static const backup = Color(0xFF22C55E);
  static const updates = Color(0xFF06B6D4);
  static const about = Color(0xFFEF4444);
}

/// Rounded-square icon on a solid colour, as in system settings.
class _IconBadge extends StatelessWidget {
  const _IconBadge(this.icon, this.color);

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }
}

/// One section: a small label over a rounded card holding [children],
/// with hairline dividers between rows.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(
          height: 1,
          thickness: 0.6,
          indent: 60,
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ));
      }
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) _SettingsSectionHeader(title!),
        Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(children: rows),
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}

/// Section label above a group.
class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The text column of a row.
class _RowText extends StatelessWidget {
  const _RowText(this.title, this.subtitle);

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface)),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: scheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}

/// Tappable row with an icon badge, subtitle, an optional [value] shown
/// before the chevron, and a [busy] spinner in place of the chevron.
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.color = _Hue.advanced,
    this.value,
    this.busy = false,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color color;
  final String? value;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            if (icon != null) ...[
              _IconBadge(icon!, color),
              const SizedBox(width: 14),
            ],
            Expanded(child: _RowText(title, subtitle)),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(value!,
                    style: TextStyle(
                        fontSize: 14, color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(width: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: busy
                  ? const SizedBox(
                      key: ValueKey('busy'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.chevron_right,
                      key: const ValueKey('chevron'),
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Switch row in the same shape as [_SettingsTile].
class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.title,
    this.subtitle,
    this.icon,
    this.color = _Hue.advanced,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color color;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Row(
          children: [
            if (icon != null) ...[
              _IconBadge(icon!, color),
              const SizedBox(width: 14),
            ],
            Expanded(child: _RowText(title, subtitle)),
            const SizedBox(width: 8),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Row whose control sits under its title (segmented buttons, sliders).
class _SettingsControlRow extends StatelessWidget {
  const _SettingsControlRow({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _IconBadge(icon, color),
              const SizedBox(width: 14),
              Expanded(child: _RowText(title, null)),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Theme(data: modernSurfaceTheme(Theme.of(context)), child: _body(ref));

  Widget _body(WidgetRef ref) => Builder(builder: (context) {
        // Watch useful providers
        final themeMode = ref.watch(themeModeProvider);
        final openPdfExternal = ref.watch(openPdfWithExternalAppProvider);
        final openEpubExternal = ref.watch(openEpubWithExternalAppProvider);
        final showManualDownload = ref.watch(showManualDownloadButtonProvider);
        final backgroundVerification =
            ref.watch(backgroundVerificationProvider);
        final fontSizeScale = ref.watch(fontSizeScaleProvider);
        final saveHistory = ref.watch(searchHistoryEnabledProvider);
        final historyCount =
            ref.watch(searchHistoryProvider).valueOrNull?.length ?? 0;
        final l10n = AppLocalizations.of(context);

        MyLibraryDb dataBase = MyLibraryDb.instance;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LargeTitle(l10n.settingsTitle,
                  padding: const EdgeInsets.fromLTRB(4, 4, 0, 18)),
              const _SearchProvidersWidget(),
              _SettingsGroup(
                title: l10n.searchHistorySection,
                children: [
                  _SettingsSwitchTile(
                    title: l10n.saveSearchHistory,
                    subtitle: l10n.saveSearchHistoryHint,
                    icon: Icons.history,
                    color: _Hue.history,
                    value: saveHistory,
                    onChanged: (val) => ref
                        .read(searchHistoryEnabledProvider.notifier)
                        .set(val),
                  ),
                  _SettingsTile(
                    title: l10n.clearSearchHistory,
                    subtitle: l10n.savedSearchCount(historyCount),
                    icon: Icons.delete_sweep_outlined,
                    color: _Hue.history,
                    onTap: historyCount == 0
                        ? null
                        : () async {
                            await clearSearches(ref);
                            if (context.mounted) {
                              showSnackBar(
                                  context: context,
                                  message: l10n.searchHistoryCleared);
                            }
                          },
                  ),
                ],
              ),
              _SettingsGroup(
                title: l10n.libraryInstancesSection,
                children: [
                  _SettingsTile(
                    title: l10n.mirrorsAndProviders,
                    icon: Icons.dns_outlined,
                    color: _Hue.library,
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const InstancesPage()));
                    },
                  ),
                ],
              ),
              _SettingsGroup(
                title: l10n.appearanceSection,
                children: [
                  _LanguageSelectorWidget(),
                  _SettingsControlRow(
                    title: l10n.themeTitle,
                    icon: Icons.contrast,
                    color: _Hue.appearance,
                    child: SegmentedButton<ThemeMode>(
                      key: const ValueKey('themeSegments'),
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                            value: ThemeMode.system,
                            icon: const Icon(Icons.brightness_auto, size: 18),
                            label: Text(l10n.themeSystemShort)),
                        ButtonSegment(
                            value: ThemeMode.light,
                            icon:
                                const Icon(Icons.light_mode_outlined, size: 18),
                            label: Text(l10n.themeLightShort)),
                        ButtonSegment(
                            value: ThemeMode.dark,
                            icon:
                                const Icon(Icons.dark_mode_outlined, size: 18),
                            label: Text(l10n.themeDarkShort)),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (v) => ref
                          .read(themeModeProvider.notifier)
                          .setTheme(v.first),
                    ),
                  ),
                  _SettingsControlRow(
                    title: l10n.fontSizeTitle,
                    icon: Icons.format_size,
                    color: _Hue.appearance,
                    trailing: Text(
                      l10n.scaleValue(fontSizeScale.toStringAsFixed(1)),
                      style: TextStyle(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    child: Row(
                      children: [
                        const Text('A', style: TextStyle(fontSize: 13)),
                        Expanded(
                          child: Slider(
                            value: fontSizeScale,
                            min: 0.8,
                            max: 2.0,
                            divisions: 12,
                            label: fontSizeScale.toStringAsFixed(1),
                            onChanged: (val) {
                              ref.read(fontSizeScaleProvider.notifier).state =
                                  val;
                            },
                            onChangeEnd: (val) {
                              dataBase.savePreference(
                                  'fontSizeScale', val.toString());
                            },
                          ),
                        ),
                        const Text('A',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              _SettingsGroup(
                title: l10n.generalSection,
                children: [
                  FutureBuilder<dynamic>(
                    future: dataBase.getPreference('bookStorageDirectory'),
                    builder: (context, snapshot) {
                      String subtitle = "Change where books are saved";
                      if (snapshot.hasData && snapshot.data is String) {
                        subtitle = snapshot.data as String;
                      }
                      return _SettingsTile(
                        title: l10n.storageLocation,
                        subtitle: subtitle,
                        icon: Icons.folder_outlined,
                        color: _Hue.general,
                        onTap: () async {
                          final currentDirectory = await dataBase
                              .getPreference('bookStorageDirectory');
                          String? pickedDirectory =
                              await pickBookStorageDirectory();
                          if (pickedDirectory == null) return;
                          await requestStoragePermission();
                          if (!await canWriteDirectory(pickedDirectory)) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text(l10n.storageNotWritable)));
                            }
                            return;
                          }

                          // Move the books from wherever they live now - the
                          // old code only moved them when leaving the
                          // internal default, so switching between two
                          // custom folders left every file behind and the
                          // library showed "File not found" on the next
                          // open.
                          if (currentDirectory != pickedDirectory) {
                            await moveLibraryFiles(
                                currentDirectory, pickedDirectory);
                          }

                          await dataBase.savePreference(
                              'bookStorageDirectory', pickedDirectory);
                          await scanAndImportBooks(
                              pickedDirectory, dataBase, ref);
                          // ignore: unused_result
                          ref.refresh(myLibraryProvider);
                          // The FutureBuilder reads the db future directly,
                          // so rebuild manually to show the new path
                          // immediately.
                          (context as Element).markNeedsBuild();
                        },
                      );
                    },
                  ),
                ],
              ),
              _SettingsGroup(
                title: l10n.readerSection,
                children: [
                  _SettingsTile(
                    title: l10n.readerFonts,
                    subtitle: l10n.fontsSettingsSubtitle,
                    icon: Icons.font_download_outlined,
                    color: _Hue.reader,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ReaderFontSettingsPage())),
                  ),
                  _SettingsTile(
                    title: l10n.translationSettingsTitle,
                    subtitle: l10n.translationSettingsSubtitle,
                    icon: Icons.translate,
                    color: _Hue.reader,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const TranslationSettingsPage())),
                  ),
                  _SettingsSwitchTile(
                    title: l10n.openPdfExternally,
                    subtitle: l10n.useDefaultPdfViewer,
                    icon: Icons.picture_as_pdf_outlined,
                    color: _Hue.reader,
                    value: openPdfExternal,
                    onChanged: (val) {
                      ref.read(openPdfWithExternalAppProvider.notifier).state =
                          val;
                      dataBase.savePreference('openPdfwithExternalApp', val);
                    },
                  ),
                  _SettingsSwitchTile(
                    title: l10n.openEpubExternally,
                    subtitle: l10n.useDefaultEpubReader,
                    icon: Icons.menu_book_outlined,
                    color: _Hue.reader,
                    value: openEpubExternal,
                    onChanged: (val) {
                      ref.read(openEpubWithExternalAppProvider.notifier).state =
                          val;
                      dataBase.savePreference('openEpubwithExternalApp', val);
                    },
                  ),
                ],
              ),
              _SettingsGroup(
                title: l10n.advancedSection,
                children: [
                  _SettingsSwitchTile(
                    title: l10n.manualDownloadButton,
                    subtitle: l10n.showManualDownloadHint,
                    icon: Icons.touch_app_outlined,
                    value: showManualDownload,
                    onChanged: (val) {
                      ref
                          .read(showManualDownloadButtonProvider.notifier)
                          .state = val;
                      dataBase.savePreference('showManualDownloadButton', val);
                    },
                  ),
                  _SettingsSwitchTile(
                    title: l10n.backgroundVerification,
                    subtitle: l10n.backgroundVerificationHint,
                    icon: Icons.verified_user_outlined,
                    value: backgroundVerification,
                    onChanged: (val) {
                      ref.read(backgroundVerificationProvider.notifier).state =
                          val;
                      WebviewChallengeSolver.headlessEnabled = val;
                      dataBase.savePreference(
                          'backgroundVerification', val ? 1 : 0);
                    },
                  ),
                  _SettingsTile(
                    title: l10n.donationKeyTitle,
                    subtitle: l10n.enterKeyForFasterDownloads,
                    icon: Icons.key_outlined,
                    onTap: () => _showDonationKeyDialog(context, ref, dataBase),
                  ),
                ],
              ),
              _BackupSettingsWidget(database: dataBase),
              const _UpdateSettingsWidget(),
              _SettingsGroup(
                title: l10n.aboutSection,
                children: [
                  _SettingsTile(
                    title: l10n.aboutOpenlib,
                    icon: Icons.info_outline,
                    color: _Hue.about,
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const AboutPage()));
                    },
                  ),
                  _SettingsTile(
                    title: l10n.redoOnboarding,
                    subtitle: l10n.resetAppSetup,
                    icon: Icons.restart_alt,
                    color: _Hue.about,
                    onTap: () async {
                      // Clear relevant preferences
                      await dataBase.savePreference('onboardingCompleted', 0);

                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                              builder: (context) => const OnboardingPage()),
                          (route) => false,
                        );
                      }
                    },
                  ),
                  _SettingsTile(
                    title: l10n.exportLogs,
                    subtitle: l10n.shareDiagnosticLogs,
                    icon: Icons.bug_report_outlined,
                    color: _Hue.about,
                    onTap: () async {
                      final l10n = AppLocalizations.of(context);
                      try {
                        await AppLogger().exportLogs();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(l10n.failedExportLogs('$e'))),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Center(
                      child: Text(
                        "Version ${snapshot.data!.version}+${snapshot.data!.buildNumber}",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        );
      });
  void _showDonationKeyDialog(
      BuildContext context, WidgetRef ref, MyLibraryDb dataBase) {
    final dialogL10n = AppLocalizations.of(context);
    final currentKey = ref.read(donationKeyProvider);
    final controller = TextEditingController(text: currentKey);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context).donationKeyDialog),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: dialogL10n.enterYourKey,
            helperText: dialogL10n.donationKeyHelper,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogL10n.cancel),
          ),
          TextButton(
            onPressed: () {
              final newKey = controller.text.trim();
              ref.read(donationKeyProvider.notifier).state = newKey;
              dataBase.savePreference('donationKey', newKey);
              Navigator.pop(dialogContext);
            },
            child: Text(dialogL10n.save),
          ),
        ],
      ),
    );
  }
}

// Update settings widget with prerelease toggle and check button
class _UpdateSettingsWidget extends StatefulWidget {
  const _UpdateSettingsWidget();

  @override
  State<_UpdateSettingsWidget> createState() => _UpdateSettingsWidgetState();
}

class _UpdateSettingsWidgetState extends State<_UpdateSettingsWidget> {
  final UpdateCheckerService _updateChecker = UpdateCheckerService();
  bool _includePrereleases = false;
  bool _autoDownload = true;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final value = await _updateChecker.getIncludePrereleases();
    final auto = await _updateChecker.getAutoDownload();
    if (mounted) {
      setState(() {
        _includePrereleases = value;
        _autoDownload = auto;
      });
    }
  }

  Future<void> _checkForUpdates() async {
    final updateL10n = AppLocalizations.of(context);
    setState(() {
      _isChecking = true;
    });

    try {
      final result = await _updateChecker.checkForUpdates(
        includePrereleases: _includePrereleases,
      );

      if (!mounted) return;

      if (result.updateAvailable && result.latestRelease != null) {
        await _updateChecker.showUpdateDialog(context, result.latestRelease!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(updateL10n.onLatestVersion(result.currentVersion)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(updateL10n.failedCheckUpdates(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _SettingsGroup(
      title: l10n.updatesSection,
      children: [
        _SettingsSwitchTile(
          title: l10n.includeBetaUpdates,
          subtitle: l10n.getPreReleaseVersions,
          icon: Icons.science_outlined,
          color: _Hue.updates,
          value: _includePrereleases,
          onChanged: (bool value) async {
            setState(() {
              _includePrereleases = value;
            });
            await _updateChecker.setIncludePrereleases(value);
          },
        ),
        if (Platform.isAndroid)
          _SettingsSwitchTile(
            title: l10n.autoDownloadUpdates,
            subtitle: l10n.autoDownloadUpdatesHint,
            icon: Icons.download_for_offline_outlined,
            color: _Hue.updates,
            value: _autoDownload,
            onChanged: (bool value) async {
              setState(() => _autoDownload = value);
              await _updateChecker.setAutoDownload(value);
            },
          ),
        _SettingsTile(
          title: l10n.checkForUpdates,
          icon: Icons.system_update_outlined,
          color: _Hue.updates,
          busy: _isChecking,
          onTap: _isChecking ? null : _checkForUpdates,
        ),
        _SettingsTile(
          title: l10n.releaseHistoryTitle,
          subtitle: l10n.releaseHistoryHint,
          icon: Icons.history_rounded,
          color: _Hue.updates,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ReleaseHistoryPage())),
        ),
      ],
    );
  }
}

/// Toggles which catalogs the search fans out to. Disabling the last
/// source is refused - there is nothing to search without one.
class _SearchProvidersWidget extends ConsumerWidget {
  const _SearchProvidersWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final enabled = ref.watch(searchProviderToggles);

    return enabled.when(
      data: (enabledIds) {
        final manager = SearchManager();
        return _SettingsGroup(
          title: l10n.searchProvidersSection,
          children: [
            for (final provider in [
              (
                SearchProviderId.annasArchive,
                "Anna's Archive",
                l10n.providerSourceOriginal
              ),
              (
                SearchProviderId.libgen,
                'Library Genesis',
                l10n.providerLibgenCatalog
              ),
              (
                SearchProviderId.zlibrary,
                'Z-Library',
                l10n.providerZlibMirrors
              ),
              (
                SearchProviderId.welib,
                'WeLib',
                'Cloudflare-gated search and open book pages'
              ),
            ])
              _SettingsSwitchTile(
                title: provider.$2,
                subtitle: provider.$3,
                icon: Icons.travel_explore,
                color: _Hue.search,
                value: enabledIds.contains(provider.$1),
                onChanged: (on) async {
                  if (!on && enabledIds.length == 1) {
                    showSnackBar(
                        context: context, message: l10n.atLeastOneSource);
                    return;
                  }
                  await manager.setProviderEnabled(provider.$1, on);
                  // ignore: unused_result
                  ref.refresh(searchProviderToggles);
                },
              ),
          ],
        );
      },
      // The header stays put while the toggles load.
      loading: () => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: _SettingsSectionHeader(l10n.searchProvidersSection),
      ),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

/// Export/import the whole app state: settings, saved books, reading
/// positions, instances. One JSON file, shareable or pickable.
class _BackupSettingsWidget extends ConsumerWidget {
  const _BackupSettingsWidget({required this.database});

  final MyLibraryDb database;

  Future<void> _export(BuildContext context) async {
    final service = BackupService(database: database);
    final exportL10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await service.createBackupJson();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final fileName = 'openlib_backup_$timestamp.json';

      if (PlatformUtils.isDesktop) {
        final target = await FilePicker.saveFile(
          dialogTitle: exportL10n.saveBackupTitle,
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(utf8.encode(json)),
        );
        if (target == null) return;
        if (context.mounted) {
          showSnackBar(
              context: context,
              message: AppLocalizations.of(context).backupSaved);
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsString(json);
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path)],
          text: 'LightLib backup',
        ));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(exportL10n.failedExportBackup('$e'))));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final service = BackupService(database: database);
    final importL10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: importL10n.pickBackupFile,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = files.single.path;
      if (path == null) return;

      final restored = await service.restoreBackupFile(path);
      if (!restored) {
        if (context.mounted) {
          showSnackBar(context: context, message: importL10n.notABackup);
        }
        return;
      }
      // Imported preferences/instances must reach the live UI.
      // ignore: unused_result
      ref.refresh(myLibraryProvider);
      // ignore: unused_result
      ref.refresh(searchProviderToggles);
      if (context.mounted) {
        showSnackBar(
            context: context,
            message: AppLocalizations.of(context).backupRestored);
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(importL10n.failedImportBackup('$e'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SettingsGroup(
      title: AppLocalizations.of(context).backupSection,
      children: [
        _SettingsTile(
          title: 'Export Backup',
          subtitle: 'Save settings, books and instances to a JSON file',
          icon: Icons.file_upload_outlined,
          color: _Hue.backup,
          onTap: () => _export(context),
        ),
        _SettingsTile(
          title: 'Import Backup',
          subtitle: 'Restore from a backup file (replaces current data)',
          icon: Icons.file_download_outlined,
          color: _Hue.backup,
          onTap: () => _import(context, ref),
        ),
      ],
    );
  }
}

// ====================================================================
// LANGUAGE SELECTOR
// Dropdown that pins the app to one of the supported locales, or
// follows the system default. Choice persists in the preferences
// table under the 'locale' key.
// ====================================================================
class _LanguageSelectorWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeOverrideProvider);
    final l10n = AppLocalizations.of(context);

    // Native display names: a French user should see 'Francais' even
    // while the app still renders in English.
    const nativeNames = {
      'en': 'English',
      'de': 'Deutsch',
      'fr': 'Français',
      'es': 'Español',
      'ko': '한국어',
      'ja': '日本語',
    };

    String nameOf(Locale? loc) => loc == null
        ? l10n.systemLanguage
        : nativeNames[loc.languageCode] ?? loc.languageCode;

    void choose(Locale? val) {
      ref.read(localeOverrideProvider.notifier).state = val;
      MyLibraryDb.instance
          .savePreference('locale', val?.languageCode ?? '')
          .catchError((_) => 0);
    }

    return _SettingsTile(
      key: const ValueKey('languageTile'),
      title: l10n.languageSetting,
      icon: Icons.language,
      color: _Hue.appearance,
      value: nameOf(locale),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (sheetContext) => Theme(
          data: modernSurfaceTheme(Theme.of(sheetContext)),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(l10n.languageSetting,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                for (final option in <Locale?>[
                  null,
                  ...AppLocalizations.supportedLocales
                ])
                  ListTile(
                    key: ValueKey('locale-${option?.languageCode ?? 'system'}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(nameOf(option)),
                    trailing: option == locale
                        ? Icon(Icons.check,
                            color: Theme.of(sheetContext).colorScheme.primary)
                        : null,
                    onTap: () {
                      choose(option);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
