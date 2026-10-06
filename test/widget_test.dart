import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xs/src/pages/image_search/view.dart';
import 'package:xs/src/widgets/player/controller.dart';
import 'package:xs/src/widgets/player/controls.dart';

class _SpeedController extends PlayerController {
  @override
  Future<void> setPlaybackSpeed(double rate) async => playerSpeed.value = rate;
  @override
  void showControls() {}
}

void main() {
  testWidgets('speed menu selects and displays the requested rate',
      (tester) async {
    final controller = _SpeedController();
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(body: buildPlaybackSpeedButton(controller))));
    await tester.tap(find.byType(PopupMenuButton<double>));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<double>, '1.5×'));
    await tester.pumpAndSettle();
    expect(controller.playerSpeed.value, 1.5);
    expect(find.text('1.5×'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('image search switches inputs and validates missing images',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const ImageSearchPage()));
    expect(find.text('本地图片'), findsOneWidget);
    expect(find.text('图片链接'), findsOneWidget);
    await tester.tap(find.text('识别番剧'));
    await tester.pump();
    expect(find.text('请先选择动画截图'), findsOneWidget);
    await tester.tap(find.text('图片链接'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'not-a-url');
    await tester.tap(find.text('识别番剧'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效的 HTTP 或 HTTPS 图片链接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
