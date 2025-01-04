import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AutarchService {
  late bool isEndpointSet = false;

  // Singleton pattern (optional, if you want a single instance)
  static final AutarchService _instance = AutarchService._internal();

  factory AutarchService() {
    return _instance;
  }

  AutarchService._internal();

  Future<bool> checkIfEndpointSet(String url) async {
    print('Checking endpoint: $url');
    final Uri uri = Uri.parse('$url/tags');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        print("Endpoint is set.");
        isEndpointSet = true;
        return isEndpointSet;
      } else {
        debugPrint(
            'Failed to fetch tags. Status code: ${response.statusCode}. Body: ${response.body}');
        isEndpointSet = false;
      }
    } catch (e) {
      debugPrint("Exception while fetching tags: $e");
      isEndpointSet = false;
    }
    return isEndpointSet;
  }
}
