import 'package:crease/config/in_app_update_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testChannel = MethodChannel('app.crease.crease/in_app_update_test');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(testChannel, null);
  });

  test('checks Play Store once per session on Android and forwards completeUpdate', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(testChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'checkForFlexibleUpdate') return 'started';
      if (call.method == 'completeUpdate') return true;
      return null;
    });

    final service = InAppUpdateService(channel: testChannel);
    var downloadedCount = 0;
    service.init(onUpdateDownloaded: () => downloadedCount++);

    expect(await service.checkForFlexibleUpdate(), 'started');
    // Second call in same session is deduplicated unless forced
    expect(await service.checkForFlexibleUpdate(), 'already_checked');
    expect(await service.checkForFlexibleUpdate(force: true), 'started');

    // Simulate native Play Core notifying Flutter that background download finished
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      testChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onUpdateDownloaded'),
      ),
      (_) {},
    );
    expect(downloadedCount, 1);

    expect(await service.completeUpdate(), isTrue);
    expect(calls, [
      'checkForFlexibleUpdate',
      'checkForFlexibleUpdate',
      'completeUpdate',
    ]);
  });

  test('handles MissingPluginException and non-Android platforms gracefully', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = InAppUpdateService(channel: testChannel);
    expect(await service.checkForFlexibleUpdate(), 'unavailable');
    expect(await service.completeUpdate(), isFalse);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final iosService = InAppUpdateService(channel: testChannel);
    expect(await iosService.checkForFlexibleUpdate(), 'unsupported');
    expect(await iosService.completeUpdate(), isFalse);
  });
}
