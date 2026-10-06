import 'dart:convert';

/// Reads JSON objects embedded in script assignments without executing JS.
Iterable<dynamic> embeddedJson(String text) sync* {
  final starts = RegExp(
    r'(?:__NEXT_DATA__[^>]*>|__INITIAL_STATE__\s*=|(?:var\s+)?(?:player_[\w]+|VIDEO_INFO|COVER_INFO|__NUXT__)\s*=)',
  ).allMatches(text);
  for (final match in starts) {
    final start = text.indexOf(RegExp(r'[\[{]'), match.end);
    if (start < 0) continue;
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          quoted = false;
        }
      } else if (char == '"') {
        quoted = true;
      } else if (char == '{' || char == '[') {
        depth++;
      } else if (char == '}' || char == ']') {
        depth--;
        if (depth == 0) {
          try {
            yield jsonDecode(text.substring(start, i + 1));
          } on FormatException {
            // Non-JSON JavaScript is intentionally not evaluated.
          }
          break;
        }
      }
    }
  }
}

String plainTitle(String text) => text
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&nbsp;', ' ')
    .trim();
