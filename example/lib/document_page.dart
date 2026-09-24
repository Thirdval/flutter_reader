import 'package:flutter/material.dart';
import 'package:flutter_reader/flutter_reader.dart';

/// A paragraph of the document.
class const Paragraph({required final int number, required final String text}) {
  String get id => 'p$number';
  String get typeKey => number % 25 == 0 ? 'heading' : 'body';
}

List<Paragraph> generateDocument(int count) => [
  for (var i = 0; i < count; i++)
    Paragraph(
      number: i,
      text: i % 25 == 0
          ? 'Chapter ${i ~/ 25 + 1}'
          : 'Paragraph $i. ${_lorem.substring(0, 40 + (i * 37) % (_lorem.length - 40))}',
    ),
];

const _lorem =
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod '
    'tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim '
    'veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea '
    'commodo consequat. Duis aute irure dolor in reprehenderit in voluptate '
    'velit esse cillum dolore eu fugiat nulla pariatur.';

/// 10,000 paragraphs with headings: jump by number, search with
/// highlights, and a live "paragraph N" readout from the visibility.
class const DocumentPage({super.key}) extends StatefulWidget {
  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState() extends State<DocumentPage> {
  static const _bodyStyle = TextStyle(fontSize: 16, height: 1.4);
  static const _headingStyle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
  );

  final _premeasurer = TextPremeasurer();
  final _scroll = ScrollController();
  final _jumpField = TextEditingController();
  final _searchField = TextEditingController();
  late final ReaderController<Paragraph> _reader = ReaderController<Paragraph>(
    items: generateDocument(10000),
    idOf: (p) => p.id,
    typeKeyOf: (p) => p.typeKey,
    typeConfigs: {
      'heading': const ItemTypeConfig<Paragraph>(
        typeName: 'heading',
        defaultHeight: 56,
        defaultConfidence: 0.9,
        widthSensitivity: WidthSensitivity.invariant,
      ),
      'body': ItemTypeConfig<Paragraph>(
        typeName: 'body',
        defaultHeight: 80,
        estimator: _premeasurer.createEstimator<Paragraph>(
          textExtractor: (p) => p.text,
          style: _bodyStyle,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
    },
    initialWidth: 390,
  );
  late final ReaderSearchController<Paragraph> _search =
      ReaderSearchController<Paragraph>(
        reader: _reader,
        textExtractors: {'body': (p) => p.text, 'heading': (p) => p.text},
      );

  @override
  void dispose() {
    _search.dispose();
    _reader.dispose();
    _scroll.dispose();
    _jumpField.dispose();
    _searchField.dispose();
    _premeasurer.dispose();
    super.dispose();
  }

  void _jump() {
    final number = int.tryParse(_jumpField.text);
    if (number == null) return;
    _reader.jumpToId('p$number', alignment: 0);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<VisibilityState>(
          valueListenable: _reader.visibility,
          builder: (_, visibility, _) => Text(
            visibility.hasVisible
                ? 'Paragraph ${visibility.firstVisible} of ${_reader.itemCount}'
                : 'Document',
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _jumpField,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'Jump to paragraph',
                    ),
                    onSubmitted: (_) => _jump(),
                  ),
                ),
                IconButton(
                  onPressed: _jump,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ListenableBuilder(
              listenable: _search,
              builder: (_, _) => Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchField,
                      decoration: const InputDecoration(hintText: 'Search'),
                      onChanged: _search.search,
                    ),
                  ),
                  if (_search.isActive)
                    Text(
                      _search.hasMatches
                          ? '${_search.currentMatchIndex + 1} of ${_search.matchCount}'
                          : 'No results',
                    ),
                  IconButton(
                    onPressed: _search.hasMatches
                        ? _search.previousMatch
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    onPressed: _search.hasMatches ? _search.nextMatch : null,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ReaderView<Paragraph>(
              controller: _reader,
              scrollController: _scroll,
              itemUpdateListenable: _search,
              itemBuilder: (context, index, paragraph) => Padding(
                padding: paragraph.typeKey == 'heading'
                    ? const EdgeInsets.fromLTRB(16, 24, 16, 8)
                    : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text.rich(
                  buildHighlightedSpan(
                    text: paragraph.text,
                    matches: _search.matchesForItem(index),
                    currentMatch: _search.currentMatch,
                    style: paragraph.typeKey == 'heading'
                        ? _headingStyle
                        : _bodyStyle,
                    highlightStyle: TextStyle(
                      backgroundColor: colors.secondaryContainer,
                    ),
                    currentHighlightStyle: TextStyle(
                      backgroundColor: colors.tertiaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
