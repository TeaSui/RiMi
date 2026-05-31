import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Pill filter chip — ink when active (matches CatChips / FilterChips).
class PillChip extends StatelessWidget {
  const PillChip({super.key, required this.label, required this.active, required this.onTap, this.activeColor = RM.ink, this.activeText = Colors.white});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color activeColor;
  final Color activeText;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? activeColor : RM.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? activeColor : RM.line),
        ),
        child: Text(label, style: RMType.body(size: 12.5, weight: active ? FontWeight.w700 : FontWeight.w600, color: active ? activeText : RM.ink70)),
      ),
    );
  }
}

/// iOS-style toggle switch.
class RmToggle extends StatelessWidget {
  const RmToggle({super.key, required this.value, required this.onTap, this.color = RM.herb});
  final bool value;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 42,
        height: 25,
        decoration: BoxDecoration(color: value ? color : RM.line, borderRadius: BorderRadius.circular(13)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 19,
            height: 19,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 3, offset: const Offset(0, 1))],
            ),
          ),
        ),
      ),
    );
  }
}

/// Labeled text field used inside composer sheets.
class RmTextField extends StatelessWidget {
  const RmTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboard,
    this.autofocus = false,
    this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboard;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.muted)),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          keyboardType: keyboard,
          autofocus: autofocus,
          onChanged: onChanged,
          style: RMType.body(size: 14),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: RM.card,
            hintText: hint,
            hintStyle: RMType.body(size: 14, color: RM.faint),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: RM.line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: RM.brand, width: 1.5)),
          ),
        ),
      ],
    );
  }
}

/// Header row for a bottom-sheet composer (title + close).
class SheetHeader extends StatelessWidget {
  const SheetHeader(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(children: [
            Expanded(child: Text(title, style: RMType.display(size: 20))),
            GestureDetector(onTap: () => Navigator.of(context).pop(), child: const Icon(Icons.close_rounded, size: 24, color: RM.ink)),
          ]),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// Full-width primary action button used at the foot of sheets.
class SheetSubmit extends StatelessWidget {
  const SheetSubmit({super.key, required this.label, required this.enabled, required this.onPressed});
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: RM.brand,
          disabledBackgroundColor: RM.line,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label, style: RMType.body(size: 15, weight: FontWeight.w700, color: enabled ? Colors.white : RM.faint)),
      ),
    );
  }
}
