import 'package:flutter/material.dart';

import 'chat_page.dart';
import 'document_page.dart';

void main() => runApp(const ExampleApp());

class const ExampleApp({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'flutter_reader',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: const HomePage(),
  );
}

class const HomePage({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('flutter_reader')),
    body: ListView(
      children: [
        ListTile(
          title: const Text('Document'),
          subtitle: const Text(
            '10,000 paragraphs: jump anywhere, search, watch the position',
          ),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const DocumentPage())),
        ),
        ListTile(
          title: const Text('Chat'),
          subtitle: const Text(
            'reverse list: older pages, live messages, edits, anchored jumps',
          ),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const ChatPage())),
        ),
      ],
    ),
  );
}
