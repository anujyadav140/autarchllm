import 'package:autarchllm/providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ollama_dart/ollama_dart.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

/// Manages the app’s theme (light/dark).
class ThemeProvider extends ChangeNotifier {
  bool _isLightMode = true; // default is light mode

  bool get isLightMode => _isLightMode;

  set isLightMode(bool newValue) {
    _isLightMode = newValue;
    notifyListeners();
  }

  /// Returns the corresponding ThemeData for light or dark mode.
  ThemeData get themeData {
    if (_isLightMode) {
      return ThemeData.light().copyWith(
        // Customize your light theme here if needed
        scaffoldBackgroundColor: Colors.white,
      );
    } else {
      return ThemeData.dark().copyWith(
        // Customize your dark theme here if needed
        scaffoldBackgroundColor: const Color(0xFF1B1B1D), // for that dark look
      );
    }
  }
}

void main() {
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
  @override
  Widget build(BuildContext context) {
    // Listen to the theme provider for changes
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Autarch LLM',
      theme: themeProvider.themeData,
      home: OllamaChatPage(),
    );
  }
}

class OllamaChatPage extends StatefulWidget {
  const OllamaChatPage({Key? key}) : super(key: key);

  @override
  _OllamaChatPageState createState() => _OllamaChatPageState();
}

class _OllamaChatPageState extends State<OllamaChatPage> {
  final _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  // User-configurable settings
  String _ollamaServerURI = 'http://127.0.0.1:11434';
  String _systemPrompt = '';
  String _defaultModel = 'llama3.2:1b'; // default selection

  // The list of all AI model options
  final List<String> _modelOptions = [
    'llama3.2:1b',
    'llama2-7b',
    'llama2-13b',
    'llama2-70b',
    // ...
  ];

  late OllamaClient client;

  @override
  void initState() {
    super.initState();
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    client = OllamaClient(baseUrl: settingsProvider.ollamaServerURI);
  }

  /// Open the settings dialog
  Future<void> _openSettingsDialog() async {
    final themeProvider = context.read<ThemeProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final TextEditingController serverUriController =
        TextEditingController(text: settingsProvider.ollamaServerURI);
    final TextEditingController systemPromptController =
        TextEditingController(text: _systemPrompt);

    // Local copy of the model selection & theme mode
    String tempSelectedModel = _defaultModel;
    bool tempIsLightMode = themeProvider.isLightMode;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: !kIsWeb ? const EdgeInsets.all(0.0) : const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
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
                              onPressed: () {
                                settingsProvider.ollamaServerURI = serverUriController.text;
                                setState(() {
                                  _systemPrompt = systemPromptController.text;
                                  _defaultModel = tempSelectedModel;

                                  client = OllamaClient(baseUrl: '${settingsProvider.ollamaServerURI}/api');
                                });
                                themeProvider.isLightMode = tempIsLightMode;
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
                            labelText: 'Ollama server URI',
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
                            DropdownButton<String>(
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
                            ),
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

  Future<void> _sendMessage(String messageText) async {
    if (messageText.isEmpty) return;
    setState(() {
      _messages.add(ChatMessage(text: messageText, isUser: true));
      _isLoading = true;
    });

    final stream = client.generateCompletionStream(
      request: GenerateCompletionRequest(
        model: _defaultModel,
        prompt: _systemPrompt.isNotEmpty
            ? "$_systemPrompt\n\nUser: $messageText"
            : messageText,
      ),
    );

    ChatMessage botMessage = ChatMessage(text: '', isUser: false);
    setState(() {
      _messages.add(botMessage);
    });

    try {
      await for (final res in stream) {
        setState(() {
          botMessage.text += res.response!;
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

  @override
  Widget build(BuildContext context) {
    // Determine whether we are in Light or Dark mode
    final isLight = context.watch<ThemeProvider>().isLightMode;

    // Pick the colors for the AppBar, border, icons, text accordingly
    final appBarColor = isLight ? Colors.white : Colors.black;
    final iconColor = isLight ? Colors.black : Colors.white;
    final textColor = isLight ? Colors.black : Colors.white;
    final borderColor = isLight ? Colors.black : Colors.white;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: appBarColor,
        iconTheme: IconThemeData(color: iconColor),
        // Ensure the title text is correct color
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
                        color: textColor, // apply color to text
                        fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
                      ),
                    ),
                  ),
                  Divider(),
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
            Divider(),
            Container(
              alignment: Alignment.center,
              margin: const EdgeInsets.only(bottom: 16.0, right: 16.0),
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: textColor,
                  side: BorderSide(color: borderColor, width: 0),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero, // No border radius
                  ),
                ),
                onPressed: _openSettingsDialog,
                child: const Text('Settings'),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages area
          Expanded(
            child: Container(
              // If you want a black (dark) background for the chat area,
              // rely on the scaffold background for dark mode or override here
              color: isLight ? Colors.white : const Color(0xFF1B1B1D),
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
          // Input area
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  onSubmitted: _sendMessage,
                  minLines: 1,
                  maxLines: 3,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Write something...',
                    hintStyle: TextStyle(color: textColor.withOpacity(0.6)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: borderColor, width: 1.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: borderColor, width: 1.0),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: !_isLoading
                    ? Icon(Icons.arrow_circle_right_outlined, color: iconColor)
                    : Icon(Icons.hourglass_top, color: iconColor),
                onPressed: () => _sendMessage(_controller.text),
                iconSize: 38,
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class ChatMessage {
  String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isLight;

  const ChatBubble({required this.message, required this.isLight});

  @override
  Widget build(BuildContext context) {
    final alignment =
        message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    // For dark mode, use a darker bubble if it's user, or slightly lighter if it's bot.
    final userBgColor = isLight ? Colors.blue[100]! : Colors.blueGrey[700]!;
    final botBgColor = isLight ? Colors.grey[200]! : Colors.blueGrey[800]!;

    final bgColor = message.isUser ? userBgColor : botBgColor;
    final textColor = isLight ? Colors.black : Colors.white;

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
          child: Text(
            message.text.trim(),
            style: TextStyle(color: textColor),
          ),
        ),
      ],
    );
  }
}
