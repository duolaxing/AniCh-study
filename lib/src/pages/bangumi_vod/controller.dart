import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:xs/protobuf/bangumi.pb.dart';
import 'package:xs/protobuf/danmaku.pb.dart';
import 'package:xs/src/apis/bangumi.dart';
import 'package:xs/src/pages/bangumi_detail/models/bangumi_detail_model.dart';
import 'package:xs/src/models/danmaku_source.dart';
import 'package:xs/src/models/website_source.dart';
import 'package:xs/src/pages/website_source/view.dart';
import 'package:xs/src/services/episode_danmaku.dart';
import 'package:xs/src/services/platform_danmaku.dart';
import 'package:xs/src/services/website_sources.dart';
import 'package:xs/src/utils/subtitle_language.dart';
import 'package:xs/src/pages/settings/storage/play_history_storage.dart';
import 'package:xs/src/utils/time.dart';
import 'package:xs/src/widgets/danmaku_settings/storage.dart';
import 'package:xs/src/widgets/danmaku_shield/storage.dart';
import 'package:xs/src/utils/app_style.dart';
import 'package:xs/src/utils/color.dart';
import 'package:xs/src/utils/log.dart';
import 'package:xs/src/utils/utils.dart';
import 'package:xs/src/widgets/danmaku_settings/view.dart';
import 'package:xs/src/widgets/danmaku_shield/view.dart';
import 'package:xs/src/widgets/ns_danmaku/danmaku_controller.dart';
import 'package:xs/src/widgets/ns_danmaku/models/danmaku_item.dart';
import 'package:xs/src/widgets/ns_danmaku/utils.dart';
import 'package:xs/src/widgets/player/controller.dart';
import 'package:xs/src/widgets/settings/settings_card.dart';
import 'package:xs/src/widgets/settings/settings_switch.dart';

final box = GetStorage('playHistory');
const String assetName = 'assets/images/no_image.svg';
final Widget noImage = SvgPicture.asset(assetName);

class BangumiVodPageController extends PlayerController
    with StateMixin, WidgetsBindingObserver, GetTickerProviderStateMixin {
  final int pId;
  final int pEpisode;
  BangumiVodPageController({
    required this.pId,
    required this.pEpisode,
  }) {
    rxId = pId.obs;
    rxEpisode = pEpisode.obs;
  }

  late RxInt rxId;
  int get id => rxId.value;
  late RxInt rxEpisode;
  int get episode => rxEpisode.value;

  // 音量
  RxDouble playerVolume = 100.0.obs;

  // 线路数据
  RxList<vod_item_> playUrls = RxList<vod_item_>();

  // 当前线路
  var currentLineIndex = -1;
  var currentLineInfo = ''.obs;

  // 加载失败
  var loadError = false.obs;
  Error? error;

  // 退出
  RxBool leave = false.obs;

  // 导航栏
  final List<Tab> tabs = <Tab>[
    const Tab(
      child: Align(
        alignment: Alignment.center,
        child: Text('简介'),
      ),
    ),
    const Tab(
      child: Align(
        alignment: Alignment.center,
        child: Text('评论'),
      ),
    ),
  ];

  late TabController tabController;
  late final AnimationController animationController;
  RxInt tabIndex = 0.obs;

  BangumiDetailModel data = BangumiDetailModel();
  bangumi_episodes_data_ get episodeDetail => getEpisodeData();
  List<bangumi_episodes_data_> episodes = [];
  List<data_> danmakuList = [];
  final serverDanmakuCount = 0.obs;
  final websiteError = ''.obs;
  final sourceStorage = GetStorage();
  late final externalDanmaku = EpisodeDanmaku(
    loader: PlatformDanmaku(),
    read: sourceStorage.read,
    write: (key, value) {
      sourceStorage.write(key, value);
    },
  );
  final websiteSources = WebsiteSources();
  final Map<String, WebsiteStream> websiteStreams = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _listening = false;
  bool _bangumiDataRequested = false;
  bool _bangumiEpisodesRequested = false;
  int _videoSession = 0;
  CancelToken? _serverRequest;
  CancelToken? _websiteRequest;
  double? _lastDanmakuPosition;

  ScrollController playListScrollController = ScrollController();
  ScrollController playListScrollController2 = ScrollController();

  Map<dynamic, dynamic> bangumiInfo = {'episodes': []};

  RxInt lastPosition = 0.obs;

  RxBool playing = true.obs;

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);

    get();

    tabController =
        TabController(vsync: this, length: tabs.length, initialIndex: 0);
    tabController.addListener(() {
      tabIndex(tabController.index);
    });

    animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    super.onInit();
  }

  void listen() {
    if (_listening) return;
    _listening = true;
    int position = 0;
    int inSeconds = 0;

    _listen(player.stream.error, (event) {
      // if (RegExp('Failed to open').hasMatch(event)) {
      //   SmartDialog.showToast(event);
      // }
      SmartDialog.showToast('播放失败: $event');
    });

    _listen(player.stream.completed, (event) {
      if (event) {
        showControls();
      }
    });

    _listen(player.stream.playing, (event) {
      playing(player.state.playing);
      showDanmakuState.value = DanmakuSettingsStorage.danmakuEnable.value;

      if (showDanmakuState.value && danmakuController is DanmakuController) {
        if (event) {
          int currentPosition = player.state.position.inMilliseconds ~/ 1000;
          if (position != currentPosition) {
            position = currentPosition;
          }
          danmakuController!.resume();
        } else {
          danmakuController!.pause();
        }
      }
    });

    _listen(player.stream.position, (event) async {
      int currentinSeconds = event.inSeconds;
      if (currentinSeconds > 0 && lastPosition.value > 0) {
        final thisLastPosition = Duration(seconds: lastPosition.value);
        lastPosition(0);
        await player.seek(thisLastPosition);
        debugPrint('跳转到$thisLastPosition');
      }
      if ((inSeconds - currentinSeconds).abs() >= 5) {
        inSeconds = currentinSeconds;
        final date = DateTime.now().millisecondsSinceEpoch;
        bangumiInfo['id'] = id;
        bangumiInfo['title'] = data.title;
        bangumiInfo['date'] = date;
        bangumiInfo['image'] = data.image;
        final episodeInfo = {
          'episode': episode,
          'title': '第$episode集 ${episodeDetail.title}',
          'position': currentinSeconds,
          'date': date,
          'image': episodeDetail.image
        };
        final item = bangumiInfo['episodes'].firstWhere(
          (e) {
            return e['episode'] == episode;
          },
          orElse: () => {},
        );
        if (item.isEmpty) {
          bangumiInfo['episodes'].add(episodeInfo);
          // print(bangumiInfo);
        } else {
          item['position'] = episodeInfo['position'];
          item['date'] = episodeInfo['date'];
          // print(bangumiInfo);
        }
        box.write('$id', bangumiInfo);
        // print(box.getValues());
      }
      if (showDanmakuState.value && danmakuController is DanmakuController) {
        int currentPosition = event.inMilliseconds ~/ 100;
        if (position != currentPosition) {
          position = currentPosition;
          final now = event.inMilliseconds / 1000;
          final previous = _lastDanmakuPosition;
          final from = previous == null || now < previous || now - previous > 1
              ? now - 0.1
              : previous;
          // 默认弹幕
          if (serverDanmakuState.value && danmakuList.isNotEmpty) {
            final currentDanmakuList = danmakuList.where((e) {
              return e.time > from &&
                  e.time <= now &&
                  DanmakuShieldStorage.shieldCheck(e.text);
            });
            final currentDanmakuListQueue = currentDanmakuList.map((e) {
              return DanmakuItem(e.text,
                  color: ColorUtil.fromHex(e.color),
                  // time: currentPosition,
                  time: e.time,
                  type: DanmakuUtils.getPosition(e.type));
            }).toList();
            try {
              danmakuController!.addItems(currentDanmakuListQueue);
            } catch (e) {
              debugPrint(e.toString());
            }
          }
          for (final source in externalDanmaku.sources.values) {
            final comments = source
                .between(from, now)
                .where((e) => DanmakuShieldStorage.shieldCheck(e.text))
                .map((e) => DanmakuItem(e.text,
                    color: ColorUtil.decimalToColor(e.color),
                    time: e.time + source.offsetSeconds,
                    type: DanmakuUtils.getPosition(e.type)))
                .toList();
            if (comments.isNotEmpty) danmakuController!.addItems(comments);
          }
          _lastDanmakuPosition = now;
        }
      }
    });
  }

  // 番剧数据
  void setBangumiData(data) async {
    try {
      debugPrint('BangumiVodController-setBangumiData');
      this.data = data;
      change(data, status: RxStatus.success());
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  // 获取番剧数据
  void getBangumiData() async {
    if (_bangumiDataRequested || leave.value) return;
    _bangumiDataRequested = true;
    try {
      debugPrint('BangumiVodController-getBangumiData');
      change(null, status: RxStatus.loading());
      final response = await BangumiApi.getBangumiDetail(id: id);
      if (response.statusCode == 200) {
        final data = BangumiDetailModel.fromJson(response.data);
        this.data = data;
        change(data, status: RxStatus.success());
      } else {
        throw Error();
      }
    } catch (e) {
      debugPrint(e.toString());
      change(null, status: RxStatus.error('error'));
    }
  }

  // 番剧剧集
  void setBangumiEpisodes(episodes) async {
    try {
      debugPrint('BangumiVodController-setBangumiEpisodes');
      this.episodes = episodes;
      loadAutomaticDanmaku();
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  // 获取番剧剧集
  void getBangumiEpisodes() async {
    if (_bangumiEpisodesRequested || leave.value) return;
    _bangumiEpisodesRequested = true;
    try {
      debugPrint('BangumiVodController-getBangumiEpisodes');
      final response = await BangumiApi.getBangumiEpisodes(id: id);
      if (response.statusCode == 200) {
        final data = bangumi_episodes_.fromBuffer(response.data);
        if (leave.value) return;
        episodes = data.data.toList();
        loadAutomaticDanmaku();
        update();
      } else {
        throw Error();
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  // 获取服务端弹幕，关闭时取消请求并丢弃已在途的响应。
  void getDanmaku() async {
    if (!serverDanmakuState.value || leave.value) return;
    _serverRequest?.cancel('Reloaded');
    final token = CancelToken();
    _serverRequest = token;
    final thisId = id;
    final thisEpisode = episode;
    var index = 0;
    const length = 3000;
    bool current() =>
        !leave.value &&
        serverDanmakuState.value &&
        thisId == id &&
        thisEpisode == episode &&
        identical(_serverRequest, token) &&
        !token.isCancelled;
    while (current()) {
      try {
        final response = await BangumiApi.getDanmaku(
            id: thisId,
            episode: thisEpisode,
            skip: index * length,
            cancelToken: token);
        if (!current()) return;
        if (response.statusCode != 200) return;
        final data = danmaku_.fromBuffer(response.data);
        danmakuList.addAll(data.data);
        serverDanmakuCount(danmakuList.length);
        if (data.data.length < length) return;
        index++;
      } catch (error) {
        if (!(error is DioException && CancelToken.isCancel(error)))
          debugPrint('服务端弹幕加载失败');
        return;
      }
    }
  }

  void _listen<T>(Stream<T> stream, void Function(T event) onData) {
    _subscriptions.add(stream.listen(onData));
  }

  @override
  void setServerDanmakuEnabled(bool enabled) {
    super.setServerDanmakuEnabled(enabled);
    sourceStorage.write('server-danmaku:$id:$episode', enabled);
    _serverRequest?.cancel('Source changed');
    danmakuList.clear();
    serverDanmakuCount(0);
    danmakuController?.clear();
    if (enabled) getDanmaku();
  }

  @override
  void setExternalDanmakuEnabled(DanmakuProvider provider, bool enabled) {
    super.setExternalDanmakuEnabled(provider, enabled);
    if (externalDanmaku.sources.containsKey(provider)) {
      externalDanmaku.setEnabled(provider, enabled);
      danmakuController?.clear();
    }
  }

  void loadAutomaticDanmaku() {
    if (externalDanmaku.episodeKey != '$id:$episode' || leave.value) return;
    final current = getEpisodeData();
    for (final provider in DanmakuProvider.values) {
      final siteName = switch (provider) {
        DanmakuProvider.bilibili => 'bili_cid',
        DanmakuProvider.bilibiliHmt => 'bili_hmt_cid',
        DanmakuProvider.tencent => 'qq',
      };
      final site = current.sites.where((e) => e.site == siteName).firstOrNull;
      if (site == null || site.id.isEmpty) continue;
      var sourceId = site.id;
      if (provider == DanmakuProvider.tencent) {
        sourceId = PlatformDanmaku.tencentVid(Uri.tryParse(site.id) ?? Uri()) ??
            site.id.split('/').last.replaceAll('.html', '');
      }
      externalDanmaku.setAutomatic(DanmakuBinding(
          provider: provider,
          id: sourceId,
          title: '自动匹配 · 第 $episode 集 ${current.title}',
          durationSeconds: current.duration));
    }
  }

  String lineName(int index) {
    final item = playUrls[index];
    return websiteStreams[item.url]?.title ??
        '线路${index + 1}${item.type.isEmpty ? '' : ' · ${item.type}'}';
  }

  String subtitleLabel(int index) {
    final item = playUrls[index];
    final stream = websiteStreams[item.url];
    return SubtitleLanguage.fromMetadata(
            stream?.episode.subtitleMetadata ?? item.caption)
        .label;
  }

  Future<void> pickWebsiteSource() async {
    final key = '$id:$episode';
    final stream = await Get.to<WebsiteStream>(
        () => WebsiteSourcePicker(keyword: data.title ?? ''));
    if (stream == null || key != '$id:$episode' || leave.value) return;
    final stored = sourceStorage.read('website-matches:$key');
    final matches = <String, dynamic>{
      if (stored is Map) ...Map<String, dynamic>.from(stored)
    };
    matches[stream.episode.provider.name] = stream.episode.toJson();
    sourceStorage.write('website-matches:$key', matches);
    _appendWebsiteStream(stream, play: true);
  }

  void _appendWebsiteStream(WebsiteStream stream, {bool play = false}) {
    websiteStreams[stream.url] = stream;
    var index = playUrls.indexWhere((e) => e.url == stream.url);
    if (index < 0) {
      playUrls.add(vod_item_(
          url: stream.url,
          sort: playUrls.length,
          type: stream.episode.provider.label,
          caption: stream.episode.subtitleMetadata));
      index = playUrls.length - 1;
    }
    if (play || currentLineIndex < 0) {
      currentLineIndex = index;
      setPlayer();
    }
  }

  Future<void> _restoreWebsiteStreams(int session, CancelToken token) async {
    final saved = sourceStorage.read('website-matches:$id:$episode');
    if (saved is! Map) return;
    for (final value in saved.values) {
      final match = WebsiteEpisode.fromJson(value);
      if (match == null || token.isCancelled) continue;
      try {
        // Refresh signed playback URLs instead of caching expired URLs.
        final stream = await websiteSources.resolve(match, token: token);
        if (session != _videoSession || leave.value || token.isCancelled)
          return;
        _appendWebsiteStream(stream);
      } catch (error) {
        if (session != _videoSession || token.isCancelled) return;
        websiteError(error is WebsiteLoginRequired
            ? '${match.provider.label} 需要重新登录，请点击“搜索网站资源”。'
            : '${match.provider.label} 的匹配资源暂时无法加载，请重新选择。');
      }
    }
  }

  // URL解密
  String urlDecode(str) {
    if (str is String &&
        (str.startsWith('https://') || str.startsWith('http://'))) return str;
    try {
      return utf8.decode(base64
          .decode(base64.normalize(str.substring(0, 3) + str.substring(4))));
    } catch (e) {
      debugPrint(e.toString());
      return '';
    }
  }

  // 服务端线路与本地网站匹配独立加载，任何迟到响应都不能覆盖新集。
  void getPlayUrl() async {
    final session = ++_videoSession;
    final thisId = id;
    final thisEpisode = episode;
    _websiteRequest?.cancel('Episode changed');
    final token = CancelToken();
    _websiteRequest = token;
    playUrls.clear();
    websiteStreams.clear();
    websiteError('');
    currentLineInfo('获取中...');
    currentLineIndex = -1;
    unawaited(_restoreWebsiteStreams(session, token));
    try {
      final response = await BangumiApi.getBangumiEpisodeVod(
          id: thisId, episode: thisEpisode);
      if (session != _videoSession || leave.value) return;
      if (response.statusCode == 200) {
        final data = vod_.fromBuffer(response.data.cast<int>());
        playUrls.addAll(data.data);
        if (currentLineIndex < 0 && playUrls.isNotEmpty) {
          currentLineIndex = 0;
          setPlayer();
        }
      } else {
        websiteError('服务端线路不可用，可以搜索网站资源。');
      }
    } catch (_) {
      if (session != _videoSession || leave.value) return;
      websiteError('服务端线路读取失败，可以搜索网站资源。');
    }
    if (playUrls.isEmpty && session == _videoSession && !leave.value) {
      currentLineInfo('暂无资源');
    }
  }

  // 设置视频链接
  void setPlayer() async {
    if (playUrls.isNotEmpty) {
      lastPosition(PlayHistoryStorage.getLastPosition(id, episode));
      currentLineInfo.value = lineName(currentLineIndex);
      final session = _videoSession;
      final line = currentLineIndex;
      final position = player.state.position;
      final headers =
          websiteStreams[playUrls[line].url]?.headers ?? <String, String>{};
      await player.open(
        Media(
          urlDecode(playUrls[currentLineIndex].url),
          httpHeaders: headers,
        ),
      );
      if (session != _videoSession || currentLineIndex != line || leave.value)
        return;
      await player.setRate(playerSpeed.value);
      if (lastPosition.value == 0 && position > Duration.zero)
        await player.seek(position);

      // final history = box.read(id.toString());
      // if (history != null) {
      //   final thisEpisode = history['episodes'].firstWhere(
      //       (e) => e['episode'].toString() == episode.toString(),
      //       orElse: () => {});
      //   lastPosition(int.parse(thisEpisode['position'].toString()));
      // }

      Log.d('播放链接\r\n：${urlDecode(playUrls[currentLineIndex].url)}');
    }
  }

  // 获取集数据
  bangumi_episodes_data_ getEpisodeData() {
    return episodes.firstWhere((e) => e.sort == episode,
        orElse: () => bangumi_episodes_data_());
  }

  // 切换线路
  void changePlayLine(int index) {
    currentLineIndex = index;
    setPlayer();
  }

  // 刷新
  void reload() async {
    getPlayUrl();
  }

  // 获取数据
  void get() async {
    getPlayUrl();
    danmakuList.clear();
    _lastDanmakuPosition = null;
    serverDanmakuCount(0);
    _serverRequest?.cancel('Episode changed');
    serverDanmakuState(
        sourceStorage.read<bool>('server-danmaku:$id:$episode') ??
            DanmakuSettingsStorage.serverDanmakuEnable.value);
    externalDanmaku.open('$id:$episode', defaults: {
      DanmakuProvider.bilibili:
          DanmakuSettingsStorage.bilibiliDanmakuEnable.value,
      DanmakuProvider.bilibiliHmt:
          DanmakuSettingsStorage.bilibiliHmtDanmakuEnable.value,
      DanmakuProvider.tencent: DanmakuSettingsStorage.qqDanmakuEnable.value,
    });
    getDanmaku();
    loadAutomaticDanmaku();
  }

  // 跳转到指定集数位置
  void scrollToIndex() {
    WidgetsBinding.instance.addPostFrameCallback((callback) {
      try {
        final index = episodes.indexWhere((e) => e.sort == episode);
        if (playListScrollController.position.hasPixels) {
          playListScrollController.animateTo(index * 150,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeIn);
        }
      } catch (e) {
        debugPrint(e.toString());
      }
    });
  }

  /// 底部打开播放器设置
  void showDanmakuSettingsSheet() {
    Utils.showBottomSheet(
      title: '弹幕设置',
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          DanmakuSettingsView(
            playerController: this,
            danmakuController: danmakuController,
            onTapDanmakuShield: () {
              Get.back();
              DanmakuShieldView.showDanmakuShieldBottomSheet();
            },
          ),
        ],
      ),
    );
  }

  void showDanmakuShield() {
    TextEditingController keywordController = TextEditingController();

    void addKeyword() {
      if (keywordController.text.isEmpty) {
        SmartDialog.showToast('请输入关键词');
        return;
      }

      DanmakuShieldStorage.addShieldList(keywordController.text.trim());
      keywordController.text = '';
    }

    Utils.showBottomSheet(
      title: '关键词屏蔽',
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          TextField(
            controller: keywordController,
            decoration: InputDecoration(
              contentPadding: AppStyle.edgeInsetsH12,
              border: const OutlineInputBorder(),
              hintText: '请输入关键词',
              suffixIcon: TextButton.icon(
                onPressed: addKeyword,
                icon: const Icon(Icons.add),
                label: const Text('添加'),
              ),
            ),
            onSubmitted: (e) {
              addKeyword();
            },
          ),
          AppStyle.vGap12,
          Obx(
            () => Text(
              '已添加${DanmakuShieldStorage.shieldList.length}个关键词（点击移除）',
              style: Get.textTheme.titleSmall,
            ),
          ),
          AppStyle.vGap12,
          Obx(
            () => Wrap(
              runSpacing: 12,
              spacing: 12,
              children: DanmakuShieldStorage.shieldList
                  .map(
                    (item) => InkWell(
                      borderRadius: AppStyle.radius24,
                      onTap: () {
                        DanmakuShieldStorage.removeShieldList(item);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: AppStyle.radius24,
                        ),
                        padding: AppStyle.edgeInsetsH12.copyWith(
                          top: 4,
                          bottom: 4,
                        ),
                        child: Text(
                          item,
                          style: Get.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  void showPlayerSettingsSheet() {
    Utils.showBottomSheet(
      scrollControlDisabledMaxHeightRatio: 0.7,
      title: '播放设置',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: ListView(
          padding: AppStyle.edgeInsetsV12,
          children: [
            Padding(
              padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
              child: Text(
                '画面尺寸',
                style: Get.textTheme.titleSmall,
              ),
            ),
            SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Obx(
                    () => SettingsSwitch(
                      title: '适应',
                      value: scaleMode.value == 0,
                      onChanged: (e) {
                        updateScaleMode(0);
                      },
                    ),
                  ),
                  AppStyle.divider,
                  Obx(
                    () => SettingsSwitch(
                      title: '拉伸',
                      value: scaleMode.value == 1,
                      onChanged: (e) {
                        updateScaleMode(1);
                      },
                    ),
                  ),
                  AppStyle.divider,
                  Obx(
                    () => SettingsSwitch(
                      title: '铺满',
                      value: scaleMode.value == 2,
                      onChanged: (e) {
                        updateScaleMode(2);
                      },
                    ),
                  ),
                  AppStyle.divider,
                  Obx(
                    () => SettingsSwitch(
                      title: '16:9',
                      value: scaleMode.value == 3,
                      onChanged: (e) {
                        updateScaleMode(3);
                      },
                    ),
                  ),
                  AppStyle.divider,
                  Obx(
                    () => SettingsSwitch(
                      title: '4:3',
                      value: scaleMode.value == 4,
                      onChanged: (e) {
                        updateScaleMode(4);
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: AppStyle.edgeInsetsA12.copyWith(top: 12),
              child: Text(
                '播放速度',
                style: Get.textTheme.titleSmall,
              ),
            ),
            SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: speedsList.map((rate) {
                  return Obx(
                    () => SizedBox(
                      child: Column(
                        children: [
                          SettingsSwitch(
                            title: '${rate}X',
                            value: playerSpeed.value == rate,
                            onChanged: (e) {
                              setPlaybackSpeed(rate);
                            },
                          ),
                          AppStyle.divider,
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void showEpisodesSheet() {
    Utils.showRightDialog(
      title: '选集',
      width: 400,
      useSystem: true,
      child: Builder(builder: (builder) {
        WidgetsBinding.instance.addPostFrameCallback((callback) {
          if (playListScrollController2.position.hasPixels) {
            final index = episodes.indexWhere((e) => e.sort == episode);
            playListScrollController2.animateTo(index * 100,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeIn);
          }
        });
        return ListView(
          controller: playListScrollController2,
          children: episodes.map((item) {
            return Material(
              child: InkWell(
                onTap: () {
                  if (episode == item.sort) {
                    return;
                  }
                  rxEpisode(item.sort);
                  debugPrint('切换到第$episode集');
                  player.stop();
                  danmakuController?.clear();
                  get();
                  Utils.hideRightDialog();
                },
                child: Obx(() {
                  return Container(
                    height: 100,
                    decoration: BoxDecoration(
                        color: episode == item.sort
                            ? Colors.grey.withOpacity(0.2)
                            : Colors.transparent),
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          constraints: const BoxConstraints(maxWidth: 150),
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(7),
                              color: Colors.grey.withOpacity(0.1)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: Stack(
                              alignment: AlignmentDirectional.bottomCenter,
                              // fit: StackFit.expand,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: item.image.isNotEmpty
                                      ? Image.network(
                                          item.image,
                                          width: double.infinity,
                                          height: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            return noImage;
                                          },
                                        )
                                      : noImage,
                                ),
                                Positioned(
                                  bottom: 5,
                                  right: 0,
                                  child: Row(
                                    children: [
                                      Visibility(
                                        visible: true,
                                        maintainSize: false,
                                        maintainSemantics: false,
                                        maintainAnimation: false,
                                        child: Container(
                                          padding: const EdgeInsets.only(
                                              top: 1,
                                              left: 5,
                                              right: 5,
                                              bottom: 3),
                                          margin:
                                              const EdgeInsets.only(right: 5),
                                          decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              color:
                                                  Colors.black.withAlpha(120)),
                                          child: Text(
                                            item.status ? '有资源' : '无资源',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12),
                                          ),
                                        ),
                                      ),
                                      Visibility(
                                        visible: item.duration > 0,
                                        maintainSize: false,
                                        maintainSemantics: false,
                                        maintainAnimation: false,
                                        child: Container(
                                          padding: const EdgeInsets.only(
                                              top: 1,
                                              left: 5,
                                              right: 5,
                                              bottom: 3),
                                          margin:
                                              const EdgeInsets.only(right: 5),
                                          decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              color:
                                                  Colors.black.withAlpha(120)),
                                          child: Text(
                                            Duration(seconds: item.duration)
                                                .toString()
                                                .split('.')
                                                .first,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        Expanded(
                            child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '第${item.sort}集 ${item.title}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15),
                            ),
                            Opacity(
                              opacity: 0.7,
                              child: Text(
                                Time.dateTimeFormat(item.airdate.toInt()),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Opacity(
                              opacity: 0.7,
                              child: Text(
                                item.overview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                ),
                              ),
                            )
                          ],
                        ))
                      ],
                    ),
                  );
                }),
              ),
            );
          }).toList(),
        );
      }),
    );
  }

  void showPlayUrlsSheet() {
    Utils.showBottomSheet(
      title: '切换线路',
      child: ListView.builder(
        itemCount: playUrls.length,
        itemBuilder: (_, i) {
          return RadioListTile(
            value: i,
            groupValue: currentLineIndex,
            title: Text(lineName(i)),
            subtitle: Text('字幕：${subtitleLabel(i)}'),
            secondary: Text(
              playUrls[i].caption,
            ),
            onChanged: (e) {
              Get.back();
              //currentLineIndex = i;
              //setPlayer();
              changePlayLine(i);
            },
          );
        },
      ),
    );
  }

  void showVolumeSlider(BuildContext targetContext) {
    SmartDialog.showAttach(
      targetContext: targetContext,
      alignment: Alignment.topCenter,
      displayTime: const Duration(seconds: 3),
      maskColor: const Color(0x00000000),
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: AppStyle.radius12,
            color: Theme.of(context).cardColor,
          ),
          padding: AppStyle.edgeInsetsA4,
          child: SizedBox(
            width: 200,
            child: Obx(() => Slider(
                  min: 0,
                  max: 100,
                  value: playerVolume.value,
                  onChanged: (newValue) {
                    player.setVolume(newValue);
                    playerVolume(newValue);
                    // AppSettingsController.instance.setPlayerVolume(newValue);
                  },
                )),
          ),
        );
      },
    );
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    leave(true);
    _serverRequest?.cancel('Player closed');
    _websiteRequest?.cancel('Player closed');
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    externalDanmaku.dispose();
    danmakuController = null;
    super.onClose();
  }
}
