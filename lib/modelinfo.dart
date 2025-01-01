import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ModelInformationPage extends StatefulWidget {
  final String modelName;
  final String url;
  const ModelInformationPage({super.key, required this.url, required this.modelName});

  @override
  _ModelInformationPageState createState() => _ModelInformationPageState();
}

class _ModelInformationPageState extends State<ModelInformationPage> {
  Map<String, dynamic>? modelInfo;

  @override
  void initState() {
    super.initState();
    fetchModelInfo();
  }

  Future<void> fetchModelInfo() async {
    final Uri uri = Uri.parse('${widget.url}/tags'); // Adjust endpoint as needed

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      print('Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
          Map<String, dynamic> jsonData = json.decode(response.body);
        List<dynamic> models = jsonData['models'];
        for (var model in models) {
          if (model['name'] == widget.modelName) {
            setState(() {
              modelInfo = model;
            });
            break;
          }
        }
      } else {
        throw Exception('Failed to load model information');
      }
    } catch (e) {
      print('Error fetching model information: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Information'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: modelInfo == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Name: ${modelInfo!['name']}'),
                  Text('Modified At: ${modelInfo!['modified_at']}'),
                  Text('Size: ${modelInfo!['size']}'),
                  Text('Format: ${modelInfo!['details']['format']}'),
                  Text('Family: ${modelInfo!['details']['family']}'),
                  Text('Parameter Size: ${modelInfo!['details']['parameter_size']}'),
                  Text('Quantization Level: ${modelInfo!['details']['quantization_level']}'),
                ],
              ),
            ),
    );
  }
}