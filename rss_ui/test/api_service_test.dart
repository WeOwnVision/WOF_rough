import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:rss_ui/models/api_models.dart';
import 'package:rss_ui/services/api_service.dart';

const _article = {
  'id': '82a5ecf9-e6ab-4152-afae-5ca536361bd5',
  'source': 'Wired',
  'title': 'Automakers Accelerate Next-Gen Solid-State Battery Roadmaps',
  'url': 'https://wired.com/x',
  'author': 'Steven Levy',
  'published_at': '2026-10-08T10:00:00+00:00',
  'macro_tag': 'Tech',
  'macro_tags': ['Tech', 'Hardware'],
  'micro_tags': ['solid_state_battery'],
  'tldr': 'Batteries are getting better.',
};

const _benchmark = {
  'id': 'dc5c5475-1427-4e29-a486-d9fcb771daff',
  'source': 'Benchmark News',
  'title': 'Automated Pipeline Integrity Verification Article',
  'url': 'https://eval.example.com/x',
  'author': 'QA Bot',
  'published_at': '2026-10-10T12:00:00+00:00',
  'macro_tag': null,
  'macro_tags': <String>[],
  'micro_tags': null,
  'tldr': null,
};

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

ApiService _api(MockClientHandler handler) =>
    ApiService(baseUrl: 'https://api.test/', client: MockClient(handler));

void main() {
  group('getArticles', () {
    test('sends page/page_size and bypass header, hides test data', () async {
      late http.Request sent;
      final api = _api((req) async {
        sent = req;
        return _json([_article, _benchmark]);
      });

      final articles = await api.getArticles(
        page: 2,
        pageSize: 5,
        macro: 'Tech',
      );

      expect(sent.url.path, '/api/articles');
      expect(sent.url.queryParameters, {
        'page': '2',
        'page_size': '5',
        'macro': 'Tech',
      });
      expect(sent.headers['bypass-tunnel-reminder'], 'true');
      expect(articles, hasLength(1));
      final a = articles.single;
      expect(a.source, 'Wired');
      expect(a.macroTags, ['Tech', 'Hardware']);
      expect(a.publishedAt, DateTime.utc(2026, 10, 8, 10));
    });

    test('clamps invalid paging values', () async {
      late Uri url;
      final api = _api((req) async {
        url = req.url;
        return _json([]);
      });
      await api.getArticles(page: 0, pageSize: 1000);
      expect(url.queryParameters['page'], '1');
      expect(url.queryParameters['page_size'], '100');
    });

    test('page of only test data still reports hasMore', () async {
      final api = _api((_) async => _json([_benchmark, _benchmark]));
      final page = await api.getArticlePage(pageSize: 2);
      expect(page.items, isEmpty);
      expect(page.hasMore, isTrue);
    });

    test('null macro_tags falls back to macro_tag', () {
      final a = Article.fromJson({..._article, 'macro_tags': null});
      expect(a.macroTags, ['Tech']);
    });
  });

  group('errors', () {
    test('tunnel down (503 plain text) -> unavailable', () async {
      final api = _api(
        (_) async => http.Response('503 - Tunnel Unavailable', 503),
      );
      await expectLater(
        api.getArticles(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.unavailable)
              .having(
                (e) => e.userMessage,
                'userMessage',
                contains('Server unavailable'),
              ),
        ),
      );
    });

    test('500 -> server with generic English message', () async {
      final api = _api(
        (_) async => http.Response('Internal Server Error', 500),
      );
      await expectLater(
        api.getArticle('abc'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.server)
              .having(
                (e) => e.userMessage,
                'userMessage',
                'Something went wrong. Please try again.',
              ),
        ),
      );
    });

    test('422 validation detail is surfaced', () async {
      final api = _api(
        (_) async => _json({
          'detail': [
            {'msg': 'String should have at least 2 characters'},
          ],
        }, 422),
      );
      await expectLater(
        api.getUsers(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'String should have at least 2 characters',
          ),
        ),
      );
    });

    test('network failure -> network', () async {
      final api = _api(
        (_) async => throw http.ClientException('XMLHttpRequest error'),
      );
      await expectLater(
        api.getArticles(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.network,
          ),
        ),
      );
    });

    test('non-JSON 200 -> invalidResponse', () async {
      final api = _api((_) async => http.Response('<html>tunnel</html>', 200));
      await expectLater(
        api.getArticles(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.invalidResponse,
          ),
        ),
      );
    });
  });

  group('search', () {
    test('short query does not hit the server', () async {
      var calls = 0;
      final api = _api((_) async {
        calls++;
        return _json([]);
      });
      expect(await api.searchArticles(' a '), isEmpty);
      expect((await api.searchGrouped('a')).isEmpty, isTrue);
      expect(calls, 0);
    });

    test('grouped search parses direct/explore', () async {
      late Uri url;
      final api = _api((req) async {
        url = req.url;
        return _json({
          'query': 'battery',
          'total_direct': 1,
          'total_explore': 1,
          'direct': [
            {..._article, 'match_tier': 'direct', 'relevance_score': 91},
          ],
          'explore': [
            {
              ..._article,
              'id': 'other',
              'match_tier': 'explore',
              'relevance_score': 62,
              'possibility': 'Adjacent Horizon',
              'explore_angle': 'Energy & Materials',
            },
            {..._benchmark, 'match_tier': 'explore'},
          ],
        });
      });

      final r = await api.searchGrouped('battery');
      expect(url.queryParameters, {'q': 'battery', 'grouped': 'true'});
      expect(r.direct.single.isDirect, isTrue);
      expect(r.direct.single.relevanceScore, 91);
      expect(r.explore, hasLength(1));
      expect(r.explore.single.exploreAngle, 'Energy & Materials');
    });
  });

  group('chat', () {
    test('sends question + last 4 history turns, returns text', () async {
      late Map<String, dynamic> body;
      final api = _api((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode('Solid‑state batteries charge in 10 minutes.'),
          200,
          headers: {'content-type': 'text/plain; charset=utf-8'},
        );
      });

      final answer = await api.chatWithArticle(
        'id-1',
        question: ' Why? ',
        history: [for (var i = 0; i < 6; i++) ChatTurn.user('q$i')],
      );

      expect(answer, 'Solid‑state batteries charge in 10 minutes.');
      expect(body['question'], 'Why?');
      expect((body['history'] as List).map((t) => t['content']), [
        'q2',
        'q3',
        'q4',
        'q5',
      ]);
    });

    test('empty 200 body -> emptyResponse', () async {
      final api = _api((_) async => http.Response('', 200));
      await expectLater(
        api.chatWithArticle('id-1', question: 'hi'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.emptyResponse)
              .having(
                (e) => e.userMessage,
                'userMessage',
                'Something went wrong. Please try again.',
              ),
        ),
      );
    });

    test('whitespace-only body -> emptyResponse', () async {
      final api = _api((_) async => http.Response('  \n ', 200));
      await expectLater(
        api.chatWithArticle('id-1', question: 'hi'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.emptyResponse,
          ),
        ),
      );
    });
  });

  group('sse', () {
    ApiService sse(List<String> chunks) => ApiService(
      baseUrl: 'https://api.test',
      client: MockClient.streaming(
        (req, _) async => http.StreamedResponse(
          Stream.fromIterable(chunks.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        ),
      ),
    );

    test('joins tokens split across chunks and stops at [DONE]', () async {
      final api = sse([
        'data: {"token": "Hel',
        'lo"}\n\ndata: {"token": " wor',
        'ld"}\r\n\r\ndata: {"token": "\u202f!"}\n\ndata: [DONE]\n\n',
        'data: {"token": "ignored"}\n\n',
      ]);
      expect(
        await api.chatWithArticle('a', question: 'q'),
        'Hello world\u202f!',
      );
    });

    test('error event -> server error', () async {
      final api = sse([
        'data: {"token": "Hi"}\n\n',
        'data: {"error": "model crashed"}\n\n',
      ]);
      await expectLater(
        api.chatWithArticle('a', question: 'q'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.server)
              .having((e) => e.message, 'message', 'model crashed'),
        ),
      );
    });

    test('only [DONE] -> emptyResponse', () async {
      final api = sse(['data: [DONE]\n\n']);
      await expectLater(
        api.chatWithArticle('a', question: 'q'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.emptyResponse,
          ),
        ),
      );
    });

    test('synthesize stream yields markdown tokens', () async {
      final api = sse([
        'data: {"token": "**1."}\n\ndata: {"token": " Shared**"}\n\n',
        'data: [DONE]\n\n',
      ]);
      expect(await api.synthesizeArticles(['a', 'b']), '**1. Shared**');
    });
  });

  group('synthesize', () {
    test('needs at least 2 ids', () async {
      final api = _api((_) async => fail('should not be called'));
      await expectLater(
        api.synthesizeArticles(['one']),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.badRequest,
          ),
        ),
      );
    });

    test('returns markdown text', () async {
      final api = _api(
        (_) async => http.Response('**1. Shared Consensus**', 200),
      );
      expect(
        await api.synthesizeArticles(['a', 'b']),
        '**1. Shared Consensus**',
      );
    });
  });

  group('users & comments', () {
    const user = AppUser(
      id: 'u1',
      username: 'can_test',
      avatarUrl: 'https://a/x',
    );

    test('login trims and parses user', () async {
      late Map<String, dynamic> body;
      final api = _api((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({
          'id': 'u1',
          'username': 'can_test',
          'avatar_url': 'https://a/x',
        });
      });
      final u = await api.login('  can_test ');
      expect(body, {'username': 'can_test'});
      expect(u.id, 'u1');
    });

    test('empty username is rejected locally', () async {
      final api = _api((_) async => fail('should not be called'));
      await expectLater(api.login('  '), throwsA(isA<ApiException>()));
    });

    test('postComment fills the comment from the response id', () async {
      late Map<String, dynamic> body;
      final api = _api((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({'id': 'c1', 'created_at': '2026-10-12T10:00:00+00:00'});
      });
      final c = await api.postComment(
        'a1',
        user: user,
        commentText: ' Nice ',
        selectedText: '',
      );
      expect(body, {'user_id': 'u1', 'comment_text': 'Nice'});
      expect(c.id, 'c1');
      expect(c.username, 'can_test');
      expect(c.comment, 'Nice');
    });

    test('getComments maps the "comment" field', () async {
      final api = _api(
        (_) async => _json([
          {
            'id': 'c1',
            'selected_text': 'Steam Deck 2',
            'comment': 'Great',
            'created_at': '2026-10-12T10:00:00+00:00',
            'username': 'alice',
            'avatar_url': null,
          },
        ]),
      );
      final c = (await api.getComments('a1')).single;
      expect(c.comment, 'Great');
      expect(c.selectedText, 'Steam Deck 2');
    });
  });
}
