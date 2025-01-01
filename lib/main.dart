import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ollama_dart/ollama_dart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;
// ----------------- HIVE imports --------------------
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

// --------------------------------------------------
// 0) ChatSession and provider for multiple sessions
// --------------------------------------------------
class ChatSession {
  final String id;
  String title;            // first user message
  List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
  });

  // Convert to Map for saving into Hive
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'messages': messages
          .map((m) => {
                'text': m.text,
                'imageData': m.imageData,
                'isUser': m.isUser,
              })
          .toList(),
    };
  }

  // Convert from Map
  factory ChatSession.fromMap(Map<String, dynamic> map) {
    return ChatSession(
      id: map['id'],
      title: map['title'] ?? '',
      messages: (map['messages'] as List<dynamic>)
          .map((msg) => ChatMessage(
                text: msg['text'] ?? '',
                imageData: msg['imageData'] != null
                    ? Uint8List.fromList(List<int>.from(msg['imageData']))
                    : null,
                isUser: msg['isUser'] ?? false,
              ))
          .toList(),
    );
  }
}

/// Provider to handle creating/loading/saving ChatSession objects
class ChatSessionsProvider extends ChangeNotifier {
  List<ChatSession> _sessions = [];
  List<ChatSession> get sessions => _sessions;

  late Box<dynamic> _chatsBox;

  Future<void> init() async {
    _chatsBox = await Hive.openBox('chats');
    _loadSessionsFromHive();
  }

  // Called once at startup
  void _loadSessionsFromHive() {
    final List<dynamic> stored = _chatsBox.get('sessions', defaultValue: []);
    _sessions = stored
        .map((item) => ChatSession.fromMap(item as Map<String, dynamic>))
        .toList();
    notifyListeners();
  }

  // Save entire sessions list to Hive
  Future<void> _saveSessionsToHive() async {
    final List<Map<String, dynamic>> asMaps =
        _sessions.map((s) => s.toMap()).toList();
    await _chatsBox.put('sessions', asMaps);
  }

  // Create new session with blank messages
  Future<ChatSession> createNewSession() async {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    ChatSession newSession =
        ChatSession(id: newId, title: 'Untitled', messages: []);
    _sessions.insert(0, newSession);
    await _saveSessionsToHive();
    notifyListeners();
    return newSession;
  }

  // Get existing session
  ChatSession? getSessionById(String id) {
    try {
      return _sessions.firstWhere((s) => s.id == id);
    } catch (e) {
      return null;
    }
  }

  // Add a message to a session
  Future<void> addMessage({
    required String sessionId,
    required ChatMessage message,
  }) async {
    final session = getSessionById(sessionId);
    if (session == null) return;

    // If session has no user messages yet, let's set the title
    if (session.title == 'Untitled' && message.isUser && message.text.isNotEmpty) {
      session.title = message.text;
    }

    session.messages.add(message);
    await _saveSessionsToHive();
    notifyListeners();
  }

  // Overwrite the last bot message text (streaming tokens)
  Future<void> updateLastBotMessage({
    required String sessionId,
    required String newText,
  }) async {
    final session = getSessionById(sessionId);
    if (session == null) return;
    if (session.messages.isEmpty) return;

    session.messages.last.text = newText;
    // Because we are streaming tokens, let's NOT overkill saving every token.
    // In a real app, you might do a debounce. Here, let's skip immediate save
    notifyListeners();
  }

  // Finalize the streaming message
  Future<void> finalizeMessage(String sessionId) async {
    await _saveSessionsToHive();
  }
}

// --------------------------------------------------
// 1) SettingsProvider & ThemeProvider
// --------------------------------------------------
class SettingsProvider extends ChangeNotifier {
  String _ollamaServerURI;
  String _systemPrompt;

  SettingsProvider({
    required String initialOllamaServerURI,
    required String initialSystemPrompt,
  })  : _ollamaServerURI = initialOllamaServerURI,
        _systemPrompt = initialSystemPrompt;

  String get ollamaServerURI => _ollamaServerURI;
  String get systemPrompt => _systemPrompt;

  set ollamaServerURI(String val) {
    _ollamaServerURI = val;
    notifyListeners();
  }

  set systemPrompt(String val) {
    _systemPrompt = val;
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
  final settingsBox = await Hive.openBox('settings');

  // Pull whatever was last saved, or fallback to a default
  final savedServerURI = settingsBox.get('serverURI', defaultValue: 'http://xyz:11434');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(
            initialOllamaServerURI: savedServerURI, initialSystemPrompt: 'Be nice',
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ChatSessionsProvider()..init(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final chatSessionsProvider = context.watch<ChatSessionsProvider>();

    // We'll pick the first session if it exists, else create a new one
    final sessions = chatSessionsProvider.sessions;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Autarch',
      theme: themeProvider.themeData,
      // Instead of 'home: const HomePage()', we directly load OllamaChatPage
      home: sessions.isEmpty
          ? FutureBuilder<ChatSession>(
              future: chatSessionsProvider.createNewSession(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  final newSession = snapshot.data;
                  if (newSession == null) {
                    return const Scaffold(
                      body: Center(child: Text("Error creating session")),
                    );
                  }
                  return OllamaChatPage(sessionId: newSession.id);
                } else {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
              },
            )
          : OllamaChatPage(sessionId: sessions[0].id),
    );
  }
}

// --------------------------------------------------
// 2A) HomePage - (NO LONGER USED, but we keep it here for reference)
// --------------------------------------------------
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final chatSessionsProvider = context.watch<ChatSessionsProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final isLight = themeProvider.isLightMode;
    final appBarColor = isLight ? Colors.white : Colors.black;
    final iconColor = isLight ? Colors.black : Colors.white;
    final textColor = isLight ? Colors.black : Colors.white;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: appBarColor,
        iconTheme: IconThemeData(color: iconColor),
        title: Row(
          children: [
            Text(
              'Autarch - Chat Sessions',
              style: GoogleFonts.roboto(
                color: textColor,
                fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              // Create a new session
              final newSession = await chatSessionsProvider.createNewSession();
              // Navigate to that session's chat page
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OllamaChatPage(sessionId: newSession.id),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: chatSessionsProvider.sessions.length,
        itemBuilder: (context, index) {
          final session = chatSessionsProvider.sessions[index];
          return ListTile(
            title: Text(
              session.title == 'Untitled' ? '(New Chat)' : session.title,
              style: TextStyle(color: textColor),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OllamaChatPage(sessionId: session.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// --------------------------------------------------
// 3) Chat Page
// --------------------------------------------------
class OllamaChatPage extends StatefulWidget {
  final String sessionId;
  const OllamaChatPage({super.key, required this.sessionId});

  @override
  _OllamaChatPageState createState() => _OllamaChatPageState();
}

class _OllamaChatPageState extends State<OllamaChatPage> {
  final _controller = TextEditingController();
  bool _isLoading = false;

  // Instead of local list, we'll pull from the provider
  ChatSession? _currentSession;

  // User-configurable settings
  String serverURI = '';
  String _systemPrompt = '';
  String _defaultModel = ''; // default selection

  // The list of all AI model options
  late List<String> _modelOptions = [];

  late OllamaClient client;
  late bool _isModelListPossible = false;

 @override
  void initState() {
    super.initState();
    print(_defaultModel);
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    _systemPrompt = settingsProvider.systemPrompt;
    serverURI = settingsProvider.ollamaServerURI;

    // Define a default URI
    const String defaultURI = 'https://default.server.com';

    // Use the provided URI or fallback to the default
    final uriToUse = serverURI.isNotEmpty ? serverURI : defaultURI;

    // Ensure '/api' is appended only once
    final baseUri = uriToUse.endsWith('/api') ? uriToUse : '$uriToUse/api';

    client = OllamaClient(baseUrl: baseUri);

    // Load the session from ChatSessionsProvider
    final chatSessionsProvider =
        Provider.of<ChatSessionsProvider>(context, listen: false);
    _currentSession = chatSessionsProvider.getSessionById(widget.sessionId);

    // Fetch model options after initializing the client
    fetchTags(baseUri);
  }




  Future<void> clearHiveBox() async {
    final box = Hive.box('settings'); 
    await box.clear();
    debugPrint('Hive box cleared!');
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
        final chatSessionsProvider =
            Provider.of<ChatSessionsProvider>(context, listen: false);
        await chatSessionsProvider.addMessage(
          sessionId: widget.sessionId,
          message: ChatMessage(
            text: '',
            imageData: bytes,
            isUser: true,
          ),
        );
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
        final chatSessionsProvider =
            Provider.of<ChatSessionsProvider>(context, listen: false);
        await chatSessionsProvider.addMessage(
          sessionId: widget.sessionId,
          message: ChatMessage(
            text: '',
            imageData: bytes,
            isUser: true,
          ),
        );
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
          final chatSessionsProvider =
              Provider.of<ChatSessionsProvider>(context, listen: false);

          if (kIsWeb) {
            final bytes = pickedFile.bytes;
            if (bytes != null) {
              await chatSessionsProvider.addMessage(
                sessionId: widget.sessionId,
                message: ChatMessage(
                  text: '',
                  imageData: bytes,
                  isUser: true,
                ),
              );
            }
          } else {
            if (pickedFile.path != null) {
              final file = File(pickedFile.path!);
              final bytes = await file.readAsBytes();
              await chatSessionsProvider.addMessage(
                sessionId: widget.sessionId,
                message: ChatMessage(
                  text: '',
                  imageData: bytes,
                  isUser: true,
                ),
              );
            }
          }
        } else {
          // Some other file
          final chatSessionsProvider =
              Provider.of<ChatSessionsProvider>(context, listen: false);
          await chatSessionsProvider.addMessage(
            sessionId: widget.sessionId,
            message: ChatMessage(
              text: '[Uploaded File: ${pickedFile.name}]',
              imageData: null,
              isUser: true,
            ),
          );
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
                                settingsProvider.ollamaServerURI =
                                    serverUriController.text;

                                setState(() {
                                  _systemPrompt = systemPromptController.text;
                                  _defaultModel = tempSelectedModel;
                                  print("Server URI: ${serverUriController.text}");
                                  client = OllamaClient(
                                    baseUrl:
                                        '${settingsProvider.ollamaServerURI}/api',
                                  );
                                });
                                // Update theme
                                themeProvider.isLightMode = tempIsLightMode;
                                // Refresh the model list
                                fetchTags(serverUriController.text);

                                // ---------- SAVE to HIVE ----------
                                final box = Hive.box('settings');
                                await box.put('modelOptions', _modelOptions);
                                await box.put('defaultModel', _defaultModel);
                                await box.put('systemPrompt', _systemPrompt);
                                await box.put(
                                    'serverURI', serverUriController.text);

                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
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
                            _isModelListPossible
                                ? DropdownButton<String>(
                                    value: tempSelectedModel,
                                    onChanged: (String? newValue) {
                                      if (newValue == null) return;
                                      setStateDialog(() {
                                        tempSelectedModel = newValue;
                                      });
                                    },
                                    items:
                                        _modelOptions.map((String modelName) {
                                      return DropdownMenuItem<String>(
                                        value: modelName,
                                        child: Text(modelName),
                                      );
                                    }).toList(),
                                  )
                                : const Text('None available'),
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
  // 3C) Streaming chat
  // --------------------------------------------------
Future<void> _sendMessage(String messageText) async {
  if (messageText.isEmpty) return;
  setState(() {
    _isLoading = true;
  });

  // Access the existing SettingsProvider
  final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
  _defaultModel = Hive.box('settings').get('defaultModel', defaultValue: '');

  // Add user message to the session
  final chatSessionsProvider =
      Provider.of<ChatSessionsProvider>(context, listen: false);
  await chatSessionsProvider.addMessage(
    sessionId: widget.sessionId,
    message: ChatMessage(text: messageText, isUser: true),
  );

  // Create an empty botMessage to hold partial tokens
  final botMessage = ChatMessage(text: '', isUser: false);
  await chatSessionsProvider.addMessage(
    sessionId: widget.sessionId,
    message: botMessage,
  );

  final stream = client.generateCompletionStream(
    request: GenerateCompletionRequest(
      model: _defaultModel,
      prompt: settingsProvider.systemPrompt.isNotEmpty
          ? "${settingsProvider.systemPrompt}\n\nUser: $messageText"
          : messageText,
    ),
  );

  try {
    await for (final res in stream) {
      final newText = botMessage.text + (res.response ?? '');
      await chatSessionsProvider.updateLastBotMessage(
        sessionId: widget.sessionId,
        newText: newText,
      );
    }
  } catch (e) {
    await chatSessionsProvider.updateLastBotMessage(
      sessionId: widget.sessionId,
      newText: 'Error: $e',
    );
  } finally {
    await chatSessionsProvider.finalizeMessage(widget.sessionId);
    setState(() {
      _isLoading = false;
    });
  }
  _controller.clear();
}


Future<void> fetchTags(String url) async {
  print('Fetching tags from: $url');
  print('..................................................');
   print('..................................................');
    print('..................................................');
     print('..................................................');
      print('..................................................');
       print('..................................................');

  final Uri uri = Uri.parse('$url/api/tags'); // Adjust endpoint as needed

  try {
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      Map<String, dynamic> jsonData = json.decode(response.body);
      List<dynamic> models = jsonData['models'];
      List<String> modelNames =
          models.map((model) => model['name'] as String).toList();

      setState(() {
        print("..........................");
        print('Fetched models: $modelNames');
        _modelOptions = modelNames;
        _isModelListPossible = true;
        if (_modelOptions.isNotEmpty) {
          _defaultModel = _modelOptions[0];
        }
      });
    } else {
      debugPrint("Error in fetchTags: ${response.statusCode}");
      setState(() {
        _isModelListPossible = false;
      });
    }
  } catch (e) {
    debugPrint("Exception while fetching tags: $e");
    setState(() {
      _isModelListPossible = false;
    });
  } finally {
    // Save updated values in Hive
    final box = Hive.box('settings');
    await box.put('modelOptions', _modelOptions);
    await box.put('defaultModel', _defaultModel);
    await box.put('systemPrompt', _systemPrompt);
    await box.put('serverURI', url);
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
    final themeProvider = context.watch<ThemeProvider>();
    final isLight = themeProvider.isLightMode;

    final appBarColor = isLight ? Colors.white : Colors.black;
    final iconColor = isLight ? Colors.black : Colors.white;
    final textColor = isLight ? Colors.black : Colors.white;
    final borderColor = isLight ? Colors.black : Colors.white;

    // Re-fetch the current session from provider in case it changed
    final chatSessionsProvider = context.watch<ChatSessionsProvider>();
    _currentSession = chatSessionsProvider.getSessionById(widget.sessionId);

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: appBarColor,
          iconTheme: IconThemeData(color: iconColor),
          title: Row(
            children: [
              Text(
                'Autarch',
                style: GoogleFonts.roboto(
                  color: textColor,
                  fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
                ),
              ),
              const SizedBox(width: 16),
              if (_modelOptions.isNotEmpty)
                DropdownButton<String>(
                  dropdownColor: isLight ? Colors.white : Colors.grey[800],
                  iconEnabledColor: iconColor,
                  value: _defaultModel.isNotEmpty
                      ? _defaultModel
                      : _modelOptions[0],
                  items: _modelOptions.map((String modelName) {
                    return DropdownMenuItem<String>(
                      value: modelName,
                      child: Text(modelName, style: TextStyle(color: textColor)),
                    );
                  }).toList(),
                  onChanged: (String? newValue) async {
                    if (newValue == null) return;
                    setState(() {
                      _defaultModel = newValue;
                    });

                    // Persist in Hive
                    final box = Hive.box('settings');
                    await box.put('defaultModel', _defaultModel);
                  },
                ),
            ],
          ),
          // The "New Chat Page" icon in *this* page can also open a fresh chat
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_document),
              onPressed: () async {
                // Create a new session
                final newSession =
                    await chatSessionsProvider.createNewSession();
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          OllamaChatPage(sessionId: newSession.id),
                    ),
                  );
                }
              },
            ),
          ],
          bottomOpacity: 1,
          shape: LinearBorder.bottom(
            side: BorderSide(color: borderColor, width: 1.0),
          ),
        ),
        // Drawer: list out existing chat sessions
        drawer: Drawer(
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // Label
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 8.0),
                      child: Text(
                        'Your Chats',
                        style: GoogleFonts.roboto(
                          color: textColor,
                          fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
                        ),
                      ),
                    ),
                    const Divider(),
                    for (final session in chatSessionsProvider.sessions)
                      ListTile(
                        title: Text(
                          session.title == 'Untitled'
                              ? '(New Chat)'
                              : session.title,
                          style: TextStyle(color: textColor),
                        ),
                        onTap: () {
                          Navigator.pop(context); // close drawer
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  OllamaChatPage(sessionId: session.id),
                            ),
                          );
                        },
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
                    itemCount: _currentSession?.messages.length ?? 0,
                    itemBuilder: (context, index) {
                      final message = _currentSession!.messages[index];
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
                                  hintStyle: TextStyle(
                                    color: textColor.withOpacity(0.6),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Row of attach vs. send
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // Attach files/images
                                  IconButton(
                                    icon: Icon(Icons.attach_file,
                                        color: iconColor),
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
                                    onPressed: () =>
                                        _sendMessage(_controller.text),
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
// 1) ChatMessage model
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
// 2) Custom CopyCodeIcon widget (Stateful)
// --------------------------------------------------
class CopyCodeIcon extends StatefulWidget {
  final String codeText;

  const CopyCodeIcon({super.key, required this.codeText});

  @override
  State<CopyCodeIcon> createState() => _CopyCodeIconState();
}

class _CopyCodeIconState extends State<CopyCodeIcon> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copyText() async {
    // Copy text to clipboard
    await Clipboard.setData(ClipboardData(text: widget.codeText));

    // Update icon state to "copied"
    setState(() {
      _copied = true;
    });

    // Revert icon back to "copy" after 5 seconds
    _timer = Timer(const Duration(seconds: 5), () {
      setState(() {
        _copied = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _copied ? Icons.check : Icons.copy,
        color: Colors.black,
      ),
      onPressed: _copyText,
      tooltip: _copied ? 'Copied!' : 'Copy code',
    );
  }
}

// --------------------------------------------------
// 3) Custom CodeBlockBuilder
// --------------------------------------------------
class CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final codeText = element.textContent;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: SelectableText(
              codeText,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: CopyCodeIcon(codeText: codeText),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// 4) ChatBubble widget
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
      contentWidget = MarkdownBody(
        data: message.text.trim(),
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(color: textColor),
          codeblockDecoration: const BoxDecoration(),
          code: TextStyle(color: textColor, fontFamily: 'monospace'),
        ),
        builders: {
          'blockquote': CodeBlockBuilder(),
        },
        onTapLink: (text, href, title) {
          if (href != null) {
            // Implement any link handling if needed
          }
        },
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
