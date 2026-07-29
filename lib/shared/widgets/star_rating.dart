import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class StarRating extends StatefulWidget {
  final int initialRating;
  final ValueChanged<int>? onChanged;
  final bool readOnly;
  const StarRating({super.key, required this.initialRating, this.onChanged, this.readOnly = false});

  @override
  State<StarRating> createState() => _StarRatingState();
}

class _StarRatingState extends State<StarRating> {
  late int rating;

  @override
  void initState() {
    super.initState();
    rating = widget.initialRating.clamp(1, 5);
  }

  @override
  void didUpdateWidget(covariant StarRating oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialRating != widget.initialRating) rating = widget.initialRating.clamp(1, 5);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final value = i + 1;
        return GestureDetector(
          onTap: widget.readOnly ? null : () {
            setState(() => rating = value);
            widget.onChanged?.call(value);
          },
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(value <= rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 26, color: value <= rating ? AppColors.amber : AppColors.textMuted),
          ),
        );
      }),
    );
  }
}
