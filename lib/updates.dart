import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'forms.dart';

const updateRepository = 'ahmedroou/haseela';
const updateChannel = MethodChannel('haseela/updates');
const maxUpdateBytes = 160 * 1024 * 1024;

/// A published stable version. Android also verifies a greater versionCode and
/// the installed app's signing certificate before handing the APK to its installer.
class AppVersion implements Comparable<AppVersion> {
  AppVersion(this.parts);
  final List<int> parts;
  factory AppVersion.parse(String value) {
    if (!RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(value)) {
      throw const FormatException('صيغة إصدار التحديث غير صالحة');
    }
    return AppVersion(
      value.replaceFirst(RegExp('^v'), '').split('.').map(int.parse).toList(),
    );
  }
  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < 3; i++) {
      final result = parts[i].compareTo(other.parts[i]);
      if (result != 0) return result;
    }
    return 0;
  }

  @override
  String toString() => parts.join('.');
}

class AvailableUpdate {
  AvailableUpdate({
    required this.version,
    required this.url,
    required this.bytes,
    required this.digest,
    required this.notes,
  });
  final AppVersion version;
  final Uri url;
  final int bytes;
  final String digest, notes;

  static AvailableUpdate? fromRelease(
    Map<String, dynamic> json,
    String current,
    List<String> abis,
  ) {
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final version = AppVersion.parse(json['tag_name'] as String);
    if (version.compareTo(AppVersion.parse(current)) <= 0) return null;
    final assets = json['assets'];
    if (assets is! List) throw const FormatException('ملفات التحديث غير متاحة');
    for (final abi in abis.where(
      (a) => ['arm64-v8a', 'armeabi-v7a', 'x86_64'].contains(a),
    )) {
      final name = 'haseela-$version-$abi.apk';
      for (final asset in assets.whereType<Map>()) {
        if (asset['name'] != name) continue;
        final url = Uri.tryParse(
          asset['browser_download_url'] as String? ?? '',
        );
        final expectedPath =
            '/$updateRepository/releases/download/v$version/$name';
        final size = asset['size'];
        final digest = asset['digest'];
        if (url == null ||
            url.scheme != 'https' ||
            url.host != 'github.com' ||
            url.path != expectedPath ||
            url.hasQuery ||
            url.hasFragment ||
            url.userInfo.isNotEmpty ||
            url.port != 443 ||
            size is! int ||
            size <= 0 ||
            size > maxUpdateBytes ||
            digest is! String ||
            !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
          throw const FormatException('بيانات ملف التحديث غير صالحة');
        }
        return AvailableUpdate(
          version: version,
          url: url,
          bytes: size,
          digest: digest.substring(7).toLowerCase(),
          notes: json['body'] is String
              ? (json['body'] as String).substring(
                  0,
                  (json['body'] as String).length.clamp(0, 4000),
                )
              : 'تحسينات جديدة لحصيلة.',
        );
      }
    }
    throw const FormatException('لا يتوفر ملف تحديث مناسب لهذا الجهاز بعد');
  }
}

class UpdateController extends ChangeNotifier {
  UpdateController({
    Uri? endpoint,
    HttpClient Function()? clientFactory,
    MethodChannel? channel,
  }) : endpoint =
           endpoint ??
           Uri.https(
             'api.github.com',
             '/repos/$updateRepository/releases/latest',
           ),
       clientFactory = clientFactory ?? HttpClient.new,
       channel = channel ?? updateChannel;
  final Uri endpoint;
  final HttpClient Function() clientFactory;
  final MethodChannel channel;
  String current = '', directory = '', message = '';
  List<String> abis = [];
  AvailableUpdate? available;
  bool checking = false,
      downloading = false,
      installing = false,
      supported = false,
      disposed = false;
  double progress = 0;
  File? downloaded;
  HttpClient? downloadClient;
  Future<void>? initialization;
  DateTime? lastCheck;
  Timer? timer;
  bool get busy => checking || downloading || installing;
  void changed() {
    if (!disposed) notifyListeners();
  }

  Future<void> initialize() => initialization ??= _initialize();
  Future<void> _initialize() async {
    try {
      final info = await channel.invokeMapMethod<String, dynamic>('info');
      if (disposed || info == null) return;
      current = info['version'] as String;
      AppVersion.parse(current);
      directory = info['directory'] as String;
      abis = List<String>.from(info['abis'] as List);
      supported = true;
      changed();
      timer = Timer.periodic(const Duration(minutes: 15), (_) => check());
      await check();
    } catch (_) {
      message = 'التحديث داخل التطبيق متاح على Android.';
      changed();
    }
  }

  Future<void> check({bool manual = false}) async {
    if (busy || disposed || !supported) return;
    if (!manual &&
        lastCheck != null &&
        DateTime.now().difference(lastCheck!) < const Duration(minutes: 15)) {
      return;
    }
    lastCheck = DateTime.now();
    checking = true;
    if (manual) message = '';
    changed();
    final client = clientFactory()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client
          .getUrl(endpoint)
          .timeout(const Duration(seconds: 15));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'Haseela/$current');
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode == 404) {
        if (manual) message = 'لا توجد إصدارات جديدة منشورة بعد.';
        return;
      }
      if (response.statusCode != 200) {
        throw const HttpException('Release unavailable');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) {
          throw const FormatException('بيانات التحديث أكبر من المتوقع');
        }
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic>) {
        throw const FormatException('بيانات التحديث غير صالحة');
      }
      final next = AvailableUpdate.fromRelease(data, current, abis);
      if (disposed) return;
      if (next?.version.toString() != available?.version.toString()) {
        downloaded = null;
      }
      available = next;
      message = next == null
          ? 'أنتِ تستخدمين أحدث إصدار ✨'
          : 'إصدار ${next.version} متاح الآن';
    } catch (e) {
      if (manual) {
        message = e is FormatException
            ? e.message
            : 'تعذّر فحص التحديثات. تحققي من اتصال الإنترنت وأعيدي المحاولة.';
      }
    } finally {
      client.close(force: true);
      checking = false;
      changed();
    }
  }

  Future<void> download() async {
    final update = available;
    if (update == null || busy || disposed) return;
    downloading = true;
    progress = 0;
    message = 'جارٍ تنزيل التحديث…';
    changed();
    final client = clientFactory()
      ..connectionTimeout = const Duration(seconds: 15);
    downloadClient = client;
    final temporary = File('$directory/update.part');
    IOSink? sink;
    try {
      await Directory(directory).create(recursive: true);
      final request = await client
          .getUrl(update.url)
          .timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.userAgentHeader, 'Haseela/$current');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw const HttpException('Download failed');
      }
      if (response.contentLength > maxUpdateBytes ||
          response.contentLength >= 0 &&
              response.contentLength != update.bytes) {
        throw const FormatException('حجم ملف التحديث غير صحيح');
      }
      sink = temporary.openWrite();
      var received = 0;
      var lastProgress = 0.0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (disposed || downloadClient != client) {
          throw const HttpException('Cancelled');
        }
        received += chunk.length;
        if (received > update.bytes) {
          throw const FormatException('ملف التحديث أكبر من المتوقع');
        }
        sink.add(chunk);
        await sink.flush();
        progress = received / update.bytes;
        if (progress - lastProgress >= .01) {
          lastProgress = progress;
          changed();
        }
      }
      await sink.close();
      sink = null;
      if (received != update.bytes) {
        throw const FormatException('لم يكتمل تنزيل التحديث. أعيدي المحاولة.');
      }
      final digest = await sha256.bind(temporary.openRead()).first;
      if (disposed || downloadClient != client) {
        throw const HttpException('Cancelled');
      }
      if (digest.toString() != update.digest) {
        throw const FormatException(
          'تعذّر التحقق من سلامة التحديث. أعيدي تنزيله.',
        );
      }
      final target = File('$directory/update.apk');
      if (await target.exists()) await target.delete();
      downloaded = await temporary.rename(target.path);
      progress = 1;
      message = 'التحديث جاهز للتثبيت؛ بياناتك ستبقى محفوظة.';
    } catch (e) {
      message = downloadClient != client
          ? 'تم إيقاف التنزيل. يمكنك المحاولة مجددًا.'
          : e is FormatException
          ? e.message
          : 'تعذّر تنزيل التحديث. تحققي من الإنترنت ومساحة الجهاز.';
      await sink?.close();
      sink = null;
      if (await temporary.exists()) await temporary.delete();
    } finally {
      await sink?.close();
      client.close(force: true);
      if (downloadClient == client) downloadClient = null;
      downloading = false;
      changed();
    }
  }

  void cancelDownload() {
    final client = downloadClient;
    downloadClient = null;
    client?.close(force: true);
  }

  Future<void> install() async {
    final file = downloaded;
    if (file == null || busy || disposed) return;
    installing = true;
    changed();
    try {
      final result = await channel.invokeMethod<String>('install', {
        'path': file.path,
      });
      message = result == 'permission'
          ? 'اسمحي لحصيلة بتثبيت التطبيقات، ثم ارجعي لإكمال التحديث.'
          : 'أكملي التثبيت في نافذة Android. إن أغلقتِها، يمكنك إعادة المحاولة.';
    } on PlatformException catch (e) {
      message = e.message ?? 'تعذّر فتح مثبّت التحديث.';
    } catch (_) {
      message = 'تعذّر فتح مثبّت التحديث. حاولي مرة أخرى.';
    } finally {
      installing = false;
      changed();
    }
  }

  @override
  void dispose() {
    disposed = true;
    timer?.cancel();
    cancelDownload();
    super.dispose();
  }
}

Future<void> updateSheet(
  BuildContext context,
  UpdateController controller,
) async {
  unawaited(
    controller.initialize().then((_) => controller.check(manual: true)),
  );
  await openSheet(context, UpdateSheet(controller: controller));
}

class UpdateSheet extends StatelessWidget {
  const UpdateSheet({super.key, required this.controller});
  final UpdateController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final update = controller.available;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            4,
            24,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: FlowerMark(size: 52)),
              const SizedBox(height: 18),
              Text(
                'حصيلة، تتحسّن معك',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'الإصدار المثبّت ${controller.current.isEmpty ? '…' : controller.current}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      update == null
                          ? Icons.system_update_outlined
                          : Icons.auto_awesome_rounded,
                      color: Theme.of(context).colorScheme.primary,
                      size: 30,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      controller.checking
                          ? 'جارٍ البحث عن تحديث…'
                          : controller.message.isEmpty
                          ? 'افحصي التحديثات للحصول على آخر التحسينات.'
                          : controller.message,
                      textAlign: TextAlign.center,
                    ),
                    if (update != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        'حجم التنزيل ${(update.bytes / 1024 / 1024).toStringAsFixed(1)} MB',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      Text(update.notes),
                    ],
                    if (controller.downloading) ...[
                      const SizedBox(height: 18),
                      LinearProgressIndicator(
                        value: controller.progress,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(controller.progress * 100).round()}٪',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: controller.cancelDownload,
                        child: const Text('إيقاف التنزيل'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (update != null)
                FilledButton.icon(
                  key: const ValueKey('download_update'),
                  onPressed: controller.busy
                      ? null
                      : () async {
                          if (controller.downloaded == null) {
                            await controller.download();
                          }
                          if (controller.downloaded != null &&
                              !controller.disposed) {
                            await controller.install();
                          }
                        },
                  icon: Icon(
                    controller.downloaded == null
                        ? Icons.download_rounded
                        : Icons.system_update_rounded,
                  ),
                  label: Text(
                    controller.downloaded == null
                        ? 'تنزيل وتثبيت التحديث'
                        : 'تثبيت التحديث',
                  ),
                ),
              TextButton.icon(
                key: const ValueKey('check_updates'),
                onPressed: controller.busy || !controller.supported
                    ? null
                    : () => controller.check(manual: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('فحص التحديثات'),
              ),
              const SizedBox(height: 8),
              Text(
                'الإنترنت للتحديث فقط؛ حساباتك وطلباتك تبقى على جهازك.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    },
  );
}
