import 'package:xs/protobuf/bangumi.pb.dart';
import 'package:xs/src/models/website_source.dart';
import 'package:xs/src/pages/bangumi_detail/models/bangumi_detail_model.dart';

/// Local video identities never overlap the server's positive bangumi IDs.
Map<String, dynamic> websitePlaybackArguments(WebsiteStream stream) {
  final ep = stream.episode;
  var hash = 2166136261;
  for (final unit in '${ep.provider.name}:${ep.id}:${ep.pageUrl}'.codeUnits) {
    hash = ((hash ^ unit) * 16777619) & 0x7fffffff;
  }
  final number =
      int.tryParse(RegExp(r'\d+').firstMatch(ep.title)?.group(0) ?? '') ?? 1;
  return {
    'id': -(hash + 1),
    'episode': number,
    'data': BangumiDetailModel(
        title: ep.animeTitle,
        overview: '${ep.provider.label} · ${ep.route} · ${ep.title}'),
    'episodes': [bangumi_episodes_data_(sort: number, title: ep.title)],
    'websiteStream': stream,
  };
}
