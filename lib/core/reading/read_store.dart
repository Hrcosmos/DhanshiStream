import 'package:hive/hive.dart';

import '../privacy/incognito_mode.dart';

/// Hive-backed per-(sourceId, showId, chapterId) reading positions.
///
/// The reading analogue of ResumeStore: local-only, not synced (Continue
/// Reading syncs via ReadHistory, added separately).
///
/// Convention:
///  - manga: pos = page index, total = page count.
///  - novel: pos = scroll permille (0–1000), total = 1000.
class ReadStore {
  static const String boxName = 'read_positions';

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<Map>(boxName);
    }
  }

  Box<Map> get _box => Hive.box<Map>(boxName);

  // Key includes the SHOW because chapter ids can repeat across titles —
  // without it, one show's read position collides with another's.
  String _key(String sourceId, String showId, String chapterId) =>
      '$sourceId::$showId::$chapterId';

  Future<void> save(
    String sourceId,
    String showId,
    String chapterId, {
    required int pos,
    required int total,
  }) async {
    if (IncognitoMode.on) return; // incognito: don't remember reading position
    await _box.put(_key(sourceId, showId, chapterId), {
      'pos': pos,
      'total': total,
    });
  }

  ({int pos, int total})? get(String sourceId, String showId, String chapterId) {
    final raw = _box.get(_key(sourceId, showId, chapterId));
    if (raw == null) return null;
    final m = Map<String, dynamic>.from(raw);
    return (
      pos: (m['pos'] as num?)?.toInt() ?? 0,
      total: (m['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// True when the chapter is effectively done: last page (manga) or ≥95%
  /// scrolled (novel, where total is always 1000).
  bool finished(String sourceId, String showId, String chapterId) {
    final mark = get(sourceId, showId, chapterId);
    if (mark == null || mark.total <= 0) return false;
    if (mark.total == 1000) return mark.pos >= 950;
    return mark.pos >= mark.total - 1;
  }
}
