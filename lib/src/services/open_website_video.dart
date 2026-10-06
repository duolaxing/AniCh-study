import 'package:get/get.dart';
import 'package:xs/src/models/website_source.dart';
import 'package:xs/src/pages/website_source/view.dart';
import 'package:xs/src/utils/website_playback.dart';

Future<void> openWebsiteVideo({String keyword = ''}) async {
  final stream =
      await Get.to<WebsiteStream>(() => WebsiteSourcePicker(keyword: keyword));
  if (stream != null) {
    await Get.toNamed('/website_player',
        arguments: websitePlaybackArguments(stream));
  }
}
