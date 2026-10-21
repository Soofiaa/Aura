import 'dart:convert';
import 'dart:io';

import 'package:aura/data/backup/drive_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Future<String> token() async => 'TOKEN';

  DriveApiClient clientWith(MockClient mock) =>
      DriveApiClient(accessToken: token, client: mock);

  group('buildDriveMultipartBody', () {
    test('lleva la metadata JSON y el contenido entre los bordes', () {
      final body = buildDriveMultipartBody(
        boundary: 'BORDE',
        metadata: const {'name': 'a.json', 'parents': ['F1']},
        media: utf8.encode('HOLA'),
      );
      final text = utf8.decode(body);

      expect(text, contains('--BORDE\r\n'));
      expect(text, contains('"name":"a.json"'));
      expect(text, contains('"parents":["F1"]'));
      expect(text, contains('HOLA'));
      expect(text.trimRight(), endsWith('--BORDE--'));
    });
  });

  group('ensureFolder', () {
    test('devuelve la carpeta Aura si ya existe', () async {
      final log = <http.Request>[];
      final client = clientWith(MockClient((request) async {
        log.add(request);
        return http.Response('{"files":[{"id":"F1"}]}', 200);
      }));

      expect(await client.ensureFolder(), 'F1');
      expect(log.single.method, 'GET');
      expect(log.single.url.host, 'www.googleapis.com');
      expect(log.single.url.path, '/drive/v3/files');
      expect(log.single.url.queryParameters['q'], contains("name='Aura'"));
      expect(log.single.headers['authorization'], 'Bearer TOKEN');
    });

    test('la crea si no existe', () async {
      final log = <http.Request>[];
      final client = clientWith(MockClient((request) async {
        log.add(request);
        if (request.method == 'GET') {
          return http.Response('{"files":[]}', 200);
        }
        return http.Response('{"id":"NUEVA"}', 201);
      }));

      expect(await client.ensureFolder(), 'NUEVA');
      expect(log.last.method, 'POST');
      expect(log.last.url.path, '/drive/v3/files');
      expect(jsonDecode(log.last.body), {
        'name': 'Aura',
        'mimeType': 'application/vnd.google-apps.folder',
      });
    });
  });

  group('uploadOrReplace', () {
    test('si el archivo ya existe, reemplaza su contenido (PATCH media)',
        () async {
      final log = <http.Request>[];
      final client = clientWith(MockClient((request) async {
        log.add(request);
        if (request.method == 'GET') {
          return http.Response('{"files":[{"id":"EXISTE"}]}', 200);
        }
        return http.Response('{}', 200);
      }));

      await client.uploadOrReplace(
          folderId: 'F1', fileName: 'r.json', bytes: utf8.encode('BYTES'));

      final patch = log.last;
      expect(patch.method, 'PATCH');
      expect(patch.url.host, 'www.googleapis.com');
      expect(patch.url.path, '/upload/drive/v3/files/EXISTE');
      expect(patch.url.queryParameters['uploadType'], 'media');
      expect(patch.body, 'BYTES');
    });

    test('si no existe, lo crea con multipart y los padres correctos',
        () async {
      final log = <http.Request>[];
      final client = clientWith(MockClient((request) async {
        log.add(request);
        if (request.method == 'GET') {
          return http.Response('{"files":[]}', 200);
        }
        return http.Response('{"id":"NUEVO"}', 201);
      }));

      await client.uploadOrReplace(
          folderId: 'F1', fileName: 'r.json', bytes: utf8.encode('BYTES'));

      final post = log.last;
      expect(post.method, 'POST');
      expect(post.url.path, '/upload/drive/v3/files');
      expect(post.url.queryParameters['uploadType'], 'multipart');
      expect(post.headers['content-type'], contains('multipart/related'));
      final body = utf8.decode(post.bodyBytes);
      expect(body, contains('"name":"r.json"'));
      expect(body, contains('"parents":["F1"]'));
      expect(body, contains('BYTES'));
    });
  });

  group('errores', () {
    test('401 y 403 son unauthorized', () async {
      for (final status in [401, 403]) {
        final client = clientWith(
            MockClient((request) async => http.Response('{"err":1}', status)));
        expect(
          () => client.ensureFolder(),
          throwsA(isA<DriveApiException>()
              .having((e) => e.cause, 'cause', DriveApiFailure.unauthorized)),
        );
      }
    });

    test('500 es failed', () async {
      final client = clientWith(
          MockClient((request) async => http.Response('boom', 500)));
      expect(
        () => client.ensureFolder(),
        throwsA(isA<DriveApiException>()
            .having((e) => e.cause, 'cause', DriveApiFailure.failed)),
      );
    });

    test('sin red es offline', () async {
      final client = clientWith(MockClient(
          (request) => throw const SocketException('sin conexion')));
      expect(
        () => client.ensureFolder(),
        throwsA(isA<DriveApiException>()
            .having((e) => e.cause, 'cause', DriveApiFailure.offline)),
      );
    });

    test('nunca deja el contenido del respaldo en el detalle', () async {
      final client = clientWith(
          MockClient((request) async => http.Response('boom', 500)));
      try {
        await client.uploadOrReplace(
            folderId: 'F1', fileName: 'r.json', bytes: utf8.encode('SECRETO'));
        fail('debio lanzar');
      } on DriveApiException catch (e) {
        expect(e.detail ?? '', isNot(contains('SECRETO')));
      }
    });
  });
}
