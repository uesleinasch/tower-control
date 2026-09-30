import 'package:flutter/material.dart';

const _acento = Color(0xFF5B8DEF);
const perigo = Color(0xFFE05A5A);

ThemeData _base(ColorScheme cores, Color fundo, Color painel, Color borda) => ThemeData(
      colorScheme: cores,
      scaffoldBackgroundColor: fundo,
      canvasColor: fundo,
      dividerColor: borda,
      dividerTheme: DividerThemeData(color: borda, space: 1, thickness: 1),
      appBarTheme: AppBarTheme(backgroundColor: painel, surfaceTintColor: Colors.transparent, elevation: 0),
      navigationBarTheme: NavigationBarThemeData(backgroundColor: painel, height: 64),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: painel,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: borda)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: borda)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: _acento)),
      ),
      useMaterial3: true,
    );

final temaEscuro = _base(
  ColorScheme.fromSeed(
    seedColor: _acento,
    brightness: Brightness.dark,
    surface: const Color(0xFF171B25),
    surfaceContainerHighest: const Color(0xFF1E2330),
    onSurface: const Color(0xFFE4E8F1),
    onSurfaceVariant: const Color(0xFF8B93A7),
    primary: _acento,
    error: perigo,
  ),
  const Color(0xFF10131A),
  const Color(0xFF171B25),
  const Color(0xFF2A3040),
);

final temaClaro = _base(
  ColorScheme.fromSeed(
    seedColor: _acento,
    surface: const Color(0xFFFFFFFF),
    surfaceContainerHighest: const Color(0xFFEEF1F6),
    onSurface: const Color(0xFF1A1F2B),
    onSurfaceVariant: const Color(0xFF5D6578),
    primary: const Color(0xFF3D6FD6),
    error: const Color(0xFFC43D3D),
  ),
  const Color(0xFFF5F7FA),
  const Color(0xFFFFFFFF),
  const Color(0xFFDDE2EA),
);
