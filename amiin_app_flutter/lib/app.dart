import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'navigation/app_router.dart';
import 'services/auth_service.dart';
import 'services/chat_controller.dart';
import 'services/settings_service.dart';
import 'theme/themes.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatController()),
        ChangeNotifierProvider.value(value: settingsService),
        ChangeNotifierProvider.value(value: authService),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settings, _) {
          final variant = AmiinThemeVariantExt.fromId(settings.themeVariant);
          return MaterialApp.router(
            title: 'Amiin',
            locale: Locale(settings.language),
            supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            // Un seul thème par variante — chaque variante porte sa propre
            // brightness (nuit = dark, les trois autres = light).
            theme: AmiinThemes.forVariant(variant, settings.font),
            routerConfig: appRouter,
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: TextScaler.linear(settings.textScale),
                ),
                child: child!,
              );
            },
          );
        },
      ),
    );
  }
}
