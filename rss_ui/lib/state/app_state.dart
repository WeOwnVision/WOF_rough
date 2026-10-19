import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_models.dart';
import '../services/api_service.dart';
import '../services/local_cache.dart';

/// Arayüzün tek paylaşılan durumu: oturum, haberler, WAI sohbetleri ve
/// cihazda tutulan tercihler (kaydedilenler, beğeniler, ayarlar).
///
/// Testlerde sahte bir [ApiService] ile yeni örnek atanabilir:
/// `AppState.instance = AppState(api: ...)`.
class AppState extends ChangeNotifier {
  AppState({ApiService? api})
    : api = api ?? ApiService(logger: kDebugMode ? debugPrint : null);

  static AppState instance = AppState();

  final ApiService api;
  LocalCache? _cache;

  /// `true` when the current feed is served from local cache (seed or stale).
  bool get isOffline => _offline;
  bool _offline = false;

  // -------------------------------------------------------------------------
  // Gezinme
  // -------------------------------------------------------------------------
  static const navHome = 0;
  static const navFeed = 1;
  static const navChat = 2;
  static const navDiscover = 3;
  static const navProfile = 4;

  int navIndex = navHome;

  void goTo(int index) {
    if (navIndex == index) return;
    navIndex = index;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Oturum
  // -------------------------------------------------------------------------
  static const _kUsername = 'username';
  static const _kSaved = 'saved_ids';
  static const _kLiked = 'liked_ids';
  static const _kRead = 'read_ids';

  /// Sunucuya ulaşılamadığında oluşturulan geçici kullanıcıların öneki.
  static const _localPrefix = 'local-';

  SharedPreferences? _prefs;
  bool _initialized = false;

  AppUser? user;

  /// Açılışta kayıtlı kullanıcıyla giriş denenirken `true`.
  bool sessionLoading = true;
  bool loggingIn = false;
  ApiException? sessionError;

  /// Kullanıcı sunucuda gerçekten var mı? Çevrimdışı oluşturulan
  /// `local-…` kullanıcılarla kişiselleştirme uç noktaları çağrılmaz
  /// (sunucu geçersiz kimlik için 400 döndürür).
  bool get hasServerUser => user != null && !user!.id.startsWith(_localPrefix);

  /// Giriş yapmış ama ilgi alanlarını seçmemiş: onboarding ekranı açılır.
  bool get needsOnboarding => hasServerUser && !user!.onboardingCompleted;

  /// Tercihleri yükler ve daha önce giriş yapılmışsa sessizce tekrar dener.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      _cache = LocalCache(_prefs!);
    } catch (_) {
      // Depolama kullanılamıyorsa (gizli sekme vb.) yalnızca bellek kullan.
    }
    final username = _prefs?.getString(_kUsername);
    if (username != null && username.isNotEmpty) {
      await login(username);
    }
    sessionLoading = false;
    notifyListeners();
  }

  /// `POST /api/users/login`. Kullanıcı yoksa sunucu oluşturur; yanıttaki
  /// `onboarding_completed` ilgi alanı ekranının açılıp açılmayacağını
  /// belirler.
  Future<void> login(String username) async {
    loggingIn = true;
    sessionError = null;
    notifyListeners();
    try {
      user = await api.login(username);
      await _prefs?.setString(_kUsername, user!.username);
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.unavailable ||
          e.kind == ApiErrorKind.network ||
          e.kind == ApiErrorKind.timeout) {
        user = AppUser(
          id: '$_localPrefix${username.trim()}',
          username: username.trim(),
        );
        await _prefs?.setString(_kUsername, user!.username);
      } else {
        sessionError = e;
      }
    } finally {
      if (user != null) {
        _loadLibrary();
        // Akış kişiye özel olduğu için önceki oturumunkini kullanma.
        _clearFeed();
        _resetOnboarding();
        follows = const [];
        if (needsOnboarding) onboardingStep = OnboardingStep.pick;
        if (hasServerUser) loadFollows();
      }
      loggingIn = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    user = null;
    sessionError = null;
    navIndex = navHome;
    interestSummary = null;
    follows = const [];
    saved.clear();
    liked.clear();
    read.clear();
    _disliked.clear();
    _clearFeed();
    _resetOnboarding();
    await _prefs?.remove(_kUsername);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // İlgi alanları (taksonomi + tercihler)
  // -------------------------------------------------------------------------
  /// Sunucudaki sabit kategori listesi; oturum boyunca bir kez yüklenir.
  List<TaxonomyCategory>? taxonomy;
  bool taxonomyLoading = false;
  ApiException? taxonomyError;

  bool savingPreferences = false;
  ApiException? preferencesError;

  /// Sunucunun seçimlerden kurduğu cümle (ilgi vektörünün kaynağı).
  String? interestSummary;

  /// Seçilen ana kategoriler (sunucudan).
  List<String> get interests => user?.preferredMacroTags ?? const [];

  /// Seçilen alt etiketler (sunucudan).
  List<String> get interestTags => user?.preferredMicroTags ?? const [];

  /// Onboarding'deki "neden" cümlesi (sunucudan); yazılmadıysa `null`.
  String? get interestContext => user?.interestContext;

  /// `GET /api/taxonomy`.
  Future<void> loadTaxonomy() async {
    if (taxonomy != null || taxonomyLoading) return;
    taxonomyLoading = true;
    taxonomyError = null;
    await Future<void>.value();
    notifyListeners();
    try {
      taxonomy = await api.getTaxonomy();
    } on ApiException catch (e) {
      taxonomyError = e;
    } finally {
      taxonomyLoading = false;
      notifyListeners();
    }
  }

  /// Alt etiketin arayüzdeki adı ("llm_agents" → "LLM Agents").
  String tagLabel(String tag) {
    for (final c in taxonomy ?? const <TaxonomyCategory>[]) {
      for (final t in c.microTags) {
        if (t.tag == tag) return t.label;
      }
    }
    return tag
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// `PUT /api/users/{id}/preferences`. Başarılıysa akış ve günün özeti
  /// yeni tercihlerle yeniden yüklenir. `context`: `null` sunucudaki cümleyi
  /// korur, boş metin siler.
  Future<bool> savePreferences({
    required List<String> macroTags,
    required List<String> microTags,
    String? context,
  }) async {
    final current = user;
    if (current == null || !hasServerUser || savingPreferences) return false;
    savingPreferences = true;
    preferencesError = null;
    notifyListeners();
    try {
      final result = await api.updatePreferences(
        current.id,
        macroTags: macroTags,
        microTags: microTags,
        interestContext: context,
      );
      user = AppUser(
        id: result.user.id,
        username: result.user.username,
        avatarUrl: result.user.avatarUrl ?? current.avatarUrl,
        createdAt: current.createdAt,
        onboardingCompleted: result.user.onboardingCompleted,
        preferredMacroTags: result.user.preferredMacroTags,
        preferredMicroTags: result.user.preferredMicroTags,
        interestContext: result.user.interestContext,
      );
      interestSummary = result.interestSummary;
      _clearFeed();
      return true;
    } on ApiException catch (e) {
      preferencesError = e;
      return false;
    } finally {
      savingPreferences = false;
      notifyListeners();
    }
  }

  // -------------------------------------------------------------------------
  // "+" takipler (belirli şirket, ürün, kişi)
  // -------------------------------------------------------------------------
  /// Sunucudaki takipler (eklenme sırasıyla).
  List<UserFollow> follows = const [];

  /// `GET /api/users/{id}/follows`.
  Future<void> loadFollows() async {
    final current = user;
    if (current == null || !hasServerUser) return;
    try {
      final list = await api.getFollows(current.id);
      if (user?.id != current.id) return;
      follows = list;
      notifyListeners();
    } on ApiException {
      // Takipler gösterilemezse ilgi alanları yine çalışır.
    }
  }

  /// Kategori/alt konu tercihlerini ve "neden" cümlesini (`PUT /preferences`)
  /// ve takipleri birlikte kaydeder. Onboarding ve Profil'deki düzenleme aynı
  /// yolu kullanır.
  Future<bool> saveInterests({
    required List<String> macroTags,
    required List<String> microTags,
    List<UserFollow> follows = const [],
    String? context,
  }) async {
    final ok = await savePreferences(
      macroTags: macroTags,
      microTags: microTags,
      context: context,
    );
    if (!ok) return false;
    await _syncFollows(follows);
    return true;
  }

  /// İstenen takip listesine göre eksikleri ekler, çıkarılanları siler.
  /// Takip hatası tercihlerin kaydını geri almaz; liste sunucudan yenilenir.
  Future<void> _syncFollows(List<UserFollow> desired) async {
    final current = user;
    if (current == null || !hasServerUser) return;
    final wanted = {for (final f in desired) f.key: f};
    final existing = {for (final f in follows) f.key: f};
    for (final f in existing.values) {
      if (!wanted.containsKey(f.key) && f.id != null) {
        try {
          await api.removeFollow(current.id, f.id!);
        } on ApiException {
          // Sonraki yüklemede sunucudaki hali görünür.
        }
      }
    }
    for (final f in wanted.values) {
      if (!existing.containsKey(f.key)) {
        try {
          await api.addFollow(current.id, name: f.name, macro: f.macro);
        } on ApiException {
          // Geçersiz ya da sınır aşımı: sunucu reddeder, liste yenilenince görünmez.
        }
      }
    }
    await loadFollows();
  }

  /// `GET /api/users/{id}/preferences`: profil açılınca güncel tercihleri
  /// çeker. Hata olursa eldeki değerler kalır.
  Future<void> refreshPreferences() async {
    final current = user;
    if (current == null || !hasServerUser) return;
    try {
      final fresh = await api.getPreferences(current.id);
      if (user?.id != current.id) return;
      user = AppUser(
        id: fresh.id,
        username: fresh.username,
        avatarUrl: fresh.avatarUrl ?? current.avatarUrl,
        createdAt: current.createdAt,
        onboardingCompleted: fresh.onboardingCompleted,
        preferredMacroTags: fresh.preferredMacroTags,
        preferredMicroTags: fresh.preferredMicroTags,
        interestContext: fresh.interestContext,
      );
      notifyListeners();
    } on ApiException {
      // Eldeki tercihler gösterilmeye devam eder.
    }
  }

  // -------------------------------------------------------------------------
  // Onboarding akışı (hedef: 60 sn içinde kişisel akış)
  // -------------------------------------------------------------------------
  /// Akışın hangi adımında olunduğu; `null`: onboarding açık değil.
  ///
  /// Sunucu seçimler kaydedilir kaydedilmez `onboarding_completed = true`
  /// yapar; adımlar burada tutulmasa ilk adımdan sonra ana kabuğa geçilirdi.
  OnboardingStep? onboardingStep;

  /// WebGate onboarding ekranını göstermeli mi?
  bool get showOnboarding => onboardingStep != null || needsOnboarding;

  /// "Tadına bak" destesindeki kart sayısı (~30 sn).
  static const tasteSize = 8;

  /// Bundan az uygun haber varsa adım atlanır; tek kartla kalibrasyon olmaz.
  static const tasteMin = 4;

  List<Article> tasteDeck = const [];
  int tasteIndex = 0;
  int tasteLikes = 0;
  bool tasteLoading = false;

  /// Destede gösterilen haberler; açılış ekranı ve akış bunları sona atar.
  final Set<String> _tasted = {};

  Article? get currentTasteCard =>
      tasteIndex < tasteDeck.length ? tasteDeck[tasteIndex] : null;

  /// Açılış ekranı akış yüklenirken `true`.
  bool revealLoading = false;

  /// 1. adım: seçimleri kaydeder (`PUT /preferences`) ve 2. adıma geçer.
  Future<bool> submitOnboardingPicks({
    required List<String> macroTags,
    required List<String> microTags,
    List<UserFollow> follows = const [],
    String? context,
  }) async {
    final ok = await saveInterests(
      macroTags: macroTags,
      microTags: microTags,
      follows: follows,
      context: context,
    );
    if (!ok) return false;
    onboardingStep = OnboardingStep.taste;
    tasteDeck = const [];
    tasteIndex = 0;
    tasteLikes = 0;
    _tasted.clear();
    notifyListeners();
    await _loadTasteDeck();
    return true;
  }

  /// Seçilen kategorilerden, kategoriler arasında dönüşümlü 8 gerçek haber.
  /// Kişisel akıştan alınır; sunucu zaten seçilen kategorilere süzüyor.
  Future<void> _loadTasteDeck() async {
    final current = user;
    if (current == null) return;
    tasteLoading = true;
    notifyListeners();
    var deck = const <Article>[];
    try {
      final page = await api.getPersonalizedFeed(current.id, pageSize: 40);
      deck = _diversify(page.articles, current.preferredMacroTags, tasteSize);
    } on ApiException {
      // Deste olmadan da devam edilir; açılış ekranı seçimlerle kurulur.
    }
    if (onboardingStep != OnboardingStep.taste) return;
    _remember(deck);
    tasteDeck = deck;
    tasteLoading = false;
    if (deck.length < tasteMin) {
      await finishTasteCheck();
    } else {
      notifyListeners();
    }
  }

  /// Kategorileri sırayla dolaşarak (önce kullanıcının seçim sırası) her
  /// birinden bir haber alır; deste tek bir kategoriye yığılmasın.
  static List<Article> _diversify(
    List<Article> items,
    List<String> macros,
    int size,
  ) {
    final buckets = <String, List<Article>>{};
    for (final a in items) {
      buckets.putIfAbsent(a.macroTag ?? '', () => []).add(a);
    }
    final order = [
      ...macros.where(buckets.containsKey),
      ...buckets.keys.where((k) => !macros.contains(k)),
    ];
    final out = <Article>[];
    for (var round = 0; out.length < size; round++) {
      var added = false;
      for (final k in order) {
        final bucket = buckets[k]!;
        if (round < bucket.length && out.length < size) {
          out.add(bucket[round]);
          added = true;
        }
      }
      if (!added) break;
    }
    return out;
  }

  /// 2. adımda kartı sağa (okurum) ya da sola (bana göre değil) kaydırma.
  /// Akıştaki kaydırmayla aynı sinyali gönderir; ilgi vektörü ve etiketler
  /// sunucuda o anda güncellenir.
  void tasteReact(Article article, {required bool like}) {
    if (currentTasteCard?.id != article.id) return;
    if (like) tasteLikes++;
    _tasted.add(article.id);
    _recordOpinion(article.id, like: like);
    tasteIndex++;
    notifyListeners();
    if (tasteIndex >= tasteDeck.length) finishTasteCheck();
  }

  /// 2. adım bitti ya da atlandı: beğeni isteklerinin sunucuya ulaşmasını
  /// bekler (akış güncel ilgi vektörüyle sıralansın), sonra açılış ekranı.
  Future<void> finishTasteCheck() async {
    if (onboardingStep != OnboardingStep.taste) return;
    onboardingStep = OnboardingStep.reveal;
    revealLoading = true;
    notifyListeners();
    await _interactionsSettled();
    if (onboardingStep != OnboardingStep.reveal) return;
    await refreshFeed();
    if (onboardingStep != OnboardingStep.reveal) return;
    revealLoading = false;
    notifyListeners();
    // Ana sayfanın "Latest developments" kartı güncel profille şimdiden
    // yazılsın; kullanıcı ana sayfaya geçtiğinde hazır olur.
    loadBrief();
  }

  Future<void> _interactionsSettled() async {
    try {
      await Future.wait(_interactionQueue.values.toList());
    } catch (_) {
      // Tek tek ele alınıyor; burada yalnızca bitmelerini bekliyoruz.
    }
  }

  /// Açılış ekranının "senin için" haberleri: destede görülmemiş olanlar.
  List<Article> get revealPicks =>
      feed.where((a) => !_tasted.contains(a.id)).toList();

  /// Akışta henüz az haberi olan seçili alt konular ve haberi düşmemiş
  /// takipler. Sunucu ilgi alanları kaydedilince bunları çekip veritabanına
  /// kaydediyor; açılış ekranı yalnızca "toplanıyor" diye bilgi verir
  /// (kredi harcayan, kaydetmeyen canlı arama yok).
  List<String> get collectingTopics {
    int count(bool Function(Article) test) => feed.where(test).length;
    return [
      for (final t in interestTags)
        if (count((a) => a.microTags.contains(t)) < 2) tagLabel(t),
      for (final f in follows)
        if (count((a) => a.matchedFollows.contains(f.name)) == 0) f.name,
    ];
  }

  /// 3. adım: onboarding biter, akış açılır. Destede görülen haberler
  /// akışın sonuna alınır ki kullanıcı ilk kartlarda yeni haber görsün.
  void completeOnboarding({int openTab = navFeed}) {
    final fresh = feed.where((a) => !_tasted.contains(a.id)).toList();
    final seen = feed.where((a) => _tasted.contains(a.id)).toList();
    feed
      ..clear()
      ..addAll([...fresh, ...seen]);
    onboardingStep = null;
    navIndex = openTab;
    notifyListeners();
  }

  void _resetOnboarding() {
    onboardingStep = null;
    tasteDeck = const [];
    tasteIndex = 0;
    tasteLikes = 0;
    tasteLoading = false;
    _tasted.clear();
    revealLoading = false;
  }

  /// "Neden bu haber": kullanıcının seçtiği (ya da beğenilerle öğrenilen)
  /// alt konular, yoksa kategori. Kişiselleştirmeyi görünür kılar.
  List<String> reasonsFor(Article a) {
    final u = user;
    if (u == null || !hasServerUser) return const [];
    // "+" ile takip edilen şeyin adı geçiyorsa en güçlü gerekçe odur.
    if (a.matchedFollows.isNotEmpty) return a.matchedFollows.take(2).toList();
    final topics = [
      for (final t in a.microTags)
        if (u.preferredMicroTags.contains(t)) tagLabel(t),
    ];
    if (topics.isNotEmpty) return topics.take(3).toList();
    return [
      for (final m in a.macroTags)
        if (u.preferredMacroTags.contains(m)) m,
    ].take(1).toList();
  }

  // -------------------------------------------------------------------------
  // Haber önbelleği ve detaylar
  // -------------------------------------------------------------------------
  final Map<String, Article> _articles = {};

  /// Tam metni yüklenmiş haberler.
  final Map<String, Article> _details = {};

  Article? articleById(String id) => _details[id] ?? _articles[id];

  void _remember(Iterable<Article> items) {
    for (final a in items) {
      _articles[a.id] = a;
    }
  }

  /// Haberin detayını (tam metin) getirir; bir kez yüklenir.
  Future<Article> loadDetail(String id) async {
    final cached = _details[id];
    if (cached != null) return cached;
    final article = await api.getArticle(id);
    _details[id] = article;
    _articles[id] = article;
    return article;
  }

  /// Önbellekte olmayan haberleri (ör. önceki oturumda kaydedilenler) getirir.
  Future<void> ensureArticles(Iterable<String> ids) async {
    final missing = ids.where((id) => !_articles.containsKey(id)).toList();
    if (missing.isEmpty) return;
    await Future.wait(
      missing.map((id) async {
        try {
          await loadDetail(id);
        } on ApiException {
          // Silinmiş/erişilemeyen haber; listede gösterilmez.
        }
      }),
    );
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Akış (sayfalı)
  // -------------------------------------------------------------------------
  static const pageSize = 20;

  final List<Article> feed = [];
  int _feedPage = 0;
  bool feedHasMore = true;
  bool feedLoading = false;
  ApiException? feedError;

  /// Akış kişiye özel mi (`/api/feed/personalized`)?
  bool feedIsPersonal = false;

  /// Kişisel akış istendi ama kullanıcının tercihi yok; sunucu tarih sıralı
  /// akış döndürdü.
  bool feedIsFallback = false;

  /// Bekleyen bir yüklemenin sonucu, akış o sırada temizlendiyse atılır.
  int _feedGeneration = 0;

  Future<void>? _feedRequest;

  /// Akış henüz yüklenmediyse ilk sayfayı getirir; yükleme sürüyorsa onu
  /// bekler.
  Future<void> ensureFeed() {
    if (_feedRequest != null) return _feedRequest!;
    return feed.isEmpty ? loadMoreFeed() : Future.value();
  }

  /// Sonraki sayfayı getirir. Test kayıtları gizlendiği için boş gelen
  /// sayfaları atlar. Yükleme sürüyorsa aynı isteği döndürür.
  Future<void> loadMoreFeed() {
    if (_feedRequest != null) return _feedRequest!;
    if (!feedHasMore) return Future.value();
    feedLoading = true;
    feedError = null;
    late final Future<void> request;
    request = _loadMoreFeed().whenComplete(() {
      // Bu arada akış temizlenip yeni istek başladıysa ona dokunma.
      if (identical(_feedRequest, request)) _feedRequest = null;
    });
    return _feedRequest = request;
  }

  Future<void> _loadMoreFeed() async {
    final generation = _feedGeneration;
    // Sayfaların initState'inden çağrılabilir; çizim bitince bildir.
    await Future<void>.value();
    notifyListeners();
    try {
      var added = 0;
      while (added == 0 && feedHasMore) {
        final List<Article> items;
        // Giriş yapmış kullanıcıya kişisel akış; mobil / çevrimdışı
        // kullanıcıya genel akış.
        final personal = hasServerUser;
        if (personal) {
          final page = await api.getPersonalizedFeed(
            user!.id,
            page: _feedPage + 1,
            pageSize: personalPageSize,
          );
          if (generation != _feedGeneration) return;
          items = page.articles;
          feedHasMore = page.hasMore;
          feedIsFallback = page.isFallback;
          _syncLikes(items);
        } else {
          final page = await api.getArticlePage(
            page: _feedPage + 1,
            pageSize: pageSize,
          );
          if (generation != _feedGeneration) return;
          items = page.items;
          feedHasMore = page.hasMore;
        }
        feedIsPersonal = personal;
        _feedPage++;
        final known = feed.map((a) => a.id).toSet();
        final fresh = items.where((a) => !known.contains(a.id)).toList();
        _remember(fresh);
        feed.addAll(fresh);
        added = fresh.length;
      }
      // Server responded — replace local cache with fresh data.
      _offline = false;
      _cache?.saveArticles(feed);
    } on ApiException catch (e) {
      if (generation != _feedGeneration) return;
      // First page failed and feed is empty → fall back to local cache.
      if (feed.isEmpty) {
        final cached = _cache?.loadArticles() ?? const [];
        if (cached.isNotEmpty) {
          _remember(cached);
          feed.addAll(cached);
          feedHasMore = false;
          _offline = true;
          feedError = null;
        } else {
          feedError = e;
        }
      } else {
        feedError = e;
      }
    } finally {
      if (generation == _feedGeneration) {
        feedLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshFeed() async {
    _clearFeed();
    await loadMoreFeed();
  }

  /// Akışı ve ona bağlı özeti sıfırlar (giriş, çıkış, tercih değişikliği).
  void _clearFeed() {
    _feedGeneration++;
    _feedRequest = null;
    feed.clear();
    _feedPage = 0;
    feedHasMore = true;
    feedLoading = false;
    feedError = null;
    feedIsPersonal = false;
    feedIsFallback = false;
    // Tercihler değişince açık kategori artık seçili olmayabilir.
    feedCategory = null;
    _deckHold = null;
    sessionLikes = 0;
    sessionDislikes = 0;
    _offline = false;
    _briefGeneration++;
    brief = null;
    briefTitle = null;
    briefLoading = false;
    briefError = null;
    _briefSources = const [];
  }

  /// Kişisel akış her haber için sunucudaki beğeni durumunu (`is_liked`)
  /// gönderir; cihazdaki liste buna göre güncellenir.
  void _syncLikes(Iterable<Article> items) {
    var changed = false;
    for (final a in items) {
      final serverLiked = a.isLiked;
      if (serverLiked == null) continue;
      changed |= serverLiked ? liked.add(a.id) : liked.remove(a.id);
    }
    if (changed) _persistIds(_kLiked, liked);
  }

  /// Okunmamış sayıları bütün akışı gerektirir; kişisel akış bu yüzden büyük
  /// sayfalarla gelir (sunucu 400 haberi ~0,07 sn'de döndürüyor).
  static const personalPageSize = 100;

  /// Menüdeki okunmamış sayıları için akışın tamamını arka planda yükler.
  Future<void> loadWholeFeed() async {
    await ensureFeed();
    while (hasServerUser && feedHasMore && feedError == null) {
      await loadMoreFeed();
    }
  }

  // -------------------------------------------------------------------------
  // WOF kaydırma ve kategori akışları
  // -------------------------------------------------------------------------
  int sessionLikes = 0;
  int sessionDislikes = 0;

  /// WOF Feed'de açık olan kategori; `null` = bütün kategoriler.
  String? feedCategory;

  /// Okunan haberler: kaydırılan ya da detayı açılan. Cihazda kullanıcıya
  /// göre saklanır; menüdeki okunmamış sayıları buna göre hesaplanır.
  final Set<String> read = {};

  /// Desteden detayı açılan kart okundu sayılır ama kaydırılana kadar
  /// destede kalır; yoksa pencere kapanınca kart kaybolurdu.
  String? _deckHold;

  /// WOF Feed'i [category] ile açar (`null` = bütün kategoriler).
  void openFeed(String? category) {
    if (navIndex == navFeed && feedCategory == category) return;
    feedCategory = category;
    _deckHold = null;
    navIndex = navFeed;
    notifyListeners();
  }

  /// [category] kategorisinin haberleri, kişisel sıralamayla.
  List<Article> feedFor(String? category) => category == null
      ? feed
      : [
          for (final a in feed)
            if (a.macroTags.contains(category) || a.macroTag == category) a,
        ];

  int unreadCount(String? category) =>
      feedFor(category).where((a) => !read.contains(a.id)).length;

  /// Açık sekmenin destesi: okunmamış haberler.
  List<Article> get deck => [
    for (final a in feedFor(feedCategory))
      if (!read.contains(a.id) || a.id == _deckHold) a,
  ];

  Article? get currentFeedArticle => deck.firstOrNull;

  void markRead(String id) {
    if (!read.add(id)) return;
    _persistIds(_kRead, read);
    notifyListeners();
  }

  /// Desteden detayı açılan kartı okundu sayar ama destede tutar.
  void openFromDeck(Article article) {
    _deckHold = article.id;
    markRead(article.id);
  }

  /// Bu oturumda beğenilmeyen haberler. Sunucu bunları akıştan çıkarır;
  /// "Start over" ile aynı kart tekrar geçilirse istek yeniden gönderilmez.
  final Set<String> _disliked = {};

  /// Kartı sağa (beğen) ya da sola (beğenme) kaydırma.
  ///
  /// Beğeni: ilgi vektörü habere doğru kayar, haberin kategorisi ve
  /// etiketleri tercihlere eklenir. Beğenmeme: vektör haberden uzaklaşır,
  /// haber kişisel akıştan çıkar. Sunucu ikisini birbirini dışlayan
  /// sinyaller olarak işler (biri kaydedilince diğeri silinir).
  void react(Article article, {required bool like}) {
    if (like) {
      sessionLikes++;
    } else {
      sessionDislikes++;
    }
    _recordOpinion(article.id, like: like);
    if (_deckHold == article.id) _deckHold = null;
    read.add(article.id);
    _persistIds(_kRead, read);
    notifyListeners();
    // Kartlar bitmeden sonraki sayfayı hazırla.
    if (deck.length <= 3) loadMoreFeed();
  }

  /// Beğeni ya da beğenmemeyi cihazda kaydeder ve sunucuya gönderir.
  /// Aynı haber için tekrar beğenmeme gönderilmez (sunucu her seferinde
  /// vektörü yeniden iterdi).
  void _recordOpinion(String id, {required bool like}) {
    if (like) {
      _disliked.remove(id);
      if (liked.add(id)) {
        _persistIds(_kLiked, liked);
        _syncInteraction(id, InteractionType.like, true);
      }
    } else {
      if (liked.remove(id)) _persistIds(_kLiked, liked);
      if (_disliked.add(id)) {
        _syncInteraction(id, InteractionType.dislike, true);
      }
    }
  }

  /// Açık sekmenin haberlerini yeniden okunmamış yapar ("Show them again").
  void rereadFeed() {
    read.removeAll(feedFor(feedCategory).map((a) => a.id));
    _persistIds(_kRead, read);
    sessionLikes = 0;
    sessionDislikes = 0;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Günün özeti
  // -------------------------------------------------------------------------
  /// Ana sayfadaki karşılaştırmalı özetin kullandığı haber sayısı
  /// (giriş yapılmamışsa).
  static const briefSize = 3;

  String? brief;
  bool briefLoading = false;
  ApiException? briefError;

  /// Giriş yapılmışsa "Latest developments" kartının başlığı; genel özette
  /// `null`.
  String? briefTitle;

  List<Article> _briefSources = const [];
  int _briefGeneration = 0;

  /// Sunucu kartı arka planda yeniliyorsa bu kadar sonra bir kez daha sorulur.
  static const briefRefreshDelay = Duration(seconds: 8);

  /// Özetin kaynak haberleri. Giriş yapılmışsa "Latest developments"
  /// kartının yazıldığı haberler, değilse akışın ilk haberleri.
  List<Article> get briefArticles =>
      hasServerUser ? _briefSources : feed.take(briefSize).toList();

  /// Akışı yükler ve ana sayfa özetini bir kez üretir.
  ///
  /// Giriş yapılmışsa `GET /api/users/{id}/latest-developments`: en üstteki
  /// haberlerden yazılmış başlık ([briefTitle]) ve paragraf ([brief]); ilk
  /// üretim ~2 sn, sonra önbellekten. Tavily kredisi harcamaz. Değilse ilk
  /// haberler `synthesize` ile karşılaştırılır (~15-25 sn).
  Future<void> loadBrief() async {
    if (briefLoading || brief != null) return;
    // Bayrağı hemen koy ki eşzamanlı çağrılar ikinci bir istek başlatmasın.
    briefLoading = true;
    briefError = null;
    final generation = _briefGeneration;
    try {
      if (hasServerUser) {
        // Akış ve özet birbirini beklemeden yüklenir.
        ensureFeed();
        await Future<void>.value();
        notifyListeners();
        final latest = await api.getLatestDevelopments(user!.id);
        if (generation != _briefGeneration) return;
        _applyLatest(latest);
        if (latest.refreshing) _refreshBriefLater(generation);
      } else {
        await ensureFeed();
        final ids = briefArticles.map((a) => a.id).toList();
        if (ids.length < 2) return;
        await Future<void>.value();
        notifyListeners();
        final text = await api.synthesizeArticles(ids);
        if (generation != _briefGeneration) return;
        brief = text;
      }
    } on ApiException catch (e) {
      if (generation == _briefGeneration) briefError = e;
    } finally {
      if (generation == _briefGeneration) {
        briefLoading = false;
        notifyListeners();
      }
    }
  }

  void _applyLatest(LatestDevelopments latest) {
    _remember(latest.articles);
    _briefSources = latest.articles;
    briefTitle = latest.headline;
    brief = latest.paragraph;
  }

  /// Sunucu kartı arka planda yeniliyor: biraz sonra sessizce tekrar sorar;
  /// hata olursa eldeki kart kalır.
  void _refreshBriefLater(int generation) {
    Future<void>.delayed(briefRefreshDelay, () async {
      final current = user;
      if (generation != _briefGeneration || current == null) return;
      try {
        final latest = await api.getLatestDevelopments(current.id);
        if (generation != _briefGeneration) return;
        _applyLatest(latest);
        notifyListeners();
      } on ApiException {
        // Eldeki kart gösterilmeye devam eder.
      }
    });
  }

  // -------------------------------------------------------------------------
  // Arama (üst bardan Keşfet'e)
  // -------------------------------------------------------------------------
  String searchQuery = '';

  void search(String query) {
    searchQuery = query.trim();
    navIndex = navDiscover;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    if (searchQuery == query) return;
    searchQuery = query;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Kaydedilenler / beğeniler
  // -------------------------------------------------------------------------
  /// Cihazda kullanıcı başına tutulur ve sunucuya da gönderilir. Sunucuda
  /// listeleme uç noktası olmadığı için listeler cihazdan gösterilir.
  final Set<String> saved = {};
  final Set<String> liked = {};

  bool isSaved(String id) => saved.contains(id);
  bool isLiked(String id) => liked.contains(id);

  void toggleSaved(String id) {
    final active = saved.add(id);
    if (!active) saved.remove(id);
    _persistIds(_kSaved, saved);
    _syncInteraction(id, InteractionType.bookmark, active);
    notifyListeners();
  }

  void toggleLiked(String id) {
    final active = liked.add(id);
    if (!active) liked.remove(id);
    // Sunucu beğeni kaydedilince beğenmemeyi siler.
    if (active) _disliked.remove(id);
    _persistIds(_kLiked, liked);
    _syncInteraction(id, InteractionType.like, active);
    notifyListeners();
  }

  List<Article> get savedArticles => _known(saved);
  List<Article> get likedArticles => _known(liked);

  /// Önbellekte olanlar, en son eklenen önce.
  List<Article> _known(Set<String> ids) =>
      ids.toList().reversed.map(articleById).whereType<Article>().toList();

  /// Aynı haber için istekler sırayla gönderilir; sunucu aç/kapa çalıştığı
  /// için üst üste tıklamalar birbirini bozmasın. Beğeni ve beğenmeme
  /// sunucuda birbirini sildiği için aynı sırayı paylaşır.
  final Map<String, Future<void>> _interactionQueue = {};

  void _syncInteraction(String articleId, InteractionType type, bool active) {
    final current = user;
    if (current == null || !hasServerUser) return;
    final lane = type == InteractionType.bookmark ? 'bookmark' : 'opinion';
    final key = '$lane:$articleId';
    final previous = _interactionQueue[key] ?? Future<void>.value();
    late final Future<void> next;
    next = previous.then((_) async {
      try {
        final result = await api.setInteraction(
          articleId,
          userId: current.id,
          type: type,
          active: active,
        );
        _applyLearnedPreferences(current.id, result);
      } on ApiException {
        // Cihazdaki durum korunur; kişisel akış bir sonraki yüklemede
        // sunucudaki beğeni durumunu (`is_liked`) geri getirir.
      }
      if (identical(_interactionQueue[key], next)) {
        _interactionQueue.remove(key);
      }
    });
    _interactionQueue[key] = next;
  }

  /// Sunucu beğeni / beğenmeme sonrası tercihleri kendisi günceller
  /// (beğenilen haberin kategorisi ve etiketleri eklenir, beğenilmeyenin
  /// etiketleri çıkarılır). Profil ve akış paneli güncel listeyi göstersin.
  void _applyLearnedPreferences(String userId, InteractionResult result) {
    final current = user;
    final macros = result.preferredMacroTags;
    final micros = result.preferredMicroTags;
    if (current == null || current.id != userId) return;
    if (macros == null && micros == null) return;
    user = current.copyWith(
      preferredMacroTags: macros,
      preferredMicroTags: micros,
    );
    notifyListeners();
  }

  /// Kayıtlar kullanıcı adına göre ayrı tutulur; aynı cihazda iki hesap
  /// birbirinin listesini görmez.
  String _libraryKey(String base) => '$base:${user?.username ?? ''}';

  void _loadLibrary() {
    saved
      ..clear()
      ..addAll(_readIds(_kSaved));
    liked
      ..clear()
      ..addAll(_readIds(_kLiked));
    read
      ..clear()
      ..addAll(_readIds(_kRead));
  }

  List<String> _readIds(String base) {
    final prefs = _prefs;
    if (prefs == null) return const [];
    // Eski sürüm kayıtları kullanıcıdan bağımsız anahtarda tutuyordu.
    return prefs.getStringList(_libraryKey(base)) ??
        prefs.getStringList(base) ??
        const [];
  }

  void _persistIds(String base, Set<String> ids) =>
      _prefs?.setStringList(_libraryKey(base), ids.toList());

  // -------------------------------------------------------------------------
  // WAI sohbeti
  // -------------------------------------------------------------------------
  /// Sohbetler, açılış sırasıyla. Anahtar kapsamı belirtir: `story:<haber>`,
  /// `latest` ya da `area:<alan>`; aynı kapsam ikinci kez açılırsa eski sohbete
  /// dönülür.
  final Map<String, WaiThread> threads = {};
  String? activeThreadId;

  WaiThread? get activeThread => threads[activeThreadId];

  List<ChatMessage> get activeMessages => activeThread?.messages ?? const [];

  /// Haber sohbetinin haberi; diğer sohbetlerde `null`.
  Article? get activeThreadArticle => activeThread?.article;

  /// Aktif sohbette WAI şu an yazıyor mu?
  bool get waiTyping => activeMessages.any((m) => m.streaming);

  void openThread(String id) {
    activeThreadId = id;
    notifyListeners();
  }

  /// Alan seçme ekranına döner.
  void startNewChat() {
    activeThreadId = null;
    notifyListeners();
  }

  /// Haber kartından: WAI haberin tam metnini okur ve sohbeti kendisi açar.
  void askAbout(Article article) {
    _remember([article]);
    _startThread(
      WaiThread(
        id: 'story:${article.id}',
        mode: WaiMode.story,
        title: article.title,
        article: article,
      ),
    );
  }

  /// Ana sayfadaki "Latest developments" kartından: WAI kartı ve arkasındaki
  /// haberleri okur.
  void askLatest() => _startThread(
    WaiThread(
      id: 'latest',
      mode: WaiMode.latest,
      title: briefTitle ?? 'Your latest developments',
    ),
  );

  /// WAI sekmesinde seçilen alan (kategori ya da alt konu): WAI o alanın son
  /// haberlerini okur.
  void askArea(String area, {required String label}) => _startThread(
    WaiThread(id: 'area:$area', mode: WaiMode.area, title: label, area: area),
  );

  void _startThread(WaiThread thread) {
    activeThreadId = thread.id;
    navIndex = navChat;
    if (threads.containsKey(thread.id)) {
      notifyListeners();
      return;
    }
    threads[thread.id] = thread;
    if (thread.article != null) {
      thread.messages.add(
        ChatMessage(role: ChatRole.user, article: thread.article),
      );
    }
    _openThread(thread);
  }

  /// WAI kapsamı okur ve ilk mesajı yazar (`POST /api/wai/open`). Sunucu
  /// kullanıcısı yoksa haber sohbeti eski uçla çalışır ve sabit bir giriş
  /// gösterilir.
  Future<void> _openThread(WaiThread thread) async {
    final reply = ChatMessage(
      role: ChatRole.assistant,
      streaming: true,
      isOpening: true,
    );
    thread.messages.add(reply);
    notifyListeners();
    final current = user;
    try {
      if (!hasServerUser || current == null) {
        reply.text = "I've read this story. What would you like to know?";
      } else {
        final opening = await api.openWai(
          userId: current.id,
          mode: thread.mode.name,
          articleId: thread.article?.id,
          area: thread.area,
        );
        if (opening.title.isNotEmpty) thread.title = opening.title;
        thread
          ..subtitle = opening.subtitle
          ..sources = opening.sources;
        _remember(opening.sources);
        reply.text = opening.opening;
      }
    } on ApiException catch (e) {
      reply
        ..isError = true
        ..text = e.userMessage;
    } finally {
      reply.streaming = false;
      reply.time = DateTime.now();
      notifyListeners();
    }
  }

  Future<void> send(String text) async {
    final question = text.trim();
    final thread = activeThread;
    if (question.isEmpty || thread == null || waiTyping) return;
    thread.messages.add(ChatMessage(role: ChatRole.user, text: question));
    await _answer(thread, question);
  }

  /// Hatalı yanıtı siler ve aynı soruyu yeniden sorar; açılış mesajıysa
  /// sohbeti yeniden açar.
  Future<void> retry(ChatMessage failed) async {
    final thread = activeThread;
    if (thread == null || waiTyping) return;
    final messages = thread.messages;
    final index = messages.indexOf(failed);
    if (index < 0) return;
    messages.removeAt(index);
    if (failed.isOpening) {
      await _openThread(thread);
      return;
    }
    final question = messages
        .take(index)
        .lastWhere(
          (m) => m.role == ChatRole.user && m.text.isNotEmpty,
          orElse: () => ChatMessage(role: ChatRole.user),
        )
        .text;
    if (question.isEmpty) {
      notifyListeners();
      return;
    }
    await _answer(thread, question);
  }

  Future<void> _answer(WaiThread thread, String question) async {
    // Sunucuya giden geçmiş: bu sorudan önceki başarılı turlar (WAI'nin
    // açılış mesajı dahil; "evet" gibi kısa cevaplar ona göre anlaşılır).
    final history = <ChatTurn>[
      for (final m in thread.messages)
        if (m.text.isNotEmpty && !m.isError && m.article == null)
          m.role == ChatRole.user
              ? ChatTurn.user(m.text)
              : ChatTurn.assistant(m.text),
    ];
    if (history.isNotEmpty) history.removeLast(); // Sorunun kendisi.

    final reply = ChatMessage(role: ChatRole.assistant, streaming: true);
    thread.messages.add(reply);
    notifyListeners();

    final current = user;
    final stream = hasServerUser && current != null
        ? api.waiChatStream(
            userId: current.id,
            mode: thread.mode.name,
            articleId: thread.article?.id,
            area: thread.area,
            sourceIds: [for (final s in thread.sources) s.id],
            question: question,
            history: history,
          )
        : api.chatStream(
            thread.article!.id,
            question: question,
            history: history,
          );
    // Her parçada değil, en fazla 50 ms'de bir yeniden çiz: parça başına
    // çizim, yazı akarken bütün arayüzü takılttırıyordu.
    final sinceRedraw = Stopwatch()..start();
    try {
      await for (final chunk in stream) {
        reply.text += chunk;
        if (sinceRedraw.elapsedMilliseconds >= 50) {
          sinceRedraw.reset();
          notifyListeners();
        }
      }
    } on ApiException catch (e) {
      reply
        ..isError = true
        ..text = e.userMessage;
    } finally {
      reply.streaming = false;
      reply.time = DateTime.now();
      notifyListeners();
    }
  }

  void toggleHelpful(ChatMessage message) {
    message.helpful = !message.helpful;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Ayarlar (yalnızca bu oturum)
  // -------------------------------------------------------------------------
  ThemeChoice theme = ThemeChoice.dark;

  /// Okuma metinlerine uygulanan yazı ölçeği (1.0 = 16 px).
  double fontScale = 1.0;
  double audioSpeed = 1.25;
  bool notifications = true;
  String language = 'English';

  void setTheme(ThemeChoice value) {
    theme = value;
    notifyListeners();
  }

  void setFontScale(double value) {
    fontScale = value;
    notifyListeners();
  }

  void setAudioSpeed(double value) {
    audioSpeed = value;
    notifyListeners();
  }

  void setNotifications(bool value) {
    notifications = value;
    notifyListeners();
  }

  void setLanguage(String value) {
    language = value;
    notifyListeners();
  }
}

enum ThemeChoice { light, dark, system }

/// Onboarding adımları: 1 seç, 2 tadına bak, 3 akışın hazır.
enum OnboardingStep { pick, taste, reveal }

enum ChatRole { user, assistant }

/// WAI sohbetinin kapsamı: bir haber, ana sayfadaki son gelişmeler ya da
/// WAI sekmesinde seçilen bir alan.
enum WaiMode { story, latest, area }

/// Bir WAI sohbeti: kapsamı, WAI'nin okuduğu haberler ve mesajlar.
class WaiThread {
  WaiThread({
    required this.id,
    required this.mode,
    required this.title,
    this.article,
    this.area,
  });

  final String id;
  final WaiMode mode;

  /// Haber başlığı, son gelişmeler başlığı ya da alan adı (açılınca sunucu
  /// günceller).
  String title;
  String subtitle = '';

  /// Haber sohbetinde haber.
  final Article? article;

  /// Alan sohbetinde kategori (ör. `AI`) ya da alt konu (ör. `fintech`).
  final String? area;

  /// WAI'nin okuduğu haberler; cevaplardaki [1], [2] bu sıraya karşılık gelir.
  List<Article> sources = const [];
  final List<ChatMessage> messages = [];
}

class ChatMessage {
  ChatMessage({
    required this.role,
    this.text = '',
    this.article,
    this.streaming = false,
    this.isOpening = false,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  final ChatRole role;

  /// WAI'nin sohbeti açan ilk mesajı.
  final bool isOpening;

  /// Akış sırasında parça parça büyür.
  String text;

  /// Doluysa mesaj, WAI'ye gönderilen bir haber kartıdır.
  final Article? article;
  DateTime time;
  bool streaming;
  bool isError = false;
  bool helpful = false;
}

/// Sunucunun makro kategorileri (Keşfet etiketleri).
const macroCategories = [
  'Tech',
  'AI',
  'Hardware',
  'Automotive',
  'Gaming',
  'Finance',
  'Science',
];
