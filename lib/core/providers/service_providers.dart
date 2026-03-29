import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../constants/app_constants.dart';
import 'package:localmind/features/servers/data/server_api_service.dart';

final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: Duration(milliseconds: AppConstants.connectionTimeoutMs),
      receiveTimeout: Duration(milliseconds: AppConstants.receiveTimeoutMs),
    ),
  );
});

final serverApiServiceProvider = Provider<ServerApiService>((ref) {
  return ServerApiService(ref.read(dioProvider));
});
