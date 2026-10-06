import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:xs/src/models/danmaku_source.dart';

abstract class DanmakuLoader {
  Stream<List<SourceComment>> load(DanmakuBinding binding, CancelToken token);
}

/// Owns one episode's source bindings and rejects every late response from a
/// previous episode or from a source that was replaced/disabled.
class EpisodeDanmaku extends ChangeNotifier {
  EpisodeDanmaku({
    required this.loader,
    required this.read,
    required this.write,
  });

  final DanmakuLoader loader;
  final dynamic Function(String key) read;
  final void Function(String key, dynamic value) write;
  final Map<DanmakuProvider, DanmakuSourceState> sources = {};
  final Map<DanmakuProvider, CancelToken> _requests = {};
  String episodeKey = '';
  int _session = 0;
  bool _disposed = false;

  int get enabledCount =>
      sources.values.where((s) => s.enabled).fold(0, (n, s) => n + s.count);

  void open(String key, {Map<DanmakuProvider, bool> defaults = const {}}) {
    _session++;
    _cancelAll();
    episodeKey = key;
    sources.clear();
    final saved = read('danmaku-sources:$key');
    for (final provider in DanmakuProvider.values) {
      final value = saved is Map ? saved[provider.name] : null;
      final state = DanmakuSourceState(
        provider: provider,
        enabled: value is Map
            ? value['enabled'] != false
            : defaults[provider] ?? true,
      );
      if (value is Map) {
        final binding = DanmakuBinding.fromJson(value['binding']);
        state.binding = binding?.provider == provider ? binding : null;
        state.manual = state.binding != null;
        final offset = value['offset'];
        if (offset is num && offset.isFinite) {
          state.offsetSeconds = offset.toDouble();
        }
      }
      sources[provider] = state;
      if (state.enabled && state.binding != null) _load(state);
    }
    notifyListeners();
  }

  void setAutomatic(DanmakuBinding binding) {
    final state = sources[binding.provider];
    if (state == null || state.manual || state.binding?.id == binding.id)
      return;
    state.binding = binding;
    if (state.enabled) _load(state);
    notifyListeners();
  }

  void match(DanmakuBinding binding) {
    final state = sources[binding.provider];
    if (state == null) return;
    state.binding = binding;
    state.manual = true;
    state.enabled = true;
    state.offsetSeconds = 0;
    _save();
    _load(state);
    notifyListeners();
  }

  void setEnabled(DanmakuProvider provider, bool enabled) {
    final state = sources[provider]!;
    state.enabled = enabled;
    _requests.remove(provider)?.cancel('Source disabled');
    state.loading = false;
    if (enabled && state.binding != null) _load(state);
    _save();
    notifyListeners();
  }

  void resetMatch(DanmakuProvider provider) {
    final state = sources[provider]!;
    _requests.remove(provider)?.cancel('Match reset');
    state.binding = null;
    state.manual = false;
    state.loading = false;
    state.offsetSeconds = 0;
    state.clear();
    _save();
    notifyListeners();
  }

  void setOffset(DanmakuProvider provider, double offset) {
    if (!offset.isFinite) return;
    sources[provider]!.offsetSeconds = offset.clamp(-600, 600);
    _save();
    notifyListeners();
  }

  void retry(DanmakuProvider provider) {
    final state = sources[provider]!;
    if (state.enabled && state.binding != null) _load(state);
  }

  void _save() {
    write('danmaku-sources:$episodeKey', {
      for (final state in sources.values)
        state.provider.name: {
          'enabled': state.enabled,
          'binding': state.manual ? state.binding?.toJson() : null,
          'offset': state.offsetSeconds,
        },
    });
  }

  Future<void> _load(DanmakuSourceState state) async {
    _requests.remove(state.provider)?.cancel('Replaced');
    final token = CancelToken();
    _requests[state.provider] = token;
    final session = _session;
    state.clear();
    state.loading = true;
    bool current() =>
        !_disposed &&
        session == _session &&
        identical(_requests[state.provider], token) &&
        state.enabled;
    try {
      await for (final batch in loader.load(state.binding!, token)) {
        if (!current()) return;
        state.add(batch);
        notifyListeners();
      }
    } catch (error) {
      if (current() &&
          !(error is DioException && CancelToken.isCancel(error))) {
        state.error = '加载失败，请重试或重新匹配';
      }
    } finally {
      if (current()) {
        state.loading = false;
        notifyListeners();
      }
    }
  }

  void _cancelAll() {
    for (final token in _requests.values) {
      token.cancel('Episode changed');
    }
    _requests.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    _cancelAll();
    super.dispose();
  }
}
