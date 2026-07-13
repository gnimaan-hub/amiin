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
}
