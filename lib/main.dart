import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, HttpClient;
import 'dart:typed_data';
import 'package:autarchllm/initial.dart';
import 'package:autarchllm/modelinfo.dart';
import 'package:autarchllm/services.dart';
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
// ----------------- HIVE imports --------------------
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

// --------------------------------------------------
// 0) ChatSession and provider for multiple sessions
// --------------------------------------------------
class ChatSession {
  final String id;
  String title; // first user message
  List<ChatMessage> messages;
  DateTime createdAt;

  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
  });

  // Convert to Map for saving into Hive
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'messages': messages
          .map((m) => {
                'text': m.text,
                'imageData': m.imageData != null ? m.imageData : null,
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
      createdAt: DateTime.parse(map['createdAt']),
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
  bool initialLoadUp = false;
  late Box<dynamic> _chatsBox;

  /// Initialize the provider by opening the Hive box and loading sessions
  Future<void> init() async {
    _chatsBox = await Hive.openBox('chats');
    _loadSessionsFromHive();
  }

  // Called once at startup
  void _loadSessionsFromHive() {
    try {
      final List<dynamic> stored = _chatsBox.get('sessions', defaultValue: []);
      _sessions = stored
          .map((item) => ChatSession.fromMap(Map<String, dynamic>.from(item)))
          .toList();
      // Sort sessions by createdAt descending
      _sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('Error loading sessions from Hive: $e');
      _sessions = [];
    }
    notifyListeners();
  }

  // Save entire sessions list to Hive
  Future<void> _saveSessionsToHive() async {
    try {
      final List<Map<String, dynamic>> asMaps =
          _sessions.map((s) => s.toMap()).toList();
      await _chatsBox.put('sessions', asMaps);
    } catch (e) {
      debugPrint('Error saving sessions to Hive: $e');
    }
  }

  // Create new session with blank messages
  Future<ChatSession> createNewSession() async {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    ChatSession newSession = ChatSession(
      id: newId,
      title: 'Untitled',
      messages: [],
      createdAt: DateTime.now(),
    );
    _sessions.insert(0, newSession);
    initialLoadUp = true;
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
    if (session.title == 'Untitled' &&
        message.isUser &&
        message.text.isNotEmpty) {
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

    notifyListeners();
  }

  // Finalize the streaming message
  Future<void> finalizeMessage(String sessionId) async {
    await _saveSessionsToHive();
  }

  // Delete all sessions
  Future<void> deleteAllSessions() async {
    _sessions.clear();
    await _saveSessionsToHive();
    notifyListeners();
  }

// Delete particular session
Future<void> deleteSession(String sessionId) async {
  _sessions.removeWhere((session) => session.id == sessionId);
  await _saveSessionsToHive();
  notifyListeners();
}
}

// --------------------------------------------------
// 1) SettingsProvider & ThemeProvider
// --------------------------------------------------
class SettingsProvider extends ChangeNotifier {
  String _ollamaServerURI;
  String _systemPrompt;
  String _defaultModel;
  int _contextWindow;

  SettingsProvider({
    required String initialOllamaServerURI,
    required String initialSystemPrompt,
    required String initialDefaultModel,
    required int initialContextWindow,
  })  : _ollamaServerURI = initialOllamaServerURI,
        _systemPrompt = initialSystemPrompt,
        _defaultModel = initialDefaultModel,
        _contextWindow = initialContextWindow;


  String get ollamaServerURI => _ollamaServerURI;
  String get systemPrompt => _systemPrompt;
  String get defaultModel => _defaultModel;
  int get contextWindow => _contextWindow;

  set ollamaServerURI(String val) {
    _ollamaServerURI = val;
    notifyListeners();
  }

  set systemPrompt(String val) {
    _systemPrompt = val;
    notifyListeners();
  }

  set defaultModel(String val) {
    _defaultModel = val;
    notifyListeners();
  }

  set contextWindow(int val) {
    _contextWindow = val;
    notifyListeners();
  }
}

class ThemeProvider extends ChangeNotifier {
  bool _isLightMode;

  ThemeProvider({required bool initialIsLightMode})
      : _isLightMode = initialIsLightMode;

  bool get isLightMode => _isLightMode;

  set isLightMode(bool newValue) {
    if (_isLightMode != newValue) {
      _isLightMode = newValue;
      notifyListeners();
    }
  }

  ThemeData get themeData {
    if (_isLightMode) {
      return ThemeData.light().copyWith(
        scaffoldBackgroundColor: Colors.white,
      );
    } else {
      return ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
      );
    }
  }
}

// --------------------------------------------------
// 2) Main Entry
// --------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize HIVE
  await Hive.initFlutter();

  // Open a box for storing settings
  final settingsBox = await Hive.openBox('settings');

  // Open a box for chats to ensure it's ready
  final chatsBox = await Hive.openBox('chats');

  // Instantiate ChatSessionsProvider and initialize it
  final chatSessionsProvider = ChatSessionsProvider();
  await chatSessionsProvider.init();

  // Pull whatever was last saved, or fallback to defaults
  // ** Changed default to use 'http://' instead of 'https://' **
  final savedServerURI =
      settingsBox.get('serverURI', defaultValue: 'http://xyz:11434');
  final savedSystemPrompt = settingsBox.get('systemPrompt', defaultValue: '');
  final savedDefaultModel = settingsBox.get('defaultModel', defaultValue: '');
  final savedIsLightMode = settingsBox.get('isLightMode', defaultValue: true);
  final savedContextWindow = settingsBox.get('contextWindow', defaultValue: 2);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => ThemeProvider(initialIsLightMode: savedIsLightMode)),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(
            initialOllamaServerURI: savedServerURI,
            initialSystemPrompt: savedSystemPrompt,
            initialDefaultModel: savedDefaultModel,
            initialContextWindow: savedContextWindow,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => chatSessionsProvider,
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

  // ScrollController for Auto-Scroll feature
  final ScrollController _scrollController = ScrollController();

  // Instead of local list, we'll pull from the provider
  ChatSession? _currentSession;

  // User-configurable settings
  String serverURI = '';
  String _systemPrompt = '';
  // String _defaultModel = ''; // Removed local defaultModel

  // The list of all AI model options
  List<String> _modelOptions = [];

  late OllamaClient client;
  late bool _isModelListPossible = false;

  // ** New: List to hold pending images before sending **
  List<Uint8List?> _pendingImages = [];
  @override
  void initState() {
    super.initState();

    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    _systemPrompt = settingsProvider.systemPrompt;
    serverURI = settingsProvider.ollamaServerURI;

    // Define a default URI
    // ** Ensure the default uses 'http://' to prevent TLS handshake issues **
    const String defaultURI = 'http://default.server.com';

    // Use the provided URI or fallback to the default
    final uriToUse = serverURI.isNotEmpty ? serverURI : defaultURI;

    // Ensure '/api' is appended only once
    final baseUri = uriToUse.endsWith('/api') ? uriToUse : '$uriToUse/api';

    client = OllamaClient(baseUrl: baseUri);
    AutarchService().checkIfEndpointSet(baseUri);

    // Load the session from ChatSessionsProvider
    final chatSessionsProvider =
        Provider.of<ChatSessionsProvider>(context, listen: false);
    _currentSession = chatSessionsProvider.getSessionById(widget.sessionId);
    if (chatSessionsProvider._chatsBox.isEmpty) {
      // chatSessionsProvider.createNewSession();
      chatSessionsProvider.initialLoadUp = true;
    }

    // Fetch model options after initializing the client
    fetchTags(baseUri);

    // Auto-scroll after the first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // Method to scroll to the bottom of the ListView
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
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
        setState(() {
          _pendingImages.add(bytes);
        });
        _scrollToBottom(); // Scroll after adding image
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
          _pendingImages.add(bytes);
        });
        _scrollToBottom(); // Scroll after adding photo
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
                _pendingImages.add(bytes);
              });
              _scrollToBottom(); // Scroll after adding image
            }
          } else {
            if (pickedFile.path != null) {
              final file = File(pickedFile.path!);
              final bytes = await file.readAsBytes();
              setState(() {
                _pendingImages.add(bytes);
              });
              _scrollToBottom(); // Scroll after adding image
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
          _scrollToBottom(); // Scroll after adding file message
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

    String tempSelectedModel = settingsProvider.defaultModel;
    int tempContextWindow = settingsProvider.contextWindow;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        void infoClick() {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => ModelInformationPage(
                    url: serverUriController.text,
                    modelName: settingsProvider.defaultModel,
                    isDarkMode: !themeProvider.isLightMode,
                  )));
        }

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
                              style: GoogleFonts.spaceMono(
                                fontSize: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.fontSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                // Save the server URI to the provider
                                settingsProvider.ollamaServerURI =
                                    serverUriController.text;

                                settingsProvider.systemPrompt =
                                    systemPromptController.text;

                                settingsProvider.defaultModel =
                                    tempSelectedModel;

                                settingsProvider.contextWindow =
                                    tempContextWindow;

                                setState(() {
                                  _systemPrompt = systemPromptController.text;
                                  // Re-initialize the client with new URI
                                  final uriToUse = settingsProvider
                                          .ollamaServerURI
                                          .endsWith('/api')
                                      ? settingsProvider.ollamaServerURI
                                      : '${settingsProvider.ollamaServerURI}/api';
                                  AutarchService().checkIfEndpointSet(uriToUse);
                                  client = OllamaClient(
                                    baseUrl: uriToUse,
                                  );
                                  // Fetch model options with new URI
                                  fetchTags(uriToUse);
                                });
                                // Persist settings to Hive
                                final box = Hive.box('settings');
                                await box.put('modelOptions', _modelOptions);
                                await box.put('defaultModel',
                                    settingsProvider.defaultModel);
                                await box.put('systemPrompt', _systemPrompt);
                                await box.put('serverURI', serverUriController.text);
                                await box.put('contextWindow',
                                    settingsProvider.contextWindow);

                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                              child: Text(
                                'Save',
                                style: GoogleFonts.spaceMono(
                                    fontSize: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.fontSize,
                                    fontWeight: FontWeight.bold),
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
                            style: GoogleFonts.spaceMono(
                              fontWeight: FontWeight.bold,
                              fontSize: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.fontSize,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        TextField(
                          controller: serverUriController,
                          decoration: InputDecoration(
                            labelText:
                                'Ollama server URI: https://xyz.ngrok-free.app',
                            labelStyle: GoogleFonts.spaceMono(
                              fontSize: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.fontSize,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: systemPromptController,
                          decoration: InputDecoration(
                            labelText: 'System prompt',
                            labelStyle: GoogleFonts.spaceMono(
                              fontSize: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.fontSize,
                            ),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Context Window
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Context Window',
                            style: GoogleFonts.spaceMono(
                              fontWeight: FontWeight.bold,
                              fontSize: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.fontSize,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              children: [
                                Text(
                                  'Set the context number',
                                  style: GoogleFonts.spaceMono(
                                      fontSize: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.fontSize),
                                ),
                              ],
                            ),
                            DropdownButton<int>(
                              value: tempContextWindow,
                              onChanged: (int? newValue) {
                                if (newValue != null) {
                                  setStateDialog(() {
                                    tempContextWindow = newValue;
                                  });
                                  // Update the provider
                                  settingsProvider.contextWindow = newValue;
                                  // Save to Hive
                                  final box = Hive.box('settings');
                                  box.put('contextWindow', newValue);
                                }
                              },
                              items: [
                                DropdownMenuItem<int>(
                                  value: 2,
                                  child: Text('2',
                                      style: GoogleFonts.spaceMono(
                                          fontSize: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.fontSize)),
                                ),
                                DropdownMenuItem<int>(
                                  value: 4,
                                  child: Text('4',
                                      style: GoogleFonts.spaceMono(
                                        fontSize: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.fontSize,
                                      )),
                                ),
                                 DropdownMenuItem<int>(
                                  value: 6,
                                  child: Text('6',
                                      style: GoogleFonts.spaceMono(
                                          fontSize: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.fontSize)),
                                ),
                                 DropdownMenuItem<int>(
                                  value: 8,
                                  child: Text('8',
                                      style: GoogleFonts.spaceMono(
                                          fontSize: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.fontSize)),
                                ),
                                
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Default Model
                        GestureDetector(
                          onTap: () {
                            infoClick();
                          },
                          child: Row(
                            children: [
                              Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.check_circle,
                                        size: 20,
                                        color: Colors.green,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Active Model',
                                        style: GoogleFonts.spaceMono(
                                            fontSize: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.fontSize,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  _isModelListPossible
                                      ? Row(
                                          children: [
                                            Text(
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              tempSelectedModel.isNotEmpty
                                                  ? tempSelectedModel
                                                  : 'None selected',
                                              style: GoogleFonts.spaceMono(
                                                fontSize: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.fontSize,
                                              ),
                                            ),
                                          ],
                                        )
                                      : const Text('None available'),
                                ],
                              ),
                              IconButton(
                                  onPressed: infoClick, icon: Icon(Icons.info))
                            ],
                          ),
                        ),

                        // APP Section
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'APP',
                            style: GoogleFonts.spaceMono(
                              fontWeight: FontWeight.bold,
                              fontSize: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.fontSize,
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
                              style: GoogleFonts.spaceMono(
                                  fontSize: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.fontSize),
                            ),
                            DropdownButton<bool>(
                              value: themeProvider.isLightMode,
                              onChanged: (bool? newValue) async {
                                if (newValue == null) return;
                                // Update ThemeProvider immediately
                                themeProvider.isLightMode = newValue;

                                // Save the theme setting to Hive immediately
                                final box = Hive.box('settings');
                                await box.put('isLightMode', newValue);
                              },
                              items: [
                                DropdownMenuItem<bool>(
                                  value: true,
                                  child: Text('Light',
                                      style: GoogleFonts.spaceMono(
                                          fontSize: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.fontSize)),
                                ),
                                DropdownMenuItem<bool>(
                                  value: false,
                                  child: Text('Dark',
                                      style: GoogleFonts.spaceMono(
                                          fontSize: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.fontSize)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(thickness: 1),

                        // Delete All Conversations
                        GestureDetector(
                          onTap: () async {
                            // Implement your deletion logic
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('Confirm Deletion',
                                    style: GoogleFonts.spaceMono(
                                        fontSize: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.fontSize,
                                        fontWeight: FontWeight.bold)),
                                content: Text(
                                    'Are you sure you want to delete all conversations?',
                                    style: GoogleFonts.spaceMono(
                                        fontSize: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.fontSize)),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: Text('Cancel',
                                        style: GoogleFonts.spaceMono(
                                            fontSize: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.fontSize,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: Text(
                                      'Delete',
                                      style: GoogleFonts.spaceMono(
                                          fontSize: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.fontSize,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              final chatSessionsProvider =
                                  Provider.of<ChatSessionsProvider>(context,
                                      listen: false);
                              await chatSessionsProvider.deleteAllSessions();
                              // Create a new session
                              final newSession =
                                  await chatSessionsProvider.createNewSession();
                              // Close the settings dialog before navigating
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                // Navigate to the new chat session, replacing the current page
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => OllamaChatPage(
                                        sessionId: newSession.id),
                                  ),
                                );
                              }
                            }
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'Delete All Conversations',
                              style: GoogleFonts.spaceMono(
                                fontSize: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.fontSize,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
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

  void handleImageMessages(String model, String prompt, ChatSessionsProvider chatSessionsProvider, ChatMessage botMessage) async {
    // ** Update the GenerateChatCompletionRequest **
        final stream = client.generateCompletionStream(
      request: GenerateCompletionRequest(
        model: model,
        stream: true,
        prompt: prompt,
        images: _pendingImages.map((image) => base64Encode(image!)).toList(),
      ),
    );

    _pendingImages.clear(); // Clear pending images after sending
    try {
      await for (final res in stream) {
        // Append partial tokens
        final newText = botMessage.text + (res.response ?? '');
        await chatSessionsProvider.updateLastBotMessage(
          sessionId: widget.sessionId,
          newText: newText,
        );
        _scrollToBottom(); // Scroll after updating bot message
      }
    } catch (e) {
      await chatSessionsProvider.updateLastBotMessage(
        sessionId: widget.sessionId,
        newText: 'Error: Possibly no server endpoint or invalid response.',
      );
      debugPrint("Error during message streaming: $e");
      _scrollToBottom(); // Scroll after error message
    } finally {
      await chatSessionsProvider.finalizeMessage(widget.sessionId);
      setState(() {
        _isLoading = false;
        _pendingImages.clear(); // Clear pending images after sending
      });
    }
  }

  // --------------------------------------------------
  // 3C) Streaming chat
  // --------------------------------------------------
  Future<void> _sendMessage(String messageText) async {
    final chatSessionsProvider =
        Provider.of<ChatSessionsProvider>(context, listen: false);
    chatSessionsProvider.initialLoadUp = false;
    // Prevent sending if there's no text and no pending images
    if (messageText.trim().isEmpty && _pendingImages.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    // Access the existing SettingsProvider
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    // _defaultModel = Hive.box('settings').get('defaultModel', defaultValue: ''); // Removed local defaultModel

    // Add user text message if any
    if (messageText.trim().isNotEmpty) {
      await chatSessionsProvider.addMessage(
        sessionId: widget.sessionId,
        message: ChatMessage(text: messageText.trim(), isUser: true),
      );
      _scrollToBottom(); // Scroll after adding user message
    }

    // Add pending images as user messages
    for (var imageData in _pendingImages) {
      await chatSessionsProvider.addMessage(
        sessionId: widget.sessionId,
        message: ChatMessage(text: '', imageData: imageData, isUser: true),
      );
      _scrollToBottom(); // Scroll after adding each image
    }

    // Create an empty botMessage to hold partial tokens
    final botMessage = ChatMessage(text: '', isUser: false);
    await chatSessionsProvider.addMessage(
      sessionId: widget.sessionId,
      message: botMessage,
    );
    _scrollToBottom(); // Scroll after adding bot message

    // ** New Implementation: Extract Last N Messages **
    int contextNumber = settingsProvider.contextWindow;
    List<ChatMessage> recentMessages = _currentSession?.messages ?? [];
    if (contextNumber > 0 && recentMessages.length > contextNumber) {
      recentMessages = recentMessages.sublist(recentMessages.length - contextNumber);
    } else if (contextNumber == 0) {
      recentMessages = [];
    }

    // Construct the messages for the request
    List<Message> requestMessages = [];

    // Add system prompt if it's not empty
    if (settingsProvider.systemPrompt.isNotEmpty) {
      requestMessages.add(Message(
        role: MessageRole.system,
        content: settingsProvider.systemPrompt,
      ));
    } else {
      // Fallback system prompt
      requestMessages.add(Message(
        role: MessageRole.system,
        content: 'You are a helpful assistant.',
      ));
    }

    // Convert recent ChatMessage objects to Message objects
    for (var msg in recentMessages) {
      MessageRole role = msg.isUser ? MessageRole.user : MessageRole.assistant;
      requestMessages.add(Message(
        role: role,
        content: msg.text.trim(),
      ));
    }

    // Add the new user message
    requestMessages.add(Message(
      role: MessageRole.user,
      content: messageText.trim(),
    ));

    if (settingsProvider.defaultModel.contains("vision") || settingsProvider.defaultModel.contains("llava")) {
      if (_pendingImages.map((image) => base64Encode(image!)).toList().isNotEmpty) {
        handleImageMessages(settingsProvider.defaultModel, messageText, chatSessionsProvider, botMessage);
      } else {
        handleImageMessages(settingsProvider.defaultModel, messageText, chatSessionsProvider, botMessage);

        var snackBar = SnackBar(
        content: Text("You could've also added an image to this message!", style: GoogleFonts.spaceMono(fontSize: Theme.of(context).textTheme.bodySmall?.fontSize),),);
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
        _isLoading = false;
      }
    } else {
      if (_pendingImages.map((image) => base64Encode(image!)).toList().isNotEmpty) {
        var snackBar = SnackBar(
        content: Text('You cant add an image to this model , switch to a vision model!', style: GoogleFonts.spaceMono(fontSize: Theme.of(context).textTheme.bodySmall?.fontSize),),);
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
        _isLoading = false;
        return;
      }
      // ** Update the GenerateChatCompletionRequest **
    final stream = client.generateChatCompletionStream(
      request: GenerateChatCompletionRequest(
        model: settingsProvider.defaultModel,
        stream: true,
        messages: requestMessages,
        // images: _pendingImages.map((image) => base64Encode(image!)).toList(),
      ),
    );

    _pendingImages.clear(); // Clear pending images after sending
    try {
      await for (final res in stream) {
        // Append partial tokens
        final newText = botMessage.text + (res.message.content ?? '');
        await chatSessionsProvider.updateLastBotMessage(
          sessionId: widget.sessionId,
          newText: newText,
        );
        _scrollToBottom(); // Scroll after updating bot message
      }
    } catch (e) {
      await chatSessionsProvider.updateLastBotMessage(
        sessionId: widget.sessionId,
        newText: 'Error: Possibly no server endpoint or invalid response.',
      );
      debugPrint("Error during message streaming: $e");
      _scrollToBottom(); // Scroll after error message
    } finally {
      await chatSessionsProvider.finalizeMessage(widget.sessionId);
      setState(() {
        _isLoading = false;
        _pendingImages.clear(); // Clear pending images after sending
      });
    }
    }
    _controller.clear();
  }

  Future<bool> fetchTags(String url) async {
    final Uri uri = Uri.parse('$url/tags'); // Adjust endpoint as needed

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          // Removed CORS headers as they should be managed server-side
        },
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> jsonData = json.decode(response.body);
        List<dynamic> models = jsonData['models'];
        List<String> modelNames =
            models.map((model) => model['name'] as String).toSet().toList(); // Ensure unique model names

        setState(() {
          _modelOptions = modelNames;
          _isModelListPossible = true;
          if (_modelOptions.isNotEmpty &&
              Provider.of<SettingsProvider>(context, listen: false)
                  .defaultModel
                  .isEmpty) {
            Provider.of<SettingsProvider>(context, listen: false).defaultModel =
                _modelOptions[0];
          }
          // Ensure the defaultModel is in the fetched model list
          final settingsProvider =
              Provider.of<SettingsProvider>(context, listen: false);
          if (settingsProvider.defaultModel.isNotEmpty &&
              !_modelOptions.contains(settingsProvider.defaultModel)) {
            settingsProvider.defaultModel = _modelOptions.isNotEmpty
                ? _modelOptions[0]
                : '';
            // Persist the updated defaultModel
            final box = Hive.box('settings');
            box.put('defaultModel', settingsProvider.defaultModel);
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
      await box.put('defaultModel',
          Provider.of<SettingsProvider>(context, listen: false).defaultModel);
      await box.put('systemPrompt', _systemPrompt);
      await box.put('serverURI', url);
    }
    return _isModelListPossible;
  }

  // --------------------------------------------------
  // 3D) Show popup of image upload options
  // --------------------------------------------------
  void _showImageOptionsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Add Images',
            style: GoogleFonts.spaceMono(
                fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize),
          ),
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

    final settingsProvider = context.watch<SettingsProvider>();

    String? selectedPrompt;

    void handlePromptChanged(String newPrompt) {
      setState(() {
        _controller.text = newPrompt;
      });
      // You can now use _selectedPrompt as needed
      print("Selected Prompt: $selectedPrompt");
    }

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: appBarColor,
          iconTheme: IconThemeData(color: iconColor),
          title: Row(
            children: [
              Text(
                'Autarch',
                style: GoogleFonts.spaceMono(
                  color: textColor,
                  fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 25),
              if (_modelOptions.isNotEmpty)
                SizedBox(
                  width: 125,
                  child: DropdownButton<String>(
                    isDense: true,
                    isExpanded: true,
                    style: GoogleFonts.spaceMono(
                        color: textColor,
                        fontSize:
                            Theme.of(context).textTheme.bodySmall?.fontSize),
                    dropdownColor: isLight ? Colors.white : Colors.grey[800],
                    iconEnabledColor: iconColor,
                    // Ensure the value is valid
                    value: (settingsProvider.defaultModel.isNotEmpty &&
                            _modelOptions.contains(settingsProvider.defaultModel))
                        ? settingsProvider.defaultModel
                        : (_modelOptions.isNotEmpty
                            ? _modelOptions[0]
                            : null),
                    hint: const Text('Select Model'),
                    items: _modelOptions.map((String modelName) {
                      return DropdownMenuItem<String>(
                        value: modelName,
                        child:
                            Text(modelName, style: TextStyle(color: textColor)),
                      );
                    }).toList(),
                    onChanged: (String? newValue) async {
                      if (newValue == null) return;
                      settingsProvider.defaultModel = newValue;

                      // Persist in Hive
                      final box = Hive.box('settings');
                      await box.put('defaultModel', newValue);
                      _scrollToBottom(); // Scroll after changing model
                    },
                  ),
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
                  Navigator.pushReplacement(
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
          shape: Border(
            bottom: BorderSide(color: borderColor, width: 1.0),
          ),
        ),
        // Drawer: list out existing chat sessions divided by days
        drawer: Drawer(
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    SizedBox(height: 16),
                    ..._buildGroupedSessions(chatSessionsProvider.sessions,
                        textColor, borderColor, isLight),
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
                  child: Text('Settings',
                      style: GoogleFonts.spaceMono(
                          fontSize:
                              Theme.of(context).textTheme.bodyMedium?.fontSize,
                          fontWeight: FontWeight.bold)),
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
                child: chatSessionsProvider.initialLoadUp
                    ? InitialLoadup(
                        isEndpointSet: AutarchService().isEndpointSet,
                        isDarkMode: !themeProvider.isLightMode,
                        endpointURL: serverURI,
                        onSettingsPressed: _openSettingsDialog,
                        onPromptChanged:
                            handlePromptChanged, // Pass the callback
                      )
                    : Container(
                        color: isLight ? Colors.white : const Color(0xFF1B1B1D),
                        padding: EdgeInsets.only(
                          left: kIsWeb ? 100.0 : 15.0,
                          right: kIsWeb ? 100.0 : 15.0,
                          top: kIsWeb ? 20.0 : 10.0,
                        ),
                        child: ListView.builder(
                          controller:
                              _scrollController, // Attach ScrollController
                          padding: const EdgeInsets.all(8.0),
                          itemCount: _currentSession?.messages.length ?? 0,
                          itemBuilder: (context, index) {
                            final message = _currentSession!.messages[index];
                            return ChatBubble(
                                message: message, isLight: isLight);
                          },
                        ),
                      ),
              ),

              // ** New: Display pending images above the textfield **
              if (_pendingImages.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 15.0, vertical: 5.0),
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pendingImages.length,
                    itemBuilder: (context, index) {
                      return Stack(
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 5.0),
                            child: Image.memory(
                              _pendingImages[index]!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 5,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _pendingImages.removeAt(index);
                                });
                                _scrollToBottom(); // Scroll after removing image
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

              if (_isLoading)
                LinearProgressIndicator(
                  color: isLight ? Colors.black : Colors.white,
                ),

              // 2) Bottom input area
              Padding(
                padding: EdgeInsets.only(
                  left: kIsWeb ? 100.0 : 8.0,
                  right: kIsWeb ? 100.0 : 8.0,
                  bottom: kIsWeb ? 20.0 : 4.0,
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
                            borderRadius: BorderRadius.circular(0.0),
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
                                cursorColor: textColor,
                                decoration: InputDecoration(
                                  hintText: 'Write something...',
                                  border: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 5),
                                  hintStyle: TextStyle(
                                    fontFamily:
                                        GoogleFonts.spaceMono().fontFamily,
                                    fontSize: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.fontSize,
                                    color: textColor.withOpacity(0.6),
                                  ),
                                ),
                              ),
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

                                  // Send text and images
                                  IconButton(
                                      iconSize: 24,
                                      icon: !_isLoading
                                          ? Icon(
                                              Icons.arrow_circle_right_outlined,
                                              color: iconColor)
                                          : Icon(Icons.hourglass_top,
                                              color: iconColor),
                                      onPressed: () {
                                        _sendMessage(_controller.text);
                                      }),
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

  List<Widget> _buildGroupedSessions(List<ChatSession> sessions,
      Color textColor, Color borderColor, bool isLight) {
    Map<String, List<ChatSession>> grouped = {
      'Today': [],
      'Yesterday': [],
      'Last 7 Days': [],
      'Last 30 Days': [],
      'Older': [],
    };

    DateTime now = DateTime.now();
    for (var session in sessions) {
      Duration diff = now.difference(session.createdAt);
      if (diff.inDays == 0 &&
          now.day == session.createdAt.day &&
          now.month == session.createdAt.month &&
          now.year == session.createdAt.year) {
        grouped['Today']!.add(session);
      } else if (diff.inDays == 1 ||
          (diff.inDays < 1 && now.day != session.createdAt.day)) {
        grouped['Yesterday']!.add(session);
      } else if (diff.inDays <= 7) {
        grouped['Last 7 Days']!.add(session);
      } else if (diff.inDays <= 30) {
        grouped['Last 30 Days']!.add(session);
      } else {
        grouped['Older']!.add(session);
      }
    }

    List<Widget> widgets = [];
    grouped.forEach((key, value) {
      if (value.isNotEmpty) {
        widgets.add(
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              key,
              style: GoogleFonts.spaceMono(
                fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
        );
        for (var session in value) {
          bool isActive = session.id == widget.sessionId; // Check if active

          widgets.add(
            ListTile(
              onLongPress: () async {
                print(session.id);
                print(session.title);
                // final chatSessionsProvider = Provider.of<ChatSessionsProvider>(context, listen: false);
                // chatSessionsProvider.deleteSession(session.id);
     
          // Show confirmation dialog
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Delete Conversation',
                  style: GoogleFonts.spaceMono(
                      fontSize: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.fontSize,
                      fontWeight: FontWeight.bold)),
              content: Text(
                  'Are you sure you want to delete this conversation?',
                  style: GoogleFonts.spaceMono(
                      fontSize: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.fontSize)),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(false),
                  child: Text('Cancel',
                      style: GoogleFonts.spaceMono(
                          fontSize: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.fontSize,
                          fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(true),
                  child: Text(
                    'Delete',
                    style: GoogleFonts.spaceMono(
                        fontSize: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.fontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.red),
                  ),
                ),
              ],
            ),
          );

          if (confirm == true) {
                final chatSessionsProvider =
        Provider.of<ChatSessionsProvider>(context, listen: false);
            // Proceed to delete the session
            await chatSessionsProvider.deleteSession(session.id);

            // If the deleted session was active, navigate to the first session or create a new one
            if (isActive) {
              final remainingSessions =
                  chatSessionsProvider.sessions;
              if (remainingSessions.isNotEmpty) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OllamaChatPage(
                        sessionId: remainingSessions[0].id),
                  ),
                );
              } else {
                final newSession =
                    await chatSessionsProvider.createNewSession();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        OllamaChatPage(sessionId: newSession.id),
                  ),
                );
              }
            }
          }
              },
              title: Text(
                session.title == 'Untitled' ? '(New Chat)' : session.title,
                style: GoogleFonts.spaceMono(
                  color: textColor,
                  fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: Text(
                _formatDate(session.createdAt),
                style: GoogleFonts.spaceMono(
                  color: textColor.withOpacity(0.6),
                  fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
                ),
              ),
              leading: isActive
                  ? Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      semanticLabel: 'Active Chat',
                    )
                  : null,
              selected: isActive,
              selectedTileColor: isLight
                  ? Colors.blue.withOpacity(0.1)
                  : Colors.blueGrey.withOpacity(0.3),
              onTap: () {
                Navigator.pop(context); // close drawer
                // Only navigate if not already on the selected session
                if (!isActive) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          OllamaChatPage(sessionId: session.id),
                    ),
                  );
                }
              },
            ),
          );
          widgets.add(const Divider());
        }
      }
    });

    return widgets;
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
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
// Uncomment and modify if you want to customize code blocks in Markdown
// class CodeBlockBuilder extends MarkdownElementBuilder {
//   @override
//   Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
//     final codeText = element.textContent;

//     return Container(
//       margin: const EdgeInsets.symmetric(vertical: 8),
//       decoration: BoxDecoration(
//         color: Colors.black,
//         borderRadius: BorderRadius.circular(8),
//       ),
//       child: Stack(
//         children: [
//           Padding(
//             padding: const EdgeInsets.all(12.0),
//             child: SelectableText(
//               codeText,
//               style: const TextStyle(
//                 color: Colors.white,
//                 fontFamily: 'monospace',
//               ),
//             ),
//           ),
//           Positioned(
//             top: 0,
//             right: 0,
//             child: CopyCodeIcon(codeText: codeText),
//           ),
//         ],
//       ),
//     );
//   }
// }

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
          code: GoogleFonts.spaceMono(),
        ),
        // Uncomment and modify to use custom builders
        // builders: {
        //   'blockquote': CodeBlockBuilder(),
        // },
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
