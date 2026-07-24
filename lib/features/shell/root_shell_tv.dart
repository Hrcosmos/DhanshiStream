import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/provider/cloudstream_provider.dart';
import '../../core/provider/provider_manager.dart' show AniyomiManager;
import '../../core/provider/provider_registry.dart';
import '../../core/state/active_source_cubit.dart';
import '../../core/theme/app_colors.dart';
import '../../core/tv/tv_focusable.dart';
import '../auth/auth_cubit.dart';
import '../auth/auth_screens_tv.dart';
import '../downloads/downloads_screen.dart';
import '../home/cubit/home_cubit.dart';
import '../schedule/schedule_screen.dart';
import 'root_shell.dart';
import 'tv_source_picker.dart';

/// Height of the top navigation bar (Netflix-style).
const double _kNavHeight = 74;

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
  DateTime? _lastBackPress;

  final ValueNotifier<int> _searchFocusSignal = ValueNotifier<int>(0);

  // ── D-pad bridge: top nav ↕ content ───────────────────────────────────────
  final FocusScopeNode _railScope = FocusScopeNode(debugLabel: 'tv-nav-scope');
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

  // DOWN from the top nav → drop into the content area.
  KeyEventResult _onRailKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
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

  // UP from content: move up within content first; only jump to the top nav
  // when already at the top edge.
  KeyEventResult _onContentKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final moved = FocusManager.instance.primaryFocus
              ?.focusInDirection(TraversalDirection.up) ??
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

  /// Zangetsu wordmark at the far left of the top nav (width-capped so the ornate
  /// lockup doesn't crowd the tabs).
  Widget _brand() {
    return SizedBox(
      width: 132,
      child: Image.asset(
        'assets/icon/wordmark.png',
        key: const ValueKey('tv-rail-wordmark'),
        height: 20,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
      ),
    );
  }

  /// Source switch pill on the right of the top nav (opens [TvSourcePicker]).
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
            final label = _sourceLabel(sourceId);
            final clean = label.replaceFirst(RegExp(r'^(CS|Ani) · '), '');
            final fg = focused ? Colors.black : AppColors.textSecondary;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_horiz_rounded, size: 20, color: fg),
                  const SizedBox(width: 8),
                  Text(
                    clean,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
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

  /// One text tab in the top nav. Active page = white/bold, others grey; the
  /// focused tab gets the white pill.
  Widget _navTab(int i, _RailItem item) {
    final selected = _index == i;
    return TvFocusable(
      variant: TvFocusVariant.pill,
      onTap: () => _onItemSelected(i),
      builder: (focused) {
        final Color fg = focused
            ? Colors.black
            : (selected ? AppColors.textPrimary : AppColors.textTertiary);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Text(
            item.label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: fg,
              fontSize: 16,
              fontWeight: (selected || focused) ? FontWeight.w700 : FontWeight.w500,
            ),
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
        alignment: const Alignment(0.9, -0.55), // near the profile (top-right)
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

  /// Profile avatar on the far right of the top nav. Signed in → avatar (OK
  /// opens the log-out popup); signed out → a placeholder (OK opens login).
  Widget _avatarBlock() {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, auth) {
        final loggedIn = auth.isLoggedIn;
        final name = loggedIn ? auth.displayName : '';
        final avatar = auth.avatarUrl;
        final initial =
            (loggedIn && name.isNotEmpty) ? name[0].toUpperCase() : null;
        return TvFocusable(
          key: const ValueKey('tv-nav-avatar'),
          variant: TvFocusVariant.pill,
          onTap: () {
            if (loggedIn) {
              _confirmLogout();
            } else {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LoginScreenTv()),
              );
            }
          },
          builder: (focused) => Padding(
            padding: const EdgeInsets.all(6),
            child: CircleAvatar(
              radius: 19,
              backgroundColor: focused ? Colors.white : AppColors.surface2,
              backgroundImage: (avatar != null && avatar.isNotEmpty)
                  ? NetworkImage(avatar)
                  : null,
              child: (avatar == null || avatar.isEmpty)
                  ? (initial != null
                      ? Text(initial,
                          style: TextStyle(
                              color: focused ? Colors.black : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800))
                      : Icon(Icons.person_rounded,
                          color:
                              focused ? Colors.black : AppColors.textSecondary,
                          size: 24))
                  : null,
            ),
          ),
        );
      },
    );
  }

  /// The Netflix-style top navigation bar: brand · tabs · source · profile.
  Widget _topNav() {
    return Container(
      height: _kNavHeight,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xE6000000), Color(0x00000000)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            _brand(),
            const SizedBox(width: 18),
            // Tabs take the middle and scroll if the panel is ever too narrow,
            // so the bar never overflows (and pushes source/profile to the far
            // right on a wide TV).
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < _kRailItems.length; i++)
                      _navTab(i, _kRailItems[i]),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _sourceIndicator(),
            const SizedBox(width: 6),
            _avatarBlock(),
          ],
        ),
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
              // Content fills the screen; a top inset keeps every page clear of
              // the nav bar. UP from the top row jumps to the nav (edge-gated).
              Positioned.fill(
                child: Focus(
                  focusNode: _contentScope,
                  onKeyEvent: _onContentKey,
                  child: Padding(
                    padding: const EdgeInsets.only(top: _kNavHeight),
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
              // Top nav overlay. DOWN from here drops into content.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Focus(
                  focusNode: _railScope,
                  onKeyEvent: _onRailKey,
                  child: _topNav(),
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
