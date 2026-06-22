import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Chichewa (`ny`) is not bundled in Flutter's built-in Material/Cupertino
/// localizations, so these delegates serve English strings for the framework
/// chrome (date pickers, tooltips, selection menus) when the locale is `ny`.
/// App-facing copy is still translated via easy_localization.
class NyMaterialLocalizations extends LocalizationsDelegate<MaterialLocalizations> {
  const NyMaterialLocalizations();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ny';

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(covariant LocalizationsDelegate<MaterialLocalizations> old) => false;
}

class NyCupertinoLocalizations extends LocalizationsDelegate<CupertinoLocalizations> {
  const NyCupertinoLocalizations();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ny';

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(covariant LocalizationsDelegate<CupertinoLocalizations> old) => false;
}
