import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:math' as Math; // Import math for size formatting

class ModelInformationPage extends StatefulWidget {
  final String modelName;
  final String url;
  final bool isDarkMode;
  const ModelInformationPage(
      {super.key, required this.url, required this.modelName, required this.isDarkMode});

  @override
  _ModelInformationPageState createState() => _ModelInformationPageState();
}

class _ModelInformationPageState extends State<ModelInformationPage> {
  Map<String, dynamic>? modelInfo;
  late bool isDarkMode; // Toggle for Dark Mode

  @override
  void initState() {
    super.initState();
    // Optionally, you can set isDarkMode based on system settings
    // isDarkMode = WidgetsBinding.instance.window.platformBrightness == Brightness.dark;
    isDarkMode = widget.isDarkMode;
    fetchModelInfo();
  }

  Future<void> fetchModelInfo() async {
    final Uri uri =
        Uri.parse('${widget.url}/tags'); // Adjust endpoint as needed

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

  bool _isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width > 600;
  }

  // Helper function to format size
  String formatSize(dynamic size) {
    if (size == null) return "N/A";
    double bytes;
    // Handle if size is a string or a number
    if (size is int) {
      bytes = size.toDouble();
    } else if (size is String) {
      bytes = double.tryParse(size) ?? 0.0;
    } else if (size is double) {
      bytes = size;
    } else {
      return "N/A";
    }

    if (bytes <= 0) return "0 B";
    const List<String> suffixes = ["B", "KB", "MB", "GB", "TB", "PB"];
    int i = (Math.log(bytes) / Math.log(1024)).floor();
    if (i >= suffixes.length) i = suffixes.length - 1; // Prevent overflow
    double sizeInUnit = bytes / Math.pow(1024, i);
    return "${sizeInUnit.toStringAsFixed(2)} ${suffixes[i]}";
  }

  @override
  Widget build(BuildContext context) {
    // Define colors based on the theme
    final backgroundColor = isDarkMode ? Colors.black : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final appBarBorderColor = isDarkMode ? Colors.white : Colors.black;
    final dividerColor = isDarkMode ? Colors.white54 : Colors.black54;
    final isDesktopView = _isDesktop(context);
    final logo = isDarkMode ? 'assets/autarch_dark.png' : 'assets/autarch.png';

    // Safely parse and format the 'modified_at' date
    String formattedModifiedAt = 'N/A';
    if (modelInfo != null && modelInfo!['modified_at'] != null) {
      try {
        // Adjust the date format pattern based on your date string
        DateTime modifiedAt =
            DateFormat("yyyy-MM-dd").parse(modelInfo!['modified_at']);
        formattedModifiedAt = DateFormat.yMMMMd().format(modifiedAt.toLocal());
      } catch (e) {
        print('Error parsing date: $e');
      }
    }

    // Format the size
    String formattedSize = formatSize(modelInfo != null ? modelInfo!['size'] : null);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        automaticallyImplyLeading: false,
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
                valueColor: AlwaysStoppedAnimation<Color>(
                    isDarkMode ? Colors.white : Colors.black),
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
                    value: formattedModifiedAt,
                    textColor: textColor,
                  ),
                  Divider(color: dividerColor),
                  InfoRow(
                    label: 'Size',
                    value: formattedSize,
                    textColor: textColor,
                  ),
                  Divider(color: dividerColor),
                  InfoRow(
                    label: 'Format',
                    value:
                        modelInfo!['details']?['format']?.toString() ?? 'N/A',
                    textColor: textColor,
                  ),
                  Divider(color: dividerColor),
                  InfoRow(
                    label: 'Family',
                    value:
                        modelInfo!['details']?['family']?.toString() ?? 'N/A',
                    textColor: textColor,
                  ),
                  Divider(color: dividerColor),
                  InfoRow(
                    label: 'Parameter Size',
                    value: modelInfo!['details']?['parameter_size']?.toString() ??
                        'N/A',
                    textColor: textColor,
                  ),
                  Divider(color: dividerColor),
                  InfoRow(
                    label: 'Quantization Level',
                    value: modelInfo!['details']?['quantization_level']
                            ?.toString() ??
                        'N/A',
                    textColor: textColor,
                  ),
                  // Add logo through
                  Divider(color: dividerColor),
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 30.0),
                      width: isDesktopView ? 150 : 120,
                      height: isDesktopView ? 150 : 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black,
                        image: DecorationImage(
                          image: AssetImage(logo),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: isDarkMode ? Colors.grey[800] : Colors.blue,
        onPressed: () {
          setState(() {
            isDarkMode = !isDarkMode;
          });
        },
        tooltip: isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
        child: Icon(
          isDarkMode ? Icons.wb_sunny : Icons.nightlight_round,
          color: isDarkMode ? Colors.yellow : Colors.white,
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color textColor;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    required this.textColor,
  });

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
                fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.spaceMono(
                textStyle: TextStyle(
                  color: textColor,
                  fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
