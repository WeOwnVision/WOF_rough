import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';
import 'pages/web_chat_page.dart';
import 'pages/web_discover_page.dart';
import 'pages/web_feed_page.dart';
import 'pages/web_home_page.dart';
import 'pages/web_profile_page.dart';
import 'widgets/web_ui.dart';

/// Web (PC) arayüzünün iskeleti: solda menü, üstte bar, sağda sayfa.
class WebShell extends StatelessWidget {
  const WebShell({super.key});

  /// Bu ölçülerin altında sayfa küçülmez, kaydırılır.
  static const double minWidth = 1200;
  static const double minHeight = 700;

  static const pages = <_WebPage>[
    _WebPage(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
      title: 'Home',
    ),
    _WebPage(
      icon: Icons.view_carousel_outlined,
      activeIcon: Icons.view_carousel,
      label: 'WOF Feed',
      title: 'WOF Feed',
      subtitle: 'Swipe and react',
    ),
    _WebPage(
      icon: Icons.forum_outlined,
      activeIcon: Icons.forum,
      label: 'WAI Assistant',
      title: 'WAI',
      subtitle: 'Your news assistant',
    ),
    _WebPage(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore,
      label: 'Discover',
      title: 'Discover',
      subtitle: 'Search & explore news',
    ),
    _WebPage(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile & Settings',
      title: 'Profile & Settings',
      subtitle: 'Your account and preferences',
    ),
  ];

  Widget _pageBody(int index) => switch (index) {
    AppState.navFeed => const WebFeedPage(),
    AppState.navChat => const WebChatPage(),
    AppState.navDiscover => const WebDiscoverPage(),
    AppState.navProfile => const WebProfilePage(),
    _ => const WebHomePage(),
  };

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, c) {
          final width = math.max(c.maxWidth, minWidth);
          final height = math.max(c.maxHeight, minHeight);

          Widget shell = ListenableBuilder(
            listenable: state,
            builder: (context, _) {
              final index = state.navIndex;
              final page = pages[index];
              return Row(
                children: [
                  _SideNav(currentIndex: index, onTap: state.goTo),
                  Expanded(
                    child: Column(
                      children: [
                        _TopBar(
                          title: page.title,
                          subtitle: page.subtitle ?? greetingLine(),
                          showSearch: index != AppState.navDiscover,
                        ),
                        if (state.isOffline) const _OfflineBanner(),
                        Expanded(
                          // Okuma metinleri Ayarlar'daki yazı boyutunu izler.
                          child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              textScaler: TextScaler.linear(state.fontScale),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: KeyedSubtree(
                                key: ValueKey(index),
                                child: _pageBody(index),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );

          shell = SizedBox(width: width, height: height, child: shell);

          // Pencere PC ölçülerinden küçükse düzeni bozmak yerine kaydır.
          if (c.maxWidth < minWidth) {
            shell = SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: shell,
            );
          }
          if (c.maxHeight < minHeight) {
            shell = SingleChildScrollView(child: shell);
          }
          return shell;
        },
      ),
    );
  }
}

class _WebPage {
  const _WebPage({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String title;

  /// Boşsa günün selamlaması gösterilir.
  final String? subtitle;
}

// ---------------------------------------------------------------------------
// Sol menü
// ---------------------------------------------------------------------------
class _SideNav extends StatelessWidget {
  const _SideNav({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 264,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 30, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const WofLogo(fontSize: 28),
                const SizedBox(height: 2),
                Text(
                  'World of Feeds',
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          const Padding(
            padding: EdgeInsets.only(left: 14, bottom: 10),
            child: OverlineLabel('Menu'),
          ),
          for (var i = 0; i < WebShell.pages.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _SideNavTile(
                page: WebShell.pages[i],
                selected: i == currentIndex,
                glow: i == AppState.navChat,
                onTap: () => onTap(i),
              ),
            ),
          const Spacer(),
          _WaiPromo(onTap: () => onTap(AppState.navChat)),
          const SizedBox(height: 16),
          _UserTile(onTap: () => onTap(AppState.navProfile)),
        ],
      ),
    );
  }
}

class _SideNavTile extends StatelessWidget {
  const _SideNavTile({
    required this.page,
    required this.selected,
    required this.glow,
    required this.onTap,
  });

  final _WebPage page;
  final bool selected;
  final bool glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered) {
        final color = selected
            ? AppColors.accentLight
            : (hovered ? AppColors.textPrimary : AppColors.iconMuted);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.14)
                : (hovered ? AppColors.surfaceAlt : Colors.transparent),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: glow && !selected
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.accent.withValues(alpha: 0.4),
                            AppColors.accent.withValues(alpha: 0.0),
                          ],
                        ),
                      )
                    : null,
                child: Icon(
                  selected ? page.activeIcon : page.icon,
                  size: 21,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                page.label,
                style: GoogleFonts.inter(
                  color: color,
                  fontSize: 14.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (selected) ...[
                const Spacer(),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.accentLight,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _WaiPromo extends StatelessWidget {
  const _WaiPromo({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accentDeep.withValues(alpha: 0.35),
            AppColors.quoteBg,
          ],
        ),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: AppColors.accentLight,
              ),
              const SizedBox(width: 6),
              Text(
                'Ask WAI',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Simplifies any story and explains its context and opposing '
            'views.',
            style: GoogleFonts.inter(
              color: AppColors.textBody,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: WebButton(label: 'Open chat', onTap: onTap),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: hovered ? AppColors.surfaceAlt : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            UserAvatar(size: 38, url: AppState.instance.user?.avatarUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppState.instance.user?.username ?? 'Reader',
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        size: 13,
                        color: AppColors.mint,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '14-day streak',
                        style: GoogleFonts.inter(
                          color: AppColors.mint,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.settings_outlined,
              size: 18,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Üst bar
// ---------------------------------------------------------------------------
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.showSearch,
  });

  final String title;
  final String subtitle;
  final bool showSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const GradientOrb(size: 40),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.playfairDisplay(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (showSearch) ...[
            const _TopSearchField(),
            const SizedBox(width: 14),
          ],
          const _NotificationsButton(),
          const SizedBox(width: 14),
          const _ProfileMenu(),
        ],
      ),
    );
  }
}

class _TopSearchField extends StatefulWidget {
  const _TopSearchField();

  @override
  State<_TopSearchField> createState() => _TopSearchFieldState();
}

class _TopSearchFieldState extends State<_TopSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    if (value.trim().isEmpty) return;
    AppState.instance.search(value);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      height: 46,
      child: TextField(
        controller: _controller,
        onSubmitted: _submit,
        cursorColor: AppColors.accentLight,
        style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search news, topics or sources…',
          hintStyle: GoogleFonts.inter(
            color: AppColors.textMuted,
            fontSize: 14,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.iconMuted,
            size: 20,
          ),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Center(
              widthFactor: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Enter',
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(23),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(23),
            borderSide: const BorderSide(color: AppColors.accent),
          ),
        ),
      ),
    );
  }
}

class _NotificationsButton extends StatelessWidget {
  const _NotificationsButton();

  static const _items = [
    (
      Icons.bolt_rounded,
      'Breaking',
      'Central banks announced their rate decision',
    ),
    (Icons.headphones_outlined, 'Audio bulletin ready', "Today's brief · 2:34"),
    (
      Icons.local_fire_department_rounded,
      'Reading streak',
      'You completed day 14!',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Notifications',
      offset: const Offset(0, 56),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      itemBuilder: (context) => [
        for (final (icon, title, body) in _items)
          PopupMenuItem<int>(
            height: 64,
            child: SizedBox(
              width: 300,
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 18, color: AppColors.accentLight),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: GoogleFonts.inter(
                            color: AppColors.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: AppColors.iconMuted,
              size: 22,
            ),
          ),
          Positioned(
            right: 11,
            top: 11,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.mint,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
      color: AppColors.accentDeep.withValues(alpha: 0.25),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.mint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Server is offline — showing cached articles. '
              'Live features like search and chat are unavailable.',
              style: GoogleFonts.inter(
                color: AppColors.textBody,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: () => AppState.instance.refreshFeed(),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accentLight,
              textStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu();

  @override
  Widget build(BuildContext context) {
    PopupMenuItem<int> item(
      int value,
      IconData icon,
      String label, {
      Color color = AppColors.textPrimary,
    }) => PopupMenuItem<int>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.inter(color: color, fontSize: 13.5)),
        ],
      ),
    );

    return PopupMenuButton<int>(
      tooltip: 'Account',
      offset: const Offset(0, 56),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      onSelected: (value) {
        if (value == 0) AppState.instance.goTo(AppState.navProfile);
        if (value == 1) AppState.instance.logout();
      },
      itemBuilder: (context) => [
        item(0, Icons.person_outline_rounded, 'Profile & Settings'),
        const PopupMenuDivider(),
        item(1, Icons.logout_rounded, 'Log out', color: AppColors.dislike),
      ],
      child: UserAvatar(size: 46, url: AppState.instance.user?.avatarUrl),
    );
  }
}
