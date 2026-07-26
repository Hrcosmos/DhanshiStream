import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'tv_track_helpers.dart' show subtitleFontAsset;

/// Copies the chosen bundled subtitle font to app-support once, so the native
/// TV players can `Typeface.createFromFile` it. Returns null for the default
/// family ('') or an unknown one. Shared by both TV players (the Flutter
/// PlatformView player and the fully-native TvPlayerActivity) so the staging
/// path is defined in exactly one place.
Future<String?> stageSubtitleFont(String family) async {
  if (family.isEmpty) return null;
  final asset = subtitleFontAsset(family);
  if (asset == null) return null;
  try {
    final dir = await getApplicationSupportDirectory();
    final out = File('${dir.path}/sub_fonts/${asset.split('/').last}');
    if (!await out.exists()) {
      await out.parent.create(recursive: true);
      final bytes = await rootBundle.load(asset);
      await out.writeAsBytes(bytes.buffer.asUint8List());
    }
    return out.path;
  } catch (_) {
    return null;
  }
}
