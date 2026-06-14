import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'theme/colors.dart';
import 'navigation/app_router.dart';
import 'services/chat_controller.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChatController(),
      child: MaterialApp.router(
        title: 'Amiin',
        // Widgets Material (date picker, time picker, dialogues…) en français.
        // 'ar' préparé pour la future localisation complète (RTL inclus).
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          // ColorScheme dérivé de l'identité terra : les composants Material
          // (pickers, chips, dialogues) héritent enfin des couleurs Amiin.
          colorScheme: ColorScheme.fromSeed(
            seedColor: ColorsAmiin.terra,
            primary: ColorsAmiin.terra,
            surface: ColorsAmiin.white,
          ),
          fontFamily: GoogleFonts.dmSans().fontFamily,
          scaffoldBackgroundColor: ColorsAmiin.ecru,
          appBarTheme: const AppBarTheme(
            backgroundColor: ColorsAmiin.white,
            foregroundColor: ColorsAmiin.ink,
            elevation: 0,
          ),
          textTheme: TextTheme(
            bodyLarge: GoogleFonts.dmSans(fontSize: 14, color: ColorsAmiin.ink),
            bodyMedium:
                GoogleFonts.dmSans(fontSize: 14, color: ColorsAmiin.muted),
            titleLarge: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: ColorsAmiin.ink),
          ),
        ),
        routerConfig: appRouter,
      ),
    );
  }
}
