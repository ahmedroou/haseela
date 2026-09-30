import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haseela/design.dart';
import 'package:haseela/updates.dart';

Map<String, dynamic> release({
  String version = '1.0.2',
  String? digest,
  int? size,
  String abi = 'arm64-v8a',
}) => {
  'tag_name': 'v$version',
  'draft': false,
  'prerelease': false,
  'body': 'تحسينات المنتجات والتحديثات',
  'assets': [
    <String, dynamic>{
      'name': 'haseela-$version-$abi.apk',
      'browser_download_url':
          'https://github.com/$updateRepository/releases/download/v$version/haseela-$version-$abi.apk',
      'size': size ?? 16,
      'digest': digest ?? 'sha256:${List.filled(64, 'a').join()}',
    },
  ],
};

// Production URLs remain validated as GitHub HTTPS URLs. Only this transport
// routes the download to a local server, so tests do not depend on GitHub/network.
class DirectHttpOverrides extends HttpOverrides {}

class LocalDownloadClient implements HttpClient {
  LocalDownloadClient(this.origin);
  final Uri origin;
  final client = DirectHttpOverrides().createHttpClient(null);
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      client.getUrl(url.host == 'github.com' ? origin.resolve('/apk') : url);
  @override
  set connectionTimeout(Duration? duration) =>
      client.connectionTimeout = duration;
  @override
  void close({bool force = false}) => client.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'semantic versions compare correctly including multi-digit components',
    () {
      expect(
        AppVersion.parse('v1.10.0').compareTo(AppVersion.parse('1.9.9')),
        greaterThan(0),
      );
      expect(AppVersion.parse('1.0.1').compareTo(AppVersion.parse('1.0.1')), 0);
      expect(() => AppVersion.parse('v1.2.0-beta'), throwsFormatException);
    },
  );
  test('same/older/draft/prerelease releases do not offer an update', () {
    for (final data in [
      release(version: '1.0.0'),
      release(version: '1.0.1'),
      {...release(), 'draft': true},
      {...release(), 'prerelease': true},
    ]) {
      expect(AvailableUpdate.fromRelease(data, '1.0.1', ['arm64-v8a']), isNull);
    }
  });
  test(
    'pick preferred supported architecture and reject missing architecture',
    () {
      final data = release();
      (data['assets'] as List).addAll(
        release(abi: 'armeabi-v7a')['assets'] as List,
      );
      final result = AvailableUpdate.fromRelease(data, '1.0.1', [
        'arm64-v8a',
        'armeabi-v7a',
      ]);
      expect(result!.url.path, endsWith('arm64-v8a.apk'));
      expect(
        () => AvailableUpdate.fromRelease(data, '1.0.1', ['x86_64']),
        throwsFormatException,
      );
    },
  );
  test('reject untrusted host/path, missing digest and oversized APK', () {
    for (final change in [
      {'browser_download_url': 'https://evil.example/app.apk'},
      {
        'browser_download_url':
            'http://github.com/$updateRepository/releases/download/v1.0.2/haseela-1.0.2-arm64-v8a.apk',
      },
      {
        'browser_download_url':
            'https://github.com/other/repo/releases/download/v1.0.2/app.apk',
      },
      {'digest': null},
      {'digest': 'sha256:no'},
      {'size': maxUpdateBytes + 1},
      {'size': 0},
    ]) {
      final data = release();
      (data['assets'] as List).first.addAll(change);
      expect(
        () => AvailableUpdate.fromRelease(data, '1.0.1', ['arm64-v8a']),
        throwsFormatException,
      );
    }
  });

  group('local transport and native bridge', () {
    late Directory directory;
    late HttpServer server;
    late UpdateController controller;
    late Map<String, dynamic> response;
    var responseCode = 200;
    final payload = utf8.encode('a-test-apk-payload');
    final installed = <String>[];
    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'haseela-updater-test-',
      );
      response = release(
        size: payload.length,
        digest: 'sha256:${sha256.convert(payload)}',
      );
      responseCode = 200;
      installed.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path == '/apk') {
          request.response.contentLength = payload.length;
          request.response.add(payload);
        } else {
          request.response.statusCode = responseCode;
          request.response.write(jsonEncode(response));
        }
        await request.response.close();
      });
      final origin = Uri.parse('http://127.0.0.1:${server.port}');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(updateChannel, (call) async {
            if (call.method == 'info') {
              return {
                'version': '1.0.1',
                'abis': ['arm64-v8a'],
                'directory': directory.path,
              };
            }
            if (call.method == 'install') {
              installed.add(call.arguments['path'] as String);
              return 'installer';
            }
            throw PlatformException(code: 'UNSUPPORTED');
          });
      controller = UpdateController(
        endpoint: origin.resolve('/release'),
        clientFactory: () => LocalDownloadClient(origin),
      );
    });
    tearDown(() async {
      controller.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(updateChannel, null);
      await server.close(force: true);
      await directory.delete(recursive: true);
    });
    test(
      'check, download, verify digest and explicitly launch native installer',
      () async {
        await controller.initialize();
        expect(controller.available!.version.toString(), '1.0.2');
        await controller.download();
        expect(await controller.downloaded!.readAsBytes(), payload);
        expect(controller.progress, 1);
        expect(installed, isEmpty);
        await controller.install();
        expect(installed, [controller.downloaded!.path]);
        expect(controller.message, contains('Android'));
      },
    );
    test('corrupt checksum leaves no installable APK', () async {
      response = release(size: payload.length);
      await controller.initialize();
      await controller.download();
      expect(controller.downloaded, isNull);
      expect(controller.message, contains('سلامة'));
      expect(await directory.list().toList(), isEmpty);
      await controller.install();
      expect(installed, isEmpty);
    });
    test('incorrect content length rejected without install', () async {
      response = release(
        size: payload.length + 1,
        digest: 'sha256:${sha256.convert(payload)}',
      );
      await controller.initialize();
      await controller.download();
      expect(controller.downloaded, isNull);
      expect(controller.message, contains('حجم'));
      expect(installed, isEmpty);
    });
    test(
      'failed automatic check is quiet; manual check explains retry; recovery works',
      () async {
        responseCode = 503;
        await controller.initialize();
        expect(controller.available, isNull);
        expect(controller.message, isEmpty);
        await controller.check(manual: true);
        expect(controller.message, contains('الإنترنت'));
        responseCode = 200;
        await controller.check(manual: true);
        expect(controller.available, isNotNull);
        responseCode = 503;
        await controller.check(manual: true);
        expect(controller.available, isNotNull);
        expect(controller.busy, isFalse);
      },
    );
  });

  testWidgets(
    'update sheet wraps long labels on narrow screen and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = UpdateController();
      controller.current = '1.0.1';
      controller.supported = true;
      controller.available = AvailableUpdate.fromRelease(release(), '1.0.1', [
        'arm64-v8a',
      ]);
      controller.message = 'إصدار جديد متاح الآن';
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(1.8),
              ),
              child: Scaffold(body: UpdateSheet(controller: controller)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('download_update')));
      await tester.pumpAndSettle();
      expect(find.text('تنزيل وتثبيت التحديث'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
