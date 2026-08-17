/**
 * EduPlanner AI — Firebase Cloud Functions
 *
 * Security model:
 *   • Every callable function verifies `request.auth` before doing any work.
 *   • Input lengths are capped server-side so oversized payloads cannot reach
 *     the Gemini API or Firestore.
 *   • The Gemini API key is stored in Firebase Secrets, never in source code.
 *   • Raw user content (messages, file bytes) is NEVER written to logs or
 *     Firestore — only derived results (quiz questions, completion percent …).
 *
 * AI data privacy:
 *   • Payloads sent to Gemini are the minimum necessary for each task.
 *   • To opt out of Google using API calls for model training, navigate to
 *     Google Cloud Console → APIs & Services → Generative Language API →
 *     Data Usage, and disable "Improve Google AI products".
 *   • Server-side logs (`logger.*`) never contain prompt text or student data.
 */

import {GoogleGenAI} from '@google/genai';
import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {FieldValue, getFirestore} from 'firebase-admin/firestore';
import {getMessaging} from 'firebase-admin/messaging';
import {HttpsError, onCall} from 'firebase-functions/https';
import {defineSecret} from 'firebase-functions/params';
import {onDocumentUpdated} from 'firebase-functions/v2/firestore';
import {logger} from 'firebase-functions';
import mammoth from 'mammoth';

initializeApp();

const geminiApiKey = defineSecret('GEMINI_API_KEY');

// Module-scope singletons: reused across warm invocations of the same
// instance. `getFirestore()`/`getMessaging()` are cheap after
// `initializeApp()`, but caching avoids the map lookup on every call.
// `GoogleGenAI` needs `geminiApiKey.value()` (only available at runtime),
// so it's lazily built on first use per warm instance.
let _db;
let _messaging;
let _ai;
const db = () => (_db ??= getFirestore());
const messaging = () => (_messaging ??= getMessaging());
const gemini = () => (_ai ??= new GoogleGenAI({apiKey: geminiApiKey.value()}));

const GEMINI_MODEL = 'gemini-flash-latest';

// BCP-47 code from the client's active locale (see `AppStrings.currentLocale`
// in the Flutter app) → English language name for the Gemini prompt. An
// allow-list so an arbitrary client-supplied string can never be injected
// into the prompt. Shared by every AI callable that replies in the user's
// language; falls back to Japanese for an unrecognised/missing code.
const LANGUAGE_NAMES = {
  ja: 'Japanese', en: 'English', uz: 'Uzbek', zh: 'Simplified Chinese',
  zh_TW: 'Traditional Chinese', ko: 'Korean', vi: 'Vietnamese', th: 'Thai',
  id: 'Indonesian', ms: 'Malay', hi: 'Hindi', ar: 'Arabic', es: 'Spanish',
  fr: 'French', de: 'German', pt: 'Portuguese', ru: 'Russian', it: 'Italian',
  tr: 'Turkish', nl: 'Dutch', fil: 'Filipino',
};
const replyLanguageOf = (language) => LANGUAGE_NAMES[language] ?? 'Japanese';

/// Throws the standard `unauthenticated` error every callable function opens
/// with. Centralised so the message/code stays identical across all six
/// callables instead of being retyped at each one.
function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Login is required.');
  }
}

/// `JSON.stringify` a value and cap it to [max] chars — the shared truncation
/// idiom used everywhere untrusted/unbounded data is embedded in a prompt.
function truncatedJson(value, max = 3000) {
  return JSON.stringify(value).slice(0, max);
}

// Bot system prompts. Keep ids in sync with lib/features/ai_chat/models/ai_bot.dart.
// These prompts are tiny (~100 chars each) — well below the ~1024-token minimum
// for Gemini's cached-content API, so caching would add cost without benefit.
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

const QUOTA_ERROR_RE = /quota|rate limit/i;
const INVALID_ARG_ERROR_RE = /invalid|bad request/i;
const UNAVAILABLE_ERROR_RE = /unavailable|timeout|deadline/i;

/// Map any thrown Gemini SDK error into an `HttpsError` with a code the
/// client can distinguish. Never let raw SDK error text (which may include
/// prompt fragments, endpoint URLs, or stack traces) reach the client.
function mapGeminiError(err, japaneseFallback) {
  const status = err?.status ?? err?.response?.status ?? err?.code;
  const message = String(err?.message ?? '');
  logger.error('Gemini call failed', {status, message: message.slice(0, 500)});

  if (status === 429 || QUOTA_ERROR_RE.test(message)) {
    return new HttpsError('resource-exhausted', 'AIの利用上限に達しました。しばらくしてからもう一度お試しください。');
  }
  if (status === 400 || INVALID_ARG_ERROR_RE.test(message)) {
    return new HttpsError('invalid-argument', '入力内容を確認してください。');
  }
  if (status === 401 || status === 403) {
    return new HttpsError('internal', japaneseFallback);
  }
  if (status === 503 || status === 504 || UNAVAILABLE_ERROR_RE.test(message)) {
    return new HttpsError('unavailable', 'AIサーバーが混雑しています。少し時間をおいてお試しください。');
  }
  return new HttpsError('internal', japaneseFallback);
}

/// Shared call+error-mapping wrapper for the four callables that make a
/// single, directly-awaited `generateContent` call and translate any
/// failure via [mapGeminiError]. Not used by `generateQuiz`'s grounding
/// stage, which intentionally catches-and-falls-back instead of throwing.
async function callGemini(config, japaneseFallback) {
  try {
    return await gemini().models.generateContent(config);
  } catch (err) {
    throw mapGeminiError(err, japaneseFallback);
  }
}

/// Extract a JSON object from a Gemini text response. Handles ```json fences,
/// ``` fences, leading/trailing prose ("Here's the JSON: {...}"), and stray
/// backticks. Returns the first balanced `{...}` block found.
function extractJson(raw) {
  if (!raw) return null;
  let text = raw.trim();
  // Strip a leading ```json or ``` fence and a trailing ``` fence, if present.
  text = text.replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/i, '').trim();
  // If the model added prose around the JSON, grab the first balanced object.
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start === -1 || end === -1 || end < start) return null;
  const candidate = text.slice(start, end + 1);
  try {
    return JSON.parse(candidate);
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// chatWithTutor — main hot path. Short prompt + short reply, so 256MiB / 30s
// is comfortable. `concurrency: 40` lets one warm instance serve multiple
// simultaneous students, drastically cutting cold starts vs. the v1 default
// of 1-per-instance. Consider `minInstances: 1` in production if p50 latency
// under load matters more than idle cost (~$5-10/mo per pinned instance).
// ---------------------------------------------------------------------------
export const chatWithTutor = onCall({
  region: 'asia-northeast1',
  secrets: [geminiApiKey],
  memory: '256MiB',
  timeoutSeconds: 120,
  concurrency: 40,
}, async (request) => {
  requireAuth(request);

  const {botId = 'planner', message, assignments = [], classes = [], language} = request.data ?? {};

  // Validate and sanitise all inputs before they reach the AI.
  if (typeof message !== 'string' || message.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'message is required.');
  }
  if (message.length > 4000) {
    throw new HttpsError('invalid-argument', 'メッセージが長すぎます。');
  }
  // Reject botId values that don't exist in our allow-list; fall back safely.
  const resolvedBotId = (typeof botId === 'string' && botId in botPrompts) ? botId : 'planner';
  const replyLanguage = replyLanguageOf(language);

  // Strip each context array to a safe size so a crafted client cannot send
  // an unbounded context that exhausts tokens or manipulates the system prompt.
  const safeAssignments = Array.isArray(assignments) ? assignments.slice(0, 30) : [];
  const safeClasses    = Array.isArray(classes)     ? classes.slice(0, 30)     : [];

  const prompt = [
    botPrompts[resolvedBotId],
    `Reply in ${replyLanguage}.`,
    'Keep answers practical and student-friendly.',
    `Current assignments: ${truncatedJson(safeAssignments)}`,
    `Current classes: ${truncatedJson(safeClasses)}`,
    `Student message: ${message}`
  ].join('\n\n');

  const response = await callGemini(
    {model: GEMINI_MODEL, contents: prompt},
    'AIの応答に失敗しました。もう一度お試しください。',
  );
  return {reply: response.text ?? 'すみません、もう一度質問してください。'};
});

// ---------------------------------------------------------------------------
// deleteAccount — user-initiated. Serial `await` chain replaced with a
// batched fan-out; the messages subcollection can grow large so batch it.
// ---------------------------------------------------------------------------
export const deleteAccount = onCall({
  region: 'asia-northeast1',
  memory: '256MiB',
  timeoutSeconds: 120,
}, async (request) => {
  requireAuth(request);

  const uid = request.auth.uid;
  const firestore = db();

  // Batched delete — 500 is the Firestore batch ceiling; loop until drained.
  const deleteQuery = async (query) => {
    while (true) {
      const snapshot = await query.limit(400).get();
      if (snapshot.empty) return;
      const batch = firestore.batch();
      snapshot.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
      if (snapshot.size < 400) return;
    }
  };

  try {
    await Promise.all([
      deleteQuery(firestore.collection('assignments').where('userId', '==', uid)),
      deleteQuery(firestore.collection('timetables').where('userId', '==', uid)),
      deleteQuery(firestore.collection('ai_chats').doc(uid).collection('messages')),
    ]);
    await Promise.all([
      firestore.collection('ai_chats').doc(uid).delete().catch((err) =>
        logger.warn('deleteAccount: ai_chats doc delete failed', {uid, message: String(err?.message ?? '').slice(0, 300)})),
      firestore.collection('users').doc(uid).delete().catch((err) =>
        logger.warn('deleteAccount: users doc delete failed', {uid, message: String(err?.message ?? '').slice(0, 300)})),
    ]);
    await getAuth().deleteUser(uid);
    return {success: true};
  } catch (err) {
    logger.error('deleteAccount failed', {uid, message: String(err?.message ?? '').slice(0, 500)});
    throw new HttpsError('internal', 'アカウント削除に失敗しました。もう一度お試しください。');
  }
});

const GROUP_CODE_LENGTH = 6;

/// クラス全体での共有 — a student joins a study group's shared timetable by
/// entering its 6-character code. This runs with admin privileges because
/// Firestore rules only let *existing* group members update `memberIds`; a
/// joiner isn't a member yet, so the add must happen server-side.
export const joinGroupByCode = onCall({
  region: 'asia-northeast1',
  memory: '256MiB',
  timeoutSeconds: 120,
}, async (request) => {
  requireAuth(request);
  const {code} = request.data ?? {};
  if (typeof code !== 'string' || code.trim().length !== GROUP_CODE_LENGTH) {
    throw new HttpsError('invalid-argument', 'A valid 6-character code is required.');
  }

  const firestore = db();
  const snapshot = await firestore
    .collection('study_groups')
    .where('code', '==', code.trim().toUpperCase())
    .limit(1)
    .get();
  if (snapshot.empty) {
    throw new HttpsError('not-found', 'No group found for this code.');
  }

  const groupRef = snapshot.docs[0].ref;
  await groupRef.update({memberIds: FieldValue.arrayUnion(request.auth.uid)});
  return {groupId: groupRef.id};
});

/// 休講・変更のアラート — when a shared class's status flips to
/// cancelled/changed, push-notify every other group member via FCM. Silent
/// no-op if the class isn't shared, the status didn't actually change, or no
/// member has a registered token (e.g. notifications disabled).
export const onClassStatusChanged = onDocumentUpdated({
  document: 'timetables/{classId}',
  region: 'asia-northeast1',
  memory: '256MiB',
  timeoutSeconds: 30,
}, async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!before || !after || !after.groupId) return;
  if (after.status === 'normal' || !after.status) return;
  if (before.status === after.status && before.statusNote === after.statusNote) return;

  const firestore = db();
  const groupSnap = await firestore.collection('study_groups').doc(after.groupId).get();
  if (!groupSnap.exists) return;

  const memberIds = (groupSnap.data().memberIds || []).filter((id) => id !== after.userId);
  if (memberIds.length === 0) return;

  // getAll is one round trip instead of N parallel doc reads.
  const userRefs = memberIds.map((id) => firestore.collection('users').doc(id));
  const userDocs = await firestore.getAll(...userRefs);
  const tokens = userDocs.map((d) => d.data()?.fcmToken).filter(Boolean);
  if (tokens.length === 0) return;

  const label = after.status === 'cancelled' ? '休講' : '変更';
  try {
    await messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: `${after.subject}が${label}になりました`,
        body: after.statusNote || `${after.dayOfWeek}曜日 ${after.period}限`,
      },
    });
  } catch (err) {
    logger.error('FCM multicast failed', {groupId: after.groupId, message: String(err?.message ?? '').slice(0, 300)});
  }
});

/// テスト問題の自動生成 — Exam Bot generates a 5-question multiple-choice
/// quiz for a subject on demand, returned as structured JSON (not a chat
/// reply) so the client can render tappable question cards.
export const generateQuiz = onCall({
  region: 'asia-northeast1',
  secrets: [geminiApiKey],
  memory: '512MiB',
  timeoutSeconds: 120,
  concurrency: 20,
}, async (request) => {
  requireAuth(request);
  const {subject, topic = '', useSearch = false, language} = request.data ?? {};
  if (typeof subject !== 'string' || subject.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'subject is required.');
  }
  const trimmedTopic = String(topic ?? '').trim().slice(0, 200);
  const replyLanguage = replyLanguageOf(language);

  // Two-stage when web search is enabled:
  //   Stage 1: googleSearch grounding gathers current facts (JSON output is
  //            not allowed alongside tools, so this stage returns prose).
  //   Stage 2: a second call turns that prose into structured quiz JSON
  //            (`responseMimeType: 'application/json'` needs no tools).
  // Without search: single-pass JSON generation.
  let context = '';
  if (useSearch && trimmedTopic.length > 0) {
    const groundingPrompt = [
      `Research the topic "${trimmedTopic}" within the subject "${subject}" using web search.`,
      'Summarize the 6-10 most important facts a Japanese vocational school student should know.',
      `Reply in ${replyLanguage}, plain text, no markdown, under 800 characters.`
    ].join('\n');
    try {
      const groundResp = await gemini().models.generateContent({
        model: GEMINI_MODEL,
        contents: groundingPrompt,
        config: {tools: [{googleSearch: {}}]},
      });
      context = String(groundResp.text ?? '').slice(0, 2000);
    } catch (err) {
      // Grounding is best-effort. Fall back to model knowledge on failure
      // instead of failing the whole request.
      logger.warn('quiz grounding failed, falling back', {message: String(err?.message ?? '').slice(0, 200)});
    }
  }

  const promptLines = [
    `You are Exam Bot. Create exactly 5 multiple-choice quiz questions for the subject "${subject}"${trimmedTopic ? ` specifically about "${trimmedTopic}"` : ''}, suitable for a Japanese vocational school student.`,
  ];
  if (context) {
    promptLines.push('Base the questions on the following up-to-date facts:', context);
  }
  promptLines.push(
    `Reply in ${replyLanguage}.`,
    'Vary difficulty across the 5 questions (2 easy, 2 medium, 1 hard).',
    'Return ONLY valid JSON matching this exact shape:',
    '{"questions":[{"question":"...","choices":["...","...","...","..."],"answerIndex":0,"explanation":"..."}]}',
    `Each question must have exactly 4 choices, answerIndex is the 0-based index of the correct choice, and explanation is 1-2 sentences in ${replyLanguage}.`,
  );
  const prompt = promptLines.join('\n');

  const response = await callGemini(
    {model: GEMINI_MODEL, contents: prompt, config: {responseMimeType: 'application/json'}},
    'クイズの生成に失敗しました。もう一度お試しください。',
  );

  const parsed = extractJson(response.text ?? '');
  if (!parsed) {
    throw new HttpsError('internal', 'クイズの生成に失敗しました。もう一度お試しください。');
  }

  // Shape-validate — don't leak malformed AI output to the client.
  const questions = Array.isArray(parsed.questions)
    ? parsed.questions.filter((q) =>
        q && typeof q.question === 'string' &&
        Array.isArray(q.choices) && q.choices.length === 4 &&
        Number.isInteger(q.answerIndex) && q.answerIndex >= 0 && q.answerIndex < 4)
    : [];
  if (questions.length === 0) {
    throw new HttpsError('internal', 'クイズの生成に失敗しました。もう一度お試しください。');
  }
  return {questions, grounded: context.length > 0};
});

/// 苦手分野の分析 — the client aggregates per-subject assignment stats
/// locally (no AI needed for counting) and sends just the summary numbers
/// here; Gemini turns that into a short, actionable Japanese analysis.
export const analyzeWeakArea = onCall({
  region: 'asia-northeast1',
  secrets: [geminiApiKey],
  memory: '256MiB',
  timeoutSeconds: 120,
  concurrency: 20,
}, async (request) => {
  requireAuth(request);
  const {stats, language} = request.data ?? {};
  if (!Array.isArray(stats) || stats.length === 0) {
    throw new HttpsError('invalid-argument', 'stats is required.');
  }
  // Cap stats array to prevent unbounded prompts.
  if (stats.length > 20) {
    throw new HttpsError('invalid-argument', 'stats array too large.');
  }

  const replyLanguage = replyLanguageOf(language);

  const prompt = [
    'You are Focus Bot, a study analytics assistant for a vocational school student.',
    'Below is per-subject assignment statistics as JSON: subject, totalCount, completedCount, overdueCount, avgDifficulty (1-5).',
    truncatedJson(stats),
    'Identify the 1-2 weakest subjects (highest overdue/incomplete ratio and/or difficulty) and give one concrete, practical tip for each.',
    `Reply in ${replyLanguage}, 3 sentences maximum, plain text with no markdown formatting.`
  ].join('\n\n');

  const response = await callGemini(
    {model: GEMINI_MODEL, contents: prompt},
    '分析に失敗しました。もう一度お試しください。',
  );
  return {analysis: response.text ?? '分析に必要なデータが不足しています。'};
});

// 10MB decoded ceiling — base64 inflates size by ~4/3, so this bounds the
// request payload too. Chosen to comfortably fit a phone photo or a
// multi-page scanned PDF while keeping Gemini's request size sane.
const MAX_FILE_BYTES = 10 * 1024 * 1024;
const MAX_EXTRACTED_TEXT_CHARS = 6000;

// Gemini reads images/PDF natively via inlineData; .docx/.txt are extracted
// to plain text server-side first since Gemini has no native Word support.
const NATIVE_MIME_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'application/pdf']);
const DOCX_MIME_TYPE = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
const TEXT_MIME_TYPE = 'text/plain';

/// 課題の自動チェック — a student uploads a photo/PDF/Word/text file of
/// their completed assignment; Gemini estimates how much is done, lists
/// what's missing, and gives one study tip. The file itself is never
/// written to Storage or logged — it exists only in memory for the
/// duration of this call, matching the "no raw submission is persisted"
/// privacy decision for this feature.
//
// Memory bump: 10MB base64 input decodes to ~7.5MB Buffer, then mammoth's
// DOCX-unzip + XML parse can temporarily hold several multiples of that in
// V8 heap. 512MiB gave OOM crashes in past testing; 1GiB is the safe floor.
export const analyzeAssignmentSubmission = onCall({
  region: 'asia-northeast1',
  secrets: [geminiApiKey],
  memory: '1GiB',
  timeoutSeconds: 120,
  concurrency: 5,
}, async (request) => {
  requireAuth(request);

  const {subject, title = '', description = '', fileBase64, mimeType} = request.data ?? {};
  // Validate and cap all text fields before they enter the AI prompt.
  if (typeof subject !== 'string' || subject.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'subject is required.');
  }
  if (subject.length > 100) {
    throw new HttpsError('invalid-argument', 'subject is too long.');
  }
  if (typeof fileBase64 !== 'string' || fileBase64.length === 0) {
    throw new HttpsError('invalid-argument', 'fileBase64 is required.');
  }
  if (typeof mimeType !== 'string' || !(NATIVE_MIME_TYPES.has(mimeType) || mimeType === DOCX_MIME_TYPE || mimeType === TEXT_MIME_TYPE)) {
    throw new HttpsError('invalid-argument', 'Unsupported file type.');
  }
  if (fileBase64.length > MAX_FILE_BYTES * 1.4) {
    throw new HttpsError('invalid-argument', 'ファイルサイズが大きすぎます。10MB以下のファイルをお試しください。');
  }

  const instructions = [
    `You are Exam Bot, reviewing a student's submitted work for the subject "${subject}"${title ? `, assignment titled "${title}"` : ''}.`,
    description ? `Assignment instructions/description: ${description.slice(0, 1000)}` : '',
    'Look at the submitted work and:',
    '1. Estimate what percentage of the assignment appears complete (0-100).',
    '2. List specific parts/questions that appear missing, incomplete, or incorrect (short bullet phrases).',
    '3. Give one practical, concrete study tip for what the student should review next.',
    'Reply in Japanese.',
    'Return ONLY valid JSON with no markdown code fences, matching this exact shape:',
    '{"completionPercent": 0, "missingParts": ["...", "..."], "advice": "..."}',
    'If the content is unrelated to the stated subject/assignment, still answer honestly with a low completionPercent and say so in missingParts.'
  ].filter(Boolean).join('\n');

  let contents;
  if (NATIVE_MIME_TYPES.has(mimeType)) {
    contents = [{role: 'user', parts: [{text: instructions}, {inlineData: {mimeType, data: fileBase64}}]}];
  } else {
    let buffer = Buffer.from(fileBase64, 'base64');
    let extractedText;
    try {
      if (mimeType === DOCX_MIME_TYPE) {
        const result = await mammoth.extractRawText({buffer});
        extractedText = result.value;
      } else {
        extractedText = buffer.toString('utf8');
      }
    } catch (err) {
      logger.error('File extraction failed', {mimeType, message: String(err?.message ?? '').slice(0, 300)});
      throw new HttpsError('invalid-argument', 'ファイルの読み取りに失敗しました。');
    } finally {
      // Hint V8 that the raw file buffer is done — helps peak memory under
      // load since mammoth's own intermediate allocations are still hot.
      buffer = null;
    }
    extractedText = (extractedText || '').slice(0, MAX_EXTRACTED_TEXT_CHARS);
    if (extractedText.trim().length === 0) {
      throw new HttpsError('invalid-argument', 'ファイルからテキストを読み取れませんでした。');
    }
    contents = [{role: 'user', parts: [{text: `${instructions}\n\nSubmitted work (extracted text):\n${extractedText}`}]}];
  }

  const response = await callGemini(
    {model: GEMINI_MODEL, contents, config: {responseMimeType: 'application/json'}},
    '課題のチェックに失敗しました。もう一度お試しください。',
  );

  // Never log `response.text` or the submitted content — it's the student's work.
  const parsed = extractJson(response.text ?? '');
  if (!parsed) {
    throw new HttpsError('internal', '課題のチェックに失敗しました。もう一度お試しください。');
  }

  const completionPercent = Math.max(0, Math.min(100, Number(parsed.completionPercent) || 0));
  const missingParts = Array.isArray(parsed.missingParts)
    ? parsed.missingParts.map((p) => String(p).slice(0, 200)).slice(0, 20)
    : [];
  const advice = typeof parsed.advice === 'string' ? parsed.advice.slice(0, 1000) : '';

  return {completionPercent, missingParts, advice};
});
