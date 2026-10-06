import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xs/src/models/danmaku_source.dart';
import 'package:xs/src/models/image_search_result.dart';
import 'package:xs/src/models/website_source.dart';
import 'package:xs/src/services/episode_danmaku.dart';
import 'package:xs/src/services/image_search.dart';
import 'package:xs/src/services/platform_danmaku.dart';
import 'package:xs/src/services/website_sources.dart';
import 'package:xs/src/utils/embedded_json.dart';
import 'package:xs/src/utils/subtitle_language.dart';

class _ControlledLoader implements DanmakuLoader {
  final streams = <String, StreamController<List<SourceComment>>>{};
  final tokens = <CancelToken>[];
  @override
  Stream<List<SourceComment>> load(DanmakuBinding binding, CancelToken token) {
    tokens.add(token);
    return (streams[binding.id] = StreamController<List<SourceComment>>())
        .stream;
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
          Future<void>? cancelFuture) async =>
      respond(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(dynamic value) =>
    ResponseBody.fromString(jsonEncode(value), 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });

void main() {
  test('Bilibili search retains a working type when another is restricted',
      () async {
    final client = Dio()
      ..httpClientAdapter = _Adapter((options) {
        if (options.queryParameters['search_type'] == 'video')
          return _json({'code': -412});
        return _json({
          'code': 0,
          'data': {
            'result': [
              {
                'title': '<em>测试</em>番剧',
                'url': 'https://www.bilibili.com/bangumi/play/ss687'
              }
            ]
          }
        });
      });
    final result = await PlatformDanmaku(client: client)
        .search(DanmakuProvider.bilibili, '测试');
    expect(result.single.title, '测试番剧');
  });

  test('Bilibili episode URL uses the required referer and exact episode CID',
      () async {
    final client = Dio()
      ..httpClientAdapter = _Adapter((options) {
        expect(options.headers['Referer'], 'https://www.bilibili.com/');
        expect(options.queryParameters['ep_id'], '248694');
        return _json({
          'code': 0,
          'result': {
            'title': '番剧',
            'episodes': [
              {'id': 248693, 'cid': 111, 'title': '1', 'duration': 1440000},
              {'id': 248694, 'cid': 222, 'title': '2', 'duration': 1440000}
            ]
          }
        });
      });
    final result = await PlatformDanmaku(client: client).resolve(
        DanmakuProvider.bilibili,
        'https://www.bilibili.com/bangumi/play/ep248694');
    expect(result.single.id, '222');
    expect(result.single.durationSeconds, 1440);
  });

  test('Tencent search RPC and pagination fill episodes omitted by preview',
      () async {
    var pages = 0;
    final client = Dio()
      ..httpClientAdapter = _Adapter((options) {
        if (options.method == 'POST') {
          expect(options.data['query'], '测试');
          return _json({
            'ret': 0,
            'data': {
              'normalList': {
                'itemList': [
                  {
                    'doc': {'id': 'abcdefghijklmno', 'dataType': 2},
                    'videoInfo': {'title': '测试'}
                  }
                ]
              }
            }
          });
        }
        pages++;
        final episode = options.queryParameters['scene'] == 8 ? 1 : 2;
        return _json({
          'ret': 0,
          'data': {
            'errorCode': 0,
            'normalList': {
              'itemList': [
                {
                  'videoInfo': {
                    'firstBlockSites': [
                      {
                        'enName': 'qq',
                        'episodeInfoList': [
                          {
                            'title': '$episode',
                            'url':
                                'https://v.qq.com/x/page/v123456789$episode.html',
                            'duration': '1440'
                          }
                        ]
                      }
                    ]
                  }
                }
              ]
            }
          }
        });
      });
    final service = PlatformDanmaku(client: client);
    final result = await service.search(DanmakuProvider.tencent, '测试');
    final episodes =
        await service.resolve(DanmakuProvider.tencent, result.single.url);
    expect(episodes.map((e) => e.id), ['v1234567891', 'v1234567892']);
    expect(pages, 3);
  });

  test('Ciyuan search uses video_id and site headers while resolving sections',
      () async {
    final client = Dio()
      ..httpClientAdapter = _Adapter((options) {
        expect(options.headers['X-App-Name'], 'cyc_web');
        if (options.path.endsWith('/search'))
          return _json({
            'code': 0,
            'data': {
              'list': [
                {'video_id': 42, 'title': '测试番剧'}
              ]
            }
          });
        if (options.path.endsWith('/sections'))
          return _json({
            'code': 0,
            'data': {
              'list': [
                {'id': 99, 'title': '第01集'}
              ],
              'pager': {'total': 1}
            }
          });
        expect(options.path, endsWith('/videos/42'));
        return _json({
          'code': 0,
          'data': {
            'play_from': [
              {'code': 'cychub', 'title': 'CYC_Main'}
            ]
          }
        });
      });
    final service = WebsiteSources(client: client);
    final anime =
        (await service.search(WebsiteProvider.ciyuancheng, '测试')).single;
    expect(anime.id, '42');
    final ep = (await service.episodes(anime)).single;
    expect(ep.id, '99');
    expect(SubtitleLanguage.fromMetadata(ep.subtitleMetadata),
        SubtitleLanguage.unknown);
  });

  test('Giri verification preserves the session cookie for human input',
      () async {
    final client = Dio()
      ..httpClientAdapter = _Adapter((options) {
        if (options.path.contains('verify_check')) {
          expect(options.headers['Cookie'], contains('PHPSESSID=test-session'));
          expect(options.queryParameters['verify'], '1234');
          return _json({'code': 1});
        }
        return ResponseBody.fromString(
            '<img class="ds-verify-img" src="/verify/index.html">', 200,
            headers: {
              'content-type': ['text/html'],
              'set-cookie': ['PHPSESSID=test-session; Path=/; HttpOnly']
            });
      });
    final service = WebsiteSources(client: client);
    await expectLater(
        service.search(WebsiteProvider.girigirilove, '测试'),
        throwsA(isA<WebsiteVerificationRequired>().having((e) => e.captchaUrl,
            'captcha URL', 'https://ani.girigirilove.com/verify/index.html')));
    expect(await service.verifyCaptcha('1234', 'search'), isTrue);
    expect(
        WebsiteSources.parseGirigiriSearch(
                '<div class="public-list-box"><a href="/GV27206/" title="测试番剧">封面</a></div>',
                WebsiteProvider.girigirilove.baseUrl)
            .single
            .url,
        'https://ani.girigirilove.com/GV27206/');
  });

  test(
      'subtitle labels require evidence; titles and bilingual audio are unknown',
      () {
    expect(SubtitleLanguage.fromMetadata('1080P · CHS / JPN 双语'),
        SubtitleLanguage.simplified);
    expect(SubtitleLanguage.fromMetadata('繁體中文'), SubtitleLanguage.traditional);
    expect(
        SubtitleLanguage.fromMetadata('zh-Hans'), SubtitleLanguage.simplified);
    expect(
        SubtitleLanguage.fromMetadata('CHS & CHT'), SubtitleLanguage.unknown);
    expect(SubtitleLanguage.fromMetadata('1080P · 樱花庄的宠物女孩'),
        SubtitleLanguage.unknown);
    expect(SubtitleLanguage.fromMetadata('中日双语'), SubtitleLanguage.unknown);
  });

  test(
      'fractional timestamps survive playback gaps and positive/negative offsets',
      () {
    final source = DanmakuSourceState(provider: DanmakuProvider.bilibili);
    source.add(const [
      SourceComment(text: 'first', time: 0.04),
      SourceComment(text: 'second', time: 0.16),
      SourceComment(text: 'second', time: 0.16)
    ]);
    expect(source.count, 2);
    expect(source.between(0, 0.2).map((e) => e.text), ['first', 'second']);
    source.offsetSeconds = 0.05;
    expect(source.between(0.08, 0.1).single.text, 'first');
    source.offsetSeconds = -0.05;
    expect(source.between(0.1, 0.12).single.text, 'second');
    source.enabled = false;
    expect(source.between(0, 1), isEmpty);
  });

  test('changing episode cancels requests and rejects old late batches',
      () async {
    final loader = _ControlledLoader();
    final saved = <String, dynamic>{};
    final manager = EpisodeDanmaku(
        loader: loader,
        read: (key) => saved[key],
        write: (key, value) => saved[key] = value);
    manager.open('1:1');
    manager.match(const DanmakuBinding(
        provider: DanmakuProvider.bilibili, id: '111', title: 'one'));
    loader.streams['111']!.add(const [SourceComment(text: 'old', time: 1)]);
    await Future<void>.delayed(Duration.zero);
    expect(manager.enabledCount, 1);
    manager.open('1:2');
    expect(loader.tokens.first.isCancelled, isTrue);
    loader.streams['111']!.add(const [SourceComment(text: 'late', time: 2)]);
    await Future<void>.delayed(Duration.zero);
    expect(manager.enabledCount, 0);
    expect(manager.sources[DanmakuProvider.bilibili]!.binding, isNull);
    await loader.streams['111']!.close();
    manager.dispose();
  });

  test(
      'manual matches override automatic IDs and restore only for their episode',
      () async {
    final loader = _ControlledLoader();
    final saved = <String, dynamic>{};
    final manager = EpisodeDanmaku(
        loader: loader,
        read: (key) => saved[key],
        write: (key, value) => saved[key] = value);
    manager.open('9:1');
    manager.match(const DanmakuBinding(
        provider: DanmakuProvider.tencent,
        id: 'v1234567890',
        title: 'matched'));
    manager.setAutomatic(const DanmakuBinding(
        provider: DanmakuProvider.tencent,
        id: 'v9999999999',
        title: 'automatic'));
    expect(
        manager.sources[DanmakuProvider.tencent]!.binding!.id, 'v1234567890');
    manager.setOffset(DanmakuProvider.tencent, 1.5);
    manager.setEnabled(DanmakuProvider.tencent, false);
    expect(loader.tokens.single.isCancelled, isTrue);
    await loader.streams['v1234567890']!.close();
    manager.open('9:2');
    expect(manager.sources[DanmakuProvider.tencent]!.manual, isFalse);
    manager.open('9:1');
    final source = manager.sources[DanmakuProvider.tencent]!;
    expect(source.manual, isTrue);
    expect(source.enabled, isFalse);
    expect(source.offsetSeconds, 1.5);
    expect(source.binding!.id, 'v1234567890');
    manager.dispose();
  });

  test('BV link with p=2 selects the second CID', () async {
    final client = Dio()
      ..httpClientAdapter = _Adapter((_) => _json({
            'code': 0,
            'data': {
              'title': '多分P视频',
              'pages': [
                {'cid': 111, 'page': 1, 'part': '第一集', 'duration': 1200},
                {'cid': 222, 'page': 2, 'part': '第二集', 'duration': 1300}
              ]
            }
          }));
    final bindings = await PlatformDanmaku(client: client).resolve(
        DanmakuProvider.bilibili,
        '分享视频 https://www.bilibili.com/video/BV17x411P7hu?p=2');
    expect(bindings.single.id, '222');
    expect(bindings.single.durationSeconds, 1300);
    expect(bindings.single.title, contains('P2'));
  });

  test('Tencent collection CID is not an episode VID', () {
    expect(
        PlatformDanmaku.tencentVid(
            Uri.parse('https://v.qq.com/x/cover/abcdefghijklmno.html')),
        isNull);
    expect(
        PlatformDanmaku.tencentVid(Uri.parse(
            'https://v.qq.com/x/cover/abcdefghijklmno/v1234567890.html')),
        'v1234567890');
    expect(
        PlatformDanmaku.tencentVid(
            Uri.parse('https://m.v.qq.com/play.html?vid=v1234567890')),
        'v1234567890');
  });

  test('platform resolver rejects unrelated hosts', () async {
    await expectLater(
        PlatformDanmaku().resolve(DanmakuProvider.bilibili,
            'https://bilibili.com.example.org/video/BV17x411P7hu'),
        throwsFormatException);
  });

  test('empty Tencent segments do not stop later comments', () async {
    var requests = 0;
    final client = Dio()
      ..httpClientAdapter = _Adapter((_) {
        requests++;
        return _json({
          'barrage_list': requests == 2
              ? [
                  {
                    'id': 'later',
                    'content': '第二段弹幕',
                    'time_offset': '35000',
                    'rick_type': 1
                  }
                ]
              : []
        });
      });
    final comments = await PlatformDanmaku(client: client)
        .load(
            const DanmakuBinding(
                provider: DanmakuProvider.tencent,
                id: 'v1234567890',
                title: 'test',
                durationSeconds: 60),
            CancelToken())
        .expand((batch) => batch)
        .toList();
    expect(comments.single.time, 35);
    expect(requests, 2);
  });

  test('embedded JSON preserves nested braces without executing JavaScript',
      () {
    final result = embeddedJson(
            '<script>var player_aaaa={"url":"https://x.test/a{b}.m3u8","extra":{"ok":true}};</script>')
        .single as Map;
    expect(result['url'], 'https://x.test/a{b}.m3u8');
    expect(embeddedJson('<script>var player_aaaa={url:evil()};</script>'),
        isEmpty);
  });

  test('girigirilove parsing retains subtitle evidence from routes', () {
    final results = WebsiteSources.parseGirigiriSearch(
        '<div class="vod-detail search-list"><a href="/bangumi/123/" title="测试番剧">封面</a></div>',
        WebsiteProvider.girigirilove.baseUrl);
    expect(results.single.title, '测试番剧');
    final episodes = WebsiteSources.parseGirigiriEpisodes(
        '<div class="anthology-tab"><a>简体字幕</a></div>'
        '<ul class="anthology-list-play"><li><a href="/play/123-1-1/">第01集</a></li></ul>',
        results.single);
    expect(
        episodes.single.pageUrl, 'https://ani.girigirilove.com/play/123-1-1/');
    expect(SubtitleLanguage.fromMetadata(episodes.single.subtitleMetadata),
        SubtitleLanguage.simplified);
  });

  test('signed URLs retain query tokens when decoding player data', () {
    const url = 'https://cdn.example.org/anime.m3u8?token=a%2Bb&expires=123';
    final content = '<script>var player_aaaa=${jsonEncode({
          'encrypt': 0,
          'url': url
        })};</script>';
    expect(
        WebsiteSources.parseGirigiriStream(
            content, 'https://ani.girigirilove.com/play/1/'),
        url);
    final encoded = base64Encode(utf8.encode(Uri.encodeComponent(url)));
    expect(
        WebsiteSources.parseGirigiriStream(
            '<script>var player_aaaa=${jsonEncode({
                  'encrypt': 2,
                  'url': encoded
                })};</script>',
            'https://ani.girigirilove.com/play/1/'),
        url);
  });

  test('image results support multiple episodes and non-Chinese titles', () {
    final result = ImageSearchResult.fromJson({
      'anilist': {
        'title': {'native': 'テスト'}
      },
      'episode': [1, 2],
      'similarity': 0.9,
      'from': 65.4
    });
    expect(result.title, 'テスト');
    expect(result.episode, '第 1、2 集');
    expect(result.timeLabel, '1:05');
  });

  test(
      'image search validates inputs before requests and explains quota errors',
      () async {
    var requested = false;
    final client = Dio()
      ..httpClientAdapter = _Adapter((_) {
        requested = true;
        return _json({'result': []});
      });
    await expectLater(
        ImageSearchService(client: client).search(url: 'file:///private.png'),
        throwsFormatException);
    expect(requested, isFalse);
    final error = DioException(
        requestOptions: RequestOptions(path: '/search'),
        response: Response(
            requestOptions: RequestOptions(path: '/search'), statusCode: 429));
    expect(ImageSearchService.message(error), contains('频繁'));
  });
}
