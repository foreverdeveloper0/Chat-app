import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../update/updater.dart';

/// Quietly checks on start-up and only speaks up when a new build exists.
Future<void> autoCheckForUpdate(BuildContext context) async {
  if (!Updater.supported) return;
  try {
    final info = await Updater.check();
    if (info != null && context.mounted) await showUpdateDialog(context, info);
  } catch (_) {
    // Offline or rate limited: try again next launch.
  }
}

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(info: info),
  );
}

/// Settings sheet with the installed version and a manual update check.
Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SettingsSheet(),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});
  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  double? _progress;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _progress = null;
      _error = null;
    });
    String? error;
    try {
      final path = await Updater.download(widget.info, (p) {
        if (mounted) setState(() => _progress = p);
      });
      await Updater.install(path);
      if (mounted) Navigator.of(context).pop();
      return;
    } on PlatformException catch (e) {
      error = 'Could not open the installer: ${e.message ?? e.code}';
    } catch (e) {
      error = 'Download failed. Check your internet and try again.';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<void> _browser() async {
    try {
      await Updater.openInBrowser(widget.info);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the browser.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = AppText.title.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.3,
    );
    return AlertDialog(
      backgroundColor: AppColors.cardTop,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(
        'Update available',
        style: AppText.title.copyWith(fontSize: 22),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _busy
                ? 'Downloading build ${widget.info.build}…'
                : 'A newer build (${widget.info.build}) is ready. Android will '
                      'ask you to confirm the install; the app closes while '
                      'it installs.',
            style: body,
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                color: AppColors.mint,
                backgroundColor: AppColors.cardInset,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: body.copyWith(
                color: const Color(0xFFFF8A80),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!_busy)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Later',
              style: TextStyle(color: AppColors.cream),
            ),
          ),
        if (!_busy && _error != null)
          TextButton(
            onPressed: _browser,
            child: const Text(
              'Open in browser',
              style: TextStyle(color: AppColors.cream),
            ),
          ),
        if (!_busy)
          TextButton(
            onPressed: _start,
            child: const Text(
              'Update now',
              style: TextStyle(color: AppColors.mint),
            ),
          ),
      ],
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  String _version = '';
  String _status = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (Updater.supported) {
      Updater.installed().then(
        (v) => mounted
            ? setState(() => _version = '${v.version} (build ${v.build})')
            : null,
      );
    }
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = '';
    });
    try {
      final info = await Updater.check();
      if (!mounted) return;
      if (info == null) {
        setState(() => _status = 'You have the latest version.');
      } else {
        Navigator.of(context).pop();
        await showUpdateDialog(context, info);
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _status = 'Could not check. Are you online?');
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final small = AppText.title.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: AppColors.creamDim,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(
        color: AppColors.bgTop,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AppColors.cardBorder, width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text('Settings', style: AppText.title.copyWith(fontSize: 24)),
            const SizedBox(height: 4),
            if (_version.isNotEmpty) Text('Version $_version', style: small),
            const SizedBox(height: 18),
            if (Updater.supported)
              GestureDetector(
                onTap: _checking ? null : _check,
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6BF0BD), AppColors.mintDeep],
                    ),
                  ),
                  child: _checking
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: AppColors.ink,
                          ),
                        )
                      : Text(
                          'Check for updates',
                          style: AppText.title.copyWith(
                            fontSize: 17,
                            color: AppColors.ink,
                          ),
                        ),
                ),
              )
            else
              Text('Updates are available in the Android app.', style: small),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_status, style: small.copyWith(color: AppColors.mint)),
            ],
          ],
        ),
      ),
    );
  }
}
