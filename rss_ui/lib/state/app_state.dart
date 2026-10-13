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

  SharedPreferences? _prefs;
  bool _initialized = false;

  AppUser? user;

  /// Açılışta kayıtlı kullanıcıyla giriş denenirken `true`.
  bool sessionLoading = true;
  bool loggingIn = false;
  ApiException? sessionError;

  /// Tercihleri yükler ve daha önce giriş yapılmışsa sessizce tekrar dener.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      _cache = LocalCache(_prefs!);
      saved.addAll(_prefs!.getStringList(_kSaved) ?? const []);
      liked.addAll(_prefs!.getStringList(_kLiked) ?? const []);
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
          id: 'local-${username.trim()}',
          username: username.trim(),
        );
        await _prefs?.setString(_kUsername, user!.username);
      } else {
        sessionError = e;
      }
    } finally {
      loggingIn = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    user = null;
    sessionError = null;
    navIndex = navHome;
    await _prefs?.remove(_kUsername);
    notifyListeners();
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
    return _feedRequest = _loadMoreFeed().whenComplete(() {
      _feedRequest = null;
    });
  }

  Future<void> _loadMoreFeed() async {
    // Sayfaların initState'inden çağrılabilir; çizim bitince bildir.
    await Future<void>.value();
    notifyListeners();
    try {
      var added = 0;
      while (added == 0 && feedHasMore) {
        final page = await api.getArticlePage(
          page: _feedPage + 1,
          pageSize: pageSize,
        );
        _feedPage++;
        feedHasMore = page.hasMore;
        final known = feed.map((a) => a.id).toSet();
        final fresh = page.items.where((a) => !known.contains(a.id)).toList();
        _remember(fresh);
        feed.addAll(fresh);
        added = fresh.length;
      }
      // Server responded — replace local cache with fresh data.
      _offline = false;
      _cache?.saveArticles(feed);
    } on ApiException catch (e) {
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
      feedLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshFeed() async {
    feed.clear();
    _feedPage = 0;
    feedHasMore = true;
    feedIndex = 0;
    _offline = false;
    brief = null;
    briefError = null;
    await loadMoreFeed();
  }

  // -------------------------------------------------------------------------
  // WOF kaydırma
  // -------------------------------------------------------------------------
  int feedIndex = 0;
  int sessionLikes = 0;
  int sessionDislikes = 0;

  Article? get currentFeedArticle =>
      feedIndex < feed.length ? feed[feedIndex] : null;

  void react(Article article, {required bool like}) {
    if (like) {
      liked.add(article.id);
      sessionLikes++;
    } else {
      liked.remove(article.id);
      sessionDislikes++;
    }
    _persistIds(_kLiked, liked);
    feedIndex++;
    notifyListeners();
    // Kartlar bitmeden sonraki sayfayı hazırla.
    if (feed.length - feedIndex <= 3) loadMoreFeed();
  }

  void restartFeed() {
    feedIndex = 0;
    sessionLikes = 0;
    sessionDislikes = 0;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Günün özeti (synthesize)
  // -------------------------------------------------------------------------
  /// Ana sayfadaki karşılaştırmalı özetin kullandığı haber sayısı.
  static const briefSize = 3;

  String? brief;
  bool briefLoading = false;
  ApiException? briefError;

  List<Article> get briefArticles => feed.take(briefSize).toList();

  /// İlk haberlerin karşılaştırmalı özetini bir kez üretir (~15-25 sn).
  Future<void> loadBrief() async {
    if (briefLoading || brief != null) return;
    // Bayrağı hemen koy ki eşzamanlı çağrılar ikinci bir istek başlatmasın.
    briefLoading = true;
    briefError = null;
    try {
      await ensureFeed();
      final ids = briefArticles.map((a) => a.id).toList();
      if (ids.length < 2) return;
      await Future<void>.value();
      notifyListeners();
      brief = await api.synthesizeArticles(ids);
    } on ApiException catch (e) {
      briefError = e;
    } finally {
      briefLoading = false;
      notifyListeners();
    }
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
  // Kaydedilenler / beğeniler (cihazda)
  // -------------------------------------------------------------------------
  final Set<String> saved = {};
  final Set<String> liked = {};

  bool isSaved(String id) => saved.contains(id);
  bool isLiked(String id) => liked.contains(id);

  void toggleSaved(String id) {
    if (!saved.remove(id)) saved.add(id);
    _persistIds(_kSaved, saved);
    notifyListeners();
  }

  void toggleLiked(String id) {
    if (!liked.remove(id)) liked.add(id);
    _persistIds(_kLiked, liked);
    notifyListeners();
  }

  List<Article> get savedArticles => _known(saved);
  List<Article> get likedArticles => _known(liked);

  /// Önbellekte olanlar, en son eklenen önce.
  List<Article> _known(Set<String> ids) =>
      ids.toList().reversed.map(articleById).whereType<Article>().toList();

  void _persistIds(String key, Set<String> ids) =>
      _prefs?.setStringList(key, ids.toList());

  // -------------------------------------------------------------------------
  // WAI sohbeti
  // -------------------------------------------------------------------------
  /// Haber kimliği → mesajlar. Sıra, eklenme sırasıdır.
  final Map<String, List<ChatMessage>> threads = {};
  String? activeThreadId;

  List<ChatMessage> get activeMessages => threads[activeThreadId] ?? const [];

  Article? get activeThreadArticle =>
      activeThreadId == null ? null : articleById(activeThreadId!);

  /// Aktif sohbette WAI şu an yazıyor mu?
  bool get waiTyping => activeMessages.any((m) => m.streaming);

  void openThread(String id) {
    activeThreadId = id;
    notifyListeners();
  }

  /// Haber seçme ekranına döner.
  void startNewChat() {
    activeThreadId = null;
    notifyListeners();
  }

  /// Bir haberi WAI'ye gönderir ve sohbet sayfasına geçer.
  void askAbout(Article article) {
    _remember([article]);
    threads.putIfAbsent(
      article.id,
      () => [ChatMessage(role: ChatRole.user, article: article)],
    );
    activeThreadId = article.id;
    navIndex = navChat;
    notifyListeners();
  }

  Future<void> send(String text) async {
    final question = text.trim();
    final threadId = activeThreadId;
    if (question.isEmpty || threadId == null || waiTyping) return;
    threads[threadId]!.add(ChatMessage(role: ChatRole.user, text: question));
    await _answer(threadId, question);
  }

  /// Hatalı yanıtı siler ve aynı soruyu yeniden sorar.
  Future<void> retry(ChatMessage failed) async {
    final threadId = activeThreadId;
    if (threadId == null || waiTyping) return;
    final thread = threads[threadId]!;
    final index = thread.indexOf(failed);
    if (index <= 0) return;
    final question = thread
        .take(index)
        .lastWhere(
          (m) => m.role == ChatRole.user && m.text.isNotEmpty,
          orElse: () => ChatMessage(role: ChatRole.user),
        )
        .text;
    thread.removeAt(index);
    if (question.isEmpty) {
      notifyListeners();
      return;
    }
    await _answer(threadId, question);
  }

  Future<void> _answer(String threadId, String question) async {
    final thread = threads[threadId]!;
    // Sunucuya giden geçmiş: bu sorudan önceki başarılı turlar.
    final history = <ChatTurn>[
      for (final m in thread)
        if (m.text.isNotEmpty && !m.isError && m.article == null)
          m.role == ChatRole.user
              ? ChatTurn.user(m.text)
              : ChatTurn.assistant(m.text),
    ];
    if (history.isNotEmpty) history.removeLast(); // Sorunun kendisi.

    final reply = ChatMessage(role: ChatRole.assistant, streaming: true);
    thread.add(reply);
    notifyListeners();

    try {
      await for (final chunk in api.chatStream(
        threadId,
        question: question,
        history: history,
      )) {
        reply.text += chunk;
        notifyListeners();
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
  final Set<String> interests = {'AI', 'Hardware', 'Science'};

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

  void toggleInterest(String value) {
    if (!interests.remove(value)) interests.add(value);
    notifyListeners();
  }
}

enum ThemeChoice { light, dark, system }

enum ChatRole { user, assistant }

class ChatMessage {
  ChatMessage({
    required this.role,
    this.text = '',
    this.article,
    this.streaming = false,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  final ChatRole role;

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
