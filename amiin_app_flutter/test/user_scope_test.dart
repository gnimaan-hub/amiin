// Données locales séparées par compte (voir lib/services/user_scope.dart) :
// deux comptes sur le même téléphone ne voient jamais les données l'un de
// l'autre, et les données d'avant la séparation reviennent au bon compte.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:amiin_app_flutter/models/chat_message.dart';
import 'package:amiin_app_flutter/services/memory_service.dart';
import 'package:amiin_app_flutter/services/notes_service.dart';
import 'package:amiin_app_flutter/services/settings_service.dart';
import 'package:amiin_app_flutter/services/user_scope.dart';

Future<void> _freshHive() async {
  await Hive.close();
  final dir = await Directory.systemTemp.createTemp('amiin_scope_');
  Hive.init(dir.path);
  userScope.ensureReady = () async {};
  registerUserDataAdapters();
}

Future<List<String>> _noteTitles() async =>
    (await notesService.getNotes()).map((n) => n.title).toList();

ChatMessage _msg(String text) =>
    ChatMessage(id: text, role: 'user', content: text, timestamp: DateTime.now());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deux comptes sur le même téléphone ne partagent rien', () async {
    await _freshHive();
    // Données d'avant la séparation : boxes communes + profil dans « settings »
    final legacyNotes = await Hive.openBox<AmiinNote>('notes_box');
    await legacyNotes.put('n1', AmiinNote(
      id: 'n1', title: 'Note de A', content: '', tags: const [],
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    ));
    await legacyNotes.close();
    final legacySettings = await Hive.openBox<dynamic>('settings');
    await legacySettings.putAll({'profile_firstname': 'Amina', 'theme_variant': 'nuit'});
    await legacySettings.close();
    await settingsService.init();

    // A était connecté au lancement de la nouvelle version : il récupère tout
    await userScope.activate('aaaa-1111', atStartup: true);
    expect(await _noteTitles(), ['Note de A']);
    expect(settingsService.profileFirstname, 'Amina');
    MemoryService().saveMessage(_msg('message de A'));
    expect(await Hive.boxExists('notes_box'), isFalse); // ancienne box supprimée

    // B se connecte sur le même téléphone : aucune donnée de A
    await userScope.activate('bbbb-2222');
    expect(await _noteTitles(), isEmpty);
    expect(settingsService.profileFirstname, '');
    expect(MemoryService().getAllMessages(), isEmpty);
    expect(settingsService.themeVariant, 'nuit'); // réglage de l'appareil, commun
    await notesService.createNote(CreateNotePayload(title: 'Note de B', content: ''));
    settingsService.profileFirstname = 'Bilan';

    // Déconnexion : espace invité vide
    await userScope.activate(null);
    expect(await _noteTitles(), isEmpty);
    expect(settingsService.profileFirstname, '');

    // A revient : il retrouve ses données, pas celles de B
    await userScope.activate('aaaa-1111');
    expect(await _noteTitles(), ['Note de A']);
    expect(settingsService.profileFirstname, 'Amina');
    expect(MemoryService().getAllMessages().map((m) => m.content), ['message de A']);

    // Et B retrouve les siennes
    await userScope.activate('bbbb-2222');
    expect(await _noteTitles(), ['Note de B']);
    expect(settingsService.profileFirstname, 'Bilan');
  });

  test("anciennes données sans compte connecté : effacées, jamais attribuées", () async {
    await _freshHive();
    final legacyNotes = await Hive.openBox<AmiinNote>('notes_box');
    await legacyNotes.put('n1', AmiinNote(
      id: 'n1', title: 'Note orpheline', content: '', tags: const [],
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    ));
    await legacyNotes.close();
    await settingsService.init();

    await userScope.activate(null, atStartup: true); // personne de connecté
    await userScope.activate('cccc-3333');           // un compte se connecte ensuite
    expect(await _noteTitles(), isEmpty);
    expect(await Hive.boxExists('notes_box'), isFalse);
  });

  test('wipeLocalUserData efface le compte actif seulement', () async {
    await _freshHive();
    await settingsService.init();
    await userScope.activate('dddd-4444', atStartup: true);
    await notesService.createNote(CreateNotePayload(title: 'Note de D', content: ''));
    await userScope.activate('eeee-5555');
    await notesService.createNote(CreateNotePayload(title: 'Note de E', content: ''));

    await wipeLocalUserData();
    expect(await _noteTitles(), isEmpty);
    await userScope.activate('dddd-4444');
    expect(await _noteTitles(), ['Note de D']);
  });
}
