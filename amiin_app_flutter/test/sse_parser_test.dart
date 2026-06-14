import 'package:flutter_test/flutter_test.dart';
import 'package:amiin_app_flutter/services/amiin_api_service.dart';

void main() {
  group('parseSseLine', () {
    test('parse un token', () {
      final event = parseSseLine('data: {"type":"token","text":"Bonjour é à"}');
      expect(event, isA<ChatStreamToken>());
      expect((event as ChatStreamToken).text, 'Bonjour é à');
    });

    test('parse un statut', () {
      final event = parseSseLine('data: {"type":"status","text":"Recherche…"}');
      expect(event, isA<ChatStreamStatus>());
      expect((event as ChatStreamStatus).text, 'Recherche…');
    });

    test('parse un done avec tool_calls et sources', () {
      final event = parseSseLine(
          'data: {"type":"done","tool_calls":[{"id":"t1","name":"create_note","input":{"title":"X"}}],'
          '"sources":[{"title":"Loi 2024","url":"https://example.dj"}],"processing_time":2.5}');
      expect(event, isA<ChatStreamDone>());
      final done = event as ChatStreamDone;
      expect(done.toolCalls, hasLength(1));
      expect(done.toolCalls.first['name'], 'create_note');
      expect(done.sources, hasLength(1));
      expect(done.processingTime, 2.5);
    });

    test('parse un done sans champs optionnels', () {
      final event = parseSseLine('data: {"type":"done"}');
      expect(event, isA<ChatStreamDone>());
      final done = event as ChatStreamDone;
      expect(done.toolCalls, isEmpty);
      expect(done.sources, isEmpty);
      expect(done.processingTime, 0.0);
    });

    test('parse une erreur serveur', () {
      final event = parseSseLine('data: {"type":"error","detail":"Surcharge"}');
      expect(event, isA<ChatStreamError>());
      expect((event as ChatStreamError).detail, 'Surcharge');
    });

    test('ignore les lignes vides et non-data', () {
      expect(parseSseLine(''), isNull);
      expect(parseSseLine('event: ping'), isNull);
      expect(parseSseLine(': commentaire SSE'), isNull);
      expect(parseSseLine('data: '), isNull);
    });

    test('ignore le JSON malformé sans lever', () {
      expect(parseSseLine('data: {pas du json'), isNull);
      expect(parseSseLine('data: "une chaine"'), isNull);
      expect(parseSseLine('data: {"type":"inconnu"}'), isNull);
    });

    test('tolère les espaces autour de la ligne', () {
      final event =
          parseSseLine('  data: {"type":"token","text":"ok"}  \r');
      expect(event, isA<ChatStreamToken>());
    });
  });
}
