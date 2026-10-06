import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:xs/src/models/image_search_result.dart';

class ImageSearchService {
  ImageSearchService({Dio? client})
      : client = client ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
            ));
  final Dio client;
  static const maxBytes = 25 * 1024 * 1024;

  Future<List<ImageSearchResult>> search(
      {Uint8List? bytes, String? url, CancelToken? token}) async {
    if (bytes == null) {
      final uri = Uri.tryParse(url ?? '');
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        throw const FormatException('请输入有效的 HTTP 或 HTTPS 图片链接');
      }
    } else if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('请选择小于 25 MB 的图片');
    }
    final response = await client.post<Map<String, dynamic>>(
      'https://api.trace.moe/search',
      queryParameters: {'anilistInfo': 2, if (bytes == null) 'url': url},
      data: bytes,
      cancelToken: token,
      options: Options(headers: {
        if (bytes != null) 'Content-Type': 'application/octet-stream'
      }),
    );
    final data = response.data ?? {};
    final error = data['error']?.toString() ?? '';
    if (error.isNotEmpty) throw StateError(error);
    final list = data['result'];
    final results = (list is List ? list : const [])
        .whereType<Map>()
        .map((item) =>
            ImageSearchResult.fromJson(Map<String, dynamic>.from(item)))
        .toList()
      ..sort((a, b) => b.similarity.compareTo(a.similarity));
    return results;
  }

  static String message(Object error) {
    if (error is FormatException) return error.message;
    if (error is DioException) {
      switch (error.response?.statusCode) {
        case 402:
          return '识别额度已用完或已有任务正在处理，请稍后再试';
        case 429:
          return '请求过于频繁，请稍后再试';
        case 413:
          return '图片超过 25 MB，请选择较小的图片';
      }
    }
    return '识别未完成，请检查网络或换一张截图后重试';
  }
}
