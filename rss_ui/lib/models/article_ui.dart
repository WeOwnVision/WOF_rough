import 'api_models.dart';

/// [Article]'ın arayüzde kullanılan türetilmiş alanları.
extension ArticleUi on Article {
  /// Rozette gösterilen birincil kategori.
  String get category =>
      macroTags.isNotEmpty ? macroTags.first : (macroTag ?? 'News');

  /// Kart özeti: TL;DR, yoksa tam metnin başı.
  String get summary {
    final t = tldr?.trim();
    if (t != null && t.isNotEmpty) return t;
    final text = cleanText?.trim() ?? '';
    return text.length > 280 ? '${text.substring(0, 280)}…' : text;
  }

  /// "5 min ago", "3 hr ago", "2 days ago", "Oct 8".
  String get timeAgo {
    final p = publishedAt;
    if (p == null) return '';
    final diff = DateTime.now().difference(p.toLocal());
    if (diff.isNegative || diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) {
      return diff.inDays == 1 ? '1 day ago' : '${diff.inDays} days ago';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final l = p.toLocal();
    return '${months[l.month - 1]} ${l.day}';
  }

  /// Tam metin varsa tahmini okuma süresi (dakika); yoksa `null`.
  int? get readMinutes {
    final text = cleanText;
    if (text == null || text.trim().isEmpty) return null;
    final words = text.trim().split(RegExp(r'\s+')).length;
    return (words / 220).ceil().clamp(1, 99);
  }

  /// Çözümlenen gerçek görsel; yoksa kategoriye göre yer tutucu.
  String get image {
    final netImg = imageUrl?.trim();
    if (netImg != null && netImg.startsWith('http')) {
      return netImg;
    }
    final options = _placeholders[category] ?? _fallback;
    final hash = id.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
    return options[hash % options.length];
  }

  bool get hasNetworkImage => imageUrl != null && imageUrl!.trim().startsWith('http');
}

const _dir = 'assets/images/news';

const _placeholders = <String, List<String>>{
  'Tech': ['$_dir/quantum_chip.jpg', '$_dir/smart_city.jpg'],
  'AI': ['$_dir/ai_law.jpg', '$_dir/medical_ai.jpg'],
  'Hardware': ['$_dir/quantum_chip.jpg', '$_dir/smart_city.jpg'],
  'Automotive': ['$_dir/smart_city.jpg', '$_dir/wind_energy.jpg'],
  'Gaming': ['$_dir/stadium.jpg', '$_dir/art_biennial.jpg'],
  'Finance': ['$_dir/central_bank.jpg'],
  'Science': ['$_dir/exoplanet.jpg', '$_dir/moon_rocket.jpg'],
};

const _fallback = [
  'assets/images/headline.jpg',
  '$_dir/wind_energy.jpg',
  '$_dir/art_biennial.jpg',
];
