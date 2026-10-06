enum SubtitleLanguage {
  simplified('简体'),
  traditional('繁体'),
  unknown('未知');

  const SubtitleLanguage(this.label);
  final String label;

  /// Only explicit subtitle metadata is evidence; the script used in a title
  /// does not tell us which subtitles are burned into the video.
  static SubtitleLanguage fromMetadata(String metadata) {
    final hasSimplified = RegExp(
      r'简体|簡體|简中|簡中|简字|簡字|简繁|簡繁|(?:^|[^a-z])(?:chs|sc|zh-cn|zh-hans)(?:$|[^a-z])',
      caseSensitive: false,
    ).hasMatch(metadata);
    final hasTraditional = RegExp(
      r'繁体|繁體|繁中|繁字|简繁|簡繁|(?:^|[^a-z])(?:cht|tc|zh-tw|zh-hant)(?:$|[^a-z])',
      caseSensitive: false,
    ).hasMatch(metadata);
    if (hasSimplified == hasTraditional) return unknown;
    return hasSimplified ? SubtitleLanguage.simplified : traditional;
  }
}
