import 'package:dio/dio.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xs/src/models/website_source.dart';
import 'package:xs/src/services/website_sources.dart';
import 'package:xs/src/utils/subtitle_language.dart';

class WebsiteSourcePicker extends StatefulWidget {
  const WebsiteSourcePicker({super.key, required this.keyword});
  final String keyword;
  @override
  State<WebsiteSourcePicker> createState() => _WebsiteSourcePickerState();
}

class _WebsiteSourcePickerState extends State<WebsiteSourcePicker> {
  late final _query = TextEditingController(text: widget.keyword);
  final _service = WebsiteSources();
  WebsiteProvider _provider = WebsiteProvider.ciyuancheng;
  WebsiteAnime? _anime;
  List<WebsiteAnime> _results = [];
  List<WebsiteEpisode> _episodes = [];
  bool _busy = false;
  String _error = '';
  bool _searched = false;
  CancelToken? _request;

  @override
  void dispose() {
    _request?.cancel('Page closed');
    _query.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(CancelToken token) action) async {
    _request?.cancel('Replaced');
    final token = CancelToken();
    _request = token;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      try {
        await action(token);
      } on WebsiteVerificationRequired catch (verification) {
        if (!mounted || verification.captchaUrl.isEmpty || token.isCancelled)
          rethrow;
        final verified = await showDialog<bool>(
            context: context,
            builder: (_) => _WebsiteCaptchaDialog(
                service: _service, verification: verification));
        if (verified != true || !mounted || token.isCancelled) return;
        await action(token);
      }
    } catch (error) {
      if (!mounted || (error is DioException && CancelToken.isCancel(error)))
        return;
      setState(() => _error = error is WebsiteVerificationRequired
          ? '网站需要验证或动态解析。请在网站确认访问后重试；也可选择其他线路。'
          : error is WebsiteLoginRequired
              ? '此资源需要登录次元城后获取。'
              : '请求未完成，请检查网络或稍后重试。');
    } finally {
      if (mounted && identical(_request, token)) setState(() => _busy = false);
    }
  }

  Future<void> _search() => _run((token) async {
        final results =
            await _service.search(_provider, _query.text.trim(), token: token);
        if (!mounted || token.isCancelled) return;
        setState(() {
          _results = results;
          _anime = null;
          _episodes = [];
          _searched = true;
        });
      });

  Future<void> _selectAnime(WebsiteAnime anime) => _run((token) async {
        final episodes = await _service.episodes(anime, token: token);
        if (!mounted || token.isCancelled) return;
        setState(() {
          _anime = anime;
          _episodes = episodes;
        });
      });

  Future<void> _selectEpisode(WebsiteEpisode episode) => _run((token) async {
        try {
          final stream = await _service.resolve(episode, token: token);
          if (mounted && !token.isCancelled) Navigator.pop(context, stream);
        } on WebsiteLoginRequired {
          if (!mounted) return;
          final ok = await showDialog<bool>(
              context: context,
              builder: (_) => _WebsiteLoginDialog(service: _service));
          if (ok != true || !mounted || token.isCancelled) return;
          final stream = await _service.resolve(episode, token: token);
          if (mounted && !token.isCancelled) Navigator.pop(context, stream);
        }
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('搜索网站资源'), actions: [
          IconButton(
              tooltip: '打开网站',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => launchUrl(Uri.parse(_provider.baseUrl),
                  mode: LaunchMode.externalApplication)),
        ]),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                SegmentedButton<WebsiteProvider>(
                    segments: WebsiteProvider.values
                        .map((p) =>
                            ButtonSegment(value: p, label: Text(p.label)))
                        .toList(),
                    selected: {_provider},
                    onSelectionChanged: _busy
                        ? null
                        : (selection) => setState(() {
                              _provider = selection.single;
                              _anime = null;
                              _results = [];
                              _episodes = [];
                              _error = '';
                              _searched = false;
                            })),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _query,
                          enabled: !_busy,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) {
                            if (!_busy) _search();
                          },
                          decoration: const InputDecoration(
                              labelText: '番剧名称',
                              border: OutlineInputBorder()))),
                  IconButton(
                      tooltip: '搜索',
                      onPressed: _busy ? null : _search,
                      icon: const Icon(Icons.search)),
                ]),
                const SizedBox(height: 8),
                const Text('先确认番剧，再选择当前集对应的线路和集数。匹配只应用于当前集。',
                    style: TextStyle(fontSize: 12)),
              ])),
          if (_busy) const LinearProgressIndicator(),
          if (_error.isNotEmpty)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_anime != null)
            ListTile(
                title: Text(_anime!.title),
                leading: IconButton(
                    tooltip: '返回搜索结果',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _anime = null;
                              _episodes = [];
                            }))),
          Expanded(
              child: _anime == null
                  ? _results.isEmpty && _searched && !_busy && _error.isEmpty
                      ? const Center(child: Text('没有找到资源，请尝试其他番名。'))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (_, i) => ListTile(
                              title: Text(_results[i].title),
                              subtitle: Text(_provider.label),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _busy
                                  ? null
                                  : () => _selectAnime(_results[i])))
                  : _episodes.isEmpty && !_busy && _error.isEmpty
                      ? const Center(child: Text('未能读取分集，请在网站检查此条目。'))
                      : ListView.builder(
                          itemCount: _episodes.length,
                          itemBuilder: (_, i) {
                            final ep = _episodes[i];
                            return ListTile(
                                title: Text(ep.title),
                                subtitle: Text(
                                    '${ep.route} · 字幕：${SubtitleLanguage.fromMetadata(ep.subtitleMetadata).label}'),
                                trailing: const Icon(Icons.play_arrow),
                                onTap: _busy ? null : () => _selectEpisode(ep));
                          })),
        ]),
      );
}

class _WebsiteLoginDialog extends StatefulWidget {
  const _WebsiteLoginDialog({required this.service});
  final WebsiteSources service;
  @override
  State<_WebsiteLoginDialog> createState() => _WebsiteLoginDialogState();
}

class _WebsiteLoginDialogState extends State<_WebsiteLoginDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String _error = '';
  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.service.loginCiyuan(_username.text, _password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = '登录失败，请检查账号或在网站确认验证要求。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('登录次元城'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('此线路需要网站账号。账号信息仅发送到次元城，密码不会保存。'),
          TextField(
              controller: _username,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '账号')),
          TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
              onSubmitted: (_) {
                if (!_busy) _login();
              }),
          if (_error.isNotEmpty) Text(_error),
        ])),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: _busy ? null : _login,
              child: Text(_busy ? '登录中…' : '登录'))
        ],
      );
}

class _WebsiteCaptchaDialog extends StatefulWidget {
  const _WebsiteCaptchaDialog(
      {required this.service, required this.verification});
  final WebsiteSources service;
  final WebsiteVerificationRequired verification;
  @override
  State<_WebsiteCaptchaDialog> createState() => _WebsiteCaptchaDialogState();
}

class _WebsiteCaptchaDialogState extends State<_WebsiteCaptchaDialog> {
  final _input = TextEditingController();
  Uint8List? _image;
  bool _busy = false;
  String _error = '';
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final bytes =
          await widget.service.captcha(widget.verification.captchaUrl);
      if (mounted) setState(() => _image = bytes);
    } catch (_) {
      if (mounted) setState(() => _error = '验证码读取失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_input.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final ok = await widget.service
          .verifyCaptcha(_input.text, widget.verification.type);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = '验证码不正确，请重新输入或刷新');
      }
    } catch (_) {
      if (mounted) setState(() => _error = '验证未完成，请稍后再试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('网站访问验证'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('girigirilove 要求输入图片验证码后才能继续访问。'),
          if (_image != null)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Image.memory(_image!, height: 60)),
          TextButton(
              onPressed: _busy ? null : _refresh, child: const Text('刷新验证码')),
          TextField(
              controller: _input,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '验证码'),
              onSubmitted: (_) {
                if (!_busy) _verify();
              }),
          if (_error.isNotEmpty) Text(_error),
          if (_busy) const LinearProgressIndicator(),
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: _busy ? null : _verify, child: const Text('验证并继续'))
        ],
      );
}
