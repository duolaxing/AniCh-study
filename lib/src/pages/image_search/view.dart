import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xs/src/models/image_search_result.dart';
import 'package:xs/src/pages/search/models/search_type.dart';
import 'package:xs/src/services/image_search.dart';

class ImageSearchPage extends StatefulWidget {
  const ImageSearchPage({super.key});
  @override
  State<ImageSearchPage> createState() => _ImageSearchPageState();
}

class _ImageSearchPageState extends State<ImageSearchPage> {
  final _url = TextEditingController();
  final _service = ImageSearchService();
  Uint8List? _bytes;
  String _fileName = '';
  bool _useUrl = false;
  bool _busy = false;
  bool _searched = false;
  String _error = '';
  List<ImageSearchResult> _results = [];
  CancelToken? _request;

  @override
  void dispose() {
    _request?.cancel('Page closed');
    _url.dispose();
    super.dispose();
  }

  void _clear() {
    _results = [];
    _error = '';
    _searched = false;
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.image, withData: true, allowMultiple: false);
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (file.size > ImageSearchService.maxBytes || file.bytes == null) {
        setState(() => _error = '无法读取图片或文件超过 25 MB');
        return;
      }
      setState(() {
        _bytes = file.bytes;
        _fileName = file.name;
        _clear();
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法选择图片，请检查文件权限');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _search() async {
    if (!_useUrl && _bytes == null) {
      setState(() => _error = '请先选择动画截图');
      return;
    }
    FocusScope.of(context).unfocus();
    _request?.cancel('New search');
    final token = CancelToken();
    _request = token;
    setState(() {
      _busy = true;
      _error = '';
      _results = [];
      _searched = true;
    });
    try {
      final results = await _service.search(
          bytes: _useUrl ? null : _bytes,
          url: _useUrl ? _url.text.trim() : null,
          token: token);
      if (mounted && identical(_request, token))
        setState(() => _results = results);
    } catch (error) {
      if (mounted && !(error is DioException && CancelToken.isCancel(error))) {
        setState(() => _error = ImageSearchService.message(error));
      }
    } finally {
      if (mounted && identical(_request, token)) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('以图搜番')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('选择动画正片截图，查找番名、集数和画面时间。'),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                            value: false,
                            icon: Icon(Icons.image_outlined),
                            label: Text('本地图片')),
                        ButtonSegment(
                            value: true,
                            icon: Icon(Icons.link),
                            label: Text('图片链接')),
                      ],
                      selected: {
                        _useUrl
                      },
                      onSelectionChanged: _busy
                          ? null
                          : (selection) {
                              setState(() {
                                _useUrl = selection.single;
                                _clear();
                              });
                            }),
                  const SizedBox(height: 12),
                  if (_useUrl)
                    TextField(
                      controller: _url,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                          labelText: '图片链接',
                          hintText: 'https://…',
                          border: OutlineInputBorder()),
                      onChanged: (_) => setState(_clear),
                      onSubmitted: (_) {
                        if (!_busy) _search();
                      },
                    )
                  else
                    OutlinedButton.icon(
                        onPressed: _busy ? null : _pick,
                        icon: const Icon(Icons.folder_open),
                        label: Text(_fileName.isEmpty ? '选择截图' : _fileName)),
                  if (!_useUrl && _bytes != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Image.memory(_bytes!,
                            height: 220,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const Text('图片无法预览，请换一张图片'))),
                  const SizedBox(height: 12),
                  const Text(
                      '识别由 trace.moe 提供。点击识别会发送所选图片或图片链接。\n'
                      '保留画面比例，尽量避免弹幕、字幕和黑边遮挡。相似度仅供参考。',
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                      onPressed: _busy ? null : _search,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.image_search),
                      label: Text(_busy ? '正在识别…' : '识别番剧')),
                  if (_error.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(_error,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (_searched && !_busy && _error.isEmpty && _results.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('没有找到匹配画面，请换一张截图。')),
                  for (final result in _results) _resultCard(result),
                ]),
          )),
        ]),
      );

  Widget _resultCard(ImageSearchResult result) => Card(
        margin: const EdgeInsets.only(top: 16),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (Uri.tryParse(result.image)?.scheme == 'https')
                    Image.network(result.image,
                        height: 160,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined)),
                  const SizedBox(height: 8),
                  Text(result.title,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(
                      '${result.episode} · ${result.timeLabel} · 相似度 ${(result.similarity * 100).toStringAsFixed(1)}%'),
                  if (result.similarity < 0.87) const Text('相似度较低，请对照画面确认。'),
                  Wrap(spacing: 8, children: [
                    FilledButton.tonal(
                        onPressed: () => Get.toNamed('/search', arguments: {
                              'type': SearchType.bangumi,
                              'keyword': result.title
                            }),
                        child: const Text('搜索这部番')),
                    if (Uri.tryParse(result.video)?.scheme == 'https')
                      TextButton(
                          onPressed: () async {
                            final ok = await launchUrl(Uri.parse(result.video),
                                mode: LaunchMode.externalApplication);
                            if (!ok && mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('无法打开预览片段')));
                          },
                          child: const Text('预览片段')),
                  ]),
                ])),
      );
}
