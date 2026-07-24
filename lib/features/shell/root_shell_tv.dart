import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/provider/cloudstream_provider.dart';
import '../../core/provider/provider_manager.dart' show AniyomiManager;
import '../../core/provider/provider_registry.dart';
import '../../core/state/active_source_cubit.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_focusable.dart';
import '../auth/auth_cubit.dart';
import '../downloads/downloads_screen.dart';
import '../home/cubit/home_cubit.dart';
import '../schedule/schedule_screen.dart';
import 'root_shell.dart';
import 'tv_source_picker.dart';

/// Collapsed (icon-only) and expanded (labelled) drawer widths.
const double _kNavCollapsed = 104;
const double _kNavExpanded = 340;

/// TV-only navigation shell: a collapsing left drawer over an [IndexedStack].
///
/// Rendered when [AppMode.isTv] is true (gated in [RootShell.build]). The phone
/// [RootShell] and its [NavigationBar] are completely unchanged.
///
/// The drawer overlays the page area on the left. It shows a slim icon rail by
/// default and pops open to a full labelled drawer whenever focus is in the
/// rail zone — Apple-TV style. Pages reuse [buildShellPages] from [RootShell]
/// (one source of truth); all cubits are GetIt singletons so nothing is
/// re-instantiated.
class RootShellTv extends StatefulWidget {
  const RootShellTv({super.key});

  @override
  State<RootShellTv> createState() => _RootShellTvState();
}

/// One entry in the TV nav.
class _RailItem {
  const _RailItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Nav item definitions (label + icons). Order matches [_RootShellTvState._pages].
const List<_RailItem> _kRailItems = [
  _RailItem(label: 'Home', icon: Icons.home_outlined, selectedIcon: Icons.home_filled),
  _RailItem(label: 'Search', icon: Icons.search, selectedIcon: Icons.search),
  _RailItem(label: 'My List', icon: Icons.bookmark_outline, selectedIcon: Icons.bookmark),
  _RailItem(label: 'Downloads', icon: Icons.download_outlined, selectedIcon: Icons.download),
  _RailItem(label: 'Schedule', icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month),
  _RailItem(label: 'Settings', icon: Icons.settings_outlined, selectedIcon: Icons.settings),
];

class _RootShellTvState extends State<RootShellTv> {
  static const int _searchRailItem = 1;

  int _index = 0;
  bool _navOpen = false; // drawer expanded ⇔ focus is in the rail zone
  DateTime? _lastBackPress;

  final ValueNotifier<int> _searchFocusSignal = ValueNotifier<int>(0);

  // ── D-pad bridge: rail ↔ content (unchanged from the original) ────────────
  final FocusScopeNode _railScope = FocusScopeNode(debugLabel: 'tv-rail-scope');
  final FocusScopeNode _contentScope =
      FocusScopeNode(debugLabel: 'tv-content-scope');

  @override
  void initState() {
    super.initState();
    // Guarantee a visible cursor on the empty/no-provider Home where the content
    // zone has no focusable leaf — otherwise autofocus can settle on the bare
    // scope node, which renders nothing. Only acts when nothing real is focused.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary == null || primary is FocusScopeNode) {
        _railScope.traversalDescendants
            .where((n) => n.canRequestFocus)
            .firstOrNull
            ?.requestFocus();
      }
    });
  }

  KeyEventResult _onRailKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      final lastFocused = _contentScope.focusedChild;
      if (lastFocused != null && lastFocused.canRequestFocus) {
        lastFocused.requestFocus();
      } else {
        _contentScope.traversalDescendants
            .where((n) => n.canRequestFocus)
            .firstOrNull
            ?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onContentKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      final moved = FocusManager.instance.primaryFocus
              ?.focusInDirection(TraversalDirection.left) ??
          false;
      if (!moved) _railScope.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _searchFocusSignal.dispose();
    _railScope.dispose();
    _contentScope.dispose();
    super.dispose();
  }

  /// Display name for a source id (mirrors SourceSwitcher._label).
  String _sourceLabel(String id) {
    if (id.startsWith('cs:')) {
      try {
        final name = sl<CloudStreamManager>().get(id)?.displayName;
        if (name != null && name.isNotEmpty) return 'CS · $name';
      } catch (_) {}
      return id;
    }
    if (id.startsWith('ani:')) {
      try {
        final name = sl<AniyomiManager>().get(id)?.displayName;
        if (name != null && name.isNotEmpty) return 'Ani · $name';
      } catch (_) {}
      return id;
    }
    try {
      final entry = sl<ProviderRegistry>().entryFor(id);
      if (entry != null && entry.displayName.isNotEmpty) return entry.displayName;
      return entry?.name ?? id;
    } catch (_) {
      return id;
    }
  }

  void _onItemSelected(int i) {
    setState(() => _index = i);
    if (i == _searchRailItem) _searchFocusSignal.value++;
  }

  void _handlePopInvoked(bool didPop, dynamic result) {
    if (didPop) return;
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!).inSeconds < 2) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  List<Widget> get _pages {
    final shared = buildShellPages(_searchFocusSignal);
    return [
      ...shared.sublist(0, 3), // Home, Search, My List
      const DownloadsScreen(),
      const ScheduleScreen(),
      shared.last, // Settings
    ];
  }

  // ── Drawer pieces ─────────────────────────────────────────────────────────

  /// Brand: the square app icon always, with the wordmark revealed when open.
  Widget _brand() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 10),
      child: Row(
        children: [
          Image.asset('assets/icon/app_icon.png', width: 34, height: 34),
          const SizedBox(width: 14),
          Expanded(
            child: AnimatedOpacity(
              opacity: _navOpen ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Image.asset(
                'assets/icon/wordmark.png',
                key: const ValueKey('tv-rail-wordmark'),
                height: 22,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Source indicator — unchanged behaviour (opens [TvSourcePicker]); label
  /// fades in when open.
  Widget _sourceIndicator() {
    return BlocBuilder<ActiveSourceCubit, String>(
      builder: (context, sourceId) {
        return TvFocusable(
          key: const ValueKey('tv-source-indicator'),
          variant: TvFocusVariant.pill,
          onTap: () {
            showDialog<void>(
              context: context,
              barrierColor: Colors.black54,
              builder: (_) => BlocProvider<ActiveSourceCubit>.value(
                value: context.read<ActiveSourceCubit>(),
                child: TvSourcePicker(currentId: sourceId),
              ),
            );
          },
          builder: (focused) {
            final fg = focused ? Colors.black : AppColors.textSecondary;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.swap_horiz, color: fg, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedOpacity(
                      opacity: _navOpen ? 1 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Text(
                        _sourceLabel(sourceId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _navItem(int i, _RailItem item) {
    final selected = _index == i;
    return TvFocusable(
      variant: TvFocusVariant.pill,
      onTap: () => _onItemSelected(i),
      builder: (focused) {
        final Color fg = focused
            ? Colors.black
            : (selected ? AppColors.textPrimary : AppColors.textTertiary);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(
            children: [
              Icon(
                selected ? item.selectedIcon : item.icon,
                color: focused
                    ? Colors.black
                    : (selected ? AppColors.accent : AppColors.textTertiary),
                size: 26,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: AnimatedOpacity(
                  opacity: _navOpen ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      color: fg,
                      fontSize: 18,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final auth = context.read<AuthCubit>();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogCtx) => Align(
        alignment: const Alignment(-0.72, 0.55), // near the avatar (lower-left)
        child: TvLogoutSheet(
          onConfirm: () {
            Navigator.of(dialogCtx).pop();
            auth.logout();
          },
          onCancel: () => Navigator.of(dialogCtx).pop(),
        ),
      ),
    );
  }

  Widget _avatarBlock() {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, auth) {
        if (!auth.isLoggedIn) return const SizedBox.shrink();
        final name = auth.displayName;
        final avatar = auth.avatarUrl;
        final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
        return TvFocusable(
          key: const ValueKey('tv-nav-avatar'),
          variant: TvFocusVariant.pill,
          onTap: _confirmLogout,
          builder: (focused) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.surface2,
                  backgroundImage: (avatar != null && avatar.isNotEmpty)
                      ? NetworkImage(avatar)
                      : null,
                  child: (avatar == null || avatar.isEmpty)
                      ? Text(initial,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800))
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: AnimatedOpacity(
                    opacity: _navOpen ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: focused ? Colors.black : AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        Text('Signed in',
                            maxLines: 1,
                            style: TextStyle(
                                color: focused ? const Color(0xFF555555) : AppColors.textTertiary,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The full-width (expanded) drawer content column. It's ALWAYS laid out at
  /// [_kNavExpanded] wide inside an OverflowBox and clipped to the animated
  /// width, so collapsing/expanding just reveals more of the same column — the
  /// labels fade via their own AnimatedOpacity.
  Widget _railColumn() {
    return SafeArea(
      right: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _brand(),
          const SizedBox(height: 6),
          _sourceIndicator(),
          const SizedBox(height: 6),
          const Divider(height: 1, color: AppColors.hairline, indent: 16, endIndent: 16),
          const SizedBox(height: 8),
          for (var i = 0; i < _kRailItems.length; i++) _navItem(i, _kRailItems[i]),
          const Spacer(),
          _avatarBlock(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handlePopInvoked,
      child: BlocListener<ActiveSourceCubit, String>(
        listenWhen: (prev, curr) => prev != curr,
        listener: (context, _) => sl<HomeCubit>().load(reset: true),
        child: Scaffold(
          backgroundColor: AppColors.bg,
          body: Stack(
            children: [
              // ── Page area (fills the width; inset left by the collapsed rail
              //    so content is never hidden behind it; the expanded drawer
              //    overlays this inset — Apple-TV style). ────────────────────
              Positioned.fill(
                left: _kNavCollapsed,
                child: Focus(
                  focusNode: _contentScope,
                  onKeyEvent: _onContentKey,
                  child: Padding(
                    // Overscan-safe inset (TVs crop edges). Left handled by the
                    // rail inset above.
                    padding: const EdgeInsets.fromLTRB(0, 24, 24, 16),
                    child: IndexedStack(
                      index: _index,
                      children: [
                        for (var i = 0; i < pages.length; i++)
                          ExcludeFocus(excluding: i != _index, child: pages[i]),
                      ],
                    ),
                  ),
                ),
              ),
              // ── Drawer overlay (icon rail ⇄ full drawer) ──────────────────
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                child: Focus(
                  focusNode: _railScope,
                  onKeyEvent: _onRailKey,
                  // Expand while focus is anywhere in the rail zone; collapse
                  // when it leaves (i.e. content is focused).
                  onFocusChange: (hasFocus) {
                    if (hasFocus != _navOpen) setState(() => _navOpen = hasFocus);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    width: _navOpen ? _kNavExpanded : _kNavCollapsed,
                    margin: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF23242B), Color(0xFF141519)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: OverflowBox(
                      minWidth: _kNavExpanded,
                      maxWidth: _kNavExpanded,
                      alignment: Alignment.centerLeft,
                      child: SizedBox(width: _kNavExpanded, child: _railColumn()),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact "Log out?" confirm card shown from the nav avatar. Kept top-level so
/// it can be widget-tested without the shell/DI. The "Log out" action
/// autofocuses; Back dismisses the hosting dialog.
class TvLogoutSheet extends StatelessWidget {
  const TvLogoutSheet({super.key, required this.onConfirm, this.onCancel});
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0F13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TvFocusable(
            autofocus: true,
            variant: TvFocusVariant.pill,
            onTap: onConfirm,
            builder: (focused) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              child: Row(
                children: [
                  Icon(Icons.logout_rounded,
                      size: 20,
                      color: focused ? Colors.black : const Color(0xFFFF5C5C)),
                  const SizedBox(width: 12),
                  Text('Log out',
                      style: TextStyle(
                        color: focused ? Colors.black : const Color(0xFFFF5C5C),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
          ),
          TvFocusable(
            variant: TvFocusVariant.pill,
            onTap: onCancel ?? () {},
            builder: (focused) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              child: Row(
                children: [
                  Icon(Icons.close_rounded,
                      size: 20,
                      color: focused ? Colors.black : AppColors.textSecondary),
                  const SizedBox(width: 12),
                  Text('Cancel',
                      style: TextStyle(
                        color: focused ? Colors.black : AppColors.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
