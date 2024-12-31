import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ollama_dart/ollama_dart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
// ----------------- HIVE imports --------------------
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

// --------------------------------------------------
// 1) SettingsProvider & ThemeProvider
// --------------------------------------------------
class SettingsProvider extends ChangeNotifier {
  String _ollamaServerURI = 'http://xyz:11434'; // default value
  String get ollamaServerURI => _ollamaServerURI;
  set ollamaServerURI(String val) {
    _ollamaServerURI = val;
    notifyListeners();
  }
}

class ThemeProvider extends ChangeNotifier {
  bool _isLightMode = true; // default is light mode

  bool get isLightMode => _isLightMode;

  set isLightMode(bool newValue) {
    _isLightMode = newValue;
    notifyListeners();
  }

  ThemeData get themeData {
    if (_isLightMode) {
      return ThemeData.light().copyWith(
        scaffoldBackgroundColor: Colors.white,
      );
    } else {
      return ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1B1B1D),
      );
    }
  }
}

// --------------------------------------------------
// 2) Main Entry
// --------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize HIVE
  await Hive.initFlutter();
  // Open a box for storing settings
  await Hive.openBox('settings');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Autarch LLM',
      theme: themeProvider.themeData,
      home: const OllamaChatPage(),
    );
  }
}

// --------------------------------------------------
// 3) Chat Page
// --------------------------------------------------
class OllamaChatPage extends StatefulWidget {
  const OllamaChatPage({super.key});

  @override
  _OllamaChatPageState createState() => _OllamaChatPageState();
}

class _OllamaChatPageState extends State<OllamaChatPage> {
  final _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  // User-configurable settings
  String _systemPrompt = '';
  String _defaultModel = ''; // default selection

  // The list of all AI model options
  late List<String> _modelOptions = [];

  late OllamaClient client;
  late OllamaClient clientModel;
  late bool _isModelListPossible = false;
  @override
  void initState() {
    super.initState();

    // 1) Load from Hive first
    final box = Hive.box('settings');
    final savedModelOptions = box.get('modelOptions', defaultValue: []);
    final savedDefaultModel = box.get('defaultModel', defaultValue: '');
    final savedSystemPrompt = box.get('systemPrompt', defaultValue: '');

    // Make sure we cast appropriately
    _modelOptions.addAll((savedModelOptions as List).cast<String>());
    _defaultModel = savedDefaultModel;
    _systemPrompt = savedSystemPrompt;

    // 2) Then set up the Ollama clients
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    client = OllamaClient(baseUrl: settingsProvider.ollamaServerURI);
    clientModel = OllamaClient(baseUrl: '${settingsProvider.ollamaServerURI}/api');
  }
  
  Future<void> clearHiveBox() async {
  final box = Hive.box('settings'); // Replace 'settings' with your box name
  await box.clear();
  print('Hive box cleared!');
  }

  // --------------------------------------------------
  // 3A) Image/File picking logic
  // --------------------------------------------------
  Future<void> _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile =
          await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _messages.add(ChatMessage(
            text: '',
            imageData: bytes,
            isUser: true,
          ));
        });
      }
    } catch (e) {
      debugPrint('Error picking image from gallery: $e');
    }
  }

  Future<void> _takePhoto() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not supported on web')),
      );
      return;
    }
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        final bytes = await File(photo.path).readAsBytes();
        setState(() {
          _messages.add(ChatMessage(
            text: '',
            imageData: bytes,
            isUser: true,
          ));
        });
      }
    } catch (e) {
      debugPrint('Error taking photo: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.isNotEmpty) {
        final pickedFile = result.files.single;

        // If it's an image
        if (pickedFile.extension != null &&
            ['png', 'jpg', 'jpeg']
                .contains(pickedFile.extension!.toLowerCase())) {
          if (kIsWeb) {
            final bytes = pickedFile.bytes;
            if (bytes != null) {
              setState(() {
                _messages.add(ChatMessage(
                  text: '',
                  imageData: bytes,
                  isUser: true,
                ));
              });
            }
          } else {
            if (pickedFile.path != null) {
              final file = File(pickedFile.path!);
              final bytes = await file.readAsBytes();
              setState(() {
                _messages.add(ChatMessage(
                  text: '',
                  imageData: bytes,
                  isUser: true,
                ));
              });
            }
          }
        } else {
          // Some other file
          setState(() {
            _messages.add(ChatMessage(
              text: '[Uploaded File: ${pickedFile.name}]',
              imageData: null,
              isUser: true,
            ));
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  // --------------------------------------------------
  // 3B) Settings Dialog
  // --------------------------------------------------
  Future<void> _openSettingsDialog() async {
    final themeProvider = context.read<ThemeProvider>();
    final settingsProvider = context.read<SettingsProvider>();

    final TextEditingController serverUriController =
        TextEditingController(text: settingsProvider.ollamaServerURI);
    final TextEditingController systemPromptController =
        TextEditingController(text: _systemPrompt);

    String tempSelectedModel = _defaultModel;
    bool tempIsLightMode = themeProvider.isLightMode;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: !kIsWeb
              ? const EdgeInsets.all(0.0)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
          child: StatefulBuilder(
            builder: (BuildContext context, setStateDialog) {
              return SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Settings',
                              style: GoogleFonts.roboto(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                // Save the server URI to the provider
                                settingsProvider.ollamaServerURI =
                                    serverUriController.text;
                                setState(() {
                                  _systemPrompt = systemPromptController.text;
                                  _defaultModel = tempSelectedModel;
                                  client = OllamaClient(
                                    baseUrl:
                                        '${settingsProvider.ollamaServerURI}/api',
                                  );
                                });
                                // Update theme
                                themeProvider.isLightMode = tempIsLightMode;
                                fetchTags(serverUriController.text);
                                // request(serverUriController.text);
                                // ---------- SAVE to HIVE ----------
                                final box = Hive.box('settings');
                                await box.put('modelOptions', _modelOptions);
                                await box.put('defaultModel', _defaultModel);
                                await box.put('systemPrompt', _systemPrompt);

                                Navigator.of(context).pop();
                              },
                              child: Text(
                                'Save',
                                style: GoogleFonts.roboto(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(thickness: 1),

                        // OLLAMA Section
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Ollama',
                            style: GoogleFonts.roboto(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        TextField(
                          controller: serverUriController,
                          decoration: const InputDecoration(
                            labelText:
                                'Ollama server URI: https://xyz.ngrok-free.app',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: systemPromptController,
                          decoration: const InputDecoration(
                            labelText: 'System prompt',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Default Model
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.pets, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Default Model',
                                  style: GoogleFonts.roboto(fontSize: 15),
                                ),
                              ],
                            ),
                            _isModelListPossible ? DropdownButton<String>(
                              value: tempSelectedModel,
                              onChanged: (String? newValue) {
                                if (newValue == null) return;
                                setStateDialog(() {
                                  tempSelectedModel = newValue;
                                });
                              },
                              items: _modelOptions.map((String modelName) {
                                return DropdownMenuItem<String>(
                                  value: modelName,
                                  child: Text(modelName),
                                );
                              }).toList(),
                            ) : Text('None available'),
                          ],
                        ),

                        // APP Section
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'APP',
                            style: GoogleFonts.roboto(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Appearance
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Appearance',
                              style: GoogleFonts.roboto(fontSize: 15),
                            ),
                            DropdownButton<bool>(
                              value: tempIsLightMode,
                              onChanged: (bool? newValue) {
                                if (newValue == null) return;
                                setStateDialog(() {
                                  tempIsLightMode = newValue;
                                });
                              },
                              items: const [
                                DropdownMenuItem<bool>(
                                  value: true,
                                  child: Text('Light'),
                                ),
                                DropdownMenuItem<bool>(
                                  value: false,
                                  child: Text('Dark'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(thickness: 1),

                        // Delete All Conversations
                        GestureDetector(
                          onTap: () {
                            // Implement your deletion logic
                            Navigator.of(context).pop();
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'Delete All Conversations',
                              style: TextStyle(fontSize: 15, color: Colors.red),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // --------------------------------------------------
  // 3C) Streaming chat (non-final text, so we can append)
  // --------------------------------------------------
  Future<void> _sendMessage(String messageText) async {
    if (messageText.isEmpty) return;
    setState(() {
      _messages.add(ChatMessage(text: messageText, isUser: true));
      _isLoading = true;
    });

    // Create an empty botMessage
    ChatMessage botMessage = ChatMessage(text: '', isUser: false);
    setState(() {
      _messages.add(botMessage);
    });

    final stream = client.generateCompletionStream(
      request: GenerateCompletionRequest(
        model: _defaultModel,
        prompt: _systemPrompt.isNotEmpty
            ? "$_systemPrompt\n\nUser: $messageText"
            : messageText,
      ),
    );

    try {
      await for (final res in stream) {
        setState(() {
          // Append partial tokens here
          botMessage.text = botMessage.text + (res.response ?? '');
        });
      }
    } catch (e) {
      setState(() {
        botMessage.text = 'You probably have not set up an endpoint';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
    _controller.clear();
  }

   Future<void> fetchTags(String url) async {
    print(url);
    final Uri uri = Uri.parse('$url/api/tags');

    try {
      final response = await http.get(
        uri,
        headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json' ,
        'ngrok-skip-browser-warning': 'true', 
        'Access-Control-Allow-Origin': 'https://autarch-llm.web.app/',
        'Access-Control-Allow-Methods': 'GET, POST',
        "Access-Control-Allow-Headers": "Origin, X-Requested-With, Content-Type, Accept, Authorization"
        },
      );

      if (response.statusCode == 200) {
        print(json.decode(response.body));
        Map<String, dynamic> jsonData = json.decode(response.body);
        List<dynamic> models = jsonData['models'];
        List<String> modelNames = models.map((model) => model['name'] as String).toList();
        print(modelNames);
        _modelOptions = modelNames;
        setState(() {
        _isModelListPossible = true;
        print(_modelOptions);
        });
        if (_modelOptions.isNotEmpty) {
          _defaultModel = _modelOptions[0];
        }
            }
      else{
        print("error");
      }
    } catch (e) {
      setState(() {
      
      });

          // Save updated values in Hive
    final box = Hive.box('settings');
    await box.put('modelOptions', _modelOptions);
    await box.put('defaultModel', _defaultModel);
    await box.put('systemPrompt', _systemPrompt);
    }
  }


  // --------------------------------------------------
  // 3D) Show popup of image upload options
  // --------------------------------------------------
  void _showImageOptionsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Images'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                // 1) Upload from gallery
                ListTile(
                  leading: const Icon(Icons.image),
                  title: const Text('Upload Image'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _pickImageFromGallery();
                  },
                ),
                // 2) Take Photo (mobile only)
                if (!kIsWeb)
                  ListTile(
                    leading: const Icon(Icons.camera_alt),
                    title: const Text('Take Photo'),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _takePhoto();
                    },
                  ),
                // 3) Upload any file
                ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: const Text('Upload File'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _pickFile();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------
  // 4) Build UI
  // --------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isLight = context.watch<ThemeProvider>().isLightMode;

    final appBarColor = isLight ? Colors.white : Colors.black;
    final iconColor = isLight ? Colors.black : Colors.white;
    final textColor = isLight ? Colors.black : Colors.white;
    final borderColor = isLight ? Colors.black : Colors.white;

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: appBarColor,
          iconTheme: IconThemeData(color: iconColor),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
    await clearHiveBox();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All settings have been cleared!')),
    );
  },
            ),
          ],
          title: Text(
            'Autarch LLM',
            style: GoogleFonts.roboto(
              color: textColor,
              fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
            ),
          ),
          bottomOpacity: 1,
          shape: LinearBorder.bottom(
            side: BorderSide(color: borderColor, width: 1.0),
          ),
        ),
        drawer: Drawer(
          child: Column(
            children: <Widget>[
              // Scrollable area
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 8.0),
                      child: Text(
                        'Today',
                        style: GoogleFonts.roboto(
                          color: textColor,
                          fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
                        ),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      title: Text('Chat 1', style: TextStyle(color: textColor)),
                      onTap: () => Navigator.pop(context),
                    ),
                    ListTile(
                      title: Text('Chat 2', style: TextStyle(color: textColor)),
                      onTap: () => Navigator.pop(context),
                    ),
                    ListTile(
                      title: Text('Chat 3', style: TextStyle(color: textColor)),
                      onTap: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Container(
                alignment: Alignment.center,
                margin: const EdgeInsets.only(bottom: 16.0, right: 16.0),
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: textColor,
                    side: BorderSide(color: borderColor, width: 0),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  onPressed: _openSettingsDialog,
                  child: const Text('Settings'),
                ),
              ),
            ],
          ),
        ),
        body: SelectionArea(
          child: Column(
            children: [
              // 1) Messages area
              Expanded(
                child: Container(
                  color: isLight ? Colors.white : const Color(0xFF1B1B1D),
                  padding: EdgeInsets.only(
                    left: kIsWeb ? 100.0 : 15.0,
                    right: kIsWeb ? 100.0 : 15.0,
                    top: kIsWeb ? 20.0 : 10.0,
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return ChatBubble(message: message, isLight: isLight);
                    },
                  ),
                ),
              ),

              if (_isLoading) const LinearProgressIndicator(),

              // 2) Bottom input area
              Padding(
                padding: EdgeInsets.only(
                  left: kIsWeb ? 100.0 : 15.0,
                  right: kIsWeb ? 100.0 : 15.0,
                  bottom: kIsWeb ? 20.0 : 10.0,
                ),
                child: Container(
                  color: isLight ? Colors.white : Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // The expanded Column
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          decoration: BoxDecoration(
                            border: Border.all(color: borderColor),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // The TextField
                              TextField(
                                controller: _controller,
                                onSubmitted: _sendMessage,
                                minLines: 1,
                                maxLines: 4,
                                textAlignVertical: TextAlignVertical.top,
                                style: TextStyle(color: textColor),
                                decoration: InputDecoration(
                                  hintText: 'Write something...',
                                  hintStyle:
                                      TextStyle(color: textColor.withOpacity(0.6)),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Row of attach vs. send
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // Attach files/images
                                  IconButton(
                                    icon: Icon(Icons.attach_file, color: iconColor),
                                    tooltip: 'Upload files/images',
                                    onPressed: _showImageOptionsDialog,
                                  ),

                                  // Send text
                                  IconButton(
                                    iconSize: 38,
                                    icon: !_isLoading
                                        ? Icon(Icons.arrow_circle_right_outlined,
                                            color: iconColor)
                                        : Icon(Icons.hourglass_top,
                                            color: iconColor),
                                    onPressed: () => _sendMessage(_controller.text),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------
// 5) ChatMessage (text is not final!)
// --------------------------------------------------
class ChatMessage {
  String text;
  final Uint8List? imageData; // for images
  final bool isUser;

  ChatMessage({
    required this.text,
    this.imageData,
    required this.isUser,
  });
}

// --------------------------------------------------
// 6) ChatBubble
// --------------------------------------------------
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isLight;

  const ChatBubble({super.key, required this.message, required this.isLight});

  @override
  Widget build(BuildContext context) {
    final alignment =
        message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final userBgColor = isLight ? Colors.blue[100]! : Colors.blueGrey[700]!;
    final botBgColor = isLight ? Colors.grey[200]! : Colors.blueGrey[800]!;
    final bgColor = message.isUser ? userBgColor : botBgColor;
    final textColor = isLight ? Colors.black : Colors.white;

    // If we have imageData, show it, otherwise show text
    Widget contentWidget;
    if (message.imageData != null) {
      contentWidget = SizedBox(
        width: 200,
        height: 200,
        child: Image.memory(
          message.imageData!,
          fit: BoxFit.cover,
        ),
      );
    } else {
      contentWidget = Text(
        message.text.trim(),
        style: TextStyle(color: textColor),
      );
    }

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: contentWidget,
        ),
      ],
    );
  }
}
