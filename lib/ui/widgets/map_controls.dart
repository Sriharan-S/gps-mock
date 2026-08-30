import 'package:flutter/material.dart';

/// A vertical stack of map controls sharing one rounded, elevated surface.
class MapControlGroup extends StatelessWidget {
  const MapControlGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Hairline between two buttons inside a [MapControlGroup].
class MapControlDivider extends StatelessWidget {
  const MapControlDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 8,
      endIndent: 8,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// A single 48dp map control. Passing a null [onPressed] disables it.
class MapControlButton extends StatelessWidget {
  const MapControlButton({
    super.key,
    required this.tooltip,
    required this.child,
    required this.onPressed,
    this.highlighted = false,
  });

  final String tooltip;
  final Widget child;
  final VoidCallback? onPressed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onPressed,
          child: Ink(
            color: highlighted ? scheme.primaryContainer : Colors.transparent,
            child: SizedBox(
              width: 48,
              height: 48,
              child: IconTheme.merge(
                data: IconThemeData(
                  size: 22,
                  color: onPressed == null
                      ? scheme.onSurface.withValues(alpha: .38)
                      : highlighted
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                ),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
