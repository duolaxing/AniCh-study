import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:xs/src/apis/info.dart' as info;
import 'package:xs/src/utils/utils.dart';

class _UpdateAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancelFuture) async {
    expectSync(options.uri.toString(),
        'https://api.github.com/repos/Sle2p/AniCh/releases/latest');
    return ResponseBody.fromString(
        jsonEncode({
          'name': '9.0.0',
          'body': '上游主版本更新',
          'html_url': 'https://github.com/Sle2p/AniCh/releases/latest',
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('upstream major update can be dismissed to keep using the app',
      (tester) async {
    final originalAdapter = info.api.httpClientAdapter;
    info.api.httpClientAdapter = _UpdateAdapter();
    Utils.packageInfo = PackageInfo(
        appName: 'AniCh',
        packageName: 'cx.xs.open',
        version: '1.0.0',
        buildNumber: '1');
    addTearDown(() {
      info.api.httpClientAdapter = originalAdapter;
      Get.reset();
    });
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: const Scaffold(body: Text('学习修改版')),
    ));
    Utils.checkUpdate();
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 9.0.0'), findsOneWidget);
    expect(find.text('继续使用'), findsOneWidget);
    await tester.tap(find.text('继续使用'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('学习修改版'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
