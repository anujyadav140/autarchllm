import 'package:flutter/material.dart';

class SettingsProvider extends ChangeNotifier {
  String _ollamaServerURI = 'http://127.0.0.1:11434';

  String get ollamaServerURI => _ollamaServerURI;

  set ollamaServerURI(String newURI) {
    if (_ollamaServerURI != newURI) {
      _ollamaServerURI = newURI;
      notifyListeners();
    }
  }
}
