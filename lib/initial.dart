import 'package:autarchllm/main.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class InitialLoadup extends StatelessWidget {
  final bool isDarkMode;
  final bool isEndpointSet;
  final String? endpointURL;
  final VoidCallback onSettingsPressed;
  final ValueChanged<String> onPromptChanged; // Add this line

  const InitialLoadup({
    super.key,
    required this.isEndpointSet,
    this.endpointURL,
    required this.isDarkMode, required this.onSettingsPressed, required this.onPromptChanged,
  });

  bool _isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width > 600;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopView = _isDesktop(context);
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final textColor = isDarkMode ? Colors.white : Colors.black;
    final backgroundColor = isDarkMode ? Colors.black : Colors.white;
    final subtitleColor = isDarkMode ? Colors.white70 : Colors.black87;
    final logo = isDarkMode ? 'assets/autarch_dark.png' : 'assets/autarch.png';

    return Scaffold(
      body: SingleChildScrollView(
        child: Container(
          color: backgroundColor,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
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
              const SizedBox(height: 20),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Welcome to ',
                      style: GoogleFonts.spaceMono(
                        fontSize: isDesktopView
                            ? textTheme.bodyLarge?.fontSize
                            : textTheme.bodySmall?.fontSize,
                        fontWeight: FontWeight.normal,
                        color: textColor,
                      ),
                    ),
                    TextSpan(
                      text: 'Autarch!',
                      style: GoogleFonts.spaceMono(
                        fontSize: isDesktopView
                            ? textTheme.bodyLarge?.fontSize
                            : textTheme.bodySmall?.fontSize,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Autarch connects you to powerful local Language Models, using AI directly from your personal local network for privacy, speed, and customization.',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceMono(
                  fontSize: isDesktopView
                      ? textTheme.bodyMedium?.fontSize
                      : textTheme.bodySmall?.fontSize,
                  fontWeight: FontWeight.w400,
                  color: subtitleColor,
                ),
              ),
              const SizedBox(height: 20),
              isEndpointSet
                  ? _buildActiveEndpoint(context, endpointURL, isDesktopView,
                      textColor, subtitleColor)
                  : _buildSetupEndpoint(context, isDesktopView, textColor,
                      subtitleColor, backgroundColor),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'If you ',
                            style: GoogleFonts.spaceMono(
                              fontSize: isDesktopView
                                  ? textTheme.bodyMedium?.fontSize
                                  : textTheme.bodySmall?.fontSize,
                              fontWeight: FontWeight.normal,
                              color: textColor,
                            ),
                          ),
                          TextSpan(
                            text: 'need help in starting',
                            style: GoogleFonts.spaceMono(
                              fontSize: isDesktopView
                                  ? textTheme.bodyMedium?.fontSize
                                  : textTheme.bodySmall?.fontSize,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          TextSpan(
                            text: ', we\'re here for you!',
                            style: GoogleFonts.spaceMono(
                              fontSize: isDesktopView
                                  ? textTheme.bodyMedium?.fontSize
                                  : textTheme.bodySmall?.fontSize,
                              fontWeight: FontWeight.normal,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 5),
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: backgroundColor,
                          title: Text('How Can We Help You?',
                              style: TextStyle(color: textColor)),
                          content: Text(
                            'Getting started with Autarch is easy! Here are some steps to help you configure your Language Model endpoint and begin your AI journey.',
                            style: TextStyle(color: subtitleColor),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text('Close',
                                  style: TextStyle(color: textColor)),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Icon(
                      Icons.help_outline,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              isEndpointSet ? SizedBox(
                height: isDesktopView ? 70 : 60,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildQueryChip(context, 'Tell me a joke', isDesktopView,
                        textTheme, textColor),
                    _buildQueryChip(context, 'What is Flutter?', isDesktopView,
                        textTheme, textColor),
                    _buildQueryChip(context, 'Explain quantum computing',
                        isDesktopView, textTheme, textColor),
                    _buildQueryChip(context, 'Best programming practices',
                        isDesktopView, textTheme, textColor),
                    _buildQueryChip(context, 'Upcoming tech trends',
                        isDesktopView, textTheme, textColor),
                    _buildQueryChip(context, 'Healthy living tips',
                        isDesktopView, textTheme, textColor),
                  ],
                ),
              ) : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveEndpoint(BuildContext context, String? url,
      bool isDesktopView, Color textColor, Color subtitleColor) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              'Active Endpoint:',
              style: GoogleFonts.spaceMono(
                fontSize: isDesktopView
                    ? textTheme.bodyMedium?.fontSize
                    : textTheme.bodySmall?.fontSize,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          url ?? 'No URL Provided',
          style: GoogleFonts.spaceMono(
            fontSize: isDesktopView
                ? textTheme.bodyLarge?.fontSize
                : textTheme.bodySmall?.fontSize ?? 12,
            fontWeight: FontWeight.w400,
            color: subtitleColor,
            decoration: TextDecoration.underline,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildSetupEndpoint(BuildContext context, bool isDesktopView,
      Color textColor, Color subtitleColor, Color backgroundColor) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              'LLM Endpoint not set.',
              style: GoogleFonts.spaceMono(
                fontSize: isDesktopView
                    ? textTheme.bodyMedium?.fontSize
                    : textTheme.bodySmall?.fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Please configure your LLM endpoint in the Settings to start using Autarch.',
          textAlign: TextAlign.center,
          style: GoogleFonts.spaceMono(
            fontSize: isDesktopView
                ? textTheme.bodyLarge?.fontSize
                : textTheme.bodySmall?.fontSize ?? 12,
            fontWeight: FontWeight.w400,
            color: subtitleColor,
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () {
            //call the ollamachatpage
           onSettingsPressed();
          },
          icon: const Icon(Icons.settings),
          label: Text(
            'Go to Settings',
            style: GoogleFonts.spaceMono(
              fontSize: isDesktopView
                  ? textTheme.bodyMedium?.fontSize
                  : textTheme.bodySmall?.fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: textColor,
            foregroundColor: backgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQueryChip(BuildContext context, String query, bool isDesktopView,
      TextTheme textTheme, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: ActionChip(
        label: Text(
          query,
          style: GoogleFonts.spaceMono(
            fontSize: isDesktopView
                ? textTheme.bodyMedium?.fontSize
                : textTheme.bodySmall?.fontSize,
            fontWeight: FontWeight.bold,
            color: isDarkMode ? Colors.black : Colors.white,
          ),
        ),
        backgroundColor: textColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        onPressed: () {
          // ScaffoldMessenger.of(context).showSnackBar(
          //   SnackBar(content: Text('You selected: "$query"')),
          // );
          onPromptChanged(query);
        },
      ),
    );
  }
}
