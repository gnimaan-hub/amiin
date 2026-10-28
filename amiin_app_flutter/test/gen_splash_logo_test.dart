// Outil ponctuel : génère depuis assets/logo/ (mark « A » pixel/tech) :
//   · assets/splash/splash_logo.png       — mark turquoise (splash natif clair)
//   · assets/splash/splash_logo_dark.png  — mark sel d'Assal (splash natif sombre)
//   · assets/icon/icon.png                — icône principale (iOS/web/Windows) :
//     fond dégradé turquoise saturé + mark crème large (76 % du canevas)
//   · assets/icon/adaptive_foreground.png — mark crème centré, zone sûre 66 %
//     (icône adaptative Android, fond turquoise #1E8A8A)
//   · assets/icon/adaptive_monochrome.png — mark blanc (icône thématisée A13+)
// Lancer : flutter test test/gen_splash_logo_test.dart
// Puis   : dart run flutter_launcher_icons && dart run flutter_native_splash:create

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _load(String path) async {
  final codec = await ui.instantiateImageCodec(
    File(path).readAsBytesSync(),
  );
  return (await codec.getNextFrame()).image;
}

// Dessine [src] centré dans un canevas carré [canvasSize], inscrit dans un
// carré de [boxSize] (la diagonale doit rester dans le cercle de masque natif).
Future<void> _compose({
  required String srcPath,
  required String outPath,
  required double canvasSize,
  required double boxSize,
}) async {
  final src = await _load(srcPath);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  final scale = boxSize /
      (src.width > src.height ? src.width : src.height).toDouble();
  final w = src.width * scale, h = src.height * scale;
  final dst = ui.Rect.fromLTWH(
    (canvasSize - w) / 2,
    (canvasSize - h) / 2,
    w,
    h,
  );
  canvas.drawImageRect(
    src,
    ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
    dst,
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );

  final image = await recorder
      .endRecording()
      .toImage(canvasSize.toInt(), canvasSize.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  expect(file.existsSync(), isTrue);
}

// Comme [_compose], mais peint d'abord un fond en dégradé radial saturé
// (identité turquoise) avant d'y centrer le mark — utilisé pour l'icône
// principale (non masquée par le système, donc sans contrainte de zone sûre).
Future<void> _composeOnGradient({
  required String srcPath,
  required String outPath,
  required double canvasSize,
  required double boxSize,
  required ui.Color centerColor,
  required ui.Color edgeColor,
}) async {
  final src = await _load(srcPath);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final rect = ui.Rect.fromLTWH(0, 0, canvasSize, canvasSize);

  final gradient = ui.Gradient.radial(
    ui.Offset(canvasSize / 2, canvasSize * 0.42),
    canvasSize * 0.78,
    [centerColor, edgeColor],
  );
  canvas.drawRect(rect, ui.Paint()..shader = gradient);

  final scale = boxSize /
      (src.width > src.height ? src.width : src.height).toDouble();
  final w = src.width * scale, h = src.height * scale;
  final dst = ui.Rect.fromLTWH(
    (canvasSize - w) / 2,
    (canvasSize - h) / 2,
    w,
    h,
  );
  canvas.drawImageRect(
    src,
    ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
    dst,
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );

  final image = await recorder
      .endRecording()
      .toImage(canvasSize.toInt(), canvasSize.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  expect(file.existsSync(), isTrue);
}

void main() {
  test('génère les assets splash + icône adaptative', () async {
    // Splash natif : masque circulaire de 768 px (Android 12+) sur 1152 px.
    // Boîte de 520 px → diagonale ≈ 735 px, dans le cercle.
    await _compose(
      srcPath: 'assets/logo/amiin-A-turquoise.png',
      outPath: 'assets/splash/splash_logo.png',
      canvasSize: 1152,
      boxSize: 520,
    );
    await _compose(
      srcPath: 'assets/logo/amiin-A-selassal.png',
      outPath: 'assets/splash/splash_logo_dark.png',
      canvasSize: 1152,
      boxSize: 520,
    );

    // Icône adaptative : zone sûre = cercle de 66 % de 1024 px, rayon 338 px.
    // Pour la forme du « A » (pointe haute + 2 pieds bas), les coins utiles
    // de la boîte restent dans le cercle jusqu'à boxSize ≈ 478 px — on se
    // cale juste en dessous pour un mark nettement plus grand qu'avant (460).
    await _compose(
      srcPath: 'assets/logo/amiin-A-selassal.png',
      outPath: 'assets/icon/adaptive_foreground.png',
      canvasSize: 1024,
      boxSize: 476,
    );
    await _compose(
      srcPath: 'assets/logo/amiin-A-blanc.png',
      outPath: 'assets/icon/adaptive_monochrome.png',
      canvasSize: 1024,
      boxSize: 476,
    );

    // Icône principale (iOS / web / Windows) : pas de masque système, donc
    // le mark peut occuper une bien plus grande part du canevas. Fond en
    // dégradé radial saturé (turquoise moyen → turquoise foncé, sans le
    // halo blanc délavé d'avant) pour un rendu plus contrasté et vif.
    await _composeOnGradient(
      srcPath: 'assets/logo/amiin-A-selassal.png',
      outPath: 'assets/icon/icon.png',
      canvasSize: 1024,
      boxSize: 780,
      centerColor: const ui.Color(0xFF2AADAD), // turquoiseMid
      edgeColor: const ui.Color(0xFF0F4A4A), // plus profond que turquoiseDk
    );
  });
}
