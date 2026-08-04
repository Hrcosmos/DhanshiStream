import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';

import '../state/active_source_cubit.dart';
import 'content_mode.dart';

/// App-wide content mode (anime | manga | novel), persisted across launches.
/// Also remembers the active source separately per mode, so flipping to Manga
/// and back never disturbs the anime source selection.
class ContentModeCubit extends Cubit<ContentMode> {
  ContentModeCubit._(this._box, this._active, super.initial);

  final Box _box;
  final ActiveSourceCubit _active;

  static Future<ContentModeCubit> create(ActiveSourceCubit active) async {
    final box = await Hive.openBox('content_mode');
    return ContentModeCubit._(box, active, _restore(box));
  }

  static ContentMode _restore(Box box) {
    final stored = box.get('mode') as String?;
    if (stored == null) return ContentMode.anime;
    try {
      return ContentMode.values.byName(stored);
    } catch (_) {
      return ContentMode.anime;
    }
  }

  Future<void> setMode(ContentMode m) async {
    if (m == state) return;
    // Park the current source under the outgoing mode…
    await _box.put('src.${state.name}', _active.state);
    await _box.put('mode', m.name);
    emit(m);
    // …and restore the incoming mode's remembered source (if any).
    final remembered = _box.get('src.${m.name}') as String?;
    if (remembered != null && remembered.isNotEmpty) {
      _active.setSource(remembered);
    }
  }
}
