import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:xs/src/models/website_source.dart';
import 'package:xs/src/services/platform_danmaku.dart';
import 'package:xs/src/utils/embedded_json.dart';

class WebsiteSources {
  WebsiteSources({Dio? client})
      : client = client ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              headers: {'User-Agent': PlatformDanmaku.userAgent},
            )) {
    this
        .client
        .interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) {
          final cookies = _cookies[options.uri.host];
          if (cookies != null && cookies.isNotEmpty) {
            options.headers['Cookie'] =
                cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
          }
          handler.next(options);
        }, onResponse: (response, handler) {
          final host = response.requestOptions.uri.host;
          if (WebsiteProvider.values
              .any((site) => Uri.parse(site.baseUrl).host == host)) {
            for (final value in response.headers['set-cookie'] ?? <String>[]) {
              try {
                final cookie = Cookie.fromSetCookieValue(value);
                final jar =
                    _cookies.putIfAbsent(host, () => <String, String>{});
                if (cookie.maxAge == 0 ||
                    (cookie.expires?.isBefore(DateTime.now()) ?? false)) {
                  jar.remove(cookie.name);
                } else {
                  jar[cookie.name] = cookie.value;
                }
              } on FormatException {/* Ignore malformed server cookies. */}
            }
          }
          handler.next(response);
        }));
  }
  final Dio client;
  // Kept in memory only; the application never saves a site's password.
  static String _ciyuanToken = '';
  static final Map<String, Map<String, String>> _cookies = {};

  Future<Uint8List> captcha(String url) async {
    final uri = Uri.parse(url);
    if (uri.host != Uri.parse(WebsiteProvider.girigirilove.baseUrl).host) {
      throw const FormatException('验证码地址无效');
    }
    final response = await client.get<List<int>>(
        uri.replace(queryParameters: {
          ...uri.queryParameters,
          'r': DateTime.now().millisecondsSinceEpoch.toString(),
        }).toString(),
        options: Options(responseType: ResponseType.bytes));
    return Uint8List.fromList(response.data ?? []);
  }

  Future<bool> verifyCaptcha(String value, String type) async {
    final response = await client.post<dynamic>(
      '${WebsiteProvider.girigirilove.baseUrl}/index.php/ajax/verify_check',
      queryParameters: {'type': type, 'verify': value.trim()},
      data: '',
      options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'}),
    );
    final body = response.data;
    return body is Map && body['code'].toString() == '1';
  }

  Future<void> loginCiyuan(String username, String password) async {
    final data = await _ciyuan('/auth/login',
        method: 'POST',
        data: {'username': username.trim(), 'password': password});
    final token = data is Map
        ? (data['token'] ?? data['access_token'])?.toString()
        : null;
    if (token == null || token.isEmpty) throw StateError('登录响应中没有有效登录凭据');
    _ciyuanToken = token;
  }

  Future<dynamic> _ciyuan(String path,
      {Map<String, dynamic>? query,
      String method = 'GET',
      dynamic data,
      CancelToken? token}) async {
    try {
      final response = await client.request<dynamic>(
        '${WebsiteProvider.ciyuancheng.baseUrl}/api$path',
        queryParameters: query,
        data: data,
        cancelToken: token,
        options: Options(method: method, headers: {
          'Referer': '${WebsiteProvider.ciyuancheng.baseUrl}/',
          'Origin': WebsiteProvider.ciyuancheng.baseUrl,
          'X-App-Name': 'cyc_web',
          'X-App-Version': 'cycweb',
          'X-Time-Zone': 'Asia/Shanghai',
          if (_ciyuanToken.isNotEmpty) 'Authorization': 'Bearer $_ciyuanToken',
        }),
      );
      final body = response.data;
      if (body is! Map) {
        throw WebsiteVerificationRequired(WebsiteProvider.ciyuancheng.baseUrl);
      }
      if (body['code'] == 401 || body['code'] == 403)
        throw const WebsiteLoginRequired();
      if (body['code'] != 0 && body['code'] != 200) {
        throw StateError(body['msg']?.toString() ?? '网站返回错误');
      }
      return body['data'];
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) throw const WebsiteLoginRequired();
      if (error.response?.statusCode == 403) {
        throw WebsiteVerificationRequired(WebsiteProvider.ciyuancheng.baseUrl);
      }
      rethrow;
    }
  }

  Future<List<WebsiteAnime>> search(WebsiteProvider provider, String keyword,
      {CancelToken? token}) async {
    if (keyword.trim().isEmpty) return [];
    if (provider == WebsiteProvider.ciyuancheng) {
      final data = await _ciyuan('/videos/search',
          query: {
            'q': keyword.trim(),
            'page': 1,
            'page_size': 24,
          },
          token: token);
      final list = data is Map ? data['list'] : null;
      return (list is List ? list : const [])
          .whereType<Map>()
          .where((e) => e['video_id'] != null || e['id'] != null)
          .map((e) => WebsiteAnime(
              provider: provider,
              id: (e['video_id'] ?? e['id']).toString(),
              title: e['title']?.toString() ?? '未命名番剧',
              url: '${provider.baseUrl}/anime/${e['video_id'] ?? e['id']}'))
          .toList();
    }
    final uri = Uri.parse('${provider.baseUrl}/search/-------------/')
        .replace(queryParameters: {'wd': keyword.trim()});
    final content = await _getPage(uri.toString(), token);
    return parseGirigiriSearch(content, provider.baseUrl);
  }

  Future<List<WebsiteEpisode>> episodes(WebsiteAnime anime,
      {CancelToken? token}) async {
    if (anime.provider == WebsiteProvider.ciyuancheng) {
      final detail = await _ciyuan('/videos/${anime.id}', token: token);
      final routes = detail is Map ? detail['play_from'] : null;
      final result = <WebsiteEpisode>[];
      for (final route
          in (routes is List ? routes : const []).whereType<Map>()) {
        final code = route['code']?.toString() ?? '';
        if (code.isEmpty) continue;
        var page = 1;
        var total = 1;
        var loaded = 0;
        do {
          final data = await _ciyuan('/videos/${anime.id}/sections',
              query: {
                'player_code': code,
                'page': page,
                'page_size': 100,
              },
              token: token);
          final list = data is Map ? data['list'] : null;
          final items =
              (list is List ? list : const []).whereType<Map>().toList();
          if (items.isEmpty) break;
          for (final item in items.where((e) => e['id'] != null)) {
            result.add(WebsiteEpisode(
              provider: anime.provider,
              id: item['id'].toString(),
              animeTitle: anime.title,
              title: item['title']?.toString() ?? '未命名集数',
              route: route['title']?.toString() ?? code,
              pageUrl: '${anime.provider.baseUrl}/play/${item['id']}',
              subtitleMetadata:
                  '${route['subtitle_language'] ?? ''} ${item['subtitle_language'] ?? ''} ${route['title'] ?? ''}',
            ));
          }
          loaded += items.length;
          final pager = data is Map ? data['pager'] : null;
          total = pager is Map
              ? (pager['total'] as num?)?.toInt() ?? loaded
              : loaded;
          page++;
        } while (loaded < total && page <= 100);
      }
      return result;
    }
    final content = await _getPage(anime.url, token);
    return parseGirigiriEpisodes(content, anime);
  }

  Future<WebsiteStream> resolve(WebsiteEpisode episode,
      {CancelToken? token}) async {
    if (episode.provider == WebsiteProvider.ciyuancheng) {
      if (_ciyuanToken.isEmpty) throw const WebsiteLoginRequired();
      final data =
          await _ciyuan('/v2/sections/${episode.id}/play-url', token: token);
      final url = data is Map ? data['url']?.toString() ?? '' : '';
      if (!_isHttp(url)) throw StateError('网站没有返回有效播放地址');
      return WebsiteStream(episode: episode, url: url, headers: {
        'Referer': '${episode.provider.baseUrl}/',
        'User-Agent': PlatformDanmaku.userAgent,
      });
    }
    final content = await _getPage(episode.pageUrl, token);
    final url = parseGirigiriStream(content, episode.pageUrl);
    if (url == null) {
      throw WebsiteVerificationRequired(episode.pageUrl);
    }
    return WebsiteStream(episode: episode, url: url, headers: {
      'Referer': episode.pageUrl,
      'User-Agent': PlatformDanmaku.userAgent,
    });
  }

  Future<String> _getPage(String url, CancelToken? token) async {
    final response = await client.get<String>(url,
        cancelToken: token,
        options: Options(
            responseType: ResponseType.plain,
            headers: {'Referer': '${WebsiteProvider.girigirilove.baseUrl}/'}));
    final content = response.data ?? '';
    if (RegExp(r'ds-verify-img|验证您不是|驗證您不是|captcha-container|cf-chl-')
        .hasMatch(content)) {
      final document = html.parse(content);
      final image =
          document.querySelector('img.ds-verify-img')?.attributes['src'];
      throw WebsiteVerificationRequired(url,
          captchaUrl:
              image == null ? '' : Uri.parse(url).resolve(image).toString(),
          type: document
                  .querySelector('.verify-submit')
                  ?.attributes['data-type'] ??
              'search');
    }
    return content;
  }

  static List<WebsiteAnime> parseGirigiriSearch(
      String content, String baseUrl) {
    final doc = html.parse(content);
    final unique = <String, WebsiteAnime>{};
    final cards =
        doc.querySelectorAll('.search-list, .vod-detail, .public-list-box');
    for (final card in cards) {
      final links = card.querySelectorAll('a[href]');
      for (final anchor in links) {
        final href = anchor.attributes['href'] ?? '';
        if (!RegExp(r'/(?:bangumi|voddetail|detail)/|/GV\d+/?$').hasMatch(href))
          continue;
        final title = anchor.attributes['title'] ??
            anchor.querySelector('h3')?.text.trim() ??
            anchor.text.trim();
        if (title.isEmpty) continue;
        final url = Uri.parse(baseUrl).resolve(href).toString();
        unique[url] = WebsiteAnime(
            provider: WebsiteProvider.girigirilove,
            id: Uri.parse(url).path,
            title: plainTitle(title),
            url: url);
      }
    }
    return unique.values.toList();
  }

  static List<WebsiteEpisode> parseGirigiriEpisodes(
      String content, WebsiteAnime anime) {
    final doc = html.parse(content);
    final lists =
        doc.querySelectorAll('ul.anthology-list-play, .module-play-list');
    final names = doc.querySelectorAll('.anthology-tab a, .anthology-tab span, '
        '.module-tab-item, .anthology-tab .swiper-slide');
    final result = <WebsiteEpisode>[];
    for (var i = 0; i < lists.length; i++) {
      final route = i < names.length ? names[i].text.trim() : '线路 ${i + 1}';
      for (final anchor in lists[i].querySelectorAll('a[href]')) {
        final href = anchor.attributes['href'] ?? '';
        if (href.isEmpty || href.startsWith('javascript:')) continue;
        final url = Uri.parse(anime.url).resolve(href).toString();
        if (!_isHttp(url)) continue;
        final title = anchor.attributes['title'] ?? anchor.text.trim();
        result.add(WebsiteEpisode(
            provider: anime.provider,
            id: Uri.parse(url).path,
            animeTitle: anime.title,
            title: title,
            route: route,
            pageUrl: url,
            subtitleMetadata:
                '$route ${anchor.attributes['data-subtitle'] ?? ''}'));
      }
    }
    return result;
  }

  static String? parseGirigiriStream(String content, String pageUrl) {
    final doc = html.parse(content);
    for (final Element element
        in doc.querySelectorAll('video[src], video source[src]')) {
      final src = element.attributes['src'];
      if (src != null) {
        final url = Uri.parse(pageUrl).resolve(src).toString();
        if (_isHttp(url)) return url;
      }
    }
    for (final value in embeddedJson(content)) {
      if (value is! Map || value['url'] is! String) continue;
      var url = value['url'] as String;
      try {
        final encrypt = value['encrypt']?.toString();
        if (encrypt == '1') {
          url = Uri.decodeComponent(url);
        } else if (encrypt == '2') {
          url = Uri.decodeComponent(
              utf8.decode(base64.decode(base64.normalize(url))));
        }
      } on FormatException {
        continue;
      }
      final absolute = Uri.parse(pageUrl).resolve(url).toString();
      if (_isHttp(absolute) &&
          RegExp(r'\.(?:m3u8|mp4|mkv|webm)(?:[?#]|$)', caseSensitive: false)
              .hasMatch(absolute)) return absolute;
    }
    return null;
  }

  static bool _isHttp(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        ['http', 'https'].contains(uri.scheme) &&
        uri.host.isNotEmpty;
  }
}
