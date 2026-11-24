import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/features/chat/data/image_reader.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/providers/image_reading_providers.dart';
import 'package:localmind/features/chat/utils/image_readout_messages.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';

class _FakeReader implements ImageReader {
  _FakeReader(this.results);
  final Map<String, ImageReadout?> results;
  final reads = <String>[];

  @override
  Future<ImageReadout?> read(String path) async {
    reads.add(path);
    return results[path];
  }

  @override
  Future<void> close() async {}
}

Message _msg(MessageRole role, String content, {List<String>? attachments}) =>
    Message(
      id: '$role-$content',
      conversationId: 'c',
      role: role,
      content: content,
      createdAt: DateTime.utc(2026, 11, 24),
      attachmentPaths: attachments,
    );

Server _server(ServerType type) => Server(
  id: type.name,
  name: type.name,
  type: type,
  host: 'localhost',
  port: 0,
  createdAt: DateTime.utc(2026),
  lastConnectedAt: DateTime.utc(2026),
);

class _Settings extends SettingsNotifier {
  _Settings(this.readImages);
  final bool readImages;

  @override
  AppSettings build() => AppSettings(readImagesOnDevice: readImages);
}

class _MlxEngine extends OnDeviceEngineNotifier {
  @override
  OnDeviceEngineState build() => const OnDeviceEngineState(
    status: OnDeviceEngineStatus.loaded,
    loadedModelId: 'mlx-model',
    loadedRuntime: OnDeviceModelRuntime.mlx,
  );
}

void main() {
  group('ImageReadout.toPromptText', () {
    test('lists labels and text', () {
      const readout = ImageReadout(
        text: 'OPEN 9-5',
        labels: ['sign', 'building'],
      );
      final prompt = readout.toPromptText();
      expect(prompt, contains('cannot see images'));
      expect(prompt, contains('Likely shows: sign, building'));
      expect(prompt, contains('Text in the image:\nOPEN 9-5'));
    });

    test('says when nothing was found', () {
      expect(
        const ImageReadout().toPromptText(),
        contains('No text or recognizable objects'),
      );
    });
  });

  group('replaceImagesWithReadouts', () {
    test('swaps images for readouts and keeps other attachments', () async {
      final reader = _FakeReader({
        '/a/receipt.jpg': const ImageReadout(text: 'Total 12.50'),
      });
      final result = await replaceImagesWithReadouts([
        _msg(
          MessageRole.user,
          'How much?',
          attachments: ['/a/receipt.jpg', '/a/notes.txt'],
        ),
      ], reader);

      final message = result.single;
      expect(message.attachmentPaths, ['/a/notes.txt']);
      expect(message.content, startsWith('How much?'));
      expect(message.content, contains('--- receipt.jpg ---'));
      expect(message.content, contains('Total 12.50'));
    });

    test('an unreadable image still lets the request through', () async {
      final result = await replaceImagesWithReadouts([
        _msg(MessageRole.user, '', attachments: ['/a/x.png']),
      ], _FakeReader({}));
      expect(result.single.attachmentPaths, isEmpty);
      expect(
        result.single.content,
        contains(ImageReadout.unreadablePromptText),
      );
    });

    test('leaves messages without images and non-user messages', () async {
      final reader = _FakeReader({});
      final assistant = _msg(
        MessageRole.assistant,
        'Here',
        attachments: ['/a/gen.png'],
      );
      final plain = _msg(MessageRole.user, 'Hi');
      final result = await replaceImagesWithReadouts([
        plain,
        assistant,
      ], reader);
      expect(result, [same(plain), same(assistant)]);
      expect(reader.reads, isEmpty);
    });
  });

  group('needsOnDeviceImageReading', () {
    Future<bool> decide({
      required ServerType type,
      bool readImages = true,
    }) async {
      final server = _server(type);
      final decision = FutureProvider<bool>(
        (ref) => needsOnDeviceImageReading(ref, server),
      );
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => _Settings(readImages)),
          onDeviceEngineProvider.overrideWith(_MlxEngine.new),
          imageReaderProvider.overrideWithValue(_FakeReader({})),
        ],
      );
      addTearDown(container.dispose);
      return container.read(decision.future);
    }

    test('a text-only on-device model needs it', () async {
      expect(await decide(type: ServerType.onDevice), isTrue);
    });

    test('remote servers never do', () async {
      expect(await decide(type: ServerType.lmStudio), isFalse);
    });

    test('the setting turns it off', () async {
      expect(
        await decide(type: ServerType.onDevice, readImages: false),
        isFalse,
      );
    });
  });

  test('the setting defaults on and survives a round trip', () {
    expect(AppSettings().readImagesOnDevice, isTrue);
    expect(AppSettings.fromMap(const {}).readImagesOnDevice, isTrue);
    final off = AppSettings(readImagesOnDevice: false);
    expect(AppSettings.fromMap(off.toMap()).readImagesOnDevice, isFalse);
  });
}
