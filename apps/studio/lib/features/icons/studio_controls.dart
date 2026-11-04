// Feature 024: the controls the icon and splash tabs share.
import 'package:flutter/material.dart';

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
      if (constraints.maxWidth < 860) {
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
          SizedBox(width: 412, child: side(controls)),
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

/// A value on a slider with its number.
class StudioSlider extends StatelessWidget {
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

  String get _shown => value == value.roundToDouble()
      ? '${value.round()}$unit'
      : '${value.toStringAsFixed(1)}$unit';

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 96, child: Text('$label $_shown', style: XType.support)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) / step).round(),
          label: _shown,
          onChanged: (next) => onChanged((next / step).round() * step),
        ),
      ),
    ],
  );
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
