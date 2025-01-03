import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';

class ModelInformationPage extends StatefulWidget {
  final String modelName;
  final String url;
  const ModelInformationPage({super.key, required this.url, required this.modelName});

  @override
  _ModelInformationPageState createState() => _ModelInformationPageState();
}

class _ModelInformationPageState extends State<ModelInformationPage> {
  Map<String, dynamic>? modelInfo;
  bool isDarkMode = false; // Toggle for Dark Mode

  @override
  void initState() {
    super.initState();
    // Optionally, you can set isDarkMode based on system settings
    // isDarkMode = WidgetsBinding.instance.window.platformBrightness == Brightness.dark;
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
    // Define colors based on the theme
    final backgroundColor = isDarkMode ? Colors.black : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final appBarBorderColor = isDarkMode ? Colors.white : Colors.black;
    final dividerColor = isDarkMode ? Colors.white54 : Colors.black54;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        title: Text(
          'Model Information',
          style: GoogleFonts.spaceMono(
            textStyle: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.close, color: textColor),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Container(
            color: appBarBorderColor,
            height: 1.0,
          ),
        ),
      ),
      body: modelInfo == null
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(isDarkMode ? Colors.white : Colors.black),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoRow(
                    label: 'Name',
                    value: modelInfo!['name']?.toString() ?? 'N/A',
                    textColor: textColor,
                  ),
                  Divider(color: dividerColor),
                  InfoRow(
                    label: 'Modified At',
                    value: modelInfo!['modified_at']?.toString() ?? 'N/A',
                    textColor: textColor,
                  ),
                  Divider(color: dividerColor),
                  InfoRow(
                    label: 'Size',
                    value: modelInfo!['size']?.toString() ?? 'N/A',
                    textColor: textColor,
                  ),
                  Divider(color: dividerColor),
                  InfoRow(
                    label: 'Format',
                    value: modelInfo!['details']?['format']?.toString() ?? 'N/A',
                    textColor: textColor,
                  ),
                  Divider(color: dividerColor),
                  InfoRow(
                    label: 'Family',
                    value: modelInfo!['details']?['family']?.toString() ?? 'N/A',
                    textColor: textColor,
                  ),
                  Divider(color: dividerColor),
                  InfoRow(
                    label: 'Parameter Size',
                    value: modelInfo!['details']?['parameter_size']?.toString() ?? 'N/A',
                    textColor: textColor,
                  ),
                  Divider(color: dividerColor),
                  InfoRow(
                    label: 'Quantization Level',
                    value: modelInfo!['details']?['quantization_level']?.toString() ?? 'N/A',
                    textColor: textColor,
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: isDarkMode ? Colors.grey[800] : Colors.blue,
        child: Icon(
          isDarkMode ? Icons.wb_sunny : Icons.nightlight_round,
          color: isDarkMode ? Colors.yellow : Colors.white,
        ),
        onPressed: () {
          setState(() {
            isDarkMode = !isDarkMode;
          });
        },
        tooltip: isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color textColor;

  const InfoRow({
    Key? key,
    required this.label,
    required this.value,
    required this.textColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.spaceMono(
              textStyle: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.spaceMono(
                textStyle: TextStyle(
                  color: textColor,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
