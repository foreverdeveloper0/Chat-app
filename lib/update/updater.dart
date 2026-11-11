import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(_release));
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw HttpException('GitHub answered ${res.statusCode}');
      }
      final json = jsonDecode(
        await res.transform(utf8.decoder).join(),
      ) as Map<String, dynamic>;
      final build = int.tryParse(
        RegExp(r'build:\s*(\d+)').firstMatch('${json['body']}')?.group(1) ?? '',
      );
      final assets = (json['assets'] as List?) ?? const [];
      final apk = assets.cast<Map<String, dynamic>>().where(
        (a) => '${a['name']}'.endsWith('.apk'),
      );
      if (build == null || apk.isEmpty) return null;
      final now = await installed();
      if (build <= now.build) return null;
      return UpdateInfo(
        build: build,
        url: '${apk.first['browser_download_url']}',
      );
    } finally {
      client.close(force: true);
    }
  }

  static const _channel = MethodChannel('elite_play/update');

  /// Downloads the APK into the app's own cache, reporting 0..1 as it
  /// goes (null while the size is unknown), and returns the file's path.
  static Future<String> download(
    UpdateInfo info,
    void Function(double? progress) onProgress,
  ) async {
    final dir = Directory((await _channel.invokeMethod<String>('dir'))!);
    // Clear out earlier downloads so they do not pile up.
    await for (final old in dir.list()) {
      try {
        await old.delete(recursive: true);
      } catch (_) {}
    }
    final part = File('${dir.path}/update.part');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(info.url));
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw HttpException('Download answered ${res.statusCode}');
      }
      final total = res.contentLength;
      var got = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          got += chunk.length;
          onProgress(total > 0 ? got / total : null);
        }
      } finally {
        await sink.close();
      }
      if (got == 0 || (total > 0 && got != total)) {
        throw const HttpException('The download was cut short');
      }
      final apk = await part.rename('${dir.path}/elite-play-${info.build}.apk');
      return apk.path;
    } finally {
      client.close(force: true);
    }
  }

  /// Hands a downloaded APK to Android's installer.
  static Future<void> install(String path) =>
      _channel.invokeMethod<void>('install', {'path': path});

  /// Opens the APK link in the phone's browser, as a fallback.
  static Future<void> openInBrowser(UpdateInfo info) =>
      _channel.invokeMethod<void>('open', {'url': info.url});
}
