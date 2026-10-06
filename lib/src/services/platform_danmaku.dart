import 'dart:math';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'package:xs/protobuf/danmaku.pb.dart';
import 'package:xs/src/models/danmaku_source.dart';
import 'package:xs/src/services/episode_danmaku.dart';
import 'package:xs/src/utils/embedded_json.dart';

class PlatformDanmaku implements DanmakuLoader {
  PlatformDanmaku({Dio? client})
      : client = client ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              headers: {'User-Agent': userAgent},
            ));

  final Dio client;
  final Map<String, List<Map>> _tencentPreviews = {};
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36';

  Future<List<DanmakuCandidate>> search(
    DanmakuProvider provider,
    String keyword, {
    CancelToken? cancelToken,
  }) async {
    final query = keyword.trim();
    if (query.isEmpty) return [];
    if (!provider.isBilibili) {
      final response = await client.post<Map<String, dynamic>>(
        'https://pbaccess.video.qq.com/trpc.videosearch.mobile_search.HttpMobileRecall/MbSearchHttp',
        data: {
          'version': '26022601',
          'clientType': 1,
          'query': query,
          'pagenum': 0,
          'pagesize': 30,
          'queryFrom': 0,
          'isneedQc': true,
          'filterValue': '',
          'retry': 0,
          'extraInfo': {
            'multi_terminal_pc': '1',
            'themeType': '0',
            'frontVersion': '26060108'
          },
          'featureList': [
            'DEFAULT_FEFEATURE',
            'PC_SHORT_VIDEOS_WATERFALL',
            'PC_WANT_EPISODE'
          ],
        },
        cancelToken: cancelToken,
        options: Options(headers: {
          'Referer': 'https://v.qq.com/',
          'Content-Type': 'application/json'
        }),
      );
      final body = response.data ?? {};
      if (body['ret'] != 0) throw StateError('腾讯搜索接口暂不可用');
      final data = body['data'];
      final normal = data is Map ? data['normalList'] : null;
      final items = normal is Map ? normal['itemList'] : null;
      for (final item in (items is List ? items : const []).whereType<Map>()) {
        final doc = item['doc'];
        final video = item['videoInfo'];
        if (doc is! Map || video is! Map || doc['dataType'] != 2) continue;
        final sites = video['episodeSites'];
        _tencentPreviews[doc['id'].toString()] = [
          for (final site
              in (sites is List ? sites : const []).whereType<Map>())
            if (site['enName'] == 'qq')
              ...(site['episodeInfoList'] is List
                  ? (site['episodeInfoList'] as List).whereType<Map>()
                  : <Map>[]),
        ];
      }
      return tencentSearchCandidates(body);
    }
    var failures = 0;
    final results =
        await Future.wait(['media_bangumi', 'video'].map((type) async {
      try {
        final response = await client.get<Map<String, dynamic>>(
          'https://api.bilibili.com/x/web-interface/search/type',
          queryParameters: {'search_type': type, 'keyword': query, 'page': 1},
          cancelToken: cancelToken,
          options: Options(headers: {'Referer': 'https://www.bilibili.com/'}),
        );
        final body = response.data ?? {};
        if (body['code'] != 0) {
          throw StateError('平台暂未返回搜索结果，请使用链接加载');
        }
        final data = body['data'];
        final list = data is Map ? data['result'] : null;
        return (list is List ? list : const [])
            .whereType<Map>()
            .map((item) {
              final url = item['url']?.toString() ??
                  item['arcurl']?.toString() ??
                  'https://www.bilibili.com/video/${item['bvid']}';
              return DanmakuCandidate(
                  title: plainTitle(item['title']?.toString() ?? ''), url: url);
            })
            .where((item) => item.title.isNotEmpty)
            .toList();
      } catch (error) {
        if (cancelToken?.isCancelled ?? false) rethrow;
        failures++;
        return <DanmakuCandidate>[];
      }
    }));
    final unique = <String, DanmakuCandidate>{};
    for (final item in results.expand((items) => items)) {
      unique[item.url] = item;
    }
    if (failures == 2 && unique.isEmpty)
      throw StateError('B 站搜索接口暂不可用，请使用链接加载');
    return unique.values.toList();
  }

  /// Returns every episode/part, so choosing a series never silently binds its
  /// first episode to whichever episode the user is currently watching.
  Future<List<DanmakuBinding>> resolve(
    DanmakuProvider provider,
    String input, {
    CancelToken? cancelToken,
  }) async {
    var value = input.trim();
    if (provider.isBilibili && RegExp(r'^cid:\d+$').hasMatch(value)) {
      return [
        DanmakuBinding(
            provider: provider,
            id: value.substring(4),
            title: 'CID ${value.substring(4)}')
      ];
    }
    if (!provider.isBilibili &&
        RegExp(r'^vid:[A-Za-z0-9]{11}$').hasMatch(value)) {
      return [
        DanmakuBinding(
            provider: provider,
            id: value.substring(4),
            title: 'VID ${value.substring(4)}')
      ];
    }
    if (provider.isBilibili && RegExp(r'^BV[A-Za-z0-9]{10}$').hasMatch(value)) {
      value = 'https://www.bilibili.com/video/$value';
    }
    final shared = RegExp(r'https?://[^\s<>]+').firstMatch(value)?.group(0);
    if (shared != null) value = shared.replaceAll(RegExp(r'[）)。，,]+$'), '');
    var uri = Uri.tryParse(value);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) {
      throw const FormatException('请输入完整的视频链接');
    }
    if (provider.isBilibili && uri.host == 'b23.tv') {
      final response = await client.get<String>(uri.toString(),
          cancelToken: cancelToken,
          options: Options(responseType: ResponseType.plain));
      uri = response.realUri;
    }
    if (provider.isBilibili) {
      if (uri.host != 'bilibili.com' && !uri.host.endsWith('.bilibili.com')) {
        throw const FormatException('请选择哔哩哔哩视频链接');
      }
      return _resolveBilibili(provider, uri, cancelToken);
    }
    if (uri.host != 'v.qq.com' && uri.host != 'm.v.qq.com') {
      throw const FormatException('请选择腾讯视频链接');
    }
    final vid = tencentVid(uri);
    if (vid != null) {
      return [
        DanmakuBinding(
            provider: provider,
            id: vid,
            title: '腾讯视频 · $vid',
            url: uri.toString())
      ];
    }
    final cid =
        RegExp(r'/cover/([A-Za-z0-9]{15})').firstMatch(uri.path)?.group(1);
    if (cid != null) return _tencentEpisodes(provider, cid, cancelToken);
    final response = await client.get<String>(uri.toString(),
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.plain));
    final candidates = parseTencentCandidates(response.data ?? '');
    final bindings = candidates
        .map((item) {
          final id = tencentVid(Uri.parse(item.url));
          if (id == null) return null;
          return DanmakuBinding(
              provider: provider, id: id, title: item.title, url: item.url);
        })
        .whereType<DanmakuBinding>()
        .toList();
    if (bindings.isEmpty) {
      throw const FormatException('无法解析此合集，请粘贴具体一集的播放链接');
    }
    return bindings;
  }

  Future<List<DanmakuBinding>> _tencentEpisodes(
      DanmakuProvider provider, String cid, CancelToken? token) async {
    final unique = <String, DanmakuBinding>{};
    void addEpisode(Map ep) {
      final url = ep['url']?.toString() ?? '';
      final id = tencentVid(Uri.tryParse(url) ?? Uri());
      if (id == null) return;
      unique[id] = DanmakuBinding(
          provider: provider,
          id: id,
          title: '第 ${ep['title'] ?? ''} 集',
          url: url,
          durationSeconds: int.tryParse(ep['duration']?.toString() ?? '') ?? 0);
    }

    for (final ep in _tencentPreviews[cid] ?? <Map>[]) {
      addEpisode(ep);
    }
    for (var page = -1; page < 30; page++) {
      final response = await client.get<Map<String, dynamic>>(
        'https://pbaccess.video.qq.com/trpc.videosearch.search_cgi.http/load_playsource_list_info',
        queryParameters: {
          'pageNum': max(page, 0),
          'platform': 2,
          'site': 'qq',
          'appId': '10718',
          'dataType': 2,
          'id': cid,
          'scene': page < 0 ? 8 : 3,
          'pageContext': '',
          'themeType': '0'
        },
        cancelToken: token,
        options: Options(headers: {'Referer': 'https://v.qq.com/'}),
      );
      final body = response.data ?? {};
      final data = body['data'];
      if (body['ret'] != 0 || data is! Map || (data['errorCode'] ?? 0) != 0) {
        throw const FormatException('腾讯合集分集读取失败，请使用具体一集的播放链接');
      }
      final normal = data['normalList'];
      final items = normal is Map ? normal['itemList'] : null;
      final previousCount = unique.length;
      var added = 0;
      for (final item in (items is List ? items : const []).whereType<Map>()) {
        final video = item['videoInfo'];
        if (video is! Map) continue;
        final sites = video['firstBlockSites'];
        for (final site
            in (sites is List ? sites : const []).whereType<Map>()) {
          if (site['enName'] != 'qq') continue;
          final episodes = site['episodeInfoList'];
          for (final ep
              in (episodes is List ? episodes : const []).whereType<Map>()) {
            final url = ep['url']?.toString() ?? '';
            final id = tencentVid(Uri.tryParse(url) ?? Uri());
            if (id == null) continue;
            added++;
            addEpisode(ep);
          }
        }
      }
      // The API's totalEpisode can be a remaining-count; a no-progress page
      // is the reliable stopping condition when gathering the full series.
      if (page >= 0 && (unique.length == previousCount || added == 0)) break;
    }
    if (unique.isEmpty) throw const FormatException('此合集没有可匹配分集，请使用具体视频链接');
    final result = unique.values.toList();
    result.sort((a, b) {
      final left =
          int.tryParse(RegExp(r'\d+').firstMatch(a.title)?.group(0) ?? '');
      final right =
          int.tryParse(RegExp(r'\d+').firstMatch(b.title)?.group(0) ?? '');
      return left == null || right == null
          ? a.title.compareTo(b.title)
          : left.compareTo(right);
    });
    return result;
  }

  static List<DanmakuCandidate> tencentSearchCandidates(
      Map<String, dynamic> body) {
    final data = body['data'];
    final normal = data is Map ? data['normalList'] : null;
    final items = normal is Map ? normal['itemList'] : null;
    final result = <String, DanmakuCandidate>{};
    for (final item in (items is List ? items : const []).whereType<Map>()) {
      final doc = item['doc'];
      final video = item['videoInfo'];
      if (doc is! Map || video is! Map) continue;
      final id = doc['id']?.toString() ?? '';
      final title = plainTitle(video['title']?.toString() ?? '');
      if (title.isEmpty) continue;
      final String url;
      if (doc['dataType'] == 2 && RegExp(r'^[A-Za-z0-9]{15}$').hasMatch(id)) {
        url = 'https://v.qq.com/x/cover/$id.html';
      } else if (doc['dataType'] == 1 &&
          RegExp(r'^[A-Za-z0-9]{11}$').hasMatch(id)) {
        url = 'https://v.qq.com/x/page/$id.html';
      } else {
        continue;
      }
      result[url] = DanmakuCandidate(title: title, url: url);
    }
    return result.values.toList();
  }

  Future<List<DanmakuBinding>> _resolveBilibili(
      DanmakuProvider provider, Uri uri, CancelToken? token) async {
    final bv = RegExp(r'BV[A-Za-z0-9]{10}').firstMatch(uri.path)?.group(0);
    final av = RegExp(r'av(\d+)').firstMatch(uri.path)?.group(1);
    if (bv != null || av != null) {
      final response = await client.get<Map<String, dynamic>>(
        'https://api.bilibili.com/x/web-interface/view',
        queryParameters: {
          if (bv != null) 'bvid': bv,
          if (av != null) 'aid': av
        },
        cancelToken: token,
        options: Options(headers: {'Referer': 'https://www.bilibili.com/'}),
      );
      final body = response.data ?? {};
      if (body['code'] != 0 || body['data'] is! Map) {
        throw const FormatException('无法读取 B 站视频信息');
      }
      final data = body['data'] as Map;
      final pages = (data['pages'] as List? ?? []).whereType<Map>();
      final requestedPart = int.tryParse(uri.queryParameters['p'] ?? '');
      return pages
          .where((p) => requestedPart == null || p['page'] == requestedPart)
          .map((page) => DanmakuBinding(
                provider: provider,
                id: page['cid'].toString(),
                title:
                    '${plainTitle(data['title']?.toString() ?? '')} · P${page['page']} ${page['part'] ?? ''}',
                url: uri.replace(
                    queryParameters: {'p': page['page'].toString()}).toString(),
                durationSeconds: (page['duration'] as num?)?.toInt() ?? 0,
              ))
          .toList();
    }
    final episode = RegExp(r'ep(\d+)').firstMatch(uri.path)?.group(1);
    final season = RegExp(r'ss(\d+)').firstMatch(uri.path)?.group(1);
    if (episode == null && season == null) {
      throw const FormatException('支持 BV、AV、ep、ss 播放链接或 cid:数字');
    }
    final response = await client.get<Map<String, dynamic>>(
      'https://api.bilibili.com/pgc/view/web/season',
      queryParameters: {
        if (episode != null) 'ep_id': episode,
        if (season != null) 'season_id': season
      },
      cancelToken: token,
      options: Options(headers: {'Referer': 'https://www.bilibili.com/'}),
    );
    final body = response.data ?? {};
    if (body['code'] != 0 || body['result'] is! Map) {
      throw const FormatException('无法读取番剧分集，请使用具体视频链接');
    }
    final result = body['result'] as Map;
    final episodes = (result['episodes'] as List? ?? []).whereType<Map>();
    return episodes
        .where((item) => episode == null || item['id'].toString() == episode)
        .map((item) => DanmakuBinding(
              provider: provider,
              id: item['cid'].toString(),
              title:
                  '${result['title'] ?? ''} · ${item['title'] ?? ''} ${item['long_title'] ?? ''}',
              url: 'https://www.bilibili.com/bangumi/play/ep${item['id']}',
              durationSeconds: ((item['duration'] as num? ?? 0) / 1000).ceil(),
            ))
        .toList();
  }

  static String? tencentVid(Uri uri) {
    final queryVid = uri.queryParameters['vid'];
    if (queryVid != null && RegExp(r'^[A-Za-z0-9]{11}$').hasMatch(queryVid)) {
      return queryVid;
    }
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final match = RegExp(r'^([A-Za-z0-9]{11})(?:\.html)?$').firstMatch(last);
    return match?.group(1);
  }

  static List<DanmakuCandidate> parseTencentCandidates(String content) {
    final unique = <String, DanmakuCandidate>{};
    final doc = html.parse(content);
    for (final anchor in doc.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      final uri = Uri.https('v.qq.com').resolve(href);
      if (uri.host != 'v.qq.com' || !uri.path.startsWith('/x/')) continue;
      if (!uri.path.contains('/cover/') && !uri.path.contains('/page/'))
        continue;
      final title = anchor.attributes['title'] ?? anchor.text.trim();
      if (title.isEmpty) continue;
      unique[uri.toString()] =
          DanmakuCandidate(title: title, url: uri.toString());
    }
    void visit(dynamic value, [String parentTitle = '']) {
      if (value is List) {
        for (final item in value) {
          visit(item, parentTitle);
        }
      } else if (value is Map) {
        final title = plainTitle((value['title'] ??
                value['name'] ??
                value['video_title'] ??
                parentTitle)
            .toString());
        final vid = value['vid']?.toString() ?? '';
        final cid =
            value['cid']?.toString() ?? value['cover_id']?.toString() ?? '';
        if (RegExp(r'^[A-Za-z0-9]{11}$').hasMatch(vid)) {
          final url = 'https://v.qq.com/x/page/$vid.html';
          unique[url] =
              DanmakuCandidate(title: title.isEmpty ? vid : title, url: url);
        } else if (RegExp(r'^[A-Za-z0-9]{15}$').hasMatch(cid) &&
            title.isNotEmpty) {
          final url = 'https://v.qq.com/x/cover/$cid.html';
          unique[url] = DanmakuCandidate(title: title, url: url);
        }
        for (final item in value.values) {
          if (item is Map || item is List) visit(item, title);
        }
      }
    }

    try {
      visit(jsonDecode(content));
    } on FormatException {/* HTML response. */}
    for (final json in embeddedJson(content)) {
      visit(json);
    }
    return unique.values.toList();
  }

  @override
  Stream<List<SourceComment>> load(
      DanmakuBinding binding, CancelToken token) async* {
    if (binding.provider.isBilibili) {
      final cid = int.tryParse(binding.id);
      if (cid == null || cid <= 0) throw const FormatException('CID 无效');
      final segments = max(
          1,
          ((binding.durationSeconds > 0 ? binding.durationSeconds : 1800) / 360)
              .ceil());
      for (var segment = 1; segment <= segments; segment++) {
        if (token.isCancelled) return;
        final response = await client.get<List<int>>(
          'https://api.bilibili.com/x/v2/dm/web/seg.so',
          queryParameters: {'type': 1, 'oid': cid, 'segment_index': segment},
          cancelToken: token,
          options: Options(
              responseType: ResponseType.bytes,
              headers: {'Referer': 'https://www.bilibili.com/'}),
        );
        final data = bilibili_danmaku_.fromBuffer(response.data ?? []);
        yield data.list
            .where((e) => e.mode >= 1 && e.mode <= 5)
            .map((e) => SourceComment(
                  id: e.id.toString() == '0' ? '' : e.id.toString(),
                  text: e.content,
                  time: e.progress / 1000,
                  color: e.color,
                  type: e.mode == 4
                      ? 3
                      : e.mode == 5
                          ? 2
                          : 1,
                ))
            .toList();
      }
    } else {
      if (!RegExp(r'^[A-Za-z0-9]{11}$').hasMatch(binding.id)) {
        throw const FormatException('VID 无效');
      }
      final segments = max(
          1,
          ((binding.durationSeconds > 0 ? binding.durationSeconds : 1800) / 30)
              .ceil());
      for (var segment = 0; segment < segments; segment++) {
        if (token.isCancelled) return;
        final response = await client.get<Map<String, dynamic>>(
          'https://dm.video.qq.com/barrage/segment/${binding.id}/t/v1/${segment * 30000}/${(segment + 1) * 30000}',
          cancelToken: token,
        );
        final data = response.data ?? {};
        final list = data['barrage_list'];
        yield (list is List ? list : const [])
            .whereType<Map>()
            .map((e) => SourceComment(
                  id: e['id']?.toString() ?? '',
                  text: e['content']?.toString() ?? '',
                  time: (double.tryParse(e['time_offset']?.toString() ?? '') ??
                          0) /
                      1000,
                  type:
                      (int.tryParse(e['rick_type']?.toString() ?? '') ?? 1) > 1
                          ? 2
                          : 1,
                ))
            .toList();
        // An empty segment in the middle of a video is not the end of it.
      }
    }
  }
}
