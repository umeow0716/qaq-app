// Local dialog implementation inspired by awesome_dialog.
// Reference: https://github.com/marcos930807/awesomeDialogs
//
// This file is an independent Flutter implementation for TAT UMeow and does
// not include or depend on Rive / rive_native.

import 'package:flutter/material.dart';
import 'package:flutter_app/src/navigation/app_navigator.dart';
import 'package:flutter_app/src/r.dart';

enum DialogType { noHeader, info, warning, error, success }

enum AnimType { scale, leftSlide, rightSlide, bottomSlide, topSlide }

class MsgDialogParameter {
  String? title;
  String? desc;
  String? okButtonText;
  String? cancelButtonText;
  DialogType dialogType;
  VoidCallback? onOkButtonClicked;
  VoidCallback? onCancelButtonClicked;
  final AnimType animType;
  final bool removeOkButton;
  final bool removeCancelButton;

  MsgDialogParameter({
    required this.desc,
    this.title = '',
    this.okButtonText,
    this.cancelButtonText,
    this.animType = AnimType.bottomSlide,
    this.dialogType = DialogType.noHeader,
    this.removeOkButton = false,
    this.removeCancelButton = false,
    this.onOkButtonClicked,
    this.onCancelButtonClicked,
  }) {
    if (!removeOkButton) {
      okButtonText ??= R.current.sure;
      onOkButtonClicked ??= () {};
    }

    if (!removeCancelButton) {
      cancelButtonText ??= R.current.cancel;
      onCancelButtonClicked ??= () {};
    }
  }
}

class MsgDialog {
  const factory MsgDialog(MsgDialogParameter parameter) = MsgDialog._;
  const MsgDialog._(this.parameter);

  final MsgDialogParameter parameter;

  Future<void> show({BuildContext? context}) {
    final dialogContext = context ?? AppNavigator.key.currentContext;
    if (dialogContext == null) return Future<void>.value();

    return showGeneralDialog<void>(
      context: dialogContext,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => _MsgDialogView(parameter: parameter),
      transitionBuilder: (_, animation, _, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        final fadedChild = FadeTransition(opacity: curvedAnimation, child: child);

        return switch (parameter.animType) {
          AnimType.scale => ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1).animate(curvedAnimation),
            child: fadedChild,
          ),
          AnimType.leftSlide => SlideTransition(
            position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero).animate(curvedAnimation),
            child: fadedChild,
          ),
          AnimType.rightSlide => SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(curvedAnimation),
            child: fadedChild,
          ),
          AnimType.bottomSlide => SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curvedAnimation),
            child: fadedChild,
          ),
          AnimType.topSlide => SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(curvedAnimation),
            child: fadedChild,
          ),
        };
      },
    );
  }
}

class _MsgDialogView extends StatelessWidget {
  const _MsgDialogView({required this.parameter});

  static const _okColor = Color(0xFF00CA71);
  static const _cancelColor = Color(0xFFD93E46);

  final MsgDialogParameter parameter;

  @override
  Widget build(BuildContext context) {
    final visual = _DialogVisual.fromType(parameter.dialogType);
    final hasHeader = visual != null;
    final hasTitle = parameter.title?.trim().isNotEmpty ?? false;
    final hasDescription = parameter.desc?.trim().isNotEmpty ?? false;
    final hasButtons = !parameter.removeCancelButton || !parameter.removeOkButton;

    return SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dialogTheme.backgroundColor ?? Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8))],
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, hasHeader ? 58 : 24, 24, 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasTitle)
                            Text(
                              parameter.title!.trim(),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          if (hasTitle && hasDescription) const SizedBox(height: 12),
                          if (hasDescription)
                            Text(
                              parameter.desc!.trim(),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45),
                            ),
                          if (hasButtons) const SizedBox(height: 24),
                          if (hasButtons) _buildButtons(context),
                        ],
                      ),
                    ),
                  ),
                  if (visual != null)
                    Positioned(
                      top: -42,
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: visual.color,
                          border: Border.all(color: Theme.of(context).colorScheme.surface, width: 4),
                          boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 8, offset: Offset(0, 3))],
                        ),
                        child: Icon(visual.icon, color: Colors.white, size: 46),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButtons(BuildContext context) {
    final buttons = <Widget>[];

    if (!parameter.removeCancelButton) {
      buttons.add(
        Expanded(
          child: _DialogButton(
            text: parameter.cancelButtonText ?? R.current.cancel,
            color: _cancelColor,
            onPressed: () => _closeAndRun(context, parameter.onCancelButtonClicked),
          ),
        ),
      );
    }

    if (!parameter.removeOkButton) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(
        Expanded(
          child: _DialogButton(
            text: parameter.okButtonText ?? R.current.sure,
            color: _okColor,
            onPressed: () => _closeAndRun(context, parameter.onOkButtonClicked),
          ),
        ),
      );
    }

    return Row(children: buttons);
  }

  void _closeAndRun(BuildContext context, VoidCallback? callback) {
    Navigator.of(context, rootNavigator: true).pop();
    callback?.call();
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({required this.text, required this.color, required this.onPressed});

  final String text;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
        child: Text(text),
      ),
    );
  }
}

class _DialogVisual {
  const _DialogVisual(this.color, this.icon);

  final Color color;
  final IconData icon;

  static _DialogVisual? fromType(DialogType type) {
    return switch (type) {
      DialogType.noHeader => null,
      DialogType.info => const _DialogVisual(Color(0xFF2196F3), Icons.info_outline_rounded),
      DialogType.warning => const _DialogVisual(Color(0xFFFFB300), Icons.priority_high_rounded),
      DialogType.error => const _DialogVisual(Color(0xFFF44336), Icons.close_rounded),
      DialogType.success => const _DialogVisual(Color(0xFF00CA71), Icons.check_rounded),
    };
  }
}
