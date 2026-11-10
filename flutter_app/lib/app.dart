import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/stores.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

class CCloudApp extends StatelessWidget {
  const CCloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppServices.instance.settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final locale = const Locale('fa', 'IR');
        return MaterialApp(
          title: 'CCloud',
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: const [Locale('fa', 'IR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: switch (settings.appearance) {
            AppAppearance.system => ThemeMode.system,
            AppAppearance.dark => ThemeMode.dark,
            AppAppearance.light => ThemeMode.light,
          },
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(settings.fontScale),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: const AppShell(),
        );
      },
    );
  }
}
