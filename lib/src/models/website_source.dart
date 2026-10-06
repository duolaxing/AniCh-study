enum WebsiteProvider {
  ciyuancheng('次元城', 'https://www.cycani.org'),
  girigirilove('girigirilove', 'https://ani.girigirilove.com');

  const WebsiteProvider(this.label, this.baseUrl);
  final String label;
  final String baseUrl;
}

class WebsiteAnime {
  const WebsiteAnime(
      {required this.provider,
      required this.id,
      required this.title,
      required this.url});
  final WebsiteProvider provider;
  final String id;
  final String title;
  final String url;
}

class WebsiteEpisode {
  const WebsiteEpisode(
      {required this.provider,
      required this.id,
      required this.animeTitle,
      required this.title,
      required this.route,
      required this.pageUrl,
      this.subtitleMetadata = ''});
  final WebsiteProvider provider;
  final String id;
  final String animeTitle;
  final String title;
  final String route;
  final String pageUrl;
  final String subtitleMetadata;

  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'id': id,
        'animeTitle': animeTitle,
        'title': title,
        'route': route,
        'pageUrl': pageUrl,
        'subtitles': subtitleMetadata,
      };

  static WebsiteEpisode? fromJson(dynamic value) {
    if (value is! Map) return null;
    final provider = WebsiteProvider.values
        .where((p) => p.name == value['provider'])
        .firstOrNull;
    if (provider == null || value['id'] == null || value['pageUrl'] == null)
      return null;
    return WebsiteEpisode(
        provider: provider,
        id: value['id'].toString(),
        animeTitle: value['animeTitle']?.toString() ?? '',
        title: value['title']?.toString() ?? '',
        route: value['route']?.toString() ?? '',
        pageUrl: value['pageUrl'].toString(),
        subtitleMetadata: value['subtitles']?.toString() ?? '');
  }
}

class WebsiteStream {
  const WebsiteStream(
      {required this.episode, required this.url, required this.headers});
  final WebsiteEpisode episode;
  final String url;
  final Map<String, String> headers;
  String get title =>
      '${episode.provider.label} · ${episode.route} · ${episode.title}';
}

class WebsiteLoginRequired implements Exception {
  const WebsiteLoginRequired();
}

class WebsiteVerificationRequired implements Exception {
  const WebsiteVerificationRequired(this.url,
      {this.captchaUrl = '', this.type = 'search'});
  final String url;
  final String captchaUrl;
  final String type;
}
