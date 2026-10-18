import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/api_models.dart';
import '../../services/api_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/state_views.dart';
import 'web_ui.dart';

/// İlgi alanı seçimi: kategoriler, seçilen kategorilerin alt etiketleri,
/// "+" takipler ve isteğe bağlı "neden" cümlesi.
///
/// Seçenekler `GET /api/taxonomy`'den gelir (sunucunun kodunda sabit liste).
/// Onboarding ekranında ve Profil'deki düzenleme penceresinde kullanılır.
class InterestForm extends StatefulWidget {
  const InterestForm({
    super.key,
    required this.submitLabel,
    required this.onSubmit,
    this.initialMacros = const [],
    this.initialMicros = const [],
    this.initialFollows = const [],
    this.initialContext = '',
    this.secondaryAction,
    this.columns,
  });

  final String submitLabel;

  /// Seçilen kategoriler (seçim sırasıyla), alt etiketler, "+" takipler ve
  /// "neden" cümlesi (boşsa ''; sunucu standart cümleyi kullanır).
  /// `true` dönerse kayıt başarılıdır.
  final Future<bool> Function(
    List<String> macros,
    List<String> micros,
    List<UserFollow> follows,
    String context,
  )
  onSubmit;
  final List<String> initialMacros;
  final List<String> initialMicros;
  final List<UserFollow> initialFollows;
  final String initialContext;

  /// Gönder düğmesinin solunda (ör. "Cancel").
  final Widget? secondaryAction;

  /// Kategori kartı sütun sayısı; verilmezse genişliğe göre seçilir.
  final int? columns;

  /// Sunucunun kabul ettiği en fazla alt etiket sayısı.
  static const maxTopics = 12;

  /// "Neden" cümlesi için tek dokunuşluk örnekler.
  static const contextExamples = [
    'I invest',
    'I build products',
    'I study this',
    'I just follow the news',
  ];

  @override
  State<InterestForm> createState() => _InterestFormState();
}

class _InterestFormState extends State<InterestForm> {
  final _state = AppState.instance;

  /// Seçim sırası korunur: sunucu günün özetini ilk kategoriden üretir.
  late final LinkedHashSet<String> _macros = LinkedHashSet.of(
    widget.initialMacros,
  );
  late final Set<String> _micros = {...widget.initialMicros};
  bool _limitHit = false;

  /// "+" takipler: kullanıcının kendi yazdığı şirket, ürün ya da kişi.
  late final List<UserFollow> _follows = [...widget.initialFollows];
  final _followCtrl = TextEditingController();
  String? _followMacro;
  String? _followError;

  /// "Neden" cümlesi: akış bu cümleye anlamca yakın haberleri öne alır.
  late final _contextCtrl = TextEditingController(text: widget.initialContext);

  static final _urlish = RegExp(
    r'https?://|www\.|\.(com|net|org|io)\b',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _state.loadTaxonomy();
  }

  @override
  void dispose() {
    _followCtrl.dispose();
    _contextCtrl.dispose();
    super.dispose();
  }

  /// Takibin bağlanacağı kategori: seçilen, yoksa ilk seçili kategori.
  String? _followMacroFor(List<String> macros) =>
      macros.contains(_followMacro) ? _followMacro : macros.firstOrNull;

  /// Sunucudaki kurallarla aynı doğrulama; hata varsa formda gösterilir.
  void _addFollow(List<TaxonomyCategory> taxonomy) {
    final name = _followCtrl.text.trim().split(RegExp(r'\s+')).join(' ');
    final macro = _followMacroFor(_selectedMacros(taxonomy));
    final draft = UserFollow(name: name, macro: macro ?? '');
    final String? error;
    if (macro == null) {
      error = 'Pick a category above first.';
    } else if (name.length < 2 || name.length > 40) {
      error = 'Use 2 to 40 characters.';
    } else if (_urlish.hasMatch(name)) {
      error = 'Type a name, not a link.';
    } else if (_follows.any((f) => f.key == draft.key)) {
      error = '$name is already in your list.';
    } else if (_follows.length >= ApiService.maxFollows) {
      error = 'You can follow up to ${ApiService.maxFollows} things.';
    } else {
      error = null;
    }
    setState(() {
      _followError = error;
      if (error == null) {
        _follows.add(draft);
        _followCtrl.clear();
      }
    });
  }

  /// Kategorisi artık seçili olmayan takip ilk seçili kategoriye taşınır.
  List<UserFollow> _followsFor(List<String> macros) => [
    for (final f in _follows)
      macros.contains(f.macro)
          ? f
          : UserFollow(id: f.id, name: f.name, macro: macros.first),
  ];

  /// Yalnızca seçili kategorilere ait alt etiketler, taksonomi sırasıyla.
  List<String> _selectedMicros(List<TaxonomyCategory> taxonomy) => [
    for (final c in taxonomy)
      if (_macros.contains(c.macro))
        for (final t in c.microTags)
          if (_micros.contains(t.tag)) t.tag,
  ];

  /// Taksonomide olmayan eski kategoriler gönderilmez.
  List<String> _selectedMacros(List<TaxonomyCategory> taxonomy) {
    final known = {for (final c in taxonomy) c.macro};
    return [
      for (final m in _macros)
        if (known.contains(m)) m,
    ];
  }

  void _toggleMacro(String macro) => setState(() {
    if (!_macros.remove(macro)) _macros.add(macro);
    _limitHit = false;
  });

  void _toggleMicro(List<TaxonomyCategory> taxonomy, String tag) =>
      setState(() {
        if (_micros.remove(tag)) {
          _limitHit = false;
          return;
        }
        if (_selectedMicros(taxonomy).length >= InterestForm.maxTopics) {
          _limitHit = true;
          return;
        }
        _micros.add(tag);
      });

  Future<void> _submit(List<TaxonomyCategory> taxonomy) async {
    final macros = _selectedMacros(taxonomy);
    if (macros.isEmpty || _state.savingPreferences) return;
    await widget.onSubmit(
      macros,
      _selectedMicros(taxonomy),
      _followsFor(macros),
      _contextCtrl.text.trim().split(RegExp(r'\s+')).join(' '),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final taxonomy = _state.taxonomy;
        if (taxonomy == null) {
          final error = _state.taxonomyError;
          return error != null
              ? ErrorView(error: error, onRetry: _state.loadTaxonomy)
              : const LoadingView(message: 'Loading topics…');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CategoryGrid(
              taxonomy: taxonomy,
              selected: _macros,
              columns: widget.columns,
              onToggle: _toggleMacro,
            ),
            const SizedBox(height: 32),
            _topics(taxonomy),
            const SizedBox(height: 14),
            _followSection(taxonomy),
            const SizedBox(height: 32),
            _contextSection(),
            const SizedBox(height: 28),
            _footer(taxonomy),
          ],
        );
      },
    );
  }

  Widget _topics(List<TaxonomyCategory> taxonomy) {
    final chosen = [
      for (final c in taxonomy)
        if (_macros.contains(c.macro)) c,
    ];
    final count = _selectedMicros(taxonomy).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Fine-tune with topics',
              style: GoogleFonts.playfairDisplay(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 12),
            const OverlineLabel('Optional'),
            const Spacer(),
            Text(
              '$count / ${InterestForm.maxTopics} topics',
              style: GoogleFonts.inter(
                color: _limitHit ? AppColors.dislike : AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _limitHit
              ? 'You can pick up to ${InterestForm.maxTopics} topics. '
                    'Remove one to add another.'
              : 'Stories tagged with these topics rank higher in your Feed.',
          style: GoogleFonts.inter(
            color: _limitHit ? AppColors.dislike : AppColors.textMuted,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 18),
        if (chosen.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'Pick a category above to see its topics.',
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 13.5,
              ),
            ),
          )
        else
          for (final c in chosen)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OverlineLabel(c.displayName, color: categoryColor(c.macro)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in c.microTags)
                        PillButton(
                          label: t.label,
                          selected: _micros.contains(t.tag),
                          showCheck: true,
                          dense: true,
                          onTap: () => _toggleMicro(taxonomy, t.tag),
                        ),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }

  /// "+" ile belirli bir şirket, ürün ya da kişiyi takip etme.
  Widget _followSection(List<TaxonomyCategory> taxonomy) {
    final macros = _selectedMacros(taxonomy);
    final macro = _followMacroFor(macros);
    final full = _follows.length >= ApiService.maxFollows;
    final enabled = macros.isNotEmpty && !full;
    final names = {for (final c in taxonomy) c.macro: c.displayName};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Follow something specific',
              style: GoogleFonts.playfairDisplay(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 12),
            const OverlineLabel('Optional'),
            const Spacer(),
            Text(
              '${_follows.length} / ${ApiService.maxFollows}',
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'A company, product or person, e.g. Revolut, Steam Deck or OpenAI. '
          'We search for it and put stories that mention it first.',
          style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13.5),
        ),
        const SizedBox(height: 14),
        Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _followCtrl,
                  enabled: enabled,
                  maxLength: 40,
                  onSubmitted: (_) => _addFollow(taxonomy),
                  cursorColor: AppColors.accentLight,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                  ),
                  decoration: _inputDecoration(
                    macros.isEmpty
                        ? 'Pick a category above first'
                        : full
                        ? 'You follow ${ApiService.maxFollows} things'
                        : 'Type a name to follow',
                    prefixIcon: const Icon(
                      Icons.add_rounded,
                      color: AppColors.iconMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Takibin kategorisi; sorguya bağlam katar ("Revolut finance").
              PopupMenuButton<String>(
                enabled: enabled && macros.length > 1,
                tooltip: 'Category',
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.border),
                ),
                onSelected: (m) => setState(() => _followMacro = m),
                itemBuilder: (context) => [
                  for (final m in macros)
                    PopupMenuItem(
                      value: m,
                      child: Text(
                        names[m] ?? m,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        macro ?? 'Category',
                        style: GoogleFonts.inter(
                          color: macro == null
                              ? AppColors.textMuted
                              : categoryColor(macro),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (macros.length > 1)
                        const Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              WebButton(
                label: 'Add',
                primary: false,
                onTap: () => _addFollow(taxonomy),
              ),
            ],
          ),
        ),
        if (_followError != null) ...[
          const SizedBox(height: 8),
          Text(
            _followError!,
            style: GoogleFonts.inter(color: AppColors.dislike, fontSize: 13),
          ),
        ],
        if (_follows.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in _followsFor(macros.isEmpty ? [''] : macros))
                _FollowChip(
                  follow: f,
                  onRemove: () => setState(() {
                    _follows.removeWhere((x) => x.key == f.key);
                    _followError = null;
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// "What should your feed help you with?": isteğe bağlı tek cümle, her
  /// dilde. Sunucu cümleyi İngilizceye çevirip ilgi vektörünü ondan kurar.
  Widget _contextSection() {
    return ListenableBuilder(
      listenable: _contextCtrl,
      builder: (context, _) {
        final text = _contextCtrl.text.trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    'What should your feed help you with?',
                    style: GoogleFonts.playfairDisplay(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const OverlineLabel('Optional'),
                const Spacer(),
                Text(
                  '${_contextCtrl.text.length} / ${ApiService.maxContextChars}',
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'One sentence, in any language. Stories closer to it rank '
              'higher in your Feed.',
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _contextCtrl,
              maxLength: ApiService.maxContextChars,
              minLines: 1,
              maxLines: 3,
              cursorColor: AppColors.accentLight,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 14.5,
              ),
              decoration: _inputDecoration(
                'e.g. I invest in fintech and want early signals on IPOs',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final example in InterestForm.contextExamples)
                  PillButton(
                    label: example,
                    dense: true,
                    selected: text == example,
                    onTap: () =>
                        _contextCtrl.text = text == example ? '' : example,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Formdaki metin alanlarının ortak görünümü.
  InputDecoration _inputDecoration(String hint, {Widget? prefixIcon}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.border),
    );
    return InputDecoration(
      hintText: hint,
      counterText: '',
      isDense: true,
      hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14.5),
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: AppColors.surface,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.accent),
      ),
    );
  }

  Widget _footer(List<TaxonomyCategory> taxonomy) {
    final macros = _selectedMacros(taxonomy);
    final topics = _selectedMicros(taxonomy).length;
    final error = _state.preferencesError;
    final saving = _state.savingPreferences;

    final String summary;
    if (macros.isEmpty) {
      summary = 'Pick at least one category to continue.';
    } else {
      summary = [
        'Your Feed: ${macros.join(', ')}',
        if (topics > 0) '$topics topic${topics == 1 ? '' : 's'}',
        if (_follows.isNotEmpty)
          'following ${_follows.map((f) => f.name).join(', ')}',
      ].join(' · ');
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary,
                  style: GoogleFonts.inter(
                    color: macros.isEmpty
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (macros.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Your Daily Brief covers ${macros.first}, your first pick.',
                    style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    error.userMessage,
                    style: GoogleFonts.inter(
                      color: AppColors.dislike,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.secondaryAction != null) ...[
            const SizedBox(width: 12),
            widget.secondaryAction!,
          ],
          const SizedBox(width: 12),
          if (saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.accentLight,
                ),
              ),
            )
          else
            Opacity(
              opacity: macros.isEmpty ? 0.4 : 1,
              child: IgnorePointer(
                ignoring: macros.isEmpty,
                child: WebButton(
                  label: widget.submitLabel,
                  icon: Icons.arrow_forward_rounded,
                  onTap: () => _submit(taxonomy),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Takip edilen şeyin etiketi: ad, kategori ve kaldırma düğmesi.
class _FollowChip extends StatelessWidget {
  const _FollowChip({required this.follow, required this.onRemove});

  final UserFollow follow;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(follow.macro);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            follow.name,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (follow.macro.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              follow.macro,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(width: 4),
          Tooltip(
            message: 'Stop following ${follow.name}',
            child: Hoverable(
              onTap: onRemove,
              builder: (context, hovered) => Icon(
                Icons.close_rounded,
                size: 16,
                color: hovered ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kategoriye göre simge.
IconData categoryIcon(String macro) => switch (macro) {
  'Tech' => Icons.code_rounded,
  'AI' => Icons.auto_awesome_rounded,
  'Hardware' => Icons.memory_rounded,
  'Automotive' => Icons.electric_car_rounded,
  'Gaming' => Icons.sports_esports_rounded,
  'Finance' => Icons.trending_up_rounded,
  'Science' => Icons.science_rounded,
  _ => Icons.label_outline_rounded,
};

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.taxonomy,
    required this.selected,
    required this.onToggle,
    this.columns,
  });

  final List<TaxonomyCategory> taxonomy;
  final LinkedHashSet<String> selected;
  final ValueChanged<String> onToggle;
  final int? columns;

  @override
  Widget build(BuildContext context) {
    const gap = 16.0;
    return LayoutBuilder(
      builder: (context, c) {
        final cols =
            columns ?? ((c.maxWidth + gap) ~/ (240 + gap)).clamp(1, 4).toInt();
        final width = (c.maxWidth - gap * (cols - 1)) / cols;
        final first = selected.isEmpty ? null : selected.first;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final cat in taxonomy)
              SizedBox(
                width: width,
                child: _CategoryCard(
                  category: cat,
                  selected: selected.contains(cat.macro),
                  isFirst: cat.macro == first,
                  onTap: () => onToggle(cat.macro),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.selected,
    required this.isFirst,
    required this.onTap,
  });

  final TaxonomyCategory category;
  final bool selected;

  /// İlk seçilen kategori günün özetinin konusu olur.
  final bool isFirst;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(category.macro);
    return Semantics(
      button: true,
      selected: selected,
      label: category.displayName,
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 156,
          padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.10)
                : (hovered ? AppColors.surfaceAlt : AppColors.surface),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.75)
                  : (hovered
                        ? AppColors.textMuted.withValues(alpha: 0.5)
                        : AppColors.border),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      categoryIcon(category.macro),
                      size: 20,
                      color: color,
                    ),
                  ),
                  const Spacer(),
                  if (isFirst) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.mint.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Daily Brief',
                        style: GoogleFonts.inter(
                          color: AppColors.mint,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? color : Colors.transparent,
                      border: Border.all(
                        color: selected ? color : AppColors.barInactive,
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: Color(0xFF16121F),
                          )
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                category.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Expanded(
                child: Text(
                  category.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 12.5,
                    height: 1.45,
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
