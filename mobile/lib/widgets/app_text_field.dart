import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Labeled text field with error state and accessibility semantics. Supports
/// password visibility toggling. The controller is owned here and disposed
/// properly (no leaked controllers).
class AppTextField extends StatefulWidget {
  final String label;
  final String? initialValue;
  final ValueChanged<String> onChanged;
  final String? errorText;
  /// Optional Form-level validator. When set, the field participates in
  /// Form.validate() and shows the returned message as its error text.
  final String? Function(String?)? validator;
  final String? hintText;
  final TextInputType keyboardType;
  final bool obscureText;
  final bool showToggle;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final VoidCallback? onSubmitted;
  final IconData icon;
  final bool autofillHints;
  final String? autofillHintsGroup;

  /// Optional externally-owned controller. When omitted, one is created and
  /// disposed internally.
  final TextEditingController? controller;

  const AppTextField({
    super.key,
    required this.label,
    required this.onChanged,
    this.initialValue,
    this.errorText,
    this.validator,
    this.hintText,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.showToggle = false,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.onSubmitted,
    this.icon = Icons.edit_outlined,
    this.autofillHints = false,
    this.autofillHintsGroup,
    this.controller,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final TextEditingController _controller;
  late final bool _ownsController;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isObscure = widget.obscureText && (!widget.showToggle || _obscure);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.foreground),
        ),
        const SizedBox(height: 7),
        TextFormField(
          key: ValueKey(widget.label),
          controller: _controller,
          keyboardType: widget.keyboardType,
          textCapitalization: widget.textCapitalization,
          obscureText: isObscure,
          textInputAction: widget.textInputAction,
          autocorrect: !widget.obscureText,
          enableSuggestions: !widget.obscureText,
          onChanged: widget.onChanged,
          onFieldSubmitted: (_) => widget.onSubmitted?.call(),
          autofillHints: widget.autofillHints ? [widget.autofillHintsGroup ?? ''] : null,
          decoration: InputDecoration(
            hintText: widget.hintText,
            errorText: widget.errorText,
            errorStyle: const TextStyle(fontSize: 11),
            prefixIcon:
                Icon(widget.icon, size: 18, color: AppColors.muted),
            suffixIcon: widget.showToggle
                ? IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                      size: 18,
                      color: AppColors.muted,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}