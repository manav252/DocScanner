// HTTP client for the DocScanner backend (see backend/app/api).
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The server is unreachable (no network, server down, timeout).
class OfflineException implements Exception {
  const OfflineException(this.cause);
  final Object cause;
  @override
  String toString() => 'Offline: $cause';
}

class ApiException implements Exception {
  const ApiException(this.status, this.message, [this.body]);
  final int status;
  final String message;
  final Object? body;

  bool get isUnauthorized => status == 401;
  @override
  String toString() => 'ApiException($status): $message';
}

/// PUT /documents/{id} answered 409: [server] holds the current server copy.
class ConflictException implements Exception {
  const ConflictException(this.server);
  final Map<String, dynamic> server;
}

class Session {
  const Session({required this.accessToken, required this.refreshToken, required this.userId, required this.email});
  final String accessToken, refreshToken, userId, email;

  Map<String, String> toJson() => {'access': accessToken, 'refresh': refreshToken, 'userId': userId, 'email': email};
  static Session fromJson(Map<String, dynamic> j) => Session(
        accessToken: j['access'] as String,
        refreshToken: j['refresh'] as String,
        userId: j['userId'] as String,
        email: j['email'] as String,
      );

  static Session fromTokenResponse(Map<String, dynamic> j) => Session(
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String,
        userId: (j['user'] as Map)['id'] as String,
        email: (j['user'] as Map)['email'] as String,
      );
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.session,
    this.onSessionChanged,
    this.timeout = const Duration(seconds: 30),
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  final Duration timeout;
  Session? session;

  /// Called after login, token refresh, or when the session becomes invalid (null).
  final void Function(Session?)? onSessionChanged;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? json,
    List<int>? bytes,
    String? contentType,
    bool auth = true,
    bool retry = true,
    Duration? timeout,
  }) async {
    final req = http.Request(method, _uri(path, query));
    if (auth && session != null) req.headers['Authorization'] = 'Bearer ${session!.accessToken}';
    if (json != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(json);
    } else if (bytes != null) {
      req.headers['Content-Type'] = contentType ?? 'application/octet-stream';
      req.bodyBytes = bytes;
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout ?? this.timeout));
    } on TimeoutException catch (e) {
      throw OfflineException(e);
    } on http.ClientException catch (e) {
      throw OfflineException(e);
    }
    if (res.statusCode == 401 && auth && retry && session != null && await _refresh()) {
      return _send(method, path,
          query: query, json: json, bytes: bytes, contentType: contentType, retry: false, timeout: timeout);
    }
    if (res.statusCode >= 400) {
      Object? body;
      try {
        body = jsonDecode(res.body);
      } catch (_) {}
      final detail = body is Map ? body['detail'] : null;
      final message = detail is String ? detail : (detail is Map ? '${detail['message'] ?? detail}' : res.reasonPhrase ?? 'HTTP ${res.statusCode}');
      if (res.statusCode == 401 && auth) {
        session = null;
        onSessionChanged?.call(null);
      }
      throw ApiException(res.statusCode, message, body);
    }
    return res;
  }

  Future<bool> _refresh() async {
    final s = session;
    if (s == null) return false;
    try {
      final res = await _send('POST', '/auth/refresh', json: {'refresh_token': s.refreshToken}, auth: false);
      session = Session.fromTokenResponse(jsonDecode(res.body) as Map<String, dynamic>);
      onSessionChanged?.call(session);
      return true;
    } on ApiException {
      return false;
    }
  }

  Map<String, dynamic> _json(http.Response r) => jsonDecode(r.body) as Map<String, dynamic>;

  // ---------- auth ----------

  Future<Session> register(String email, String password) => _authenticate('/auth/register', email, password);
  Future<Session> login(String email, String password) => _authenticate('/auth/login', email, password);

  Future<Session> _authenticate(String path, String email, String password) async {
    final res = await _send('POST', path, json: {'email': email.trim(), 'password': password}, auth: false);
    session = Session.fromTokenResponse(_json(res));
    onSessionChanged?.call(session);
    return session!;
  }

  Future<bool> health() async {
    try {
      final r = await _send('GET', '/health', auth: false, timeout: const Duration(seconds: 5));
      return _json(r)['status'] == 'ok';
    } on Exception {
      return false;
    }
  }

  // ---------- documents ----------

  Future<Map<String, dynamic>> listDocuments({int? since, int limit = 200}) async => _json(await _send(
        'GET',
        '/documents',
        query: {if (since != null) 'since': '$since', 'limit': '$limit'},
      ));

  /// Upsert; throws [ConflictException] when [json]'s base_version is stale.
  Future<Map<String, dynamic>> putDocument(String id, Map<String, dynamic> json) async {
    try {
      return _json(await _send('PUT', '/documents/$id', json: json));
    } on ApiException catch (e) {
      if (e.status == 409 && e.body is Map && (e.body! as Map)['document'] is Map) {
        throw ConflictException(((e.body! as Map)['document'] as Map).cast<String, dynamic>());
      }
      rethrow;
    }
  }

  Future<void> deleteDocument(String id, {int? baseVersion}) async {
    await _send('DELETE', '/documents/$id', query: {if (baseVersion != null) 'base_version': '$baseVersion'});
  }

  Future<void> putPageFile(String docId, String pageId, String kind, List<int> bytes) async {
    await _send('PUT', '/documents/$docId/pages/$pageId/files/$kind',
        bytes: bytes, contentType: 'image/jpeg', timeout: const Duration(minutes: 2));
  }

  Future<List<int>> getPageFile(String docId, String pageId, String kind) async =>
      (await _send('GET', '/documents/$docId/pages/$pageId/files/$kind', timeout: const Duration(minutes: 2))).bodyBytes;

  // ---------- server-side processing ----------

  /// POST /process (multipart). Returns the response for the caller to read
  /// JSON (detect_only) or the JPEG + X-Document-* headers.
  Future<http.Response> process(List<int> image, Map<String, String> fields) async {
    Future<http.Response> send() async {
      final req = http.MultipartRequest('POST', _uri('/process'))
        ..fields.addAll(fields)
        ..files.add(http.MultipartFile.fromBytes('file', image, filename: 'image.jpg'));
      if (session != null) req.headers['Authorization'] = 'Bearer ${session!.accessToken}';
      try {
        return await http.Response.fromStream(await _http.send(req).timeout(const Duration(minutes: 1)));
      } on TimeoutException catch (e) {
        throw OfflineException(e);
      } on http.ClientException catch (e) {
        throw OfflineException(e);
      }
    }

    var res = await send();
    if (res.statusCode == 401 && await _refresh()) res = await send();
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.reasonPhrase ?? 'HTTP ${res.statusCode}');
    return res;
  }

  void close() => _http.close();
}
