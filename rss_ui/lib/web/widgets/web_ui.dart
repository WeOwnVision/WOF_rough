import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/api_models.dart';
import '../../models/article_ui.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import 'article_dialog.dart';

/// Web sayfalarında paylaşılan bileşenler.

/// Fare üzerine gelince değişen, tıklanabilir alan.
class Hoverable extends StatefulWidget {
  const Hoverable({super.key, required this.builder, this.onTap});

  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.builder(context, _hovered),
      ),
    );
  }
}

/// Kenarlıklı koyu panel.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? AppColors.surface : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// Bölüm başlığı: solda nane renkli çubuk, sağda isteğe bağlı eylem.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.mint,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: GoogleFonts.playfairDisplay(
            color: AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// Küçük, büyük harfli etiket ("AYARLAR", "ETİKETLER").
class OverlineLabel extends StatelessWidget {
  const OverlineLabel(this.text, {super.key, this.color = AppColors.textMuted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: GoogleFonts.inter(
      color: color,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
    ),
  );
}

/// Metin bağlantısı görünümünde düğme ("Tümünü gör ›").
class LinkButton extends StatelessWidget {
  const LinkButton(this.label, {super.key, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: AppColors.accentLight),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              color: hovered ? AppColors.textPrimary : AppColors.accentLight,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (icon == null)
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: hovered ? AppColors.textPrimary : AppColors.accentLight,
            ),
        ],
      ),
    );
  }
}

/// Kategoriye göre rozet rengi.
Color categoryColor(String category) => switch (category) {
  'Tech' || 'AI' => AppColors.accent,
  'Finance' || 'Hardware' => const Color(0xFF7DD3FC),
  'Science' || 'Space' => const Color(0xFFFBBF24),
  'Health' => AppColors.mint,
  'Sports' || 'Gaming' => const Color(0xFFF49A8A),
  _ => AppColors.iconMuted,
};

/// Görsel üzerine yerleşen kategori rozeti.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key});

  final String category;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        category,
        style: GoogleFonts.inter(
          color: const Color(0xFF16121F),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

<<<<<<< HEAD
=======
/// Kişisel akıştaki uygunluk puanı; tarih sıralı (fallback) akışta sunucu
/// herkese sabit 50 verdiği için gösterilmez.
int? matchScore(Article a) =>
    AppState.instance.feedIsFallback ? null : a.personalScore;

/// "76% match" rozeti (görsel üzerinde).
class MatchBadge extends StatelessWidget {
  const MatchBadge(this.score, {super.key, this.fontSize = 12});

  final int score;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          'How well this story fits your interests: topics, category, '
          'stories you liked and freshness',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xCC1A1A1F),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: fontSize + 2,
              color: AppColors.mint,
            ),
            const SizedBox(width: 5),
            Text(
              '$score% match',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
/// Kaydet düğmesi; durumu [AppState]'ten okur.
class BookmarkButton extends StatelessWidget {
  const BookmarkButton(this.news, {super.key, this.size = 20});

  final Article news;
  final double size;

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final saved = state.isSaved(news.id);
        return Tooltip(
          message: saved ? 'Remove from saved' : 'Save',
          child: Hoverable(
            onTap: () => state.toggleSaved(news.id),
            builder: (context, hovered) => Icon(
              saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              size: size,
              color: saved
                  ? AppColors.accentLight
                  : (hovered ? AppColors.textPrimary : AppColors.textMuted),
            ),
          ),
        );
      },
    );
  }
}

/// Izgara içindeki haber kartı (Keşfet, Ana Sayfa).
class NewsGridCard extends StatelessWidget {
  const NewsGridCard(this.news, {super.key});

  final Article news;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: () => showArticleDialog(context, news),
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(0, hovered ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: hovered ? AppColors.surfaceAlt : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hovered
                ? AppColors.accent.withValues(alpha: 0.45)
                : AppColors.border,
          ),
          boxShadow: hovered
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedScale(
                    duration: const Duration(milliseconds: 300),
                    scale: hovered ? 1.05 : 1.0,
                    child: Image.asset(news.image, fit: BoxFit.cover),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: CategoryBadge(news.category),
                  ),
<<<<<<< HEAD
=======
                  if (matchScore(news) case final score?)
                    Positioned(right: 12, top: 12, child: MatchBadge(score)),
>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 48,
                    child: Text(
                      news.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.playfairDisplay(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: Text(
                      news.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.sourceSerif4(
                        color: AppColors.textBody,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sourceLine(news),
                          style: GoogleFonts.inter(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      BookmarkButton(news, size: 19),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yatay haber satırı (Kaydedilenler, Sıradaki listeleri).
class NewsListTile extends StatelessWidget {
  const NewsListTile(
    this.news, {
    super.key,
    this.thumbSize = 72,
    this.showBookmark = true,
  });

  final Article news;
  final double thumbSize;
  final bool showBookmark;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: () => showArticleDialog(context, news),
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: hovered ? AppColors.surfaceAlt : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                news.image,
                width: thumbSize,
                height: thumbSize,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OverlineLabel(news.category, color: AppColors.mint),
                  const SizedBox(height: 4),
                  Text(
                    news.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.playfairDisplay(
                      color: AppColors.textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sourceLine(news),
                    style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (showBookmark) ...[
              const SizedBox(width: 10),
              BookmarkButton(news),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hap biçimli seçim düğmesi (etiketler, segmentler).
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showCheck = false,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showCheck;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 12 : 16,
          vertical: dense ? 6 : 9,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentLight
              : (hovered ? AppColors.surfaceAlt : AppColors.surface),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accentLight : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected && showCheck) ...[
              const Icon(Icons.check_rounded, size: 15, color: onAccent),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                color: selected ? onAccent : AppColors.textBody,
                fontSize: dense ? 12.5 : 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Açık mor zemin üzerindeki koyu metin rengi.
const onAccent = Color(0xFF2E1F66);

/// Birincil (dolu) ve ikincil (çerçeveli) web düğmesi.
class WebButton extends StatelessWidget {
  const WebButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = true,
    this.color,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool primary;

  /// İkincil düğmede metin rengi.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? onAccent : (color ?? AppColors.textPrimary);
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: primary
              ? (hovered ? AppColors.textPrimary : AppColors.accentLight)
              : (hovered ? AppColors.surfaceAlt : AppColors.surface),
          borderRadius: BorderRadius.circular(14),
          border: primary ? null : Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                color: fg,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Wired · 3 hr ago" (tarih yoksa yalnızca kaynak).
String sourceLine(Article a) =>
    [a.source, a.timeAgo].where((s) => s.isNotEmpty).join(' · ');

/// Greeting such as "Good morning · October 12".
String greetingLine([DateTime? now]) {
  final t = now ?? DateTime.now();
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final greeting = switch (t.hour) {
    >= 5 && < 12 => 'Good morning',
    >= 12 && < 18 => 'Good afternoon',
    _ => 'Good evening',
  };
  return '$greeting · ${months[t.month - 1]} ${t.day}';
}

String formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
