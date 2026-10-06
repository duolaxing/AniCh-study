import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xs/src/pages/bangumi_vod/controller.dart';

class ResourceSourcesPanel extends StatelessWidget {
  const ResourceSourcesPanel({super.key, required this.controller});
  final BangumiVodPageController controller;
  @override
  Widget build(BuildContext context) => Obx(() => Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
              title: const Text('视频资源'),
              subtitle: Text(controller.currentLineInfo.value)),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: FilledButton.tonalIcon(
                  onPressed: controller.pickWebsiteSource,
                  icon: const Icon(Icons.search),
                  label: const Text('搜索次元城 / girigirilove'))),
          if (controller.websiteError.value.isNotEmpty)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text(controller.websiteError.value)),
          for (var i = 0; i < controller.playUrls.length; i++)
            ListTile(
              selected: controller.currentLineIndex == i,
              title: Text(controller.lineName(i)),
              subtitle: Text('字幕：${controller.subtitleLabel(i)}'),
              leading: Icon(controller.currentLineIndex == i
                  ? Icons.play_circle
                  : Icons.play_circle_outline),
              onTap: () => controller.changePlayLine(i),
            ),
        ]),
      ));
}
