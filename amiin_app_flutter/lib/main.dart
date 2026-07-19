import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait uniquement : les écrans sont conçus pour ce format, le paysage
  // cassait de nombreux layouts (dépassements, troncatures).
  // Pas de await : rien ne justifie de retarder la première frame pour ça.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Toutes les initialisations lourdes (Hive, cipher, boxes, formats de date…)
  // sont faites PENDANT le splash screen via ensureBootstrap() — voir
  // services/bootstrap.dart. runApp() immédiat = splash visible immédiatement.
  runApp(const MyApp());
}
