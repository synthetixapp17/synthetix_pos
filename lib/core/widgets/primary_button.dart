import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final double elevation;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final bool isFullWidth;
  final TextStyle? textStyle;
  final bool isLoading;

  const PrimaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.elevation = 8.0,
    this.borderRadius = 16.0,
    this.padding = const EdgeInsets.symmetric(vertical: 16),
    this.isFullWidth = true,
    this.textStyle,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = ElevatedButton.styleFrom(
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      padding: padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      elevation: elevation,
      shadowColor: colors.primary.withValues(alpha: 0.3),
      minimumSize: isFullWidth ? const Size.fromHeight(50) : null,
    );

    if (icon != null) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: ElevatedButton.icon(
          onPressed: isLoading ? null : onPressed,
          icon: isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: colors.onPrimary,
                    strokeWidth: 2,
                  ),
                )
              : Icon(icon),
          label: Text(
            label,
            style: textStyle,
          ),
          style: style,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: style,
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: colors.onPrimary,
                  strokeWidth: 2,
                ),
              )
            : Text(
                label,
                style: textStyle,
              ),
      ),
    );
  }
}
