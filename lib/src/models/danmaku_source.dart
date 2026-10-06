enum DanmakuProvider {
  bilibili('哔哩哔哩'),
  bilibiliHmt('哔哩哔哩（港澳台）'),
  tencent('腾讯视频');

  const DanmakuProvider(this.label);
  final String label;
  bool get isBilibili => this != tencent;
}

class DanmakuBinding {
  const DanmakuBinding({
    required this.provider,
    required this.id,
    required this.title,
    this.url = '',
    this.durationSeconds = 0,
  });

  final DanmakuProvider provider;

  /// Bilibili CID, or Tencent VID (never a series CID).
  final String id;
  final String title;
  final String url;
  final int durationSeconds;

  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'id': id,
        'title': title,
        'url': url,
        'duration': durationSeconds,
      };

  static DanmakuBinding? fromJson(dynamic value) {
    if (value is! Map) return null;
    final provider = DanmakuProvider.values
        .where((e) => e.name == value['provider'])
        .firstOrNull;
    final id = value['id']?.toString() ?? '';
    if (provider == null || id.isEmpty) return null;
    return DanmakuBinding(
      provider: provider,
      id: id,
      title: value['title']?.toString() ?? id,
      url: value['url']?.toString() ?? '',
      durationSeconds: (value['duration'] as num?)?.toInt() ?? 0,
    );
  }
}

class DanmakuCandidate {
  const DanmakuCandidate({required this.title, required this.url});
  final String title;
  final String url;
}

class SourceComment {
  const SourceComment({
    required this.text,
    required this.time,
    this.color = 0xffffff,
    this.type = 1,
    this.id = '',
  });
  final String text;
  final double time;
  final int color;

  /// 1 = scroll, 2 = top, 3 = bottom.
  final int type;
  final String id;

  String get identity => id.isNotEmpty ? id : '$time:$type:$color:$text';
}

class DanmakuSourceState {
  DanmakuSourceState({required this.provider, this.enabled = true});
  final DanmakuProvider provider;
  bool enabled;
  DanmakuBinding? binding;
  bool manual = false;
  bool loading = false;
  String error = '';
  double offsetSeconds = 0;
  final Map<String, SourceComment> _comments = {};
  final Map<int, List<SourceComment>> _timeline = {};
  int get count => _comments.length;

  void add(Iterable<SourceComment> comments) {
    for (final comment in comments) {
      if (!comment.time.isFinite || comment.time < 0 || comment.text.isEmpty) {
        continue;
      }
      if (_comments.containsKey(comment.identity)) continue;
      _comments[comment.identity] = comment;
      _timeline.putIfAbsent((comment.time * 10).floor(), () => []).add(comment);
    }
  }

  Iterable<SourceComment> between(double from, double to) sync* {
    if (!enabled || to < from) return;
    final start = ((from - offsetSeconds) * 10).floor();
    final end = ((to - offsetSeconds) * 10).floor();
    for (var tick = start; tick <= end; tick++) {
      yield* (_timeline[tick] ?? const <SourceComment>[]).where((comment) =>
          comment.time + offsetSeconds > from &&
          comment.time + offsetSeconds <= to);
    }
  }

  void clear() {
    _comments.clear();
    _timeline.clear();
    error = '';
  }
}
