import '../aniyomi/aniyomi_repo.dart';

/// One available update for an installed Mihon manga extension package.
///
/// Structural twin of [AniyomiUpdate] (`lib/core/aniyomi/aniyomi_update.dart`) —
/// duplicated per spec Decision 3 rather than shared. [entry] is typed
/// [AniyomiRepoEntry] because Mihon's repo index is byte-identical in shape to
/// Aniyomi's, so `AniyomiRepo`/`AniyomiRepoEntry` are reused unchanged rather
/// than re-derived (spec, verbatim). Comparison is by integer [availableCode]
/// vs the installed versionCode; [availableVersion] is the human versionName
/// shown on the Update button.
class MihonUpdate {
  const MihonUpdate({
    required this.pkg,
    required this.name,
    required this.installedCode,
    required this.availableCode,
    required this.availableVersion,
    required this.entry,
  });

  final String pkg;
  final String name;
  final int installedCode;
  final int availableCode;
  final String availableVersion;
  final AniyomiRepoEntry entry;
}
