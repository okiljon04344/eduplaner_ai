class QuizQuestion {
  final String question;
  final List<String> choices;
  final int answerIndex;
  final String explanation;

  const QuizQuestion({
    required this.question,
    required this.choices,
    required this.answerIndex,
    required this.explanation,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final rawChoices = json['choices'] as List<dynamic>? ?? [];
    return QuizQuestion(
      question: json['question'] as String? ?? '',
      choices: rawChoices.map((e) => e.toString()).toList(),
      answerIndex: (json['answerIndex'] as num?)?.toInt() ?? 0,
      explanation: json['explanation'] as String? ?? '',
    );
  }
}
