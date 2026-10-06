import 'package:flutter/material.dart';
import 'package:xs/src/services/open_website_video.dart';

class ContentStatusView extends StatelessWidget {
  const ContentStatusView(
      {super.key,
      required this.title,
      required this.onRetry,
      this.detail = ''});
  final String title;
  final String detail;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 40),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(detail.isEmpty ? '原服务端暂未提供内容，可以重试或直接搜索网站资源。' : detail,
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
                FilledButton.icon(
                    onPressed: openWebsiteVideo,
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('搜索网站资源')),
              ]),
        ]),
      ));
}
