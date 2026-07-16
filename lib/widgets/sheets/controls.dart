import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/shape_theme.dart';

/// Slider styled per #24.3, with a DM Mono value label to the right and a light
/// haptic tick during drag (#20.1).
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.onStart,
    this.onEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;
  final VoidCallback? onStart;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(label,
                style: ShapeText.labelMD
                    .copyWith(color: ShapeColors.secondaryText)),
          ),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                trackHeight: 4,
                activeTrackColor: ShapeColors.shapeBlue,
                inactiveTrackColor: ShapeColors.trackBase,
                thumbColor: ShapeColors.glassTint,
                overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 11),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChangeStart: (_) {
                  HapticFeedback.selectionClick();
                  onStart?.call();
                },
                onChanged: onChanged,
                onChangeEnd: (_) => onEnd?.call(),
              ),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(display,
                textAlign: TextAlign.right,
                style: ShapeText.monoSize(12)),
          ),
        ],
      ),
    );
  }
}

/// Segmented control - #24.2. Selected option gets a Shape Blue underline.
class Segmented extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.selected,
    this.onChanged,
  });
  final List<String> options;
  final int selected;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: ShapeColors.fieldBase,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: onChanged == null ? null : () => onChanged!(i),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      options[i],
                      style: ShapeText.labelMD.copyWith(
                        color: i == selected
                            ? ShapeColors.primaryText
                            : ShapeColors.secondaryText,
                        fontWeight:
                            i == selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 3,
                      width: 22,
                      decoration: BoxDecoration(
                        color: i == selected
                            ? ShapeColors.shapeBlue
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Row of icon choices used for cap/join/align style pickers (#12.4).
class IconChoiceRow extends StatelessWidget {
  const IconChoiceRow({
    super.key,
    required this.label,
    required this.icons,
    required this.selected,
    required this.onChanged,
  });
  final String label;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(label,
                style: ShapeText.labelMD
                    .copyWith(color: ShapeColors.secondaryText)),
          ),
          for (var i = 0; i < icons.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  width: 40,
                  height: 36,
                  decoration: BoxDecoration(
                    color: i == selected
                        ? ShapeColors.shapeBlue.withValues(alpha: 0.20)
                        : ShapeColors.fieldBase,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: i == selected
                          ? ShapeColors.shapeBlue
                          : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Icon(icons[i],
                      size: 18,
                      color: i == selected
                          ? ShapeColors.primaryText
                          : ShapeColors.secondaryText),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

