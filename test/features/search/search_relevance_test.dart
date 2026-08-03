import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/features/search/bloc/search_state.dart';

MediaItem _item(String title, {String? english}) => MediaItem(
  id: 'id-$title',
  title: title,
  englishTitle: english,
  url: 'https://example.com/$title',
  type: ProviderType.anime,
  sourceId: 'src',
);

SearchState _stateFor(String query, List<MediaItem> items) => SearchState(
  status: SearchStatus.success,
  query: query,
  groups: [
    SourceResultGroup(sourceId: 'src', sourceName: 'src', items: items),
  ],
);

List<String> _titles(SearchState s) =>
    s.visibleResults.map((i) => i.title).toList();

void main() {
  group('best-match relevance sort', () {
    test('exact title beats prefix matches buried in source order', () {
      final state = _stateFor('one piece', [
        _item('One Piece Film: Red'),
        _item('One Piece: Stampede'),
        _item('One Piece'), // exact, but last from the source
      ]);
      expect(_titles(state).first, 'One Piece');
    });

    test('ranks exact > prefix > substring > word overlap', () {
      final state = _stateFor('naruto', [
        _item('Boruto: Naruto Next Generations'), // substring
        _item('Naruto Shippuden'), // prefix
        _item('Naruto'), // exact
        _item('The Last: A Movie'), // no match
      ]);
      expect(_titles(state), [
        'Naruto',
        'Naruto Shippuden',
        'Boruto: Naruto Next Generations',
        'The Last: A Movie',
      ]);
    });

    test('matches on the English title too', () {
      final state = _stateFor('attack on titan', [
        _item('Bleach'),
        _item('Shingeki no Kyojin', english: 'Attack on Titan'), // exact (en)
      ]);
      expect(_titles(state).first, 'Shingeki no Kyojin');
    });

    test('equal scores keep the source order', () {
      final state = _stateFor('one piece', [
        _item('One Piece: Stampede'), // prefix
        _item('One Piece Film: Red'), // prefix — same score
      ]);
      // Both prefix-match (80); source order is preserved on the tie.
      expect(_titles(state), ['One Piece: Stampede', 'One Piece Film: Red']);
    });

    test('empty query leaves the order untouched', () {
      final state = _stateFor('', [
        _item('Zeta'),
        _item('Alpha'),
      ]);
      expect(_titles(state), ['Zeta', 'Alpha']);
    });
  });
}
