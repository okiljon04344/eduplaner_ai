// Compare AI providers (Gemini vs Claude) or run `--smoke` across every task
// defined in `AI_TASK_CONFIG`.
// Usage:
//   npm run ai:smoke -- --provider=claude
//   npm run ai:compare -- --out=compare_results.jsonl
//
// Excluded from `npm test` (`test/*.test.js`). Never logs response text or API keys.

import { appendFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import {
  AI_TASK_CONFIG,
  calculateRequestCostUsd,
  resolveActiveProviderName,
  resolveTaskSettings,
} from '../ai/ai_config.js';
import { AiError, classifyRawAiError, extractSafeErrorDiag } from '../ai/ai_errors.js';
import { getProvider } from '../ai/ai_provider.js';
import { SECRET_NAMES, resolveProviderApiKey } from './ai_keys.mjs';

const FN_DIR = dirname(dirname(fileURLToPath(import.meta.url)));
const ROOT_DIR = resolve(FN_DIR, '..');
const DEFAULT_SCRIPT_TIMEOUT_MS = 20_000;
const DEFAULT_SCRIPT_MAX_RETRIES = 1;

function withHardTimeout(promise, ms, provider) {
  let timer;
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(() => {
      reject(
        new AiError({
          kind: 'timeout',
          provider,
          status: 504,
          diag: {
            httpStatus: 504,
            errorCode: 'ETIMEDOUT',
            errorName: 'TimeoutError',
            host: provider === 'claude' ? 'api.anthropic.com' : 'generativelanguage.googleapis.com',
          },
        }),
      );
    }, ms);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => clearTimeout(timer));
}

function isNetworkFailure(errorKind, diag) {
  if (errorKind === 'timeout') return true;
  const code = String(diag?.errorCode ?? '');
  const name = String(diag?.errorName ?? '');
  return (
    /^(ENOTFOUND|ECONNRESET|ETIMEDOUT|ECONNREFUSED|EAI_AGAIN|EHOSTUNREACH|UND_ERR_CONNECT_TIMEOUT|UND_ERR_HEADERS_TIMEOUT|UND_ERR_BODY_TIMEOUT)$/.test(code) ||
    name === 'fetch failed' ||
    name === 'APIConnectionTimeoutError' ||
    name === 'APIConnectionError' ||
    name === 'TimeoutError'
  );
}

function parseDotEnvFile(filePath) {
  if (!existsSync(filePath)) return;
  const raw = readFileSync(filePath, 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let val = trimmed.slice(eq + 1).trim();
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    if (!process.env[key]) {
      process.env[key] = val;
    }
  }
}

export function loadLocalEnvAndSecrets(fnDir = FN_DIR) {
  parseDotEnvFile(`${fnDir}/.env`);
  parseDotEnvFile(`${fnDir}/.env.local`);
}

export function resolveKeysOrThrow(
  providers,
  { keyResolver = (name) => resolveProviderApiKey(name, { rootDir: ROOT_DIR, fnDir: FN_DIR }) } = {},
) {
  const apiKeys = {};
  const missing = [];
  for (const name of providers) {
    const resolved = keyResolver(name);
    if (resolved?.ok && resolved.key) {
      apiKeys[name] = resolved.key;
    } else {
      missing.push(SECRET_NAMES[name] || name);
    }
  }
  if (missing.length > 0) {
    const err = new Error(
      `Kalit topilmadi: ${missing.join(', ')} (process.env, functions/.secret.local yoki Firebase Secret Manager da yo‘q).`,
    );
    err.code = 'MISSING_API_KEY';
    throw err;
  }
  return apiKeys;
}

function extractFirstJson(raw) {
  if (!raw) return null;
  const cleaned = String(raw)
    .trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/```\s*$/i, '')
    .trim();
  const start = cleaned.indexOf('{');
  const end = cleaned.lastIndexOf('}');
  if (start === -1 || end === -1 || end < start) return null;
  try {
    return JSON.parse(cleaned.slice(start, end + 1));
  } catch {
    return null;
  }
}

async function buildSmokeRequestForTask(task, providerName) {
  const settings = resolveTaskSettings(task, providerName);
  const base = {
    task,
    model: settings.model,
    maxTokens: settings.maxTokens,
    timeoutMs: settings.timeoutMs,
    responseFormat: settings.responseFormat,
    webSearch: settings.webSearch,
    webSearchType: settings.webSearchType,
    webSearchMaxUses: settings.webSearchMaxUses,
    jsonSchema: settings.jsonSchema,
    thinking: settings.claude?.thinking,
    effort: settings.claude?.effort,
  };

  switch (task) {
    case 'aiStudyTip':
      return {
        ...base,
        systemInstruction: 'Give 1 short tip in Japanese.',
        contents: '10分勉強のヒントを1文で。',
      };
    case 'analyzeWeakArea':
      return {
        ...base,
        systemInstruction: 'Identify weakest subject in 1 sentence.',
        contents: '[{"subject":"数学","totalCount":3,"completedCount":1,"overdueCount":1,"avgDifficulty":4}]',
      };
    case 'chatWithTutor':
      return {
        ...base,
        systemInstruction: 'Reply briefly in Japanese.',
        contents: '1+1は?',
      };
    case 'generateQuiz:grounding':
      return {
        ...base,
        systemInstruction: 'Summarize 2 short facts in Japanese.',
        contents: '日本の祝日「春分の日」について2行で。',
      };
    case 'generateQuiz':
      return {
        ...base,
        systemInstruction: 'Return ONLY JSON: {"questions":[{"question":"...","choices":["A","B","C","D"],"answerIndex":0,"explanation":"..."}]}',
        contents: '算数「足し算」の超短い1問をJSONで。',
      };
    case 'analyzeAssignmentSubmission': {
      const tinyPng = await sharp({
        create: { width: 64, height: 64, channels: 3, background: '#FFFFFF' },
      }).png().toBuffer();
      return {
        ...base,
        systemInstruction: 'Return ONLY JSON: {"completionPercent":50,"missingParts":[],"advice":"ok"}',
        contents: [{
          role: 'user',
          parts: [
            { text: 'Subject: 数学' },
            { type: 'image', mimeType: 'image/png', data: tinyPng.toString('base64') },
          ],
        }],
      };
    }
    case 'previewTimetableImport':
      return {
        ...base,
        systemInstruction: 'Return ONLY JSON: {"slots":[{"dayOfWeek":"月","period":"1","subject":"数学","teacher":"[TEACHER_1]"}]}',
        contents: '月曜 1限 数学 [TEACHER_1]',
      };
    default:
      return {
        ...base,
        contents: 'こんにちは',
      };
  }
}

/**
 * Smoke-tests EVERY task in `AI_TASK_CONFIG` once against the specified
 * provider(s). Resolves API keys once upfront (`env -> .secret.local ->
 * Secret Manager`) and never invokes any API if a key is missing.
 * Returns summary rows and NEVER includes AI output text.
 */
export async function runSmokeTests({
  providers = ['claude'],
  providerFactory,
  apiKeys,
  keyResolver,
  timeoutMs = DEFAULT_SCRIPT_TIMEOUT_MS,
  maxRetries = DEFAULT_SCRIPT_MAX_RETRIES,
  onProgress,
} = {}) {
  const tasks = Object.keys(AI_TASK_CONFIG);
  const results = [];

  const resolvedKeys = providerFactory
    ? (apiKeys ?? {})
    : (apiKeys ?? resolveKeysOrThrow(providers, { keyResolver }));

  const effectiveFactory = providerFactory ??
    ((name) => getProvider({ providerName: name, apiKey: resolvedKeys[name], maxRetries }));

  const totalSteps = providers.length * tasks.length;
  let stepIndex = 0;

  for (const providerName of providers) {
    if (!providerFactory && !String(resolvedKeys[providerName] ?? '').trim()) {
      const secretName = SECRET_NAMES[providerName] || providerName;
      throw new Error(`Kalit topilmadi: ${secretName}`);
    }
    const provider = effectiveFactory(providerName);
    for (const task of tasks) {
      stepIndex += 1;
      const baseReq = await buildSmokeRequestForTask(task, providerName);
      const effectiveTimeout = Math.min(baseReq.timeoutMs ?? timeoutMs, timeoutMs);
      const req = { ...baseReq, timeoutMs: effectiveTimeout, maxRetries };
      const t0 = performance.now();
      let row;
      try {
        const res = await withHardTimeout(provider.generate(req), effectiveTimeout + 2_000, providerName);
        const latencyMs = Math.round(performance.now() - t0);
        row = {
          task,
          provider: providerName,
          model: res.model || req.model,
          ok: true,
          status: 'OK',
          errorKind: null,
          latencyMs,
          inputTokens: res.usage?.inputTokens ?? 0,
          outputTokens: res.usage?.outputTokens ?? 0,
          webSearchRequests: res.usage?.webSearchCount ?? 0,
          costUsd: calculateRequestCostUsd({
            provider: providerName,
            model: res.model || req.model,
            usage: res.usage,
          }),
        };
      } catch (err) {
        const latencyMs = Math.round(performance.now() - t0);
        const errorKind = err instanceof AiError ? err.kind : classifyRawAiError(err);
        const diag = (err instanceof AiError && err.diag)
          ? err.diag
          : extractSafeErrorDiag(err, providerName);
        const httpStatus = diag.httpStatus ?? (typeof err?.status === 'number' ? err.status : null);
        const isNet = isNetworkFailure(errorKind, diag);
        const statusLabel = isNet
          ? 'NETWORK'
          : (httpStatus ? `ERR(${errorKind}:${httpStatus})` : `ERR(${errorKind})`);
        row = {
          task,
          provider: providerName,
          model: req.model,
          ok: false,
          status: statusLabel,
          errorKind,
          httpStatus,
          errorCode: diag.errorCode ?? null,
          errorName: diag.errorName ?? null,
          host: diag.host ?? null,
          latencyMs,
          inputTokens: err?.usage?.inputTokens ?? 0,
          outputTokens: err?.usage?.outputTokens ?? 0,
          webSearchRequests: err?.usage?.webSearchCount ?? 0,
          costUsd: 0,
        };
      }
      results.push(row);
      if (typeof onProgress === 'function') {
        onProgress({ index: stepIndex, total: totalSteps, row });
      }
    }
  }

  return results;
}

export async function buildComparisonSamples() {
  const tinyPng = await sharp({
    create: { width: 120, height: 80, channels: 3, background: '#FFFFFF' },
  }).png().toBuffer();

  return [
    {
      id: 'sample_01_tip_focus',
      task: 'aiStudyTip',
      systemInstruction: 'You are Focus Bot. Reply in Japanese (1-2 sentences). Keep tokens like [STUDENT_1] verbatim.',
      contents: '[STUDENT_1]さんの明日の数学テストに向けた集中アドバイスをください。',
      expectedTokens: ['[STUDENT_1]'],
    },
    {
      id: 'sample_02_tip_short',
      task: 'aiStudyTip',
      systemInstruction: 'Reply in Japanese (max 2 sentences).',
      contents: '英語の単語暗記を25分で進めるコツを教えてください。',
      expectedTokens: [],
    },
    {
      id: 'sample_03_weak_area_math',
      task: 'analyzeWeakArea',
      systemInstruction: 'You are Focus Bot. Reply in Japanese (3 sentences max, plain text). Keep [STUDENT_1] verbatim.',
      contents: '[STUDENT_1]の統計: [{"subject":"数学","totalCount":8,"completedCount":2,"overdueCount":3,"avgDifficulty":5},{"subject":"英語","totalCount":6,"completedCount":5,"overdueCount":0,"avgDifficulty":2}]',
      expectedTokens: ['[STUDENT_1]'],
    },
    {
      id: 'sample_04_weak_area_prog',
      task: 'analyzeWeakArea',
      systemInstruction: 'Reply in Japanese (3 sentences max, plain text).',
      contents: '[{"subject":"プログラミング","totalCount":5,"completedCount":1,"overdueCount":2,"avgDifficulty":4}]',
      expectedTokens: [],
    },
    {
      id: 'sample_05_chat_planner',
      task: 'chatWithTutor',
      systemInstruction: 'You are Planner Bot. Reply in Japanese. Keep [STUDENT_1] and [TEACHER_1] verbatim.',
      contents: '[STUDENT_1]です。[TEACHER_1]先生の線形代数の課題と物理レポートを今日中に終わらせる計画を立ててください。',
      expectedTokens: ['[STUDENT_1]', '[TEACHER_1]'],
    },
    {
      id: 'sample_06_chat_math',
      task: 'chatWithTutor',
      systemInstruction: 'You are Math Bot. Reply in Japanese step by step.',
      contents: '二次方程式 x^2 - 5x + 6 = 0 の解き方を高校生向けにわかりやすく説明してください。',
      expectedTokens: [],
    },
    {
      id: 'sample_07_chat_career',
      task: 'chatWithTutor',
      systemInstruction: 'You are Career Bot. Reply in Japanese. Keep [STUDENT_1] and [PHONE_1] verbatim.',
      contents: '[STUDENT_1]の連絡先 [PHONE_1] は先生に共有済みです。高専から大学編入するための準備ポイントを教えてください。',
      expectedTokens: ['[STUDENT_1]', '[PHONE_1]'],
    },
    {
      id: 'sample_08_quiz_math',
      task: 'generateQuiz',
      systemInstruction: 'Return ONLY valid JSON: {"questions":[{"question":"...","choices":["...","...","...","..."],"answerIndex":0,"explanation":"..."}]}',
      contents: '微分積分の基礎について3問の4択クイズを日本語JSONで作成してください。',
      expectedTokens: [],
      expectJson: true,
    },
    {
      id: 'sample_09_quiz_tokenized',
      task: 'generateQuiz',
      systemInstruction: 'Return ONLY valid JSON: {"questions":[{"question":"...","choices":["...","...","...","..."],"answerIndex":0,"explanation":"..."}]}. Keep [TEACHER_1] verbatim.',
      contents: '[TEACHER_1]先生の情報セキュリティ入門から2問の4択クイズを日本語JSONで作成してください。',
      expectedTokens: ['[TEACHER_1]'],
      expectJson: true,
    },
    {
      id: 'sample_10_assignment_text',
      task: 'analyzeAssignmentSubmission',
      systemInstruction: 'Return ONLY valid JSON: {"completionPercent":0,"missingParts":["..."],"advice":"..."}. Keep [STUDENT_1] verbatim.',
      contents: 'Subject: 物理\nSubmitted work: [STUDENT_1]の実験レポート。目的と実験手順は記載済みだが、誤差考察と結論が未記入。',
      expectedTokens: ['[STUDENT_1]'],
      expectJson: true,
    },
    {
      id: 'sample_11_assignment_image',
      task: 'analyzeAssignmentSubmission',
      systemInstruction: 'Return ONLY valid JSON: {"completionPercent":0,"missingParts":["..."],"advice":"..."}',
      contents: [{
        role: 'user',
        parts: [
          { text: 'Subject: 数学\nAssignment title: [TEACHER_1]先生の微積演習' },
          { type: 'image', mimeType: 'image/png', data: tinyPng.toString('base64') },
        ],
      }],
      expectedTokens: [],
      expectJson: true,
    },
    {
      id: 'sample_12_timetable_fallback',
      task: 'previewTimetableImport',
      systemInstruction: 'Return ONLY valid JSON: {"slots":[{"dayOfWeek":"月|火|水|木|金","period":"1","subject":"...","teacher":"..."}]}. Keep [TEACHER_1] verbatim.',
      contents: '来週の予定: 月曜1限は[TEACHER_1]先生の情報工学(201教室)、火曜2限は英語会話。',
      expectedTokens: ['[TEACHER_1]'],
      expectJson: true,
    },
  ];
}

export async function runComparison({
  providers = ['gemini', 'claude'],
  providerFactory,
  apiKeys,
  keyResolver,
  outFile = null,
  timeoutMs = DEFAULT_SCRIPT_TIMEOUT_MS,
  maxRetries = DEFAULT_SCRIPT_MAX_RETRIES,
  onProgress,
} = {}) {
  const samples = await buildComparisonSamples();
  const rows = [];

  const resolvedKeys = providerFactory
    ? (apiKeys ?? {})
    : (apiKeys ?? resolveKeysOrThrow(providers, { keyResolver }));

  const effectiveFactory = providerFactory ??
    ((name) => getProvider({ providerName: name, apiKey: resolvedKeys[name], maxRetries }));

  if (outFile) {
    writeFileSync(outFile, '', 'utf8');
  }

  const totalSteps = samples.length * providers.length;
  let stepIndex = 0;
  const unreachableProviders = new Map();

  const recordRow = (row) => {
    rows.push(row);
    if (outFile) {
      appendFileSync(outFile, `${JSON.stringify(row)}\n`, 'utf8');
    }
    if (typeof onProgress === 'function') {
      onProgress({ index: stepIndex, total: totalSteps, row });
    }
  };

  for (const sample of samples) {
    for (const providerName of providers) {
      stepIndex += 1;
      const settings = resolveTaskSettings(sample.task, providerName);
      const effectiveTimeout = Math.min(settings.timeoutMs ?? timeoutMs, timeoutMs);

      if (unreachableProviders.has(providerName)) {
        const cached = unreachableProviders.get(providerName);
        recordRow({
          sampleId: sample.id,
          task: sample.task,
          provider: providerName,
          model: settings.model,
          ok: false,
          status: 'NETWORK',
          errorKind: cached.errorKind,
          httpStatus: cached.httpStatus,
          errorCode: cached.errorCode,
          errorName: cached.errorName,
          host: cached.host,
          latencyMs: 0,
          inputTokens: 0,
          outputTokens: 0,
          webSearchRequests: 0,
          costUsd: 0,
          validJson: sample.expectJson ? false : null,
          tokensPreserved: false,
        });
        continue;
      }

      const req = {
        task: sample.task,
        model: settings.model,
        maxTokens: settings.maxTokens,
        timeoutMs: effectiveTimeout,
        maxRetries,
        responseFormat: settings.responseFormat,
        jsonSchema: settings.jsonSchema,
        thinking: settings.claude?.thinking,
        effort: settings.claude?.effort,
        systemInstruction: sample.systemInstruction,
        contents: sample.contents,
      };
      const provider = effectiveFactory(providerName);
      const t0 = performance.now();
      try {
        const res = await withHardTimeout(provider.generate(req), effectiveTimeout + 2_000, providerName);
        const latencyMs = Math.round(performance.now() - t0);
        const validJson = sample.expectJson ? extractFirstJson(res.text) !== null : null;
        const tokensPreserved = sample.expectedTokens.every((t) =>
          String(res.text ?? '').includes(t),
        );
        recordRow({
          sampleId: sample.id,
          task: sample.task,
          provider: providerName,
          model: res.model || req.model,
          ok: true,
          status: 'OK',
          latencyMs,
          inputTokens: res.usage?.inputTokens ?? 0,
          outputTokens: res.usage?.outputTokens ?? 0,
          webSearchRequests: res.usage?.webSearchCount ?? 0,
          costUsd: Number(
            calculateRequestCostUsd({
              provider: providerName,
              model: res.model || req.model,
              usage: res.usage,
            }).toFixed(6),
          ),
          validJson,
          tokensPreserved,
        });
      } catch (err) {
        const latencyMs = Math.round(performance.now() - t0);
        const errorKind = err instanceof AiError ? err.kind : classifyRawAiError(err);
        const diag = (err instanceof AiError && err.diag)
          ? err.diag
          : extractSafeErrorDiag(err, providerName);
        const httpStatus = diag.httpStatus ?? (typeof err?.status === 'number' ? err.status : null);
        const isNet = isNetworkFailure(errorKind, diag);
        if (isNet) {
          unreachableProviders.set(providerName, {
            errorKind,
            httpStatus,
            errorCode: diag.errorCode ?? null,
            errorName: diag.errorName ?? null,
            host: diag.host ?? null,
          });
        }
        recordRow({
          sampleId: sample.id,
          task: sample.task,
          provider: providerName,
          model: req.model,
          ok: false,
          status: isNet ? 'NETWORK' : `ERR(${errorKind})`,
          errorKind,
          httpStatus,
          errorCode: diag.errorCode ?? null,
          errorName: diag.errorName ?? null,
          host: diag.host ?? null,
          latencyMs,
          inputTokens: 0,
          outputTokens: 0,
          webSearchRequests: 0,
          costUsd: 0,
          validJson: sample.expectJson ? false : null,
          tokensPreserved: false,
        });
      }
    }
  }

  return rows;
}

function parseArgs(argv) {
  const opts = {
    smoke: false,
    provider: null,
    out: 'compare_results.jsonl',
    timeoutMs: DEFAULT_SCRIPT_TIMEOUT_MS,
    maxRetries: DEFAULT_SCRIPT_MAX_RETRIES,
  };
  for (const arg of argv) {
    if (arg === '--smoke') opts.smoke = true;
    else if (arg.startsWith('--provider=')) opts.provider = arg.slice('--provider='.length).trim();
    else if (arg.startsWith('--out=')) opts.out = arg.slice('--out='.length).trim();
    else if (arg.startsWith('--timeout=')) {
      const n = Number(arg.slice('--timeout='.length).trim());
      if (Number.isFinite(n) && n >= 1000) opts.timeoutMs = n;
    } else if (arg.startsWith('--max-retries=')) {
      const n = Number(arg.slice('--max-retries='.length).trim());
      if (Number.isFinite(n) && n >= 0 && n <= 3) opts.maxRetries = Math.floor(n);
    }
  }
  return opts;
}

function resolveProvidersList(providerArg) {
  if (providerArg === 'both') return ['gemini', 'claude'];
  if (providerArg === 'gemini' || providerArg === 'claude') return [providerArg];
  if (providerArg) {
    throw new Error(`Unsupported --provider value: ${providerArg}`);
  }
  return [resolveActiveProviderName()];
}

async function main() {
  loadLocalEnvAndSecrets();
  const opts = parseArgs(process.argv.slice(2));

  if (opts.smoke) {
    const providers = resolveProvidersList(opts.provider);
    let apiKeys;
    try {
      apiKeys = resolveKeysOrThrow(providers);
    } catch (err) {
      console.error(err.message);
      console.error('Avval `npm run ai:keys -- set <gemini|claude>` (yoki `--local`) bilan kalit kiriting.');
      process.exitCode = 1;
      return;
    }

    const results = await runSmokeTests({
      providers,
      apiKeys,
      timeoutMs: opts.timeoutMs,
      maxRetries: opts.maxRetries,
      onProgress: ({ index, total, row }) => {
        const detail = row.ok
          ? `OK (${row.latencyMs}ms | in:${row.inputTokens} out:${row.outputTokens})`
          : `${row.status} (${row.errorCode || row.errorName || row.errorKind} | http:${row.httpStatus ?? '-'} | host:${row.host ?? '-'}) ${row.latencyMs}ms`;
        console.log(`[${index}/${total}] ${row.provider} | ${row.task} -> ${detail}`);
      },
    });
    console.log('\n=== AI Smoke Test (vazifa bo\'yicha, javob matnisiz) ===');
    for (const r of results) {
      const flag = r.status === 'OK' ? 'OK' : r.status;
      const errDetail = r.ok ? '' : ` | ${r.errorCode || r.errorName || r.errorKind} (${r.host ?? '-'})`;
      console.log(
        `${r.provider.padEnd(7)} | ${r.task.padEnd(28)} | ${String(r.model).padEnd(19)} | ${flag.padEnd(22)} | ${String(r.latencyMs).padStart(5)}ms | in:${r.inputTokens} out:${r.outputTokens} ws:${r.webSearchRequests}${errDetail}`,
      );
    }
    const failed = results.filter((r) => !r.ok);
    if (failed.length > 0) {
      console.error(`\nXato: ${failed.length} ta vazifa muvaffaqiyatli tugamadi.`);
      process.exitCode = 1;
    } else {
      console.log(`\nBarcha ${results.length} ta smoke test muvaffaqiyatli o'tdi.`);
    }
    return;
  }

  let providers;
  const apiKeys = {};
  if (opts.provider) {
    providers = resolveProvidersList(opts.provider);
    try {
      Object.assign(apiKeys, resolveKeysOrThrow(providers));
    } catch (err) {
      console.error(err.message);
      process.exitCode = 1;
      return;
    }
  } else {
    providers = [];
    for (const p of ['gemini', 'claude']) {
      const r = resolveProviderApiKey(p, { rootDir: ROOT_DIR, fnDir: FN_DIR });
      if (r.ok && r.key) {
        providers.push(p);
        apiKeys[p] = r.key;
      }
    }
  }

  if (providers.length === 0) {
    console.error('Kalit topilmadi: GEMINI_API_KEY / ANTHROPIC_API_KEY (env, .secret.local, Secret Manager). Avval `npm run ai:keys` dan foydalaning.');
    process.exitCode = 1;
    return;
  }

  const outPath = `${FN_DIR}/${opts.out}`;
  console.log(`=== AI Taqqoslash Boshlandi (${providers.join(', ')} | timeout=${opts.timeoutMs}ms | maxRetries=${opts.maxRetries}) ===`);
  const rows = await runComparison({
    providers,
    apiKeys,
    outFile: outPath,
    timeoutMs: opts.timeoutMs,
    maxRetries: opts.maxRetries,
    onProgress: ({ index, total, row }) => {
      const detail = row.ok
        ? `OK (${row.latencyMs}ms | in:${row.inputTokens} out:${row.outputTokens})`
        : `${row.status} (${row.errorCode || row.errorName || row.errorKind} | http:${row.httpStatus ?? '-'} | host:${row.host ?? '-'}) ${row.latencyMs}ms`;
      console.log(`[${index}/${total}] ${row.provider} | ${row.sampleId} -> ${detail}`);
    },
  });
  console.log(`\n=== AI Taqqoslash Yakunlandi (${rows.length} natija) -> ${outPath} ===`);
  for (const p of providers) {
    const sub = rows.filter((r) => r.provider === p);
    const okCount = sub.filter((r) => r.ok).length;
    const netCount = sub.filter((r) => r.status === 'NETWORK').length;
    const avgMs = sub.length ? Math.round(sub.reduce((s, r) => s + r.latencyMs, 0) / sub.length) : 0;
    const totalUsd = sub.reduce((s, r) => s + r.costUsd, 0).toFixed(5);
    console.log(`${p}: ${okCount}/${sub.length} OK | NETWORK: ${netCount} | o'rtacha: ${avgMs}ms | jami taxminiy: $${totalUsd}`);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((err) => {
    console.error('compare_providers xatosi:', err?.name || 'Error');
    process.exitCode = 1;
  });
}
