import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SubjectStyle {
  final Color fill;
  final Color text;
  final Color dot;
  const SubjectStyle(
      {required this.fill, required this.text, required this.dot});
}

class SubjectColors {
  SubjectColors._();

  // Getters, not const fields: [AppColors]' text/dot tokens flip with the theme,
  // so they must be re-read on every access.
  static Map<String, SubjectStyle> get _map => <String, SubjectStyle>{
        '数学': SubjectStyle(
            fill: AppColors.mathFill,
            text: AppColors.mathText,
            dot: AppColors.mathDot),
        '英語': SubjectStyle(
            fill: AppColors.engFill,
            text: AppColors.engText,
            dot: AppColors.engDot),
        'プログラミング': SubjectStyle(
            fill: AppColors.progFill,
            text: AppColors.progText,
            dot: AppColors.progDot),
        '物理': SubjectStyle(
            fill: AppColors.physFill,
            text: AppColors.physText,
            dot: AppColors.physDot),
        '化学': SubjectStyle(
            fill: AppColors.chemFill,
            text: AppColors.chemText,
            dot: AppColors.chemDot),
        '歴史': SubjectStyle(
            fill: AppColors.histFill,
            text: AppColors.histText,
            dot: AppColors.histDot),
      };

  static SubjectStyle get _fallback => SubjectStyle(
        fill: const Color(0x14FFFFFF),
        text: AppColors.textSecondary,
        dot: AppColors.textMuted,
      );

  static SubjectStyle of(String subject) => _map[subject] ?? _fallback;
  static List<String> get all => _map.keys.toList();

  static const colorOptions = <Color>[
    AppColors.primaryMid,
    AppColors.cyan,
    AppColors.amber,
    AppColors.pink,
    AppColors.blue,
    AppColors.success,
  ];
}
