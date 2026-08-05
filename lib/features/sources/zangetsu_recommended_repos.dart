/// Curated Zangetsu (JS-provider) repo entries for the "Add repo" dialog —
/// mirrors [kRecommendedAniyomiRepos] (aniyomi_recommended_repos.dart) for
/// the JS-provider ecosystem. Nothing here is pre-installed or added on
/// launch; it's a suggestion inside the add-repo dialog only. Tapping an
/// entry fills in the URL field — the user still presses "Add" themselves,
/// same as pasting a URL by hand.
const List<({String name, String desc, String url})>
kRecommendedZangetsuRepos = [
  (
    name: "Spyou's Sozo Providers",
    desc:
        'Recommended manga & novel pack — Mangapill, MangaKatana, '
        'Mangakakalot, WeebCentral (manga) + FreeWebNovel, NovelBin, '
        'Project Gutenberg (novels)',
    url:
        'https://raw.githubusercontent.com/Spyou/sozoread-providers/main/index.json',
  ),
];
