import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xs/protobuf/list.pb.dart';
import 'package:xs/src/apis/home.dart';

class HomeController extends GetxController
    with StateMixin, GetTickerProviderStateMixin {
  // 导航栏
  final List<Tab> tabs = <Tab>[
    const Tab(
      child: Align(
        alignment: Alignment.center,
        child: Text('标签'),
      ),
    ),
    const Tab(
      child: Align(
        alignment: Alignment.center,
        child: Text('最新'),
      ),
    ),
    const Tab(
      child: Align(
        alignment: Alignment.center,
        child: Text('插画'),
      ),
    ),
    const Tab(
      child: Align(
        alignment: Alignment.center,
        child: Text('COSPLAY'),
      ),
    ),
  ];

  late TabController tabController;
  RxInt tabIndex = 1.obs;

  late final AnimationController animationController;

  @override
  void onInit() {
    super.onInit();

    tabController =
        TabController(vsync: this, length: tabs.length, initialIndex: 1);
    tabController.addListener(() {
      tabIndex(tabController.index);
    });

    animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }
}

abstract class HomeFeedController extends GetxController
    with StateMixin<List<thread_list_data_>> {
  HomeFeedController(this.feedType);
  final String feedType;
  List<thread_list_data_> result = [];
  RxBool isLoading = false.obs;
  bool _requesting = false;
  bool _hasMore = true;
  @override
  void onInit() {
    get();
    super.onInit();
  }

  Future<void> get() => _load(reset: true);
  Future<void> more() async {
    if (result.isEmpty || !_hasMore) return;
    await _load(reset: false);
  }

  Future<bool> reload() async {
    await get();
    return status.isSuccess || status.isEmpty;
  }

  Future<void> _load({required bool reset}) async {
    if (_requesting) return;
    _requesting = true;
    isLoading(true);
    if (reset) change(result, status: RxStatus.loading());
    try {
      final response = await HomeApi.getThreadList(
          type: feedType, skip: reset ? 0 : result.last.id);
      final bytes = response.data;
      if (bytes is! List<int> || bytes.isEmpty)
        throw const FormatException('首页返回了空响应');
      final data = thread_list_.fromBuffer(bytes);
      if (data.error) throw StateError('服务端拒绝加载首页数据');
      if (isClosed) return;
      if (reset) result.clear();
      final items = data.body.data
          .where((e) => !result.any((old) => old.id == e.id))
          .toList();
      result.addAll(items);
      _hasMore = items.isNotEmpty;
      change(result,
          status: result.isEmpty ? RxStatus.empty() : RxStatus.success());
    } catch (_) {
      if (!isClosed && (reset || result.isEmpty)) {
        change(null, status: RxStatus.error('原服务端请求未成功，请检查网络后重试，或使用网站资源。'));
      }
    } finally {
      _requesting = false;
      if (!isClosed) isLoading(false);
    }
  }
}

class HomeAllController extends HomeFeedController {
  HomeAllController() : super('all');
}

class HomeArtworkController extends HomeFeedController {
  HomeArtworkController() : super('artwork');
}

class HomeCosplayController extends HomeFeedController {
  HomeCosplayController() : super('cosplay');
}

class HomeTagsController extends GetxController
    with StateMixin<List<Tag>>, GetSingleTickerProviderStateMixin {
  List<Tag> result = [];
  RxBool isLoading = false.obs;

  @override
  void onInit() {
    get();
    super.onInit();
  }

  // 获取数据
  void get() async {
    try {
      debugPrint('HomeTagsController-get');
      change(result, status: RxStatus.loading());
      final response = await HomeApi.getTags();
      List<Tag> tagsList =
          List<Tag>.from(response.data.map((e) => Tag.fromJson(e)));
      result.addAll(tagsList);
      change(result,
          status: result.isEmpty ? RxStatus.empty() : RxStatus.success());
    } catch (e) {
      debugPrint(e.toString());
      change(null, status: RxStatus.error('error'));
    }
  }

  // 加载更多
  void more() async {
    try {
      debugPrint('HomeTagsController-more');
      isLoading(true);
      final response = await HomeApi.getTags(skip: result.length);
      List<Tag> tagsList =
          List<Tag>.from(response.data.map((e) => Tag.fromJson(e)));
      result.addAll(tagsList);
      change(result,
          status: result.isEmpty ? RxStatus.empty() : RxStatus.success());
    } catch (e) {
      debugPrint(e.toString());
    }
    isLoading(false);
  }

  // 刷新
  Future<bool> reload() async {
    try {
      debugPrint('HomeTagsController-reload');
      final response = await HomeApi.getTags();
      List<Tag> tagsList =
          List<Tag>.from(response.data.map((e) => Tag.fromJson(e)));
      result.clear();
      result.addAll(tagsList);
      change(result,
          status: result.isEmpty ? RxStatus.empty() : RxStatus.success());
    } catch (e) {
      debugPrint(e.toString());
    }
    return true;
  }
}

class Tag {
/*
{
  "name": "少女",
  "translate": "young girl",
  "count": 10933,
  "color": "#cebfd6",
  "image": "https://wework.qpic.cn/wwpic/195707_TozejoaOSIG2Xhy_1694591349"
} 
*/

  String? name;
  String? translate;
  int? count;
  String? color;
  String? image;

  Tag({
    this.name,
    this.translate,
    this.count,
    this.color,
    this.image,
  });
  Tag.fromJson(Map<String, dynamic> json) {
    name = json['name']?.toString();
    translate = json['translate']?.toString();
    count = json['count']?.toInt();
    color = json['color']?.toString();
    image = json['image']?.toString();
  }
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['name'] = name;
    data['translate'] = translate;
    data['count'] = count;
    data['color'] = color;
    data['image'] = image;
    return data;
  }
}
