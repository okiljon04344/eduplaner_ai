import 'package:flutter/material.dart';
import '../../core/constants/subject_colors.dart';

class SubjectModel {
  final String name;
  final SubjectStyle style;

  const SubjectModel({required this.name, required this.style});

  static List<SubjectModel> get all =>
      SubjectColors.all.map((name) => SubjectModel(name: name, style: SubjectColors.of(name))).toList();

  Color get fill => style.fill;
  Color get text => style.text;
  Color get dot => style.dot;
}
