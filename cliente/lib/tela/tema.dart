import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

import '../nucleo/design.dart';

const corSemente = Color(0xFF5B8DEF);
const _origemSucesso = Color(0xFF2E9E5B);
const _origemAviso = Color(0xFFD99A1E);

const familiaTexto = 'Inter';
const familiaMono = 'JetBrains Mono';

class CorSemantica {
  const CorSemantica({required this.cor, required this.sobre, required this.container, required this.sobreContainer});

  final Color cor;
  final Color sobre;
  final Color container;
  final Color sobreContainer;

  factory CorSemantica.de(Color origem, Brightness brilho) {
    final harmonizada = Color(Blend.harmonize(origem.toARGB32(), corSemente.toARGB32()));
    final esquema = ColorScheme.fromSeed(
      seedColor: harmonizada,
      brightness: brilho,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    return CorSemantica(
      cor: esquema.primary,
      sobre: esquema.onPrimary,
      container: esquema.primaryContainer,
      sobreContainer: esquema.onPrimaryContainer,
    );
  }

  static CorSemantica lerp(CorSemantica a, CorSemantica b, double t) => CorSemantica(
        cor: Color.lerp(a.cor, b.cor, t)!,
        sobre: Color.lerp(a.sobre, b.sobre, t)!,
        container: Color.lerp(a.container, b.container, t)!,
        sobreContainer: Color.lerp(a.sobreContainer, b.sobreContainer, t)!,
      );
}

class CoresSemanticas extends ThemeExtension<CoresSemanticas> {
  const CoresSemanticas({required this.sucesso, required this.aviso});

  final CorSemantica sucesso;
  final CorSemantica aviso;

  factory CoresSemanticas.para(Brightness brilho) => CoresSemanticas(
        sucesso: CorSemantica.de(_origemSucesso, brilho),
        aviso: CorSemantica.de(_origemAviso, brilho),
      );

  static CoresSemanticas de(BuildContext context) =>
      Theme.of(context).extension<CoresSemanticas>() ?? CoresSemanticas.para(Theme.of(context).brightness);

  @override
  CoresSemanticas copyWith({CorSemantica? sucesso, CorSemantica? aviso}) =>
      CoresSemanticas(sucesso: sucesso ?? this.sucesso, aviso: aviso ?? this.aviso);

  @override
  CoresSemanticas lerp(CoresSemanticas? other, double t) {
    if (other == null) return this;
    return CoresSemanticas(
      sucesso: CorSemantica.lerp(sucesso, other.sucesso, t),
      aviso: CorSemantica.lerp(aviso, other.aviso, t),
    );
  }
}

Color corDoPapel(PapelDeEstado papel, ColorScheme cores, CoresSemanticas semanticas) => switch (papel) {
      PapelDeEstado.neutro || PapelDeEstado.cancelado => cores.onSurfaceVariant,
      PapelDeEstado.fila => cores.secondary,
      PapelDeEstado.andamento => cores.primary,
      PapelDeEstado.revisao => cores.tertiary,
      PapelDeEstado.aviso => semanticas.aviso.cor,
      PapelDeEstado.sucesso => semanticas.sucesso.cor,
      PapelDeEstado.erro => cores.error,
    };

Color corDoEstado(BuildContext context, String? estado) =>
    corDoPapel(papelDoEstado(estado), Theme.of(context).colorScheme, CoresSemanticas.de(context));

TextStyle? _semTracking(TextStyle? estilo, [FontWeight? peso]) =>
    estilo?.copyWith(letterSpacing: 0, fontWeight: peso ?? estilo.fontWeight);

TextTheme _texto(TextTheme base) => base.copyWith(
      displayLarge: _semTracking(base.displayLarge),
      displayMedium: _semTracking(base.displayMedium),
      displaySmall: _semTracking(base.displaySmall),
      headlineLarge: _semTracking(base.headlineLarge),
      headlineMedium: _semTracking(base.headlineMedium),
      headlineSmall: _semTracking(base.headlineSmall, FontWeight.w500),
      titleLarge: _semTracking(base.titleLarge, FontWeight.w500),
      titleMedium: _semTracking(base.titleMedium, FontWeight.w600),
      titleSmall: _semTracking(base.titleSmall),
      bodyLarge: _semTracking(base.bodyLarge),
      bodyMedium: _semTracking(base.bodyMedium),
      bodySmall: _semTracking(base.bodySmall),
      labelLarge: _semTracking(base.labelLarge),
      labelMedium: _semTracking(base.labelMedium),
      labelSmall: _semTracking(base.labelSmall),
    );

ThemeData tema(Brightness brilho) {
  final cores = ColorScheme.fromSeed(
    seedColor: corSemente,
    brightness: brilho,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  final base = ThemeData(colorScheme: cores, fontFamily: familiaTexto, useMaterial3: true);
  return base.copyWith(
    textTheme: _texto(base.textTheme),
    iconTheme: base.iconTheme.copyWith(grade: brilho == Brightness.dark ? -25 : 0),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    scaffoldBackgroundColor: cores.surface,
    canvasColor: cores.surface,
    dividerColor: cores.outlineVariant,
    dividerTheme: DividerThemeData(color: cores.outlineVariant, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: cores.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cores.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      height: 80,
    ),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: cores.surfaceContainer),
    drawerTheme: DrawerThemeData(backgroundColor: cores.surfaceContainerLow, surfaceTintColor: Colors.transparent),
    cardTheme: CardThemeData(
      color: cores.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Raios.md),
        side: BorderSide(color: cores.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: Espacos.esp3, vertical: Espacos.esp3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Raios.sm),
        borderSide: BorderSide(color: cores.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Raios.sm),
        borderSide: BorderSide(color: cores.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Raios.sm),
        borderSide: BorderSide(color: cores.primary, width: 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cores.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Raios.xl)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cores.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Raios.sm)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cores.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Raios.lg))),
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    extensions: [CoresSemanticas.para(brilho)],
  );
}

final temaClaro = tema(Brightness.light);
final temaEscuro = tema(Brightness.dark);

void registrarLicencasDasFontes() {
  LicenseRegistry.addLicense(() async* {
    for (final (familia, arquivo) in [(familiaTexto, 'Inter-OFL.txt'), (familiaMono, 'JetBrainsMono-OFL.txt')]) {
      yield LicenseEntryWithLineBreaks([familia], await rootBundle.loadString('assets/fonts/$arquivo'));
    }
  });
}
