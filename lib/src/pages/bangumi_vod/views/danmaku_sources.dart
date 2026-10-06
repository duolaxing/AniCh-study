import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xs/src/models/danmaku_source.dart';
import 'package:xs/src/pages/bangumi_vod/controller.dart';
import 'package:xs/src/services/platform_danmaku.dart';
import 'package:xs/src/utils/utils.dart';

class DanmakuSourcesPanel extends StatelessWidget {
  const DanmakuSourcesPanel({super.key, required this.controller});
  final BangumiVodPageController controller;

  Future<void> _match(
      BuildContext context, DanmakuProvider provider, bool link) async {
    final key = controller.externalDanmaku.episodeKey;
    final result = await showDialog<DanmakuBinding>(
        context: context,
        builder: (_) => _DanmakuMatchDialog(
            provider: provider,
            keyword: controller.data.title ?? '',
            linkMode: link));
    if (result == null ||
        controller.leave.value ||
        controller.externalDanmaku.episodeKey != key) return;
    final duration = result.durationSeconds > 0
        ? result.durationSeconds
        : controller.player.state.duration.inSeconds > 0
            ? controller.player.state.duration.inSeconds
            : controller.getEpisodeData().duration;
    controller.externalDanmaku.match(DanmakuBinding(
        provider: result.provider,
        id: result.id,
        title: result.title,
        url: result.url,
        durationSeconds: duration));
    controller.danmakuController?.clear();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller.externalDanmaku,
        builder: (_, __) => Obx(() {
          final manager = controller.externalDanmaku;
          final serverEnabled = controller.serverDanmakuState.value;
          final serverCount = controller.serverDanmakuCount.value;
          return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                ListTile(
                    title: const Text('弹幕源'),
                    subtitle: Text(
                        '当前第 ${controller.episode} 集 · 共 ${manager.enabledCount + (serverEnabled ? serverCount : 0)} 条已启用弹幕')),
                SwitchListTile(
                    title: const Text('服务端弹幕'),
                    subtitle:
                        Text(serverEnabled ? '$serverCount 条' : '已关闭，仅影响此来源'),
                    value: serverEnabled,
                    onChanged: controller.setServerDanmakuEnabled),
                for (final provider in DanmakuProvider.values)
                  _source(context, provider),
              ]));
        }),
      );

  Widget _source(BuildContext context, DanmakuProvider provider) {
    final manager = controller.externalDanmaku;
    final source = manager.sources[provider];
    if (source == null) return const SizedBox.shrink();
    return Column(children: [
      const Divider(height: 1),
      ListTile(
          title: Text(provider.label),
          subtitle: Text([
            source.binding?.title ?? '尚未匹配，可搜索或粘贴视频链接',
            '${source.count} 条${source.loading ? ' · 加载中…' : ''}',
            if (source.manual) '手动匹配',
            if (source.offsetSeconds != 0) '时间偏移 ${source.offsetSeconds} 秒',
            if (source.error.isNotEmpty) source.error,
          ].join('\n')),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(
                value: source.enabled,
                onChanged: (enabled) {
                  controller.setExternalDanmakuEnabled(provider, enabled);
                }),
            PopupMenuButton<String>(
                tooltip: '匹配弹幕',
                itemBuilder: (_) => [
                      const PopupMenuItem(value: 'search', child: Text('搜索匹配')),
                      const PopupMenuItem(value: 'link', child: Text('链接加载')),
                      if (source.binding != null)
                        const PopupMenuItem(
                            value: 'offset', child: Text('时间偏移')),
                      if (source.binding != null)
                        const PopupMenuItem(
                            value: 'retry', child: Text('重新加载')),
                      if (source.manual)
                        const PopupMenuItem(
                            value: 'reset', child: Text('恢复自动匹配')),
                    ],
                onSelected: (action) async {
                  if (action == 'search' || action == 'link') {
                    await _match(context, provider, action == 'link');
                  } else if (action == 'retry') {
                    manager.retry(provider);
                  } else if (action == 'reset') {
                    manager.resetMatch(provider);
                    controller.loadAutomaticDanmaku();
                    controller.danmakuController?.clear();
                  } else if (action == 'offset') {
                    final key = manager.episodeKey;
                    final value = await Utils.showEditTextDialog(
                        source.offsetSeconds.toString(),
                        title: '弹幕时间偏移（秒）',
                        hintText: '正数延后，负数提前，范围 -600 到 600');
                    if (value != null && manager.episodeKey == key) {
                      final offset = double.tryParse(value);
                      if (offset != null && offset.isFinite) {
                        manager.setOffset(provider, offset);
                        controller.danmakuController?.clear();
                      }
                    }
                  }
                }),
          ])),
    ]);
  }
}

void showDanmakuSources(BangumiVodPageController controller) {
  final panel = SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: DanmakuSourcesPanel(controller: controller));
  if (Get.width < 600) {
    Utils.showBottomSheet(title: '弹幕源', child: panel, maxHeight: 650);
  } else {
    Utils.showRightDialog(
        title: '弹幕源', width: 420, useSystem: true, child: panel);
  }
}

class _DanmakuMatchDialog extends StatefulWidget {
  const _DanmakuMatchDialog(
      {required this.provider, required this.keyword, required this.linkMode});
  final DanmakuProvider provider;
  final String keyword;
  final bool linkMode;
  @override
  State<_DanmakuMatchDialog> createState() => _DanmakuMatchDialogState();
}

class _DanmakuMatchDialogState extends State<_DanmakuMatchDialog> {
  final _service = PlatformDanmaku();
  late bool _link = widget.linkMode;
  late final _input = TextEditingController(text: _link ? '' : widget.keyword);
  bool _busy = false;
  String _error = '';
  bool _searched = false;
  List<DanmakuCandidate> _candidates = [];
  List<DanmakuBinding> _bindings = [];
  CancelToken? _request;
  @override
  void dispose() {
    _request?.cancel('Dialog closed');
    _input.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(CancelToken token) action) async {
    _request?.cancel('New request');
    final token = CancelToken();
    _request = token;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await action(token);
    } catch (error) {
      if (mounted && !(error is DioException && CancelToken.isCancel(error)))
        setState(() => _error = error is FormatException
            ? error.message
            : '平台请求失败或接口受限，请重试或使用具体视频链接。');
    } finally {
      if (mounted && identical(_request, token)) setState(() => _busy = false);
    }
  }

  Future<void> _submit() => _link
      ? _resolve(_input.text)
      : _run((token) async {
          final candidates = await _service.search(widget.provider, _input.text,
              cancelToken: token);
          if (mounted && !token.isCancelled)
            setState(() {
              _candidates = candidates;
              _bindings = [];
              _searched = true;
            });
        });

  Future<void> _resolve(String value) => _run((token) async {
        final bindings =
            await _service.resolve(widget.provider, value, cancelToken: token);
        if (!mounted || token.isCancelled) return;
        if (bindings.length == 1) {
          Navigator.pop(context, bindings.single);
        } else {
          setState(() {
            _bindings = bindings;
            _candidates = [];
            _searched = true;
          });
        }
      });

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${widget.provider.label} · 匹配弹幕'),
        content: SizedBox(
            width: 600,
            height: 440,
            child: Column(children: [
              SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false,
                        label: Text('搜索匹配'),
                        icon: Icon(Icons.search)),
                    ButtonSegment(
                        value: true,
                        label: Text('链接加载'),
                        icon: Icon(Icons.link)),
                  ],
                  selected: {
                    _link
                  },
                  onSelectionChanged: _busy
                      ? null
                      : (selection) => setState(() {
                            _link = selection.single;
                            _input.text = _link ? '' : widget.keyword;
                            _error = '';
                            _bindings = [];
                            _candidates = [];
                            _searched = false;
                          })),
              const SizedBox(height: 12),
              TextField(
                  controller: _input,
                  enabled: !_busy,
                  decoration: InputDecoration(
                      labelText: _link ? '视频链接' : '番名或视频名称',
                      hintText: _link
                          ? (widget.provider.isBilibili
                              ? 'BV、播放链接或 cid:数字'
                              : '播放链接或 vid:视频ID')
                          : null,
                      border: const OutlineInputBorder()),
                  onSubmitted: (_) {
                    if (!_busy) _submit();
                  }),
              const SizedBox(height: 8),
              const Text('请选择当前集对应的视频或分集。未列出的分集可使用具体播放链接。',
                  style: TextStyle(fontSize: 12)),
              if (_busy) const LinearProgressIndicator(),
              if (_error.isNotEmpty)
                Padding(padding: const EdgeInsets.all(8), child: Text(_error)),
              Expanded(
                  child: _bindings.isNotEmpty
                      ? ListView(
                          children: _bindings
                              .map((item) => ListTile(
                                  title: Text(item.title),
                                  subtitle: Text('点击加载到当前集 · ${item.id}'),
                                  onTap: _busy
                                      ? null
                                      : () => Navigator.pop(context, item)))
                              .toList())
                      : _candidates.isNotEmpty
                          ? ListView(
                              children: _candidates
                                  .map((item) => ListTile(
                                      title: Text(item.title),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: _busy
                                          ? null
                                          : () => _resolve(item.url)))
                                  .toList())
                          : Center(
                              child: Text(_searched && !_busy
                                  ? '没有匹配结果，请尝试其他关键词或链接。'
                                  : '输入关键词搜索，或粘贴视频链接。'))),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_link ? '解析链接' : '搜索'))
        ],
      );
}
