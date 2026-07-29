import 'package:flutter/material.dart';

/// Material 3 segmented choice using filled selected buttons and tonal
/// unselected buttons. Unlike [SegmentedButton], it deliberately has no
/// outline so the selected state reads from color and elevation alone.
class M3SegmentedControl<T> extends StatelessWidget {
  const M3SegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.compact = false,
  });

  final List<M3Segment<T>> options;
  final T selected;
  final ValueChanged<T>? onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(20);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < options.length; index++)
          Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : 2),
            child: _button(
              context,
              options[index],
              RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                  topLeft: index == 0 ? radius : Radius.zero,
                  bottomLeft: index == 0 ? radius : Radius.zero,
                  topRight: index == options.length - 1 ? radius : Radius.zero,
                  bottomRight:
                      index == options.length - 1 ? radius : Radius.zero,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _button(
    BuildContext context,
    M3Segment<T> option,
    OutlinedBorder shape,
  ) {
    final isSelected = option.value == selected;
    final style = ButtonStyle(
      shape: WidgetStatePropertyAll(shape),
      minimumSize: WidgetStatePropertyAll(
        Size(compact ? 0 : 104, compact ? 40 : 44),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16),
      ),
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
    );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (option.icon != null) ...[
          Icon(option.icon, size: 18),
          const SizedBox(width: 8),
        ],
        Text(option.label),
      ],
    );
    final callback =
        onSelected == null ? null : () => onSelected!(option.value);
    return isSelected
        ? FilledButton(onPressed: callback, style: style, child: child)
        : FilledButton.tonal(onPressed: callback, style: style, child: child);
  }
}

class M3Segment<T> {
  const M3Segment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}
