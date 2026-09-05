import 'package:flutter/material.dart';

class ExpandableText extends StatefulWidget {
  final String text;
  final int maxLines;
  final TextStyle? style;
  final bool expand;

  const ExpandableText({
    Key? key,
    required this.text,
    required this.maxLines,
    this.style,
    this.expand = false,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  late bool _expand;

  @override
  void initState() {
    super.initState();
    _expand = widget.expand;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, size) {
      final span = TextSpan(text: widget.text, style: widget.style);
      final tp = TextPainter(text: span, maxLines: widget.maxLines, textDirection: TextDirection.ltr)
        ..layout(maxWidth: size.maxWidth);

      if (!tp.didExceedMaxLines) return Text(widget.text, style: widget.style);

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => setState(() => _expand = !_expand),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(child: Text('')),
                Icon(_expand ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 20),
              ],
            ),
            Text(
              widget.text,
              maxLines: _expand ? null : widget.maxLines,
              overflow: _expand ? null : TextOverflow.ellipsis,
              style: widget.style,
            ),
          ],
        ),
      );
    });
  }
}
