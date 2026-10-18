import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Ekranlar arası paylaşılan küçük UI parçaları.

class MintDot extends StatelessWidget {
  const MintDot({super.key, this.size = 6});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: AppColors.mint,
      shape: BoxShape.circle,
    ),
  );
}

class GradientOrb extends StatelessWidget {
  const GradientOrb({super.key, this.size = 32, this.child});

  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.accentLight, AppColors.accentDeep],
      ),
    ),
    child: child,
  );
}

/// Kullanıcı avatarı; [url] yüklenemezse simgeye düşer.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.size = 32, this.url});

  final double size;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.person_outline_rounded,
      size: size * 0.53,
      color: const Color(0xFF4C3A86),
    );
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.accentLight,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null || url!.isEmpty
          ? fallback
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Avatar sunucusu CORS başlığı göndermeyebilir; <img> kullan.
              webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

/// Standart koyu kart.
class WofCard extends StatelessWidget {
  const WofCard({super.key, required this.child, this.padding = 16});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// "W.O.F•" logosu.
class WofLogo extends StatelessWidget {
  const WofLogo({super.key, this.fontSize = 20, this.text = 'W.O.F'});

  final double fontSize;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: GoogleFonts.playfairDisplay(
            color: AppColors.textPrimary,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(width: fontSize * 0.25),
        Padding(
          padding: EdgeInsets.only(bottom: fontSize * 0.2),
          child: MintDot(size: fontSize * 0.27),
        ),
      ],
    );
  }
}

/// Mobil üst bar: logo, arama, bildirim, profil.
class MobileTopBar extends StatelessWidget {
  const MobileTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    Widget iconBtn(IconData icon) => InkResponse(
      onTap: () {},
      radius: 20,
      child: Icon(icon, color: AppColors.iconMuted, size: 21),
    );

    return Row(
      children: [
        const WofLogo(),
        const Spacer(),
        iconBtn(Icons.search_rounded),
        const SizedBox(width: 16),
        iconBtn(Icons.notifications_none_rounded),
        const SizedBox(width: 16),
        const UserAvatar(),
      ],
    );
  }
}

class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 38,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      child: InkWell(
        customBorder: const CircleBorder(),
        hoverColor: AppColors.surfaceAlt,
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: AppColors.iconMuted, size: size * 0.5),
        ),
      ),
    );
  }
}

/// Haberin görseli: çözümlenmiş HTTP linkiyse `Image.network`, yerel yer tutucuysa `Image.asset`.
class ArticleCoverImage extends StatelessWidget {
  const ArticleCoverImage({
    super.key,
    required this.image,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final String image;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return Image.network(
        image,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/images/headline.jpg',
          width: width,
          height: height,
          fit: fit,
        ),
      );
    }
    return Image.asset(
      image,
      width: width,
      height: height,
      fit: fit,
    );
  }
}

/// AssetImage ya da NetworkImage döndüren yardımcı.
ImageProvider articleImageProvider(String image) {
  if (image.startsWith('http://') || image.startsWith('https://')) {
    return NetworkImage(image);
  }
  return AssetImage(image);
}
