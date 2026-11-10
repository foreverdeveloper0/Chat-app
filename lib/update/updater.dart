import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  const UpdateInfo({required this.build, required this.url});
  final int build;
  final String url;
}

/// Checks the GitHub "demo" release for a newer build and installs it.
///
/// Android never lets an app install itself silently: the person always
/// sees the system installer and taps Install once.
abstract final class Updater {
  static const _release =
      'https://api.github.com/repos/foreverdeveloper0/Chat-app/releases/tags/demo';

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<({String version, int build})> installed() async {
    final info = await PackageInfo.fromPlatform();
    return (version: info.version, build: int.tryParse(info.buildNumber) ?? 0);
  }

  /// The newer build, or null when this one is current. Throws on network errors.
  static Future<UpdateInfo?> check() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(_release));
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw HttpException('GitHub answered ${res.statusCode}');
      }
      final json = jsonDecode(await res.transform(utf8.decoder).join())
          as Map<String, dynamic>;
      final build = int.tryParse(
          RegExp(r'build:\s*(\d+)').firstMatch('${json['body']}')?.group(1) ??
              '');
      final assets = (json['assets'] as List?) ?? const [];
      final apk = assets.cast<Map<String, dynamic>>().where(
          (a) => '${a['name']}'.endsWith('.apk'));
      if (build == null || apk.isEmpty) return null;
      final now = await installed();
      if (build <= now.build) return null;
      return UpdateInfo(
          build: build, url: '${apk.first['browser_download_url']}');
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads the APK and hands it to the system installer.
  static Stream<OtaEvent> install(UpdateInfo info) => OtaUpdate().execute(
        info.url,
        destinationFilename: 'elite-play-ludo-${info.build}.apk',
      );
}
