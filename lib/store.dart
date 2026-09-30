import 'package:flutter/material.dart';
import 'database.dart';
import 'domain.dart';

class AppStore extends ChangeNotifier {
  AppStore(this.database);
  final AppDatabase database;
  Report report = const Report();
  List<Account> recent = [];
  String theme = 'system';
  int revision = 0;
  bool busy = false;
  ThemeMode get themeMode => ThemeMode.values.byName(theme);
  Future<void> load() async {
    report = await database.report();
    recent = await database.accounts(limit: 5);
    theme = await database.theme();
    revision++;
    notifyListeners();
  }

  Future<T> mutate<T>(Future<T> Function() action) async {
    if (busy) throw StateError('انتظري اكتمال العملية الحالية');
    busy = true;
    notifyListeners();
    try {
      final result = await action();
      await load();
      return result;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setTheme(String value) => mutate(() => database.setTheme(value));
}
