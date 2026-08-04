import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/reading/read_history.dart';
import 'package:watch_app/core/supabase/supabase_service.dart';

/// In-memory fake for [ReadingHistoryRemote], mirroring FakeHistoryRemote in
/// watch_history_supabase_test.dart, so the store's throttle/flush/merge
/// logic is testable without a live Supabase project.
class FakeReadingHistoryRemote implements ReadingHistoryRemote {
  final List<Map<String, dynamic>> rows = [];
  int upsertCalls = 0;

  @override
  Future<void> upsert(Map<String, dynamic> row) async {
    upsertCalls++;
    rows.removeWhere((r) =>
        r['user_key'] == row['user_key'] &&
        r['source_id'] == row['source_id'] &&
        r['show_id'] == row['show_id']);
    rows.add(row);
  }

  @override
  Future<List<Map<String, dynamic>>> listFor(String userKey) async {
    return rows.where((r) => r['user_key'] == userKey).toList();
  }
}

/// Throws on every call, standing in for the `reading_history` table not
/// existing yet on the user's Supabase project (or being offline).
class _BrokenReadingHistoryRemote implements ReadingHistoryRemote {
  @override
  Future<void> upsert(Map<String, dynamic> row) async {
    throw Exception('relation "reading_history" does not exist');
  }

  @override
  Future<List<Map<String, dynamic>>> listFor(String userKey) async {
    throw Exception('relation "reading_history" does not exist');
  }
}

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('read_history');
    Hive.init(dir.path);
    await ReadHistory.init();
  });
  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ReadEntry entry(String show, {int pos = 0, int total = 20, int ts = 0}) =>
      ReadEntry(
        sourceId: 'js:m', showId: show, title: show, cover: null,
        chapterId: 'ch1', chapterNumber: 1, chapterUrl: 'u',
        pos: pos, total: total, updatedMs: ts,
      );

  test('save keeps one row per title (latest chapter wins)', () async {
    final h = ReadHistory(SupabaseService(), () => null);
    await h.save(entry('a', pos: 1, ts: 1));
    await h.save(entry('a', pos: 5, ts: 2));
    expect(h.recent(), hasLength(1));
    expect(h.recent().single.pos, 5);
  });

  test('recent() excludes finished and sorts newest-first', () async {
    final h = ReadHistory(SupabaseService(), () => null);
    await h.save(entry('done', pos: 19, total: 20, ts: 1)); // finished
    await h.save(entry('old', pos: 2, ts: 10));
    await h.save(entry('new', pos: 2, ts: 20));
    expect(h.recent().map((e) => e.showId).toList(), ['new', 'old']);
  });

  test('recent() applies the novel permille finished rule (total == 1000)',
      () async {
    final h = ReadHistory(SupabaseService(), () => null);
    await h.save(entry('almostDone', pos: 950, total: 1000, ts: 1));
    await h.save(entry('reading', pos: 500, total: 1000, ts: 2));
    expect(h.recent().map((e) => e.showId).toList(), ['reading']);
  });

  test('two save() calls for the same show within the throttle window '
      'push one upsert; the local read is always immediate', () async {
    final fake = FakeReadingHistoryRemote();
    final h = ReadHistory(SupabaseService(), () => 'user1', remote: fake);
    await h.save(entry('a', pos: 1, ts: 1));
    await h.save(entry('a', pos: 5, ts: 2));

    expect(fake.upsertCalls, 1);
    expect(h.recent().single.pos, 5); // local write is never throttled
    expect(fake.rows.single['pos'], 1); // throttled remote still has the first
  });

  test('save(flush: true) forces an immediate upsert regardless of throttle',
      () async {
    final fake = FakeReadingHistoryRemote();
    final h = ReadHistory(SupabaseService(), () => 'user1', remote: fake);
    await h.save(entry('a', pos: 1, ts: 1));
    expect(fake.upsertCalls, 1);

    await h.save(entry('a', pos: 5, ts: 2), flush: true);

    expect(fake.upsertCalls, 2);
    expect(fake.rows.single['pos'], 5);
  });

  test('pullFromCloud() merges cloud into local, keeping local-only rows '
      '(never wipes an un-synced Continue Reading item)', () async {
    final fake = FakeReadingHistoryRemote();
    final loggedOut = ReadHistory(SupabaseService(), () => null, remote: fake);
    await loggedOut.save(entry('localOnly', pos: 3, ts: 5));

    fake.rows.add({
      'user_key': 'user1', 'source_id': 'js:m', 'show_id': 'fromCloud',
      'title': 'Cloud Title', 'cover': null, 'chapter_id': 'ch1',
      'chapter_number': 1, 'chapter_url': 'u', 'pos': 2, 'total': 20,
      'updated_ms': 9,
    });

    final h = ReadHistory(SupabaseService(), () => 'user1', remote: fake);
    await h.pullFromCloud();

    final ids = h.recent().map((e) => e.showId).toSet();
    expect(ids, {'localOnly', 'fromCloud'}); // both survive — merge, not replace
  });

  test('seedCloudIfNeeded() backfills local rows to an empty cloud once, '
      'so a following pull restores instead of wiping', () async {
    final fake = FakeReadingHistoryRemote();
    final loggedOut = ReadHistory(SupabaseService(), () => null, remote: fake);
    await loggedOut.save(entry('a', pos: 1, ts: 1));
    await loggedOut.save(entry('b', pos: 1, ts: 1));

    final h = ReadHistory(SupabaseService(), () => 'user1', remote: fake);
    await h.seedCloudIfNeeded();
    expect(fake.rows.where((r) => r['user_key'] == 'user1'), hasLength(2));

    final before = fake.upsertCalls;
    await h.seedCloudIfNeeded(); // second call is a no-op
    expect(fake.upsertCalls, before);
  });

  test('a missing reading_history table (or offline) degrades to '
      'local-only silently — save/recent/pullFromCloud/seedCloudIfNeeded '
      'never throw', () async {
    final broken = _BrokenReadingHistoryRemote();
    final h = ReadHistory(SupabaseService(), () => 'user1', remote: broken);

    await h.save(entry('a', pos: 1, ts: 1), flush: true); // forces the upsert
    expect(h.recent().single.showId, 'a'); // local write still succeeded

    await h.pullFromCloud(); // must not throw despite listFor() throwing
    await h.seedCloudIfNeeded(); // must not throw despite upsert() throwing
    expect(h.recent().single.showId, 'a'); // local state untouched
  });
}
