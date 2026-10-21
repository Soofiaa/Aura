import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Por que fallo una llamada a la API de Drive.
enum DriveApiFailure {

  /// Sin conexion: no se pudo tocar la red.
  offline,

  /// La sesion de Google expiro o fue revocada: hace falta volver a entrar.
  unauthorized,

  /// Google rechazo la operacion (permiso, limite o error del servidor).
  failed,
}

/// Error al hablar con la API de Drive. [detail] es solo para depuracion:
/// nunca se muestra a la usuaria ni incluye el contenido del respaldo.
class DriveApiException implements Exception {
  DriveApiException(this.cause, [this.detail]);

  final DriveApiFailure cause;
  final String? detail;

  @override
  String toString() => 'DriveApiException($cause)';
}

/// Construye el cuerpo multipart de una creacion de archivo (Drive v3,
/// uploadType=multipart): metadata JSON + contenido. Funcion pura para
/// poder testearla sin red.
List<int> buildDriveMultipartBody({
  required String boundary,
  required Map<String, Object?> metadata,
  required List<int> media,
}) {
  final out = BytesBuilder();
  void addText(String text) => out.add(utf8.encode(text));
  addText('--$boundary\r\n'
      'content-type: application/json; charset=UTF-8\r\n\r\n');
  addText(jsonEncode(metadata));
  addText('\r\n--$boundary\r\n'
      'content-type: application/octet-stream\r\n\r\n');
  out.add(media);
  addText('\r\n--$boundary--\r\n');
  return out.takeBytes();
}

/// Cliente REST minimo de la API de Drive v3: solo la carpeta "Aura" y el
/// archivo de respaldo. Sin SDK de Google: `http` puro y el token de
/// acceso que le pasa el gateway (ver drive_backup_gateway.dart).
class DriveApiClient {
  DriveApiClient({
    required Future<String> Function() accessToken,
    http.Client? client,
  })  : _accessToken = accessToken,
        _client = client ?? http.Client();

  static const String carpetaNombre = 'Aura';
  static const String carpetaMime = 'application/vnd.google-apps.folder';
  static const String _base = 'https://www.googleapis.com/drive/v3';
  static const String _uploadBase =
      'https://www.googleapis.com/upload/drive/v3';

  final Future<String> Function() _accessToken;
  final http.Client _client;

  /// Devuelve el id de la carpeta "Aura", creandola si no existe. Con el
  /// alcance drive.file la carpeta es visible en Drive de la usuaria.
  Future<String> ensureFolder() async {
    final q = "mimeType='$carpetaMime' and name='$carpetaNombre' "
        'and trashed=false';
    final listed = await _get('$_base/files', <String, String>{
      'q': q,
      'fields': 'files(id)',
      'pageSize': '1',
    });
    final files = _filesFrom(listed);
    if (files.isNotEmpty) return files.first['id']! as String;

    final created = await _postJson('$_base/files', <String, Object?>{
      'name': carpetaNombre,
      'mimeType': carpetaMime,
    });
    return created['id']! as String;
  }

  /// Sube [bytes] como [fileName] dentro de [folderId]. Si ya existe un
  /// archivo con ese nombre se reemplaza su contenido (un solo archivo
  /// automatico, sin versiones acumuladas).
  Future<void> uploadOrReplace({
    required String folderId,
    required String fileName,
    required List<int> bytes,
  }) async {
    final existing = await _findFile(folderId, fileName);
    final headers = await _headers(
        contentType: 'application/octet-stream; charset=UTF-8');
    final uri = existing != null
        ? Uri.parse('$_uploadBase/files/$existing')
            .replace(queryParameters: const {'uploadType': 'media'})
        : Uri.parse('$_uploadBase/files')
            .replace(queryParameters: const {'uploadType': 'multipart'});

    try {
      final http.Response response;
      if (existing != null) {
        response = await _client.patch(uri, headers: headers, body: bytes);
      } else {
        final boundary = 'aura-${DateTime.now().microsecondsSinceEpoch}';
        final body = buildDriveMultipartBody(
          boundary: boundary,
          metadata: <String, Object?>{
            'name': fileName,
            'parents': <String>[folderId],
          },
          media: bytes,
        );
        response = await _client.post(uri,
            headers: <String, String>{
              'authorization': headers['authorization']!,
              'content-type': 'multipart/related; boundary=$boundary',
            },
            body: body);
      }
      _check(response);
    } on DriveApiException {
      rethrow;
    } on SocketException catch (e) {
      throw DriveApiException(DriveApiFailure.offline, e.message);
    } on http.ClientException catch (e) {
      throw DriveApiException(DriveApiFailure.offline, e.message);
    }
  }

  Future<String?> _findFile(String folderId, String fileName) async {
    final q = "name='$fileName' and '$folderId' in parents and trashed=false";
    final body = await _get('$_base/files', <String, String>{
      'q': q,
      'fields': 'files(id)',
      'pageSize': '1',
    });
    final files = _filesFrom(body);
    return files.isEmpty ? null : files.first['id']! as String;
  }

  Future<String> _get(String url, Map<String, String> query) async {
    final uri = Uri.parse(url).replace(queryParameters: query);
    try {
      final response =
          await _client.get(uri, headers: await _headers());
      _check(response);
      return response.body;
    } on DriveApiException {
      rethrow;
    } on SocketException catch (e) {
      throw DriveApiException(DriveApiFailure.offline, e.message);
    } on http.ClientException catch (e) {
      throw DriveApiException(DriveApiFailure.offline, e.message);
    }
  }

  Future<Map<String, Object?>> _postJson(
      String url, Map<String, Object?> payload) async {
    final headers = await _headers(isJson: true);
    return _requestJson(() => _client.post(Uri.parse(url),
        headers: headers, body: jsonEncode(payload)));
  }

  Future<Map<String, Object?>> _requestJson(
      Future<http.Response> Function() run) async {
    try {
      final response = await run();
      _check(response);
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        throw DriveApiException(DriveApiFailure.failed, 'respuesta inesperada');
      }
      return decoded;
    } on DriveApiException {
      rethrow;
    } on SocketException catch (e) {
      throw DriveApiException(DriveApiFailure.offline, e.message);
    } on http.ClientException catch (e) {
      throw DriveApiException(DriveApiFailure.offline, e.message);
    }
  }

  List<Map<String, Object?>> _filesFrom(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw DriveApiException(DriveApiFailure.failed, 'respuesta inesperada');
    }
    final files = decoded['files'];
    if (files is! List) return const [];
    return files
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
  }

  Future<Map<String, String>> _headers({String? contentType, bool isJson = false}) async {
    final token = await _accessToken();
    return <String, String>{
      'authorization': 'Bearer $token',
      if (contentType != null) 'content-type': contentType,
      if (isJson) 'content-type': 'application/json; charset=UTF-8',
    };
  }

  void _check(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    if (status == 401 || status == 403) {
      throw DriveApiException(DriveApiFailure.unauthorized, 'HTTP $status');
    }
    throw DriveApiException(DriveApiFailure.failed, 'HTTP $status');
  }
}
