// Feature 024: the controls the icon and splash tabs share.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/design_system.dart';
import 'studio_model.dart';

/// The controls beside the preview, filling the space it is given. In a wide
/// window each side scrolls by itself, so the preview stays in view whichever
/// control is being changed, and the actions stay under it.
class StudioLayout extends StatelessWidget {
  const StudioLayout({
    super.key,
    required this.controls,
    required this.preview,
    required this.actions,
  });

  final Widget controls;
  final Widget preview;
  final Widget actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 980) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              preview,
              const SizedBox(height: XSpace.s2),
              actions,
              const SizedBox(height: XSpace.s3),
              controls,
            ],
          ),
        );
      }
      // Room on the right of each side for its scrollbar.
      Widget side(Widget child) => SingleChildScrollView(
        padding: const EdgeInsets.only(right: XSpace.s3),
        child: child,
      );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wide enough for a slider, its number and the label without clipping;
          // wider where the window allows.
          SizedBox(
            width: (constraints.maxWidth * 0.42).clamp(500.0, 600.0),
            child: side(controls),
          ),
          const SizedBox(width: XSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: side(preview)),
                const SizedBox(height: XSpace.s2),
                actions,
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// A heading over a group of controls.
class StudioSection extends StatelessWidget {
  const StudioSection(this.title, {super.key, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: XSpace.s3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: XType.body.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: XSpace.s2),
        for (final child in children)
          Padding(
            padding: const EdgeInsets.only(bottom: XSpace.s2),
            child: child,
          ),
      ],
    ),
  );
}

/// A choice shown as a drop-down, with its label.
class StudioDropdown extends StatelessWidget {
  const StudioDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;

  /// Value to its label.
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    // A saved design can name what this version does not have.
    initialValue: options.containsKey(value) ? value : null,
    isDense: true,
    // A narrow field ends its label in dots instead of overflowing.
    isExpanded: true,
    decoration: InputDecoration(labelText: label, isDense: true),
    items: [
      for (final MapEntry(:key, value: text) in options.entries)
        DropdownMenuItem(value: key, child: Text(text)),
    ],
    onChanged: (selected) {
      if (selected != null) onChanged(selected);
    },
  );
}

/// A colour: swatches, and `#RRGGBB` to type any other.
class StudioColor extends StatefulWidget {
  const StudioColor({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowAuto = false,
    this.allowNone = false,
    this.noneLabel = 'None',
  });

  final String label;

  /// `#RRGGBB`, `auto`, or null for none.
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowAuto;
  final bool allowNone;
  final String noneLabel;

  static const swatches = [
    '#FFFFFF',
    '#000000',
    '#0A84FF',
    '#5E5CE6',
    '#30D158',
    '#FF9F0A',
    '#FF453A',
  ];

  static Color? parse(String? text) {
    if (text == null || !isHexColor(text)) return null;
    return Color(int.parse('FF${text.trim().substring(1)}', radix: 16));
  }

  @override
  State<StudioColor> createState() => _StudioColorState();
}

class _StudioColorState extends State<StudioColor> {
  late final _controller = TextEditingController(text: _hex(widget.value));

  static String _hex(String? value) =>
      value == null || value == 'auto' ? '' : value;

  @override
  void didUpdateWidget(StudioColor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = _hex(widget.value);
    if (_controller.text != text && isHexColor(text)) _controller.text = text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.value;
    Widget textChip(String label, String? value) => Padding(
      padding: const EdgeInsets.only(right: XSpace.s1),
      child: ChoiceChip(
        label: Text(label),
        visualDensity: VisualDensity.compact,
        selected: selected == value,
        onSelected: (_) => widget.onChanged(value),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: XType.support),
        const SizedBox(height: XSpace.s1),
        Wrap(
          spacing: XSpace.s1,
          runSpacing: XSpace.s1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.allowAuto) textChip('Auto', 'auto'),
            if (widget.allowNone) textChip(widget.noneLabel, null),
            for (final swatch in StudioColor.swatches)
              Semantics(
                label: 'Colour $swatch',
                button: true,
                selected: selected == swatch,
                child: InkWell(
                  onTap: () => widget.onChanged(swatch),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: StudioColor.parse(swatch),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected == swatch
                            ? Theme.of(context).colorScheme.primary
                            : const Color(0x55808080),
                        width: selected == swatch ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            XTextField(
              controller: _controller,
              label: '#RRGGBB',
              width: 100,
              onChanged: (typed) {
                final text = typed.trim();
                if (text.isNotEmpty) {
                  widget.onChanged(text);
                } else if (widget.allowAuto) {
                  widget.onChanged('auto');
                } else if (widget.allowNone) {
                  widget.onChanged(null);
                } else {
                  widget.onChanged(text);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// A value on a slider, with a field beside it for the number: type it, or
/// press the up and down arrows in the field to change it one step at a time
/// (Shift or Page Up and Page Down: ten steps). Whatever is typed is kept
/// inside the range and on a step.
class StudioSlider extends StatefulWidget {
  const StudioSlider({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    this.min = 0,
    this.unit = '%',
    this.step = 1,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;

  /// The smallest change; the CLI takes decimals where this is below 1.
  final double step;
  final ValueChanged<double> onChanged;

  @override
  State<StudioSlider> createState() => _StudioSliderState();
}

class _StudioSliderState extends State<StudioSlider> {
  late final _controller = TextEditingController(text: _format(widget.value));
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Leaving the field shows the value that was kept, not what was typed.
    _focus.addListener(() {
      if (!_focus.hasFocus) _show(widget.value);
    });
  }

  @override
  void didUpdateWidget(StudioSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus) _show(widget.value);
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// `12`, `12.5`: no trailing zeros.
  static String _format(double value) {
    final text = value.toStringAsFixed(2);
    return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
  }

  void _show(double value) {
    final text = _format(value);
    if (_controller.text != text) _controller.text = text;
  }

  /// Inside the range, on a step counted from the minimum.
  double _snap(double value) {
    final steps = ((value - widget.min) / widget.step).round();
    return (widget.min + steps * widget.step).clamp(widget.min, widget.max);
  }

  void _commit(double value) {
    final next = _snap(value);
    if (next != widget.value) widget.onChanged(next);
  }

  /// What the field holds, or the current value while it holds no number.
  double get _typed =>
      double.tryParse(_controller.text.trim().replaceAll(',', '.')) ??
      widget.value;

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final big = HardwareKeyboard.instance.isShiftPressed ? 10 : 1;
    final steps = switch (key) {
      LogicalKeyboardKey.arrowUp => big,
      LogicalKeyboardKey.arrowDown => -big,
      LogicalKeyboardKey.pageUp => 10,
      LogicalKeyboardKey.pageDown => -10,
      _ => 0,
    };
    if (steps == 0) return KeyEventResult.ignored;
    final next = _snap(_typed + steps * widget.step);
    _controller.value = TextEditingValue(
      text: _format(next),
      selection: TextSelection.collapsed(offset: _format(next).length),
    );
    _commit(next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit.trim();
    return Row(
      children: [
        SizedBox(width: 88, child: Text(widget.label, style: XType.support)),
        Expanded(
          child: Slider(
            value: widget.value.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: ((widget.max - widget.min) / widget.step).round(),
            label: '${_format(widget.value)}${widget.unit}',
            onChanged: (next) => _commit(next),
          ),
        ),
        SizedBox(
          width: 84,
          child: Focus(
            onKeyEvent: _key,
            child: Semantics(
              label: '${widget.label} value',
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                style: XType.body.copyWith(
                  color: XTheme.of(context).colors.textPrimary,
                ),
                textAlign: TextAlign.end,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: false,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: unit.isEmpty ? null : unit,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: XSpace.s2,
                    vertical: XSpace.s2,
                  ),
                ),
                onChanged: (text) {
                  final number = double.tryParse(
                    text.trim().replaceAll(',', '.'),
                  );
                  if (number != null) _commit(number);
                },
                onSubmitted: (_) => _show(widget.value),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One value for all sides, or four, with a button to switch (AC-024-17).
class StudioSides extends StatelessWidget {
  const StudioSides({
    super.key,
    required this.label,
    required this.sides,
    required this.max,
    required this.onChanged,
    this.unit = '%',
    this.step = 1,
    this.alwaysSplit = false,
  });

  final String label;
  final FourSides sides;
  final double max;
  final String unit;
  final double step;

  /// One value for all sides would do nothing here, so it is not offered.
  final bool alwaysSplit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    const names = ['Top', 'Right', 'Bottom', 'Left'];
    final split = alwaysSplit || sides.split;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: split
                  ? Text(label, style: XType.support)
                  : StudioSlider(
                      label: label,
                      value: sides.values.first,
                      max: max,
                      step: step,
                      unit: unit,
                      onChanged: (value) {
                        sides.set(0, value);
                        onChanged();
                      },
                    ),
            ),
            if (!alwaysSplit)
              XIconButton(
                icon: sides.split ? Icons.crop_square : Icons.more_horiz,
                tooltip: sides.split
                    ? 'Use one $label value'
                    : 'Set each side of $label',
                onPressed: () {
                  sides.split = !sides.split;
                  if (!sides.split) sides.set(0, sides.values.first);
                  onChanged();
                },
              ),
          ],
        ),
        if (split)
          for (var side = 0; side < 4; side++)
            StudioSlider(
              label: names[side],
              value: sides.values[side],
              max: max,
              step: step,
              unit: unit,
              onChanged: (value) {
                sides.values[side] = value;
                onChanged();
              },
            ),
      ],
    );
  }
}
