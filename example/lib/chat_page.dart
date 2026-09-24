import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reader/flutter_reader.dart';

/// A chat message; ids are stable across edits.
class const Message({
  required final int number,
  required final bool mine,
  required final String text,
}) {
  String get id => 'm$number';

  Message edited(String text) =>
      Message(number: number, mine: mine, text: text);
}

List<Message> generateMessages(int from, int count) => [
  for (var i = from; i < from + count; i++)
    Message(
      number: i,
      mine: i % 3 == 0,
      text: 'Message $i${' with more words' * (i % 4)}',
    ),
];

/// A reversed chat: the newest message at the bottom, older pages loading
/// when the top enters the cache window, live messages that never move
/// what you are reading, edits above the viewport, and anchored jumps.
class const ChatPage({super.key}) extends StatefulWidget {
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState() extends State<ChatPage> {
  static const _pageSize = 50;
  static const _pages = 20;

  final _scroll = ScrollController();
  final _composer = TextEditingController();
  final _jumpField = TextEditingController();
  late List<Message> _messages = generateMessages(
    _pages * _pageSize,
    _pageSize,
  );
  int _oldest = _pages * _pageSize;
  int _next = _pages * _pageSize + _pageSize;
  int _newBelow = 0;
  bool _atEnd = true;
  bool _loading = false;
  ReaderAnchor? _anchor;
  late final ReaderController<Message> _reader = ReaderController<Message>(
    items: _messages,
    idOf: (m) => m.id,
    typeKeyOf: (_) => 'message',
    typeConfigs: const {
      'message': ItemTypeConfig<Message>(
        typeName: 'message',
        defaultHeight: 56,
      ),
    },
    initialWidth: 390,
    hasMoreBefore: true,
    atEndThreshold: 48,
    onEdgeReached: (_) => unawaited(_loadOlder()),
    onAtEndChanged: (atEnd) => setState(() {
      _atEnd = atEnd;
      if (atEnd) _newBelow = 0;
    }),
  );

  @override
  void dispose() {
    _reader.dispose();
    _scroll.dispose();
    _composer.dispose();
    _jumpField.dispose();
    super.dispose();
  }

  void _apply(List<Message> messages) {
    _messages = messages;
    _reader.setItems(messages);
  }

  Future<void> _loadOlder() async {
    if (_loading || _oldest == 0) return;
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _oldest -= _pageSize;
    _apply([...generateMessages(_oldest, _pageSize), ..._messages]);
    _reader.hasMoreBefore = _oldest > 0;
    setState(() => _loading = false);
  }

  void _send([String? text]) {
    final body = text ?? _composer.text.trim();
    if (body.isEmpty) return;
    _composer.clear();
    _apply([
      ..._messages,
      Message(number: _next++, mine: text == null, text: body),
    ]);
    if (!_atEnd) setState(() => _newBelow++);
  }

  void _editAbove() {
    final first = _reader.visibility.value.firstVisible;
    if (first < 3) return;
    final target = _messages[first - 3];
    _apply([
      for (final m in _messages)
        if (m.id == target.id)
          m.edited(
            '${m.text} (edited, now a much longer message that wraps onto more lines)',
          )
        else
          m,
    ]);
  }

  void _deleteTopVisible() {
    final first = _reader.visibility.value.firstVisible;
    if (first < 0) return;
    final id = _messages[first].id;
    _apply([
      for (final m in _messages)
        if (m.id != id) m,
    ]);
  }

  void _jump() {
    final number = int.tryParse(_jumpField.text);
    if (number == null) return;
    setState(() => _anchor = ReaderAnchor(id: 'm$number', alignment: 0.7));
    FocusScope.of(context).unfocus();
  }

  void _toLatest() {
    setState(() {
      _anchor = null;
      _newBelow = 0;
    });
    _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat · ${_reader.itemCount} loaded'),
        actions: [
          IconButton(
            onPressed: _editAbove,
            tooltip: 'Edit a message above',
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            onPressed: _deleteTopVisible,
            tooltip: 'Delete the top message',
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            onPressed: () => _send('Incoming $_next'),
            tooltip: 'Receive a message',
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _jumpField,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'Jump to message number (anchored at 0.7)',
                    ),
                    onSubmitted: (_) => _jump(),
                  ),
                ),
                IconButton(
                  onPressed: _jump,
                  icon: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                ReaderView<Message>(
                  controller: _reader,
                  scrollController: _scroll,
                  reverse: true,
                  anchor: _anchor,
                  trailingSlivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 48,
                        child: Center(
                          child: _loading
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _oldest == 0
                                      ? 'Start of the conversation'
                                      : '',
                                ),
                        ),
                      ),
                    ),
                  ],
                  itemBuilder: (context, index, message) => Align(
                    alignment: message.mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      constraints: const BoxConstraints(maxWidth: 280),
                      decoration: BoxDecoration(
                        color: _anchor?.id == message.id
                            ? colors.tertiaryContainer
                            : message.mine
                            ? colors.primaryContainer
                            : colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(message.text),
                    ),
                  ),
                ),
                if (!_atEnd)
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: FilledButton.tonalIcon(
                      onPressed: _toLatest,
                      icon: const Icon(Icons.arrow_downward),
                      label: Text(_newBelow > 0 ? '$_newBelow new' : 'Latest'),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      decoration: const InputDecoration(hintText: 'Message'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(onPressed: _send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
