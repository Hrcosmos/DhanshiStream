import 'package:flutter/foundation.dart';

/// True while an in-tab sub-page wants the shell's floating dock hidden — set
/// by the Settings screen when you drill into a section. The shell also gates
/// on the active tab, so this only hides the dock while that tab is showing.
final ValueNotifier<bool> dockHiddenBySection = ValueNotifier<bool>(false);
