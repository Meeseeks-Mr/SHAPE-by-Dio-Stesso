import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'state/app_scope.dart';
import 'state/editor_model.dart';
import 'theme/shape_theme.dart';

/// Root widget. Owns the single [EditorModel] (shared by the splash and the
/// editor via [AppScope] mounted above the [Navigator]) and defines the light,
/// pastel, matte theme.
class ShapeApp extends StatefulWidget {
  const ShapeApp({super.key});

  @override
  State<ShapeApp> createState() => _ShapeAppState();
}

class _ShapeAppState extends State<ShapeApp> {
  final EditorModel _model = EditorModel();

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: ShapeColors.shapeBlue,
      brightness: Brightness.light,
    ).copyWith(
      surface: ShapeColors.glassTint,
      surfaceTint: ShapeColors.lavender,
    );

    return AppScope(
      model: _model,
      child: MaterialApp(
        title: 'Shape',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: ShapeColors.paper,
          colorScheme: scheme,
          useMaterial3: true,
          fontFamily: 'InstrumentSans',
          snackBarTheme: SnackBarThemeData(
            backgroundColor: ShapeColors.glassTint.withValues(alpha: 0.96),
            contentTextStyle:
                ShapeText.labelMD.copyWith(color: ShapeColors.primaryText),
            behavior: SnackBarBehavior.floating,
            elevation: 6,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
