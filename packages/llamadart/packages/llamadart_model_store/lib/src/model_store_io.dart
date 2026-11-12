import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;

import 'entry_id.dart';
import 'model_store_entry.dart';
import 'store_lock.dart';

const int _schemaVersion = 1;
const String _entryFileName = 'entry.json';
const String _referencesDirectoryName = 'refs';
final RegExp _entryIdPattern = RegExp(r'^[0-9a-f]{64}$');

/// A model library that every app able to open the same directory shares.
///
/// Files are downloaded, resumed, verified and locked per file by a
/// [DefaultModelDownloadManager] rooted at `<directory>/files`. On top of
/// that, the store keeps each [LlamaModel], model and projector together, as
/// one [ModelStoreEntry], and records which apps reference it under
/// `<directory>/entries`. An entry's files are deleted only when no app
/// references them, so one app cannot delete a model another app still uses.
///
/// Store metadata holds cache keys, app ids and timestamps only. Source
/// URLs, tokens and headers are never written to it; the file metadata
/// [DefaultModelDownloadManager] writes redacts URL secrets.
///
/// Use a store from one isolate per process. Its lock excludes other
/// processes but, on Linux, macOS, Android and iOS, not another isolate of the
/// same process, and the store does not detect one: calls from two isolates
/// are not serialized, so a release in one can delete files a concurrent
/// call in the other is about to return.
///
/// Downloads run in the foreground, as with [DefaultModelDownloadManager].
final class ModelStore implements ModelDownloadManager {
  ModelStore._(this.directory, this.appId)
    : _files = DefaultModelDownloadManager(
        defaultCacheDirectory: p.join(directory, 'files'),
      ),
      _entriesDirectory = p.join(directory, 'entries'),
      _lock = StoreLock(p.join(directory, 'store.lock'));

  /// Opens the store in [directory] for the app named [appId], creating the
  /// directory when needed.
  ///
  /// [directory] decides who shares the store: on desktop, a per-user
  /// directory such as one under
  /// [DefaultModelDownloadManager.defaultSharedCacheDirectory]; on Android, a
  /// directory the user granted every participating app; on iOS and macOS, a
  /// directory in an App Group container. [appId] names the app in the
  /// store's references, for example its bundle or application id. Every app
  /// can read the ids of the others.
  ///
  /// Throws [LlamaArgumentException] when [appId] is blank or contains a
  /// control character, and [LlamaUnsupportedException] when [directory]
  /// cannot be created, written or locked.
  static Future<ModelStore> open({
    required String directory,
    required String appId,
  }) async {
    if (appId.trim().isEmpty || appId.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw LlamaArgumentException(
        'ModelStore appId must be non-blank and free of control characters.',
        name: 'appId',
      );
    }
    final requested = p.normalize(p.absolute(directory));
    try {
      // Every spelling of the directory, such as one through a symbolic
      // link, must reach the same lock queue.
      final root = await Directory(requested).create(recursive: true);
      final store = ModelStore._(await root.resolveSymbolicLinks(), appId);
      await Directory(store._entriesDirectory).create();
      await Directory(store._files.defaultCacheDirectory).create();
      await store._lock.run(() async {});
      return store;
    } on FileSystemException catch (error) {
      throw LlamaUnsupportedException(
        'ModelStore needs a writable directory that supports file locks; '
        '$requested is not one (${error.osError?.message ?? error.message}).',
      );
    }
  }

  /// The store's root directory, with symbolic links resolved.
  final String directory;

  /// The app this store handle records references for.
  final String appId;

  final DefaultModelDownloadManager _files;
  final String _entriesDirectory;
  final StoreLock _lock;

  /// The identifier of the entry that holds [model]'s files.
  ///
  /// Derived from the files' [ModelSource.cacheKey]s, so it is the same in
  /// every app and reveals nothing about the sources.
  static String entryIdFor(LlamaModel model) => modelStoreEntryId(model);

  /// Ensures [model]'s files are in the store and records that this app
  /// references them.
  ///
  /// The reference is recorded before downloading, so no other app deletes
  /// the files while they download or after they are returned. When the call
  /// fails, this app's reference is put back as it was before the call:
  /// dropped if the call created it, kept if the app already held it. Calls
  /// of one app that overlap count as one: the reference stays when any of
  /// them succeeds, and goes back to its state before the first when all
  /// fail. Files and partial downloads stay for a later call to resume, or
  /// for [prune].
  ///
  /// [options] apply to every file, as in `LlamaEngine.load`: credentials are
  /// never sent to more than one origin, and [ModelLoadOptions.sha256] needs
  /// a model without a projector. [onProgress] reports the model's download,
  /// then the projector's.
  ///
  /// Throws [LlamaUnsupportedException] for a local [ModelSource.path] file,
  /// [ModelCachePolicy.noCache] or a [ModelLoadOptions.cacheDirectory]: the
  /// store holds remote files in its own directory.
  Future<ModelStoreEntry> ensure(
    LlamaModel model, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    final sources = <ModelSource>[model.source, ?model.projector];
    _checkEnsureArguments(sources, options);
    final id = entryIdFor(model);
    await _lock.run(
      () => _addReference(id, [for (final source in sources) source.cacheKey]),
    );
    final List<ModelCacheEntry> files;
    try {
      files = <ModelCacheEntry>[
        for (final source in sources)
          await _files.ensureModel(
            source,
            options: options,
            onProgress: onProgress,
          ),
      ];
    } catch (error, stackTrace) {
      var settling = false;
      try {
        await _lock.run(() {
          settling = true;
          return _settleFailure(id);
        });
      } on FileSystemException {
        // The reference cannot be put back without the lock, so it stays
        // until a release, and the call reports its own failure.
        if (!settling) {
          _endClaim(id, succeeded: false);
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    _endClaim(id, succeeded: true);
    return ModelStoreEntry(
      id: id,
      model: files.first,
      projector: files.length > 1 ? files[1] : null,
      references: await _readReferences(id),
    );
  }

  /// The entries whose files are all in the store, most recently used first.
  Future<List<ModelStoreEntry>> entries() async {
    final result = <ModelStoreEntry>[];
    for (final record in await _readEntries()) {
      final cacheKeys = record.cacheKeys;
      if (cacheKeys == null) {
        continue;
      }
      final files = <ModelCacheEntry>[];
      for (final cacheKey in cacheKeys) {
        final file = await _files.get(cacheKey);
        if (file == null) {
          break;
        }
        files.add(file);
      }
      if (files.length != cacheKeys.length) {
        continue;
      }
      result.add(
        ModelStoreEntry(
          id: record.id,
          model: files.first,
          projector: files.length > 1 ? files[1] : null,
          references: record.references,
        ),
      );
    }
    result.sort((a, b) => _lastUsed(b).compareTo(_lastUsed(a)));
    return result;
  }

  /// Drops this app's reference to the entry [entryId] and, when no app
  /// references it any more, deletes the entry and every file of it that no
  /// other referenced entry holds.
  ///
  /// Throws [LlamaArgumentException] when [entryId] is not an id from
  /// [entryIdFor] or [ModelStoreEntry.id]. When a file could not be deleted,
  /// the reference and the entry are gone anyway and the file stays, intact
  /// and reusable by a later [ensure], for a later [prune]: the call throws
  /// the [FileSystemException] of a file the OS refuses to delete, after
  /// deleting the others, else [ModelCacheEntryInUseException] for a file
  /// downloading elsewhere.
  Future<void> release(String entryId) async {
    if (!_entryIdPattern.hasMatch(entryId)) {
      throw LlamaArgumentException(
        'ModelStore entry ids are 64 lowercase hex characters.',
        name: 'entryId',
        invalidValue: entryId,
      );
    }
    return _lock.run(() async {
      await _dropReference(entryId);
      await _collect(<String>{entryId});
    });
  }

  /// Ensures [source] is in the store, recording this app's reference to it
  /// as an entry of its own, so the store works as an engine's download
  /// manager through `ModelFileStore(downloadManager: store)`.
  ///
  /// A local [ModelSource.path] file and a [ModelCachePolicy.noCache]
  /// download are passed to the store's file manager without a reference.
  /// Throws [LlamaUnsupportedException] for a
  /// [ModelLoadOptions.cacheDirectory].
  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    _rejectCacheDirectory(options.cacheDirectory);
    if (source.isLocal || options.cachePolicy == ModelCachePolicy.noCache) {
      return _files.ensureModel(
        source,
        options: options,
        onProgress: onProgress,
      );
    }
    final entry = await ensure(
      LlamaModel(source),
      options: options,
      onProgress: onProgress,
    );
    return entry.model;
  }

  /// Lists the store's files. Throws [LlamaUnsupportedException] for a
  /// [cacheDirectory].
  @override
  Future<List<ModelCacheEntry>> list({String? cacheDirectory}) async {
    _rejectCacheDirectory(cacheDirectory);
    return _files.list();
  }

  /// Gets the store's file for [cacheKey]. Throws
  /// [LlamaUnsupportedException] for a [cacheDirectory].
  @override
  Future<ModelCacheEntry?> get(
    String cacheKey, {
    String? cacheDirectory,
  }) async {
    _rejectCacheDirectory(cacheDirectory);
    return _files.get(cacheKey);
  }

  /// Drops this app's references to every entry holding the file for
  /// [cacheKey], then deletes the file unless another app still references
  /// it.
  ///
  /// Throws the [FileSystemException] of a file the OS refuses to delete, as
  /// [release] does, else [ModelCacheEntryInUseException] naming the file's
  /// directory when it is kept because another app references it or because
  /// it is downloading elsewhere. Throws [LlamaUnsupportedException] for a
  /// [cacheDirectory].
  @override
  Future<void> remove(String cacheKey, {String? cacheDirectory}) async {
    _rejectCacheDirectory(cacheDirectory);
    return _lock.run(() async {
      final holders = <String>{
        for (final record in await _readEntries())
          if (record.cacheKeys?.contains(cacheKey) ?? false) record.id,
      };
      for (final id in holders) {
        await _dropReference(id);
      }
      await _collect(holders, orphans: <String>{cacheKey});
    });
  }

  /// Drops every reference this app holds, then deletes every file no app
  /// references.
  ///
  /// Throws the first [FileSystemException] of a file the OS refuses to
  /// delete, after deleting the others, else
  /// [ModelCacheEntryInUseException] naming the directories of the files kept
  /// because other apps reference them or because they are downloading
  /// elsewhere. Throws [LlamaUnsupportedException] for a [cacheDirectory].
  @override
  Future<void> clear({String? cacheDirectory}) async {
    _rejectCacheDirectory(cacheDirectory);
    return _lock.run(() async {
      final records = await _readEntries();
      for (final record in records) {
        await _dropReference(record.id);
      }
      await _collect(
        <String>{for (final record in records) record.id},
        orphans: <String>{
          for (final file in await _files.list()) file.cacheKey,
        },
      );
    });
  }

  /// Deletes files no app references: those last used more than [maxAge]
  /// ago, then the least recently used until the store holds at most
  /// [maxBytes]. Returns the deleted files.
  ///
  /// Never deletes a file an app references, so the store can stay above
  /// [maxBytes]; [release] references first. Also deletes leftover entries
  /// without references and file metadata whose file is gone. Skips files
  /// downloading elsewhere and files the OS refuses to delete, and leaves
  /// them out of the result, so one such file does not stop the rest.
  /// Partial downloads stay. Throws
  /// [LlamaUnsupportedException] for a [cacheDirectory].
  @override
  Future<List<ModelCacheEntry>> prune({
    Duration? maxAge,
    int? maxBytes,
    String? cacheDirectory,
  }) async {
    _rejectCacheDirectory(cacheDirectory);
    return _lock.run(() async {
      final records = await _readEntries();
      for (final record in records) {
        if (record.references.isEmpty) {
          await _deleteEntryDirectory(record.id);
        }
      }
      if (records.any((record) => record.protectsUnknownFiles)) {
        return const <ModelCacheEntry>[];
      }
      final referenced = <String>{
        for (final record in records)
          if (record.references.isNotEmpty) ...?record.cacheKeys,
      };
      final files = (await _files.list())
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      var total = 0;
      for (final file in files) {
        total += await _fileLength(file);
      }
      final now = DateTime.now().toUtc();
      final removed = <ModelCacheEntry>[];
      for (final file in files) {
        if (referenced.contains(file.cacheKey)) {
          continue;
        }
        final expired =
            maxAge != null && now.difference(file.updatedAt.toUtc()) > maxAge;
        final overBudget = maxBytes != null && total > maxBytes;
        if (!expired && !overBudget) {
          continue;
        }
        final length = await _fileLength(file);
        try {
          await _files.remove(file.cacheKey);
        } on ModelCacheEntryInUseException {
          continue;
        } on FileSystemException {
          // A file the OS refuses to delete stays, as one in use does.
          continue;
        }
        removed.add(file);
        total -= length;
      }
      // Entries whose model file was deleted behind the store's back.
      try {
        removed.addAll(await _files.prune());
      } on FileSystemException {
        // Left for a later prune, as a refused file above is.
      }
      return removed;
    });
  }

  void _checkEnsureArguments(
    List<ModelSource> sources,
    ModelLoadOptions options,
  ) {
    _rejectCacheDirectory(options.cacheDirectory);
    if (options.cachePolicy == ModelCachePolicy.noCache) {
      throw LlamaUnsupportedException(
        'ModelStore keeps every file it downloads, so it does not support '
        'ModelCachePolicy.noCache. Use DefaultModelDownloadManager for '
        'transient downloads.',
      );
    }
    if (sources.any((source) => source.isLocal)) {
      throw LlamaUnsupportedException(
        'ModelStore holds downloaded files only; load a local ModelSource.path '
        'file directly.',
      );
    }
    if (sources.length > 1 && options.sha256 != null) {
      throw LlamaUnsupportedException(
        'ModelStore entry with a projector uses ${sources.length} files, so '
        'ModelLoadOptions.sha256 cannot apply to them. Leave it unset.',
      );
    }
    if (options.bearerToken != null || options.headers.isNotEmpty) {
      final origins = <String>{
        for (final source in sources)
          if (source.resolvedUri case final url?)
            '${url.scheme}://${url.host}:${url.port}',
      };
      if (origins.length > 1) {
        throw LlamaArgumentException(
          'ModelStore entry would send ModelLoadOptions.bearerToken or headers '
          'to more than one host (${origins.join(', ')}). Credentials are '
          'never forwarded across hosts: load these files from one host, or '
          'leave bearerToken and headers unset.',
          name: 'options',
        );
      }
    }
  }

  void _rejectCacheDirectory(String? cacheDirectory) {
    if (cacheDirectory != null) {
      throw LlamaUnsupportedException(
        'ModelStore keeps its files in its own directory, so it does not take '
        'a cacheDirectory.',
      );
    }
  }

  /// Records this app's reference to [id], rewriting an entry file this
  /// version cannot read, and returns the token it wrote.
  Future<String> _addReference(String id, List<String> cacheKeys) async {
    final entryDirectory = p.join(_entriesDirectory, id);
    final entryFile = File(p.join(entryDirectory, _entryFileName));
    if (_cacheKeysOf(await _readJson(entryFile), id) == null) {
      await Directory(entryDirectory).create(recursive: true);
      await _writeAtomically(
        entryFile,
        jsonEncode(<String, Object?>{
          'schema_version': _schemaVersion,
          'id': id,
          'cache_keys': cacheKeys,
        }),
      );
    }
    final file = _referenceFile(id);
    final current = await _readText(file);
    final token = _randomToken();
    await Directory(p.dirname(file.path)).create(recursive: true);
    await _writeAtomically(
      file,
      jsonEncode(<String, Object?>{
        'schema_version': _schemaVersion,
        'app_id': appId,
        'last_used_at': DateTime.now().toUtc().toIso8601String(),
        'token': token,
      }),
    );
    // Looked up only now: a call that succeeded meanwhile may have ended
    // the record.
    final claims = _claims[file.path] ??= _ReferenceClaims();
    if (!claims.wrote(current)) {
      // A release, or another process of this app, changed the reference
      // since these calls wrote it: failing calls go back to that state.
      claims
        ..baseline = current
        ..succeeded = false;
    }
    claims
      ..inFlight += 1
      ..tokens.add(token);
    return token;
  }

  /// Ends one `ensure` of [id] in this isolate's record, returning the record
  /// when it was the last of overlapping calls that all failed.
  _ReferenceClaims? _endClaim(String id, {required bool succeeded}) {
    final path = _referenceFile(id).path;
    final claims = _claims[path]!;
    claims.inFlight -= 1;
    claims.succeeded = claims.succeeded || succeeded;
    if (claims.inFlight > 0) {
      return null;
    }
    _claims.remove(path);
    return claims.succeeded ? null : claims;
  }

  /// Ends one failed `ensure` of [id], and when it is the last of this
  /// isolate's overlapping calls, they all failed and the reference is still
  /// one they wrote, puts back the reference from before them.
  Future<void> _settleFailure(String id) async {
    final claims = _endClaim(id, succeeded: false);
    if (claims == null) {
      return;
    }
    final file = _referenceFile(id);
    // Not rewritten since by this app in another process, or released.
    if (!claims.wrote(await _readText(file))) {
      return;
    }
    final baseline = claims.baseline;
    if (baseline == null) {
      await _dropReference(id);
    } else {
      await _writeAtomically(file, baseline);
    }
  }

  /// Drops this app's reference to [id]. An overlapping `ensure` that writes
  /// the reference again after this takes the drop as its baseline.
  Future<void> _dropReference(String id) async {
    try {
      await _referenceFile(id).delete();
    } on PathNotFoundException {
      // Already released.
    }
  }

  /// Deletes the entries among [candidates] that no app references, then the
  /// files of those entries, and the [orphans], that no remaining referenced
  /// entry holds. Throws the first [FileSystemException] of a file the OS
  /// refused to delete, after trying the others, else
  /// [ModelCacheEntryInUseException] for the [orphans] kept because an entry
  /// references them and for files downloading elsewhere.
  Future<void> _collect(
    Set<String> candidates, {
    Set<String> orphans = const <String>{},
  }) async {
    final records = await _readEntries();
    final unreferenced = <String>{...orphans};
    final referenced = <String>{};
    for (final record in records) {
      if (record.references.isNotEmpty) {
        referenced.addAll(record.cacheKeys ?? const <String>[]);
      } else if (candidates.contains(record.id)) {
        unreferenced.addAll(record.cacheKeys ?? const <String>[]);
        await _deleteEntryDirectory(record.id);
      }
    }
    if (records.any((record) => record.protectsUnknownFiles)) {
      referenced.addAll(unreferenced);
    }
    final kept = <String>[];
    for (final cacheKey in orphans.intersection(referenced)) {
      final file = await _files.get(cacheKey);
      if (file != null) {
        kept.add(p.dirname(file.filePath));
      }
    }
    (FileSystemException, StackTrace)? denied;
    for (final cacheKey in unreferenced.difference(referenced)) {
      try {
        await _files.remove(cacheKey);
      } on ModelCacheEntryInUseException catch (error) {
        kept.addAll(error.entryDirectories);
      } on FileSystemException catch (error, stackTrace) {
        denied ??= (error, stackTrace);
      }
    }
    if (denied != null) {
      Error.throwWithStackTrace(denied.$1, denied.$2);
    }
    if (kept.isNotEmpty) {
      throw ModelCacheEntryInUseException(
        '${kept.length} model store '
        '${kept.length == 1 ? 'file is' : 'files are'} referenced by another '
        'app or downloading elsewhere and '
        '${kept.length == 1 ? 'was' : 'were'} not removed.',
        entryDirectories: kept,
      );
    }
  }

  Future<void> _deleteEntryDirectory(String id) async {
    try {
      await Directory(p.join(_entriesDirectory, id)).delete(recursive: true);
    } on PathNotFoundException {
      // Already deleted.
    }
  }

  Future<List<_EntryRecord>> _readEntries() async {
    final root = Directory(_entriesDirectory);
    if (!await root.exists()) {
      return const <_EntryRecord>[];
    }
    final records = <_EntryRecord>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final id = p.basename(entity.path);
      final json = await _readJson(File(p.join(entity.path, _entryFileName)));
      records.add(
        _EntryRecord(
          id: id,
          cacheKeys: _cacheKeysOf(json, id),
          references: await _readReferences(id),
        ),
      );
    }
    return records;
  }

  Future<List<ModelStoreReference>> _readReferences(String id) async {
    final directory = Directory(
      p.join(_entriesDirectory, id, _referencesDirectoryName),
    );
    final references = <ModelStoreReference>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || p.extension(entity.path) != '.json') {
          continue;
        }
        final json = await _readJson(entity);
        final referenceAppId = json?['app_id'];
        final lastUsedAt = DateTime.tryParse('${json?['last_used_at']}');
        if (referenceAppId is String && lastUsedAt != null) {
          references.add(
            ModelStoreReference(appId: referenceAppId, lastUsedAt: lastUsedAt),
          );
        } else {
          // A reference that cannot be read still keeps the files.
          references.add(
            ModelStoreReference(
              appId: p.basenameWithoutExtension(entity.path),
              lastUsedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            ),
          );
        }
      }
    } on PathNotFoundException {
      return references;
    }
    references.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return references;
  }

  File _referenceFile(String id) {
    final appKey = sha256.convert(utf8.encode(appId)).toString();
    return File(
      p.join(_entriesDirectory, id, _referencesDirectoryName, '$appKey.json'),
    );
  }

  static DateTime _lastUsed(ModelStoreEntry entry) {
    return entry.references.isEmpty
        ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        : entry.references.first.lastUsedAt;
  }

  static Future<int> _fileLength(ModelCacheEntry file) async {
    try {
      return await File(file.filePath).length();
    } on FileSystemException {
      return 0;
    }
  }

  /// The file cache keys an entry file names, or null when it cannot be read.
  ///
  /// Later schema versions keep `cache_keys`, so an older store version still
  /// sees which files a newer app's entry protects.
  static List<String>? _cacheKeysOf(Map<String, Object?>? json, String id) {
    final cacheKeys = json?['cache_keys'];
    if (json?['id'] != id ||
        cacheKeys is! List ||
        cacheKeys.isEmpty ||
        cacheKeys.any((key) => key is! String)) {
      return null;
    }
    return cacheKeys.cast<String>();
  }

  static Future<String?> _readText(File file) async {
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  static Future<Map<String, Object?>?> _readJson(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, Object?> ? decoded : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Future<void> _writeAtomically(File file, String contents) async {
    final temporary = File('${file.path}.${_randomToken()}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(file.path);
  }

  static final Random _random = Random.secure();

  static final Map<String, _ReferenceClaims> _claims =
      <String, _ReferenceClaims>{};

  static String _randomToken() {
    return List<String>.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

/// This isolate's `ensure` calls in flight for one reference file.
final class _ReferenceClaims {
  /// The reference file before the first of these calls or, when it changed
  /// since their last write, before the next one; null when there was none.
  String? baseline;

  /// The calls still running.
  int inFlight = 0;

  /// Whether one of the calls succeeded since the last release.
  bool succeeded = false;

  /// The tokens these calls wrote.
  final Set<String> tokens = <String>{};

  /// Whether [reference], the contents of the reference file, is one of
  /// these calls' writes.
  bool wrote(String? reference) {
    if (reference == null) {
      return false;
    }
    try {
      final json = jsonDecode(reference);
      return json is Map && tokens.contains(json['token']);
    } on FormatException {
      return false;
    }
  }
}

final class _EntryRecord {
  const _EntryRecord({
    required this.id,
    required this.cacheKeys,
    required this.references,
  });

  final String id;

  /// The entry's file cache keys, or null when its metadata is unreadable.
  final List<String>? cacheKeys;

  final List<ModelStoreReference> references;

  /// Whether this entry keeps files that cannot be named, so no file may be
  /// deleted.
  bool get protectsUnknownFiles => cacheKeys == null && references.isNotEmpty;
}
