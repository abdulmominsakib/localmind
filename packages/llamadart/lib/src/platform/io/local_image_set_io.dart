import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/exceptions.dart';
import '../../core/models/download/model_download_manager.dart';
import '../../core/models/model_file_store.dart';
import '../../core/models/model_load_options.dart';
import '../../core/models/model_resolver.dart';
import '../../core/models/model_source.dart';
import '../../core/image/local_image_set_model.dart';

const _indexName = 'model.safetensors.index.json';
const _maxHeaderBytes = 1024 * 1024;
const _maxIndexBytes = 4 * 1024 * 1024;

/// Resolves a content-verified owned snapshot. Model-family admission is the
/// engine's separate responsibility; a cached content set is not qualification.
Future<({String indexPath, int totalBytes, String layoutSha256})>
resolveLocalImageSet(
  LocalImageSetModel model, {
  required ModelFileStore store,
  required ModelLoadOptions options,
  ModelDownloadProgressCallback? onProgress,
}) async {
  void cancelled() {
    if (options.cancelToken?.isCancelled ?? false) {
      throw LlamaStateException('Local image-set loading was cancelled.');
    }
  }

  cancelled();
  if (options.sha256 != null ||
      options.cacheDirectory != null ||
      options.cachePolicy != ModelCachePolicy.preferCached ||
      options.bearerToken != null ||
      options.headers.isNotEmpty ||
      !options.resume ||
      options.maxRetries != 3) {
    throw LlamaUnsupportedException(
      'Local image sets accept only cancellation in ModelLoadOptions; use their per-file identities and dedicated cache directory.',
    );
  }
  Directory? staging;
  try {
    final names = model.sha256.keys.toList()..sort();
    final identity = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              for (final name in names) [name, model.sha256[name]],
            ]),
          ),
        )
        .toString();
    final cache = Directory(
      p.join(model.cacheDirectory, 'llamadart_image_sets_v1'),
    );
    if (await FileSystemEntity.type(cache.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw LlamaModelException(
        'The owned image-set cache namespace must not be a symbolic link.',
      );
    }
    await cache.create(recursive: true);
    final cacheRoot = await cache.resolveSymbolicLinks();
    final published = Directory(p.join(cacheRoot, identity));
    final cachedType = await FileSystemEntity.type(
      published.path,
      followLinks: false,
    );
    if (cachedType == FileSystemEntityType.link) {
      throw LlamaModelException(
        'Local image-set cache must not contain symbolic links.',
      );
    }
    if (cachedType == FileSystemEntityType.directory) {
      return await _verifySet(
        published.path,
        model.sha256,
        cancelled,
        onProgress,
      );
    }
    if (cachedType != FileSystemEntityType.notFound) {
      throw LlamaModelException(
        'Local image-set cache identity is not a directory.',
      );
    }
    final input = model.source.path!;
    final type = await FileSystemEntity.type(input, followLinks: false);
    final String root;
    if (type == FileSystemEntityType.directory) {
      root = await Directory(input).resolveSymbolicLinks();
    } else if (type == FileSystemEntityType.file &&
        p.basename(input) == _indexName) {
      root = await Directory(p.dirname(input)).resolveSymbolicLinks();
    } else {
      throw LlamaModelException(
        'Local image sets require a directory or model.safetensors.index.json regular file.',
      );
    }
    await _layoutEntries(root, names.toSet());
    final indexBytes = await _readBounded(
      File(await _confinedFile(root, p.join(root, _indexName), _indexName)),
      _maxIndexBytes,
    );
    final shards = _indexShards(indexBytes);
    if ({_indexName, ...shards}.length != names.length ||
        !names.toSet().containsAll({_indexName, ...shards})) {
      throw LlamaModelException(
        'Local image-set identities must name exactly the index and every declared shard.',
      );
    }
    // Resolve every target before any manager can act; remote redirects are
    // refused instead of invoking a downloader on an index-controlled path.
    final targets = <String, String>{};
    for (final name in names) {
      cancelled();
      final source = ModelSource.path(p.join(root, name));
      final ModelLoadTarget target;
      try {
        target = await store.resolver.resolve(
          source,
          ModelResolveRequest(
            options: ModelLoadOptions(
              sha256: model.sha256[name],
              cancelToken: options.cancelToken,
            ),
          ),
        );
      } catch (_) {
        cancelled();
        throw LlamaModelException(
          'A local image-set source resolver failed; check local target availability.',
        );
      }
      if (target is! LocalModelFile) {
        throw LlamaUnsupportedException(
          'Local image-set resolution cannot redirect to a remote target.',
        );
      }
      targets[name] = await _confinedFile(root, target.path, name);
    }
    staging = await Directory(cacheRoot).createTemp('.partial-');
    var received = 0;
    final sizes = <String, int>{};
    for (final name in names) {
      sizes[name] = await File(targets[name]!).length();
    }
    final total = sizes.values.fold<int>(0, (a, b) => a + b);
    if (total > 3 * 1024 * 1024 * 1024) {
      throw LlamaModelException(
        'The bounded local checkpoint recipe accepts at most 3 GiB including headers and index.',
      );
    }
    for (final name in names) {
      cancelled();
      final ModelCacheEntry entry;
      try {
        entry = await store.downloadManager.ensureModel(
          ModelSource.path(targets[name]!),
          options: ModelLoadOptions(
            sha256: model.sha256[name],
            cancelToken: options.cancelToken,
          ),
        );
      } catch (_) {
        cancelled();
        throw LlamaModelException(
          'Local image-set source verification failed; check per-file identities and availability.',
        );
      }
      final original = await _confinedFile(root, entry.filePath, name);
      final output = await File(
        p.join(staging.path, name),
      ).open(mode: FileMode.write);
      final hashes = <Digest>[];
      final sink = sha256.startChunkedConversion(_DigestSink(hashes));
      try {
        await for (final chunk in File(original).openRead()) {
          cancelled();
          sink.add(chunk);
          await output.writeFrom(chunk);
          received += chunk.length;
          if (received > total) {
            throw LlamaModelException(
              'Local image-set files changed size while copying.',
            );
          }
          onProgress?.call(
            ModelDownloadProgress(receivedBytes: received, totalBytes: total),
          );
        }
        sink.close();
        await output.flush();
      } finally {
        await output.close();
      }
      if (hashes.single.toString() != model.sha256[name]) {
        throw LlamaModelException(
          'Local image-set copy does not match its expected SHA-256 identity.',
        );
      }
    }
    cancelled();
    final verified = await _verifySet(
      staging.path,
      model.sha256,
      cancelled,
      null,
    );
    cancelled();
    try {
      await staging.rename(published.path);
      staging = null;
    } on FileSystemException {
      if (!await published.exists()) rethrow;
      // Another load may have published the same immutable identity.
      await _verifySet(published.path, model.sha256, cancelled, null);
    }
    onProgress?.call(
      ModelDownloadProgress(
        receivedBytes: verified.totalBytes,
        totalBytes: verified.totalBytes,
      ),
    );
    return (
      indexPath: p.join(published.path, _indexName),
      totalBytes: verified.totalBytes,
      layoutSha256: verified.layoutSha256,
    );
  } on FormatException {
    throw LlamaModelException(
      'Local image-set metadata requires valid bounded JSON with unique object keys and supported tensor shapes.',
    );
  } on LlamaException {
    rethrow;
  } catch (_) {
    throw LlamaModelException(
      'Cannot resolve the local image set; check its files, identities and private cache permissions.',
    );
  } finally {
    if (staging != null && await staging.exists()) {
      try {
        await staging.delete(recursive: true);
      } catch (_) {
        throw LlamaModelException(
          'Cannot clean this load’s partial image-set snapshot; check private cache permissions.',
        );
      }
    }
  }
}

Future<String> _confinedFile(String root, String file, String name) async {
  if (await FileSystemEntity.type(file, followLinks: false) !=
      FileSystemEntityType.file) {
    throw LlamaModelException(
      'A required local image-set file is missing or is not a regular file.',
    );
  }
  final canonical = await File(file).resolveSymbolicLinks();
  if (p.dirname(canonical) != root || p.basename(canonical) != name) {
    throw LlamaModelException(
      'Local image-set files must remain adjacent and inside the approved root.',
    );
  }
  return canonical;
}

Future<void> _layoutEntries(String root, Set<String> allowed) async {
  var count = 0;
  await for (final entity in Directory(root).list(followLinks: false)) {
    if (++count > 256) {
      throw LlamaModelException(
        'Local image-set directory has too many entries.',
      );
    }
    final name = p.basename(entity.path);
    if (name == 'model_index.json' ||
        name == 'unet' ||
        (name.endsWith('.safetensors') || name.endsWith('.index.json')) &&
            !allowed.contains(name)) {
      throw LlamaUnsupportedException(
        'Only a complete-checkpoint index and its declared shards are supported; Diffusers layouts and extra model files are ambiguous.',
      );
    }
  }
}

Future<Uint8List> _readBounded(File file, int limit) async {
  if (await file.length() > limit) {
    throw LlamaModelException(
      'Local image-set metadata exceeds its supported bound.',
    );
  }
  return file.readAsBytes();
}

Set<String> _indexShards(List<int> bytes) {
  final index = _strictJson(utf8.decode(bytes));
  if (index is! Map ||
      index.keys.any((k) => k != 'metadata' && k != 'weight_map') ||
      index['weight_map'] is! Map ||
      (index['weight_map'] as Map).isEmpty) {
    throw LlamaModelException(
      'Local image-set index requires an unambiguous weight_map.',
    );
  }
  final shards = <String>{};
  for (final entry in (index['weight_map'] as Map).entries) {
    final value = entry.value;
    if (entry.key is! String ||
        (entry.key as String).isEmpty ||
        value is! String ||
        !RegExp(r'^model-[0-9]{5}-of-[0-9]{5}\.safetensors$').hasMatch(value) ||
        value.contains('..')) {
      throw LlamaModelException(
        'Local image-set shard mappings require canonical numbered adjacent Safetensors basenames.',
      );
    }
    shards.add(value);
  }
  if (shards.length > 16) {
    throw LlamaModelException('Local image sets support at most 16 shards.');
  }
  final expected = <String>{
    for (var i = 1; i <= shards.length; i++)
      'model-${i.toString().padLeft(5, '0')}-of-${shards.length.toString().padLeft(5, '0')}.safetensors',
  };
  if (!shards.containsAll(expected)) {
    throw LlamaModelException(
      'Local image-set shard numbering must be the complete contiguous 1..N set, with N from 1 through 16.',
    );
  }
  return shards;
}

Future<({String indexPath, int totalBytes, String layoutSha256})> _verifySet(
  String root,
  Map<String, String> identities,
  void Function() cancelled,
  ModelDownloadProgressCallback? progress,
) async {
  await _layoutEntries(root, identities.keys.toSet());
  final indexBytes = await _readBounded(
    File(await _confinedFile(root, p.join(root, _indexName), _indexName)),
    _maxIndexBytes,
  );
  final shards = _indexShards(indexBytes);
  if (identities.length != shards.length + 1 ||
      !identities.keys.toSet().containsAll(shards)) {
    throw LlamaModelException(
      'Local image-set identities and declared shards disagree.',
    );
  }
  final index = _strictJson(utf8.decode(indexBytes)) as Map;
  final mapping = index['weight_map'] as Map;
  final tensors = <String, List<Object>>{};
  var total = 0;
  var payloadBytes = 0;
  var received = 0;
  final names = identities.keys.toList()..sort();
  for (final name in names) {
    total += await File(
      await _confinedFile(root, p.join(root, name), name),
    ).length();
  }
  if (total > 3 * 1024 * 1024 * 1024) {
    throw LlamaModelException(
      'The bounded local checkpoint recipe accepts at most 3 GiB including headers and index.',
    );
  }
  for (final name in names) {
    cancelled();
    final file = File(await _confinedFile(root, p.join(root, name), name));
    final hashes = <Digest>[];
    final sink = sha256.startChunkedConversion(_DigestSink(hashes));
    await for (final chunk in file.openRead()) {
      cancelled();
      sink.add(chunk);
      received += chunk.length;
      if (received > total) {
        throw LlamaModelException(
          'Local image-set files changed size while verifying.',
        );
      }
      progress?.call(
        ModelDownloadProgress(receivedBytes: received, totalBytes: total),
      );
    }
    sink.close();
    if (hashes.single.toString() != identities[name]) {
      throw LlamaModelException(
        'Local image-set cache/file identity mismatch; do not mutate published cache files.',
      );
    }
    if (name == _indexName) continue;
    final handle = await file.open();
    try {
      final prefix = await handle.read(8);
      if (prefix.length != 8) {
        throw LlamaModelException('Truncated local Safetensors header.');
      }
      final length = ByteData.sublistView(prefix).getUint64(0, Endian.little);
      if (length < 2 || length > _maxHeaderBytes) {
        throw LlamaModelException('Invalid local Safetensors header length.');
      }
      final raw = await handle.read(length);
      if (raw.length != length) {
        throw LlamaModelException('Truncated local Safetensors header.');
      }
      final header = _strictJson(utf8.decode(raw));
      if (header is! Map) {
        throw LlamaModelException('Invalid local Safetensors header.');
      }
      final spans = <(int, int)>[];
      for (final entry in header.entries) {
        if (entry.key == '__metadata__') {
          if (entry.value is! Map ||
              (entry.value as Map).entries.any(
                (e) => e.key != 'format' || e.value != 'pt',
              )) {
            throw LlamaModelException(
              'Local Safetensors metadata supports only the optional format: pt marker.',
            );
          }
          continue;
        }
        final spec = entry.value;
        if (spec is! Map ||
            spec.keys.any(
              (k) => !['dtype', 'shape', 'data_offsets'].contains(k),
            ) ||
            spec['shape'] is! List ||
            spec['data_offsets'] is! List) {
          throw LlamaModelException(
            'Invalid local Safetensors tensor metadata.',
          );
        }
        final dtype = spec['dtype'];
        final shape = spec['shape'] as List;
        final offsets = spec['data_offsets'] as List;
        if (dtype != 'F16' && dtype != 'F32') {
          throw LlamaUnsupportedException(
            'Local checkpoint sets require the qualified F16/F32 dtype recipe.',
          );
        }
        if (shape.length > 8 ||
            shape.any((v) => v is! int || v < 1) ||
            offsets.length != 2 ||
            offsets.any((v) => v is! int || v < 0)) {
          throw LlamaModelException('Invalid local Safetensors shape/offsets.');
        }
        var elements = 1;
        for (final dim in shape.cast<int>()) {
          if (elements > total ~/ dim) {
            throw LlamaModelException(
              'Local tensor dimensions exceed file bounds.',
            );
          }
          elements *= dim;
        }
        final a = offsets[0] as int;
        final b = offsets[1] as int;
        if (b < a ||
            b - a != elements * (dtype == 'F16' ? 2 : 4) ||
            b > await file.length() - 8 - length) {
          throw LlamaModelException(
            'Local Safetensors tensor data exceeds file bounds.',
          );
        }
        if (tensors.containsKey(entry.key) || mapping[entry.key] != name) {
          throw LlamaModelException(
            'Local image-set tensor mapping is duplicate, missing or assigned to another shard.',
          );
        }
        tensors[entry.key as String] = [dtype, shape];
        spans.add((a, b));
      }
      spans.sort((a, b) => a.$1.compareTo(b.$1));
      var end = 0;
      for (final span in spans) {
        if (span.$1 != end) {
          throw LlamaModelException(
            'Local Safetensors tensor ranges overlap or contain holes.',
          );
        }
        end = span.$2;
      }
      if (end != await file.length() - 8 - length) {
        throw LlamaModelException(
          'Local Safetensors payload has unclaimed bytes.',
        );
      }
      payloadBytes += end;
    } finally {
      await handle.close();
    }
  }
  if (mapping.length != tensors.length ||
      !mapping.keys.every(tensors.containsKey)) {
    throw LlamaModelException(
      'Local image-set index declares missing tensors.',
    );
  }
  final metadata = index['metadata'];
  if (metadata != null &&
      (metadata is! Map ||
          metadata.keys.any((k) => k != 'total_size') ||
          metadata['total_size'] is! int ||
          metadata['total_size'] != payloadBytes)) {
    throw LlamaModelException(
      'Local image-set total_size does not match tensor payload bytes.',
    );
  }
  final ordered = tensors.keys.toList()..sort();
  final layout = sha256
      .convert(
        utf8.encode(
          jsonEncode([
            for (final name in ordered) [name, ...tensors[name]!],
          ]),
        ),
      )
      .toString();
  cancelled();
  return (
    indexPath: p.join(root, _indexName),
    totalBytes: total,
    layoutSha256: layout,
  );
}

final class _DigestSink implements Sink<Digest> {
  final List<Digest> values;
  _DigestSink(this.values);
  @override
  void add(Digest value) => values.add(value);
  @override
  void close() {}
}

Object? _strictJson(String text) {
  final value = jsonDecode(text);
  var i = 0;
  void space() {
    while (i < text.length && ' \t\r\n'.contains(text[i])) {
      i++;
    }
  }

  String string() {
    final start = i++;
    while (i < text.length) {
      if (text[i] == '\\') {
        i += 2;
      } else if (text[i++] == '"') {
        return jsonDecode(text.substring(start, i)) as String;
      }
    }
    throw const FormatException('Unterminated JSON string.');
  }

  void scan(int depth) {
    if (depth > 32) {
      throw const FormatException('JSON nesting exceeds supported depth.');
    }
    space();
    final c = text[i];
    if (c == '{') {
      i++;
      space();
      final keys = <String>{};
      if (text[i] == '}') {
        i++;
        return;
      }
      while (true) {
        space();
        final key = string();
        if (!keys.add(key)) {
          throw const FormatException('Duplicate JSON object key.');
        }
        space();
        i++;
        scan(depth + 1);
        space();
        if (text[i++] == '}') return;
      }
    } else if (c == '[') {
      i++;
      space();
      if (text[i] == ']') {
        i++;
        return;
      }
      while (true) {
        scan(depth + 1);
        space();
        if (text[i++] == ']') return;
      }
    } else if (c == '"') {
      string();
    } else {
      while (i < text.length && !',]} \t\r\n'.contains(text[i])) {
        i++;
      }
    }
  }

  scan(0);
  return value;
}
