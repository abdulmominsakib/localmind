import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';

/// The `ModelStore` entry id for [model], derived from its files'
/// [ModelSource.cacheKey]s.
String modelStoreEntryId(LlamaModel model) {
  return sha256
      .convert(
        utf8.encode(
          'model:${model.source.cacheKey}\n'
          'projector:${model.projector?.cacheKey ?? ''}',
        ),
      )
      .toString();
}
