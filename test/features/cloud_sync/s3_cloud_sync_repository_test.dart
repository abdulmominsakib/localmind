import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/cloud_sync/data/models/cloud_sync_models.dart';
import 'package:localmind/features/cloud_sync/data/repositories/s3_cloud_sync_repository.dart';
import 'package:localmind/features/cloud_sync/services/cloud_sync_crypto_service.dart';

void main() {
  test('connection test uses signed path-style conditional requests', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final authorizations = <String?>[];
    final sessionTokens = <String?>[];
    final objects = <String, List<int>>{};
    final etags = <String, String>{};
    var revision = 0;
    final subscription = server.listen((request) async {
      paths.add(request.uri.path);
      authorizations.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      sessionTokens.add(request.headers.value('x-amz-security-token'));
      final key = request.uri.path;
      if (request.method == 'PUT') {
        final ifNoneMatch = request.headers.value(
          HttpHeaders.ifNoneMatchHeader,
        );
        final ifMatch = request.headers.value(HttpHeaders.ifMatchHeader);
        if ((ifNoneMatch == '*' && objects.containsKey(key)) ||
            (ifMatch != null && etags[key] != ifMatch)) {
          request.response.statusCode = HttpStatus.preconditionFailed;
        } else {
          objects[key] = await request.fold<List<int>>(
            <int>[],
            (all, chunk) => all..addAll(chunk),
          );
          etags[key] = '"etag-${revision++}"';
          request.response.headers.set(HttpHeaders.etagHeader, etags[key]!);
        }
      } else if (request.method == 'GET') {
        final bytes = objects[key];
        if (bytes == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.headers.set(HttpHeaders.etagHeader, etags[key]!);
          request.response.add(bytes);
        }
      } else if (request.method == 'HEAD') {
        if (!objects.containsKey(key)) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.headers.set(HttpHeaders.etagHeader, etags[key]!);
        }
      } else if (request.method == 'DELETE') {
        objects.remove(key);
        etags.remove(key);
        request.response.statusCode = HttpStatus.noContent;
      }
      await request.response.close();
    });

    final repository = S3CloudSyncRepository(
      config: S3SyncConfig(
        endpoint: 'http://${server.address.address}:${server.port}',
        bucket: 'private-bucket',
        prefix: 'my sync',
        allowInsecureHttp: true,
      ),
      credentials: const CloudSyncCredentials(
        accessKeyId: 'access',
        secretAccessKey: 'secret',
        sessionToken: 'session',
      ),
    );

    await repository.testConnection();
    final crypto = CloudSyncCryptoService();
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
    );
    final salt = crypto.newSalt();
    final key = List<int>.filled(32, 7);
    final attachmentKey = repository.attachmentKey(
      await crypto.attachmentIdentifier(png, key),
    );
    final encrypted = await crypto.encryptAttachment(
      png,
      masterKey: key,
      salt: salt,
    );
    expect(await repository.objectExists(attachmentKey), isFalse);
    await repository.writeObject(attachmentKey, encrypted);
    expect(await repository.objectExists(attachmentKey), isTrue);
    final downloaded = await repository.readObject(attachmentKey);
    expect(downloaded!.bytes, isNot(png));
    expect(await crypto.decryptAttachment(downloaded.bytes, key), png);
    await repository.deleteObject(attachmentKey);

    expect(paths, isNotEmpty);
    expect(
      paths.every((path) => path.startsWith('/private-bucket/my%20sync/')),
      isTrue,
    );
    expect(
      authorizations.whereType<String>().every(
        (value) => value.startsWith('AWS4-HMAC-SHA256'),
      ),
      isTrue,
    );
    expect(sessionTokens.whereType<String>(), isNotEmpty);
    expect(
      objects,
      isEmpty,
      reason: 'connection test object must be cleaned up',
    );

    await subscription.cancel();
    await server.close(force: true);
  });

  test('connection test rejects servers that ignore stale ETags', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    List<int>? object;
    var revision = 0;
    final subscription = server.listen((request) async {
      if (request.method == 'PUT') {
        object = await request.fold<List<int>>(
          <int>[],
          (all, chunk) => all..addAll(chunk),
        );
        request.response.headers.set(
          HttpHeaders.etagHeader,
          '"etag-${revision++}"',
        );
      } else if (request.method == 'GET') {
        if (object == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.headers.set(HttpHeaders.etagHeader, '"etag-0"');
          request.response.add(object!);
        }
      } else if (request.method == 'DELETE') {
        object = null;
        request.response.statusCode = HttpStatus.noContent;
      }
      await request.response.close();
    });
    final repository = S3CloudSyncRepository(
      config: S3SyncConfig(
        endpoint: 'http://${server.address.address}:${server.port}',
        bucket: 'bucket',
        allowInsecureHttp: true,
      ),
      credentials: const CloudSyncCredentials(
        accessKeyId: 'access',
        secretAccessKey: 'secret',
      ),
    );

    await expectLater(
      repository.testConnection(),
      throwsA(
        isA<CloudSyncFailure>().having(
          (error) => error.kind,
          'kind',
          CloudSyncFailureKind.incompatibleServer,
        ),
      ),
    );

    await subscription.cancel();
    await server.close(force: true);
  });
}
