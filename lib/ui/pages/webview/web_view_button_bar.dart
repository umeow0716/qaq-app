import 'package:flutter/material.dart';

/// A simple button action bar for the WebView use.
///
/// When any of onPressed callback is `null`, that button will be disabled.
class WebViewButtonBar extends StatelessWidget {
  const WebViewButtonBar({
    super.key,
    this.onBackPressed,
    this.onForwardPressed,
    this.onRefreshPressed,
  });

  final VoidCallback? onBackPressed;
  final VoidCallback? onForwardPressed;
  final VoidCallback? onRefreshPressed;

  @override
  Widget build(BuildContext context) => OverflowBar(
        alignment: MainAxisAlignment.center,
        children: [
          _ControlButton(icon: const Icon(Icons.arrow_back), onPressed: onBackPressed),
          _ControlButton(icon: const Icon(Icons.arrow_forward), onPressed: onForwardPressed),
          _ControlButton(icon: const Icon(Icons.refresh), onPressed: onRefreshPressed),
        ],
      );
}

/// A rounded rectangle button for the [WebViewButtonBar] used.
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    this.onPressed,
  });

  final Icon icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        style: ButtonStyle(
          shape: WidgetStateProperty.all<RoundedRectangleBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30.0),
            ),
          ),
        ),
        onPressed: onPressed,
        child: icon,
      );
}
