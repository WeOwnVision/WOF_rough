import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/api_models.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import '../widgets/web_ui.dart';

/// Profil (solda) ve ayarlar (sağda) sayfası.
class WebProfilePage extends StatelessWidget {
  const WebProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 32, 40, 56),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 420,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProfileCard(state: state),
                      const SizedBox(height: 20),
                      _LibraryTabs(state: state),
                    ],
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(child: _Settings(state: state)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profil kartı
// ---------------------------------------------------------------------------
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 26),
      gradient: RadialGradient(
        center: const Alignment(0, -0.6),
        radius: 1.0,
        colors: [
          AppColors.accentDeep.withValues(alpha: 0.30),
          AppColors.surface,
        ],
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      AppColors.mint,
                      AppColors.accentLight,
                      AppColors.accentDeep,
                      AppColors.mint,
                    ],
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: UserAvatar(size: 96, url: state.user?.avatarUrl),
                ),
              ),
              Positioned(
                right: 2,
                bottom: 2,
                child: Tooltip(
                  message: 'Edit profile',
                  child: Hoverable(
                    onTap: () {},
                    builder: (context, hovered) => Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: hovered
                            ? AppColors.textPrimary
                            : AppColors.accentLight,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 3),
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        size: 14,
                        color: onAccent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            state.user?.username ?? 'Reader',
            style: GoogleFonts.playfairDisplay(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${state.saved.length} saved  ·  '
            '${state.liked.length} liked',
            style: GoogleFonts.inter(color: AppColors.textBody, fontSize: 13.5),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.mint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 15,
                  color: AppColors.mint,
                ),
                const SizedBox(width: 6),
                Text(
                  '14-DAY READING STREAK',
                  style: GoogleFonts.inter(
                    color: AppColors.mint,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kaydedilenler / Beğenilenler
// ---------------------------------------------------------------------------
class _LibraryTabs extends StatefulWidget {
  const _LibraryTabs({required this.state});

  final AppState state;

  @override
  State<_LibraryTabs> createState() => _LibraryTabsState();
}

class _LibraryTabsState extends State<_LibraryTabs> {
  bool _showSaved = true;

  @override
  void initState() {
    super.initState();
    // Önceki oturumlardan kalan kayıtlar önbellekte olmayabilir.
    widget.state.ensureArticles({...widget.state.saved, ...widget.state.liked});
  }

  @override
  Widget build(BuildContext context) {
    final List<Article> items = _showSaved
        ? widget.state.savedArticles
        : widget.state.likedArticles;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              _tab(
                label: 'Saved',
                icon: Icons.bookmark_rounded,
                selected: _showSaved,
                onTap: () => setState(() => _showSaved = true),
              ),
              _tab(
                label: 'Liked',
                icon: Icons.favorite_border_rounded,
                selected: !_showSaved,
                onTap: () => setState(() => _showSaved = false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              _showSaved ? 'No saved stories.' : 'No liked stories.',
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 13.5,
              ),
            ),
          )
        else
          for (final n in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NewsListTile(n, showBookmark: _showSaved),
            ),
      ],
    );
  }

  Widget _tab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentLight
                : (hovered ? AppColors.surfaceAlt : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? onAccent : AppColors.textBody,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: selected ? onAccent : AppColors.textBody,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ayarlar
// ---------------------------------------------------------------------------
class _Settings extends StatelessWidget {
  const _Settings({required this.state});

  final AppState state;

  static final _fontSizes = <double, String>{
    0.875: 'Small (14px)',
    1.0: 'Normal (16px)',
    1.125: 'Large (18px)',
    1.25: 'Extra large (20px)',
  };

  @override
  Widget build(BuildContext context) {
    final interests = state.interests.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Row(
            children: [
              const OverlineLabel('Settings'),
              const Spacer(),
              Text(
                'v2.4 Pro',
                style: GoogleFonts.inter(
                  color: AppColors.accentLight,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _SettingRow(
                icon: Icons.dark_mode_outlined,
                title: 'Theme',
                subtitle: 'Appearance mode',
                trailing: _Segmented<ThemeChoice>(
                  value: state.theme,
                  options: const {
                    ThemeChoice.light: 'Light',
                    ThemeChoice.dark: 'Dark',
                    ThemeChoice.system: 'System',
                  },
                  onChanged: state.setTheme,
                ),
              ),
              _SettingRow(
                icon: Icons.text_fields_rounded,
                title: 'Text Size',
                subtitle: 'Reading font size',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _fontSizes[state.fontScale] ?? 'Custom',
                    style: GoogleFonts.inter(
                      color: AppColors.textBody,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                below: Row(
                  children: [
                    Text(
                      'Aa',
                      style: GoogleFonts.playfairDisplay(
                        color: AppColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppColors.accentLight,
                          inactiveTrackColor: AppColors.barInactive,
                          thumbColor: AppColors.accentLight,
                          overlayColor: AppColors.accent.withValues(
                            alpha: 0.15,
                          ),
                          trackHeight: 4,
                          showValueIndicator: ShowValueIndicator.never,
                        ),
                        child: Slider(
                          value: state.fontScale,
                          min: 0.875,
                          max: 1.25,
                          divisions: 3,
                          onChanged: state.setFontScale,
                        ),
                      ),
                    ),
                    Text(
                      'Aa',
                      style: GoogleFonts.playfairDisplay(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                      ),
                    ),
                  ],
                ),
              ),
              _SettingRow(
                icon: Icons.graphic_eq_rounded,
                title: 'Audio Brief Speed',
                subtitle: 'WAI narration playback',
                trailing: _Segmented<double>(
                  value: state.audioSpeed,
                  options: {1.0: '1x', 1.25: '1.25x', 1.5: '1.5x', 2.0: '2x'},
                  onChanged: state.setAudioSpeed,
                ),
              ),
              _SettingRow(
                icon: Icons.notifications_active_outlined,
                title: 'Notifications',
                subtitle: 'Key bulletins & breaking news',
                trailing: Switch(
                  value: state.notifications,
                  onChanged: state.setNotifications,
                  thumbColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected)
                        ? AppColors.accentDeep
                        : AppColors.textMuted,
                  ),
                  trackColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected)
                        ? AppColors.accentLight
                        : AppColors.surfaceAlt,
                  ),
                  trackOutlineColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                ),
              ),
              _SettingRow(
                icon: Icons.interests_outlined,
                title: 'Interests',
                subtitle: 'Shapes Feed and Discover recommendations',
                onTap: () => _editInterests(context),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
                below: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final i in interests.take(4)) _Tag(i),
                    if (interests.length > 4)
                      _Tag('+${interests.length - 4}', muted: true),
                    if (interests.isEmpty)
                      Text(
                        'No interests selected yet.',
                        style: GoogleFonts.inter(
                          color: AppColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                  ],
                ),
              ),
              _SettingRow(
                icon: Icons.language_rounded,
                title: 'Language',
                subtitle: 'Interface language',
                last: true,
                trailing: PopupMenuButton<String>(
                  tooltip: 'Choose language',
                  initialValue: state.language,
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  onSelected: state.setLanguage,
                  itemBuilder: (context) => [
                    for (final l in const ['English', 'Türkçe', 'Deutsch'])
                      PopupMenuItem(
                        value: l,
                        child: Text(
                          l,
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimary,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.language,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Icon(
                        Icons.expand_more_rounded,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: WebButton(
            label: 'Log out',
            icon: Icons.logout_rounded,
            primary: false,
            color: AppColors.dislike,
            onTap: state.logout,
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            'W.O.F Editorial Systems © ${DateTime.now().year} · '
            'Privacy Policy',
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _editInterests(BuildContext context) {
    final all = {...macroCategories, ...state.interests}.toList();
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ListenableBuilder(
              listenable: state,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Interests',
                    style: GoogleFonts.playfairDisplay(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Topics you pick are prioritized in your Feed and '
                    'Discover recommendations.',
                    style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final i in all)
                        PillButton(
                          label: i,
                          selected: state.interests.contains(i),
                          showCheck: true,
                          onTap: () => state.toggleInterest(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Align(
                    alignment: Alignment.centerRight,
                    child: WebButton(
                      label: 'Done',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.below,
    this.onTap,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Widget? below;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 20, color: AppColors.iconMuted),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing,
            ],
          ),
          if (below != null) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 58),
              child: Align(alignment: Alignment.centerLeft, child: below),
            ),
          ],
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: onTap == null
          ? content
          : Hoverable(
              onTap: onTap,
              builder: (context, hovered) => ColoredBox(
                color: hovered
                    ? AppColors.surfaceAlt.withValues(alpha: 0.5)
                    : Colors.transparent,
                child: content,
              ),
            ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in options.entries)
            Hoverable(
              onTap: () => onChanged(e.key),
              builder: (context, hovered) {
                final selected = e.key == value;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.accentLight
                        : (hovered ? AppColors.surfaceAlt : null),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    e.value,
                    style: GoogleFonts.inter(
                      color: selected ? onAccent : AppColors.textBody,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: muted
            ? AppColors.surfaceAlt
            : AppColors.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: muted ? AppColors.textMuted : AppColors.accentLight,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
