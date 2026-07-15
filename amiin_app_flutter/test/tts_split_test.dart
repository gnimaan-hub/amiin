import 'package:flutter_test/flutter_test.dart';
import 'package:amiin_app_flutter/services/cloud_tts_service.dart';

void main() {
  group('splitForTts', () {
    test('texte vide → aucun morceau', () {
      expect(CloudTtsService.splitForTts('   '), isEmpty);
    });

    test('une seule phrase → un seul morceau', () {
      expect(CloudTtsService.splitForTts('Bonjour Djibouti.'),
          ['Bonjour Djibouti.']);
    });

    test('la première phrase part seule (démarrage rapide)', () {
      final chunks = CloudTtsService.splitForTts(
          'Voici la réponse. Ensuite un complément. Et une fin.');
      expect(chunks.first, 'Voici la réponse.');
      expect(chunks.length, 2);
      expect(chunks[1], 'Ensuite un complément. Et une fin.');
    });

    test('les phrases suivantes sont groupées par ~260 caractères', () {
      final s = 'Phrase de taille moyenne pour le test numero un. ' * 12;
      final chunks = CloudTtsService.splitForTts(s.trim());
      expect(chunks.first, 'Phrase de taille moyenne pour le test numero un.');
      for (final c in chunks.skip(1)) {
        expect(c.length, lessThanOrEqualTo(320));
      }
      // rien n'est perdu
      expect(chunks.join(' ').replaceAll(RegExp(r'\s+'), ' '),
          s.trim().replaceAll(RegExp(r'\s+'), ' '));
    });

    test('gère ? ! et points de suspension', () {
      final chunks = CloudTtsService.splitForTts(
          'Vraiment ? Oui ! Attendez… Voilà.');
      expect(chunks.first, 'Vraiment ?');
    });
  });

  group('extractCompleteSentences (stream)', () {
    test('rien tant que la phrase est incomplète', () {
      final (s, o) = CloudTtsService.extractCompleteSentences('Bonjour, je', 0);
      expect(s, isEmpty);
      expect(o, 0);
    });

    test('extrait la phrase dès la ponctuation + espace', () {
      final (s, o) = CloudTtsService.extractCompleteSentences(
          'Bonjour Djibouti. Ensuite', 0);
      expect(s, ['Bonjour Djibouti.']);
      expect(o, 18);
    });

    test('idempotent : re-balayage depuis le même offset', () {
      const text = 'Un. Deux. Trois est incomplet';
      final (s1, o1) = CloudTtsService.extractCompleteSentences(text, 0);
      expect(s1, ['Un.', 'Deux.']);
      final (s2, o2) = CloudTtsService.extractCompleteSentences(text, o1);
      expect(s2, isEmpty);
      expect(o2, o1);
    });

    test('extraction au fil de la croissance du texte', () {
      var offset = 0;
      final collected = <String>[];
      for (final snapshot in [
        'La météo',
        'La météo est belle.',
        'La météo est belle. Il fait 32',
        'La météo est belle. Il fait 32 degrés. Enfin voilà.',
      ]) {
        final (s, o) =
            CloudTtsService.extractCompleteSentences(snapshot, offset);
        collected.addAll(s);
        offset = o;
      }
      expect(collected,
          ['La météo est belle.', 'Il fait 32 degrés. Enfin voilà.'.substring(0, 18), 'Enfin voilà.']);
    });

    test('fin de texte sans espace après ponctuation', () {
      final (s, _) = CloudTtsService.extractCompleteSentences('Fini.', 0);
      expect(s, ['Fini.']);
    });
  });
}
