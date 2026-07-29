import 'package:flutter/material.dart';
import '../../core/constants/subject_colors.dart';

class SubjectPill extends StatelessWidget {
  final String subject;
  const SubjectPill({super.key, required this.subject});

  @override
  Widget build(BuildContext context) {
    final style = SubjectColors.of(subject);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: style.fill, borderRadius: BorderRadius.circular(6)),
      child: Text(subject, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: style.text)),
    );
  }
}
