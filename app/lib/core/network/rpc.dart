import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin, typed wrapper around Postgres RPC calls.
///
/// * converts every backend error into an [AppFailure];
/// * large JSON payloads are re-decoded on a background isolate so the UI
///   thread never janks while parsing (e.g. a 200-question model test).
extension RpcX on SupabaseClient {
  Future<T> rpcCall<T>(String fn, {Map<String, dynamic>? params}) async {
    try {
      final result = await rpc<dynamic>(fn, params: params);
      return result as T;
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// RPC returning a JSON object.
  Future<Map<String, dynamic>> rpcMap(String fn, {Map<String, dynamic>? params}) async {
    final result = await rpcCall<dynamic>(fn, params: params);
    if (result == null) return const {};
    return Map<String, dynamic>.from(result as Map);
  }

  /// RPC returning a JSON array (or a set of rows).
  Future<List<Map<String, dynamic>>> rpcList(String fn, {Map<String, dynamic>? params}) async {
    final result = await rpcCall<dynamic>(fn, params: params);
    if (result == null) return const [];
    return (result as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(growable: false);
  }
}

/// Runs a query and maps errors. Use for table selects/inserts.
Future<T> guard<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on Object catch (e) {
    throw AppFailure.from(e);
  }
}

/// Decodes a big JSON string off the UI thread.
Future<Object?> decodeJsonInBackground(String source) {
  if (source.length < 32 * 1024) return Future.value(jsonDecode(source));
  return compute(jsonDecode, source);
}
