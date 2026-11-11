import 'package:edu_planner_ai/features/ai_chat/widgets/chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renders **bold** without the stars', () {
    final span = boldMarkdown('a **b** c');
    expect(span.toPlainText(), 'a b c');
    final bold = span.children![1] as TextSpan;
    expect(bold.text, 'b');
    expect(bold.style?.fontWeight, FontWeight.w700);
  });

  test('unbalanced marker stays as plain text', () {
    expect(boldMarkdown('a ** b').toPlainText(), 'a ** b');
  });
}
