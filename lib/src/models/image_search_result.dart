class ImageSearchResult {
  const ImageSearchResult(
      {required this.title,
      required this.similarity,
      required this.episode,
      required this.from,
      required this.image,
      required this.video});

  final String title;
  final double similarity;
  final String episode;
  final double from;
  final String image;
  final String video;

  factory ImageSearchResult.fromJson(Map<String, dynamic> json) {
    final anime = json['anilist'];
    final titles = anime is Map ? anime['title'] : null;
    final names = titles is Map
        ? [
            titles['chinese'],
            titles['native'],
            titles['romaji'],
            titles['english']
          ]
        : const [];
    final title = names
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .firstOrNull ??
        json['filename']?.toString() ??
        '未知番剧';
    final rawEpisode = json['episode'];
    final episode =
        rawEpisode is List ? rawEpisode.join('、') : rawEpisode?.toString();
    final similarity = (json['similarity'] as num?)?.toDouble() ?? 0;
    final from = (json['from'] as num?)?.toDouble() ?? 0;
    return ImageSearchResult(
      title: title,
      similarity: similarity.isFinite ? similarity.clamp(0, 1) : 0,
      episode: episode == null || episode.isEmpty ? '集数未知' : '第 $episode 集',
      from: from.isFinite ? from.clamp(0, double.infinity) : 0,
      image: json['image']?.toString() ?? '',
      video: json['video']?.toString() ?? '',
    );
  }

  String get timeLabel {
    final seconds = from.round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
