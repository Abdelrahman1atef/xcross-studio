import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../theme/x_theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'x_status.dart';

/// A path field with "Browse…" (folder or file). States: empty, selected,
/// invalid ([error]).
class XFilePickerField extends StatefulWidget {
  const XFilePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.directory = true,
    this.extensions = const [],
    this.hint,
    this.error,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool directory;
  final List<String> extensions;
  final String? hint;

  /// Shown under the field when the selection is invalid.
  final String? error;

  @override
  State<XFilePickerField> createState() => _XFilePickerFieldState();
}

class _XFilePickerFieldState extends State<XFilePickerField> {
  late final _controller = TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(XFilePickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.value ?? '') != _controller.text) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    String? picked;
    if (widget.directory) {
      picked = await getDirectoryPath(initialDirectory: widget.value);
    } else {
      final file = await openFile(
        acceptedTypeGroups: [
          if (widget.extensions.isNotEmpty)
            XTypeGroup(
              label: widget.extensions.join(', '),
              extensions: widget.extensions,
            ),
        ],
      );
      picked = file?.path;
    }
    if (picked != null) widget.onChanged(picked);
  }

  void _commit() {
    final text = _controller.text.trim();
    if (text != (widget.value ?? '')) {
      widget.onChanged(text.isEmpty ? null : text);
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextField(
          controller: _controller,
          style: XType.body,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.error == null ? widget.hint : null,
            helperMaxLines: 3,
            errorText: widget.error,
            prefixIcon: Icon(
              widget.directory
                  ? Icons.folder_outlined
                  : Icons.insert_drive_file_outlined,
              size: 18,
            ),
          ),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
        ),
      ),
      const SizedBox(width: XSpace.s2),
      SizedBox(
        height: XSpace.control + 4,
        child: OutlinedButton(onPressed: _browse, child: const Text('Browse…')),
      ),
    ],
  );
}

/// Credential field states (design system §8).
enum XCredentialState { empty, obscured, invalid, verified }

/// A secret input that is always obscured and never echoed elsewhere.
class XCredentialField extends StatelessWidget {
  const XCredentialField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.state = XCredentialState.empty,
    this.error,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final XCredentialState state;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final verified = state == XCredentialState.verified;
    return TextField(
      controller: controller,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        errorText: state == XCredentialState.invalid ? error : null,
        prefixIcon: const Icon(Icons.lock_outline, size: 18),
        suffixIcon: verified
            ? Icon(Icons.verified, color: XStatus.ready.color(context))
            : null,
      ),
    );
  }
}

/// A plain labelled text field in the design system style.
class XTextField extends StatelessWidget {
  const XTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.onChanged,
    this.width,
    this.prefixIcon,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final double? width;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      onChanged: onChanged,
      style: XType.body.copyWith(color: XTheme.of(context).colors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperMaxLines: 2,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 18),
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}
