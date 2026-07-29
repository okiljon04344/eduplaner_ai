import {GoogleGenAI} from '@google/genai';
import {initializeApp} from 'firebase-admin/app';
import {HttpsError, onCall} from 'firebase-functions/https';
import {defineSecret} from 'firebase-functions/params';

initializeApp();

const geminiApiKey = defineSecret('GEMINI_API_KEY');

const botPrompts = {
  planner: 'You are Planner Bot, a concise study planning assistant.',
  math: 'You are Math Bot. Explain math step by step with short examples.',
  english: 'You are English Bot. Help with reading, writing, and vocabulary.',
  programming: 'You are Code Bot. Help with Flutter and programming tasks.',
  physics: 'You are Physics Bot. Explain formulas through practical examples.',
  chemistry: 'You are Chem Bot. Help with chemistry concepts and lab study.',
  history: 'You are History Bot. Explain timelines, causes, and effects.',
  exam: 'You are Exam Bot. Create revision plans and quiz-style practice.',
  focus: 'You are Focus Bot. Give focused, practical study discipline advice.',
  career: 'You are Career Bot. Help with school goals and career planning.'
};

export const chatWithTutor = onCall({secrets: [geminiApiKey]}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Login is required.');
  }

  const {botId = 'planner', message, assignments = [], classes = []} = request.data ?? {};
  if (typeof message !== 'string' || message.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'message is required.');
  }

  const ai = new GoogleGenAI({apiKey: geminiApiKey.value()});
  const prompt = [
    botPrompts[botId] ?? botPrompts.planner,
    'Reply in Japanese by default. If the user writes Uzbek, reply in Uzbek.',
    'Keep answers practical and student-friendly.',
    `Current assignments: ${JSON.stringify(assignments).slice(0, 3000)}`,
    `Current classes: ${JSON.stringify(classes).slice(0, 3000)}`,
    `Student message: ${message}`
  ].join('\n\n');

  const response = await ai.models.generateContent({
    model: 'gemini-2.5-flash',
    contents: prompt
  });

  return {reply: response.text ?? 'すみません、もう一度質問してください。'};
});
