import 'package:flutter/material.dart';
import '../../features/assignments/models/assignment_model.dart';

class StatusBadge extends StatelessWidget {
  final AssignmentStatus status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: status.bgColor, borderRadius: BorderRadius.circular(6), border: Border.all(color: status.borderColor)),
      child: Text(status.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: status.textColor)),
    );
  }
}
