import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/home/presentation/home_page.dart';
import 'theme/app_theme.dart';

class NoDopamineApp extends StatelessWidget {
  const NoDopamineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'No Dopamine',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light,
      home: const HomePage(),
    );
  }
}
