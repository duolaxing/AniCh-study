import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:xs/protobuf/list.pb.dart';
import 'package:xs/src/apis/home.dart' as home_api;
import 'package:xs/src/apis/bangumi.dart' as bangumi_api;
import 'package:xs/src/models/website_source.dart';
import 'package:xs/src/pages/home/controller.dart';
import 'package:xs/src/pages/home/view.dart';
import 'package:xs/src/pages/bangumi_vod/controller.dart';
import 'package:xs/src/utils/website_playback.dart';

class _HomeAdapter implements HttpClientAdapter {
  _HomeAdapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
          Future<void>? cancelFuture) async =>
      respond(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _bytes(List<int> bytes) =>
    ResponseBody.fromBytes(bytes, 200, headers: {
      Headers.contentTypeHeader: ['application/octet-stream']
    });

void main() {
  late HttpClientAdapter original;
  setUp(() => original = home_api.api.httpClientAdapter);
  tearDown(() {
    home_api.api.httpClientAdapter = original;
    Get.reset();
  });

  test(
      'empty HTTP body and error envelope cannot become a successful blank feed',
      () async {
    final controller = HomeAllController();
    home_api.api.httpClientAdapter = _HomeAdapter((_) => _bytes([]));
    await controller.get();
    expect(controller.status.isError, isTrue);
    home_api.api.httpClientAdapter = _HomeAdapter((_) => _bytes(
        thread_list_(error: true, message: 'unauthorized').writeToBuffer()));
    await controller.get();
    expect(controller.status.isError, isTrue);
    expect(controller.isLoading.value, isFalse);
  });

  test('valid empty list is explicit; retry can recover to a populated feed',
      () async {
    final controller = HomeAllController();
    home_api.api.httpClientAdapter = _HomeAdapter(
        (_) => _bytes(thread_list_(body: thread_list_body_()).writeToBuffer()));
    await controller.get();
    expect(controller.status.isEmpty, isTrue);
    home_api.api.httpClientAdapter = _HomeAdapter((_) => _bytes(
        thread_list_(body: thread_list_body_(data: [thread_list_data_(id: 7)]))
            .writeToBuffer()));
    expect(await controller.reload(), isTrue);
    expect(controller.status.isSuccess, isTrue);
    expect(controller.result.single.id, 7);
  });

  testWidgets(
      'empty homepage retains retry and a usable website resource entry',
      (tester) async {
    home_api.api.httpClientAdapter = _HomeAdapter(
        (_) => _bytes(thread_list_(body: thread_list_body_()).writeToBuffer()));
    await tester.pumpWidget(GetMaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const HomePage()));
    await tester.pumpAndSettle();
    expect(find.text('首页暂无内容'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.text('网站资源'), findsOneWidget);
    await tester.tap(find.text('网站资源'));
    await tester.pumpAndSettle();
    expect(find.text('搜索网站资源'), findsOneWidget);
    expect(find.text('次元城'), findsOneWidget);
    expect(find.text('girigirilove'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('website bindings use stable local IDs independent of signed media URLs',
      () {
    const ep = WebsiteEpisode(
        provider: WebsiteProvider.girigirilove,
        id: '42-1-2',
        animeTitle: '测试番剧',
        title: '第02集',
        route: '简中',
        pageUrl: 'https://ani.girigirilove.com/playGV42-1-2/');
    final first = websitePlaybackArguments(const WebsiteStream(
        episode: ep,
        url: 'https://cdn.example/video.m3u8?token=old',
        headers: {}));
    final refreshed = websitePlaybackArguments(const WebsiteStream(
        episode: ep,
        url: 'https://cdn.example/video.m3u8?token=new',
        headers: {}));
    expect(first['id'], lessThan(0));
    expect(first['id'], refreshed['id']);
    expect(first['episode'], 2);
  });

  test('website playback never requests central metadata or server danmaku',
      () {
    final adapter = bangumi_api.api.httpClientAdapter;
    var requests = 0;
    bangumi_api.api.httpClientAdapter = _HomeAdapter((_) {
      requests++;
      return _bytes([]);
    });
    try {
      final controller = BangumiVodPageController(
          pId: -1,
          pEpisode: 1,
          initialWebsiteStream: const WebsiteStream(
              episode: WebsiteEpisode(
                  provider: WebsiteProvider.girigirilove,
                  id: '42-1-1',
                  animeTitle: '测试番剧',
                  title: '第01集',
                  route: '简中',
                  pageUrl: 'https://ani.girigirilove.com/playGV42-1-1/'),
              url: 'https://cdn.example/video.m3u8',
              headers: {}));
      controller.getBangumiData();
      controller.getBangumiEpisodes();
      controller.getDanmaku();
      controller.loadAutomaticDanmaku();
      controller.setServerDanmakuEnabled(true);
      expect(controller.serverDanmakuState.value, isFalse);
      expect(requests, 0);
    } finally {
      bangumi_api.api.httpClientAdapter = adapter;
    }
  });
}
