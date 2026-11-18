// Cross-platform Uzbek CLI for managing Gemini & Claude API keys and
// provider configuration cleanly using Node.js built-ins only.
//
// Usage:
//   npm run ai:keys -- status
//   npm run ai:keys -- set <gemini|claude> [--local] [--yes]
//   npm run ai:keys -- remove <gemini|claude> [--local] [--yes]
//   npm run ai:keys -- provider <gemini|claude>
//   npm run ai:keys -- test <gemini|claude>
//   npm run ai:keys -- prune [--yes]
//   npm run ai:keys -- help

import { chmodSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';
import { getProvider } from '../ai/ai_provider.js';
import { AiError, classifyRawAiError, extractSafeErrorDiag } from '../ai/ai_errors.js';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_FN_DIR = resolve(SCRIPT_DIR, '..');
const DEFAULT_ROOT_DIR = resolve(DEFAULT_FN_DIR, '..');

export const SECRET_NAMES = Object.freeze({
  gemini: 'GEMINI_API_KEY',
  claude: 'ANTHROPIC_API_KEY',
});

/**
 * Resolves the API key for a provider in strict priority order:
 *   1. `process.env[SECRET_NAME]`
 *   2. `functions/.secret.local`
 *   3. Firebase Secret Manager (`firebase functions:secrets:access <SECRET_NAME>`)
 *
 * The secret value is kept strictly in memory and NEVER printed or logged.
 */
export function resolveProviderApiKey(
  provider,
  {
    rootDir = DEFAULT_ROOT_DIR,
    fnDir = DEFAULT_FN_DIR,
    env = process.env,
    fsApi = { existsSync, readFileSync },
    spawnSyncFn = spawnSync,
  } = {},
) {
  const secretName = SECRET_NAMES[provider];
  if (!secretName) {
    return { ok: false, secretName: null, key: null, source: null };
  }

  const fromEnv = String(env?.[secretName] ?? '').trim();
  if (fromEnv) {
    return { ok: true, secretName, key: fromEnv, source: 'env' };
  }

  const localSecrets = parseKeyValueFile(resolve(fnDir, '.secret.local'), fsApi);
  const fromLocal = String(localSecrets?.[secretName] ?? '').trim();
  if (fromLocal) {
    return { ok: true, secretName, key: fromLocal, source: 'secret.local' };
  }

  const res = spawnSyncFn(
    'firebase',
    ['functions:secrets:access', secretName],
    {
      cwd: rootDir,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );
  if (res.status === 0) {
    const fromCloud = String(res.stdout ?? '').trim();
    if (fromCloud) {
      return { ok: true, secretName, key: fromCloud, source: 'secret_manager' };
    }
  }

  return { ok: false, secretName, key: null, source: null };
}

export function classifyConnectivityStatus(err) {
  const kind = err instanceof AiError ? err.kind : classifyRawAiError(err);
  if (kind === 'auth') return 'auth';
  if (kind === 'rate_limited' || kind === 'overloaded') return 'quota';
  if (kind === 'invalid_request') return 'invalid_request';
  if (kind === 'truncated') return 'truncated';
  return 'network';
}

function withScriptTimeout(promise, ms, provider) {
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

/**
 * Executes a single minimal/cheapest API request to verify key validity and
 * network connectivity for the given provider (`OK` / `auth` / `quota` / `network`).
 * Enforces bounded `maxRetries: 1` and short timeout so the CLI never hangs.
 * Never logs or returns the secret key or AI response text.
 */
export async function runSingleCheapestTest({
  provider,
  apiKey,
  model,
  timeoutMs = 10_000,
  maxRetries = 1,
  providerFactory = (name, key) => getProvider({ providerName: name, apiKey: key }),
}) {
  const defaultHost = provider === 'claude'
    ? 'api.anthropic.com'
    : 'generativelanguage.googleapis.com';

  if (!apiKey || !String(apiKey).trim()) {
    return {
      ok: false,
      status: 'auth',
      errorKind: 'auth',
      httpStatus: 401,
      errorCode: 'MISSING_KEY',
      errorName: 'AuthenticationError',
      errorDetail: 'MISSING_KEY',
      host: defaultHost,
      model: model ?? null,
      latencyMs: 0,
    };
  }

  const resolvedModel =
    model || (provider === 'claude' ? 'claude-haiku-5-5' : 'gemini-flash-latest');
  const req = provider === 'claude'
    ? {
      task: 'aiStudyTip',
      model: resolvedModel,
      maxTokens: 16,
      timeoutMs,
      maxRetries,
      thinking: { type: 'disabled' },
      effort: 'low',
      systemInstruction: 'Reply with OK.',
      contents: 'Reply with OK',
    }
    : {
      task: 'aiStudyTip',
      model: resolvedModel,
      maxTokens: 256,
      explicitMaxTokens: 256,
      timeoutMs,
      maxRetries,
      systemInstruction: 'Reply with OK.',
      contents: 'Reply with OK',
    };

  const client = providerFactory(provider, apiKey);
  const t0 = performance.now();
  try {
    const res = await withScriptTimeout(client.generate(req), timeoutMs + 2_000, provider);
    const latencyMs = Math.round(performance.now() - t0);
    return {
      ok: true,
      status: 'OK',
      errorKind: null,
      httpStatus: 200,
      errorCode: null,
      errorName: null,
      errorDetail: null,
      host: defaultHost,
      model: res?.model || resolvedModel,
      latencyMs,
    };
  } catch (err) {
    const latencyMs = Math.round(performance.now() - t0);
    const errorKind = err instanceof AiError ? err.kind : classifyRawAiError(err);
    const diag = (err instanceof AiError && err.diag)
      ? err.diag
      : extractSafeErrorDiag(err, provider);
    const httpStatus = diag.httpStatus ?? (typeof err?.status === 'number' ? err.status : null);
    const errorDetail = diag.errorCode || diag.errorName || errorKind;
    const host = diag.host || defaultHost;
    return {
      ok: false,
      status: classifyConnectivityStatus(err),
      errorKind,
      httpStatus,
      errorCode: diag.errorCode ?? null,
      errorName: diag.errorName ?? null,
      errorDetail,
      host,
      model: resolvedModel,
      latencyMs,
    };
  }
}

export function readFirebaseProjectId(rootDir = DEFAULT_ROOT_DIR, fsApi = { existsSync, readFileSync }) {
  const rcPath = resolve(rootDir, '.firebaserc');
  if (!fsApi.existsSync(rcPath)) return null;
  try {
    const parsed = JSON.parse(fsApi.readFileSync(rcPath, 'utf8'));
    return parsed?.projects?.default || null;
  } catch {
    return null;
  }
}

export function parseKeyValueFile(filePath, fsApi = { existsSync, readFileSync }) {
  if (!fsApi.existsSync(filePath)) return {};
  const map = {};
  const raw = fsApi.readFileSync(filePath, 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    const k = trimmed.slice(0, eq).trim();
    let v = trimmed.slice(eq + 1).trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      v = v.slice(1, -1);
    }
    map[k] = v;
  }
  return map;
}

export function upsertKeyValueFile(filePath, key, value, { fsApi = { existsSync, readFileSync, writeFileSync, chmodSync }, privateFile = false } = {}) {
  const lines = fsApi.existsSync(filePath)
    ? fsApi.readFileSync(filePath, 'utf8').split(/\r?\n/)
    : [];
  const nextLines = [];
  let updated = false;
  for (const line of lines) {
    if (line.trim().startsWith(`${key}=`)) {
      if (value !== null) {
        nextLines.push(`${key}=${value}`);
      }
      updated = true;
    } else if (line.length > 0 || nextLines.length > 0) {
      nextLines.push(line);
    }
  }
  if (!updated && value !== null) {
    nextLines.push(`${key}=${value}`);
  }
  const filtered = nextLines.filter((l, idx) => idx < nextLines.length - 1 || l !== '');
  const clean = filtered.length === 0 ? '' : `${filtered.join('\n')}\n`;
  fsApi.writeFileSync(filePath, clean, { encoding: 'utf8', ...(privateFile ? { mode: 0o600 } : {}) });
  if (privateFile && process.platform !== 'win32' && typeof fsApi.chmodSync === 'function') {
    try {
      fsApi.chmodSync(filePath, 0o600);
    } catch {
      // Ignore chmod failures on virtual/restricted filesystems.
    }
  }
}

export function validateApiKeyInput(provider, rawKey) {
  const key = String(rawKey ?? '').trim();
  if (!key) {
    return { ok: false, error: "Xato: Bo'sh kalit kiritildi. Jarayon bekor qilindi." };
  }
  if (/\s/.test(key)) {
    return { ok: false, error: "Xato: API kalitida bo'sh joy (whitespace) bo'lmasligi kerak." };
  }
  if (key.length < 16) {
    return { ok: false, error: 'Xato: Kiritilgan kalit juda qisqa ko‘rinadi.' };
  }
  const warnings = [];
  if (provider === 'claude' && !key.startsWith('sk-ant-')) {
    warnings.push("Ogohlantirish: Anthropic kaliti odatda 'sk-ant-' bilan boshlanadi.");
  }
  if (provider === 'gemini' && !key.startsWith('AIza')) {
    warnings.push("Ogohlantirish: Google AI Studio Gemini kaliti odatda 'AIza' bilan boshlanadi.");
  }
  return { ok: true, key, warnings };
}

export async function promptHiddenSecret(promptText, { stdin = process.stdin, stdout = process.stdout } = {}) {
  stdout.write(promptText);
  if (!stdin.isTTY || typeof stdin.setRawMode !== 'function') {
    return await new Promise((resolvePromise) => {
      const rl = readline.createInterface({ input: stdin, terminal: false });
      let settled = false;
      const finish = (val) => {
        if (settled) return;
        settled = true;
        rl.close();
        if (typeof stdin.pause === 'function') stdin.pause();
        stdout.write('\n');
        resolvePromise(val);
      };
      rl.once('line', (line) => finish(line.trim()));
      rl.once('close', () => finish(''));
    });
  }

  return await new Promise((resolvePromise, rejectPromise) => {
    let buf = '';
    let settled = false;
    stdin.setRawMode(true);
    stdin.resume();

    const cleanup = () => {
      stdin.removeListener('data', onData);
      stdin.removeListener('end', onEnd);
      stdin.removeListener('close', onEnd);
      try {
        stdin.setRawMode(false);
      } catch {
        // ignore
      }
      if (typeof stdin.pause === 'function') {
        stdin.pause();
      }
    };

    const finishResolve = (val) => {
      if (settled) return;
      settled = true;
      cleanup();
      stdout.write('\n');
      resolvePromise(val);
    };

    const finishReject = (err) => {
      if (settled) return;
      settled = true;
      cleanup();
      stdout.write('\n');
      rejectPromise(err);
    };

    const onEnd = () => finishResolve(buf.trim());

    const onData = (chunk) => {
      const str = chunk.toString('utf8');
      for (const ch of str) {
        if (ch === '\u0003') {
          finishReject(new Error('USER_CANCELLED'));
          return;
        }
        if (ch === '\r' || ch === '\n' || ch === '\u0004') {
          finishResolve(buf.trim());
          return;
        }
        if (ch === '\u007f' || ch === '\b') {
          if (buf.length > 0) {
            buf = buf.slice(0, -1);
            stdout.write('\b \b');
          }
          continue;
        }
        buf += ch;
        stdout.write('*');
      }
    };

    stdin.on('data', onData);
    stdin.once('end', onEnd);
    stdin.once('close', onEnd);
  });
}

export async function promptConfirm(question, { stdin = process.stdin, stdout = process.stdout, autoYes = false } = {}) {
  if (autoYes) return true;
  stdout.write(`${question} [y/N]: `);
  const answer = await new Promise((resolvePromise) => {
    // Keep `terminal: false` so canonical/cooked TTY echo stays active and
    // raw mode is strictly reserved for hidden secret input.
    const rl = readline.createInterface({ input: stdin, terminal: false });
    let settled = false;
    const finish = (val) => {
      if (settled) return;
      settled = true;
      rl.close();
      if (typeof stdin.pause === 'function') stdin.pause();
      resolvePromise(val);
    };
    rl.once('line', (line) => finish(line.trim().toLowerCase()));
    rl.once('close', () => finish(''));
  });
  return answer === 'y' || answer === 'yes' || answer === 'ha';
}

function checkSecretIgnoreInGitignore(rootDir, fsApi) {
  const giPath = resolve(rootDir, '.gitignore');
  if (!fsApi.existsSync(giPath)) return false;
  const content = fsApi.readFileSync(giPath, 'utf8');
  return content.includes('.secret.local');
}

function getCloudSecretMeta(secretName, { rootDir, spawnSyncFn }) {
  const res = spawnSyncFn('firebase', ['functions:secrets:get', secretName], {
    cwd: rootDir,
    encoding: 'utf8',
  });
  if (res.status === 0) {
    return { exists: true, rawOutput: String(res.stdout ?? '') };
  }
  return { exists: false, error: String(res.stderr || res.stdout || '') };
}

function printHelp(stdout) {
  stdout.write(
    [
      'EduPlanner AI — Kalit va Provayder Boshqaruv CLI',
      '',
      'Buyruqlar:',
      '  status                      Lokal (.secret.local) va Firebase Cloud secret holatini ko‘rsatish',
      '  set <gemini|claude>         API kalitni yashirin kiritish orqali Firebase Secret Manager ga saqlash',
      '  set <gemini|claude> --local Lokal emulyator/test uchun functions/.secret.local ga saqlash',
      '  remove <gemini|claude>      Kalitni o‘chirish (avval faol provayder emasligini tekshiradi)',
      '  provider <gemini|claude>    functions/.env da AI_PROVIDER ni almashtirish',
      '  test <gemini|claude>        Bitta eng arzon so‘rov bilan ulanishni tekshirish (OK/auth/quota/network)',
      '  prune                       Ishlatilmayotgan eski Firebase secret versiyalarini tozalash',
      '  help                        Ushbu yordamni ko‘rsatish',
      '',
      'Xavfsizlik eslatmasi:',
      '  Kalitni HECH QACHON buyruq qatori (argv) orqali bermang — CLI uni yashirin so‘raydi.',
      '',
    ].join('\n'),
  );
}

export async function runCli(
  argv,
  {
    rootDir = DEFAULT_ROOT_DIR,
    fnDir = DEFAULT_FN_DIR,
    spawnSyncFn = spawnSync,
    fsApi = { existsSync, readFileSync, writeFileSync, chmodSync },
    stdin = process.stdin,
    stdout = process.stdout,
    stderr = process.stderr,
    env = process.env,
    hiddenPromptFn = promptHiddenSecret,
    confirmFn = promptConfirm,
    keyResolver = resolveProviderApiKey,
    providerFactory,
  } = {},
) {
  const flags = new Set(argv.filter((a) => a.startsWith('--')));
  const positional = argv.filter((a) => !a.startsWith('-'));
  const command = positional[0] || 'help';
  const target = positional[1] || '';
  const extraArg = positional[2];
  const isLocal = flags.has('--local');
  const autoYes = flags.has('--yes');

  // Reject any attempt to pass an API key via CLI arguments so it never leaks into shell history.
  const hasInlineSecretFlag = argv.some((a) => a.startsWith('--key=') || a.startsWith('--secret=') || a === '--key');
  if (extraArg !== undefined || hasInlineSecretFlag) {
    stderr.write(
      "XAVFSIZLIK XATOSI: API kalitni buyruq qatori argumenti (argv) sifatida yuborish taqiqlanadi (shell history ga tushib qoladi).\n" +
      "Faqat `npm run ai:keys -- set <gemini|claude>` yozing, kalit yashirin so‘raladi.\n",
    );
    return 1;
  }

  const projectId = readFirebaseProjectId(rootDir, fsApi);
  const envMap = parseKeyValueFile(resolve(fnDir, '.env'), fsApi);
  const localSecrets = parseKeyValueFile(resolve(fnDir, '.secret.local'), fsApi);
  const activeProvider = (env.AI_PROVIDER || envMap.AI_PROVIDER || 'gemini').trim().toLowerCase();
  const fallbackProvider = (env.AI_FALLBACK_PROVIDER || envMap.AI_FALLBACK_PROVIDER || 'none').trim().toLowerCase();
  const monthlyBudget = env.AI_MONTHLY_BUDGET_USD || envMap.AI_MONTHLY_BUDGET_USD || '0';

  if (command === 'help' || command === '--help') {
    printHelp(stdout);
    return 0;
  }

  if (command === 'status') {
    stdout.write(`=== EduPlanner AI Kalit & Konfiguratsiya Holati ===\n`);
    stdout.write(`Firebase loyiha: ${projectId ?? '(topilmadi — .firebaserc ni tekshiring)'}\n`);
    stdout.write(`Faol AI_PROVIDER: ${activeProvider}\n`);
    stdout.write(`Fallback (AI_FALLBACK_PROVIDER): ${fallbackProvider}\n`);
    stdout.write(`Oylik byudjet (AI_MONTHLY_BUDGET_USD): $${monthlyBudget}\n`);
    stdout.write(`.gitignore (.secret.local): ${checkSecretIgnoreInGitignore(rootDir, fsApi) ? 'HA (himoyalangan)' : "YO'Q (diqqat!)"} \n\n`);

    for (const [prov, secretName] of Object.entries(SECRET_NAMES)) {
      const hasLocal = Boolean(localSecrets[secretName]);
      const hasEnv = Boolean(env[secretName]);
      const cloud = getCloudSecretMeta(secretName, { rootDir, spawnSyncFn });
      stdout.write(
        `- ${prov.padEnd(7)} (${secretName}): Lokal[.secret.local]=${hasLocal ? 'MAVJUD' : "yo'q"} | Env=${hasEnv ? 'MAVJUD' : "yo'q"} | Cloud Secret=${cloud.exists ? 'MAVJUD' : "topilmadi/ulanmagan"}\n`,
      );
    }
    return 0;
  }

  if (command === 'set') {
    if (!(target in SECRET_NAMES)) {
      stderr.write("Xato: Provayderni ko‘rsating: `set gemini` yoki `set claude`.\n");
      return 1;
    }
    const secretName = SECRET_NAMES[target];

    if (isLocal) {
      if (!checkSecretIgnoreInGitignore(rootDir, fsApi)) {
        stderr.write("Xato: `.gitignore` da `.secret.local` topilmadi. Avval `.gitignore` ni tekshiring.\n");
        return 1;
      }
      const rawKey = await hiddenPromptFn(
        `${target.toUpperCase()} API kalitini kiriting (ekranda ko‘rinmaydi, lokal .secret.local ga yoziladi): `,
        { stdin, stdout },
      );
      const checked = validateApiKeyInput(target, rawKey);
      if (!checked.ok) {
        stderr.write(`${checked.error}\n`);
        return 1;
      }
      for (const w of checked.warnings) stdout.write(`${w}\n`);
      const localSecretPath = resolve(fnDir, '.secret.local');
      upsertKeyValueFile(localSecretPath, secretName, checked.key, { fsApi, privateFile: true });
      stdout.write(`Muvaffaqiyatli: ${secretName} lokal ${localSecretPath} fayliga saqlandi (gitga kirmaydi).\n`);
      return 0;
    }

    stdout.write(`Faol Firebase loyiha: ${projectId ?? '(nomaʼlum)'}\n`);
    const ok = await confirmFn(
      `${projectId ?? 'joriy loyiha'} uchun ${secretName} cloud secretini o‘rnatasizmi?`,
      { stdin, stdout, autoYes },
    );
    if (!ok) {
      stdout.write('Bekor qilindi.\n');
      return 0;
    }

    const rawKey = await hiddenPromptFn(
      `${target.toUpperCase()} API kalitini kiriting (ekranda ko‘rinmaydi, stdin orqali Firebase ga yuboriladi): `,
      { stdin, stdout },
    );
    const checked = validateApiKeyInput(target, rawKey);
    if (!checked.ok) {
      stderr.write(`${checked.error}\n`);
      return 1;
    }
    for (const w of checked.warnings) stdout.write(`${w}\n`);

    const setRes = spawnSyncFn(
      'firebase',
      ['functions:secrets:set', secretName, '--data-file', '-'],
      {
        cwd: rootDir,
        input: checked.key,
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe'],
      },
    );
    if (setRes.status !== 0) {
      stderr.write(`Firebase secret saqlashda xato:\n${setRes.stderr || setRes.stdout || 'Nomaʼlum xato'}\n`);
      return 1;
    }
    stdout.write(
      `Muvaffaqiyatli: ${secretName} Firebase Secret Manager da yangilandi.\n` +
      `MUHIM: Yangi secret versiyasi kuchga kirishi uchun funksiyalarni qayta deploy qiling:\n` +
      `  firebase deploy --only functions\n`,
    );
    return 0;
  }

  if (command === 'remove') {
    if (!(target in SECRET_NAMES)) {
      stderr.write("Xato: Provayderni ko‘rsating: `remove gemini` yoki `remove claude`.\n");
      return 1;
    }
    const secretName = SECRET_NAMES[target];

    if (activeProvider === target || fallbackProvider === target) {
      stderr.write(
        `Xato: '${target}' hozir faol (AI_PROVIDER=${activeProvider}, AI_FALLBACK_PROVIDER=${fallbackProvider}).\n` +
        `Avval provayderni o‘zgartiring (masalan: \`npm run ai:keys -- provider ${target === 'claude' ? 'gemini' : 'claude'}\`), so‘ng o‘chiring.\n`,
      );
      return 1;
    }

    if (isLocal) {
      const localSecretPath = resolve(fnDir, '.secret.local');
      upsertKeyValueFile(localSecretPath, secretName, null, { fsApi, privateFile: true });
      stdout.write(`Muvaffaqiyatli: ${secretName} lokal .secret.local dan olib tashlandi.\n`);
      return 0;
    }

    stdout.write(`Faol Firebase loyiha: ${projectId ?? '(nomaʼlum)'}\n`);
    const ok = await confirmFn(
      `${projectId ?? 'joriy loyiha'} dagi ${secretName} cloud secretini o‘chirasizmi?`,
      { stdin, stdout, autoYes },
    );
    if (!ok) {
      stdout.write('Bekor qilindi.\n');
      return 0;
    }

    const delRes = spawnSyncFn(
      'firebase',
      ['functions:secrets:destroy', secretName, '--force'],
      { cwd: rootDir, encoding: 'utf8' },
    );
    if (delRes.status !== 0) {
      stderr.write(`O‘chirishda xato:\n${delRes.stderr || delRes.stdout || 'Nomaʼlum xato'}\n`);
      return 1;
    }
    stdout.write(
      `Muvaffaqiyatli: ${secretName} o‘chirildi. Deploy qilingan funksiyalarda ishlatilayotgan bo‘lsa \`firebase deploy --only functions\` bajaring.\n`,
    );
    return 0;
  }

  if (command === 'provider') {
    if (!(target in SECRET_NAMES)) {
      stderr.write("Xato: Provayderni ko‘rsating: `provider gemini` yoki `provider claude`.\n");
      return 1;
    }
    const secretName = SECRET_NAMES[target];
    const hasLocalKey = Boolean(localSecrets[secretName] || env[secretName]);
    const hasCloudKey = isLocal ? false : getCloudSecretMeta(secretName, { rootDir, spawnSyncFn }).exists;
    if (!hasLocalKey && !hasCloudKey) {
      stderr.write(
        `Ogohlantirish/Xato: '${target}' uchun ${secretName} kaliti topilmadi.\n` +
        `Avval kalit qo‘shing: \`npm run ai:keys -- set ${target}${isLocal ? ' --local' : ''}\`\n`,
      );
      return 1;
    }

    const envFilePath = resolve(fnDir, isLocal ? '.env.local' : '.env');
    upsertKeyValueFile(envFilePath, 'AI_PROVIDER', target, { fsApi });
    stdout.write(
      `Muvaffaqiyatli: AI_PROVIDER=${target} (${envFilePath}) yozildi.\n` +
      (isLocal
        ? 'Lokal emulyator/smoke test uchun tayyor.\n'
        : 'Production ga qo‘llash uchun `firebase deploy --only functions` bajaring.\n'),
    );
    return 0;
  }

  if (command === 'test') {
    if (!(target in SECRET_NAMES)) {
      stderr.write("Xato: Provayderni ko‘rsating: `test gemini` yoki `test claude`.\n");
      return 1;
    }

    const resolvedKey = keyResolver(target, { rootDir, fnDir, env, fsApi, spawnSyncFn });
    if (!resolvedKey.ok) {
      stderr.write(
        `Kalit topilmadi: ${resolvedKey.secretName} (process.env, functions/.secret.local yoki Firebase Secret Manager da yo‘q).\n` +
        `Avval kalit qo‘shing: \`npm run ai:keys -- set ${target}\` (yoki \`--local\`)\n`,
      );
      return 1;
    }

    const modelOverride = target === 'claude'
      ? (env.AI_MODEL_CLAUDE_LIGHT || envMap.AI_MODEL_CLAUDE_LIGHT || 'claude-haiku-5-5')
      : (env.AI_MODEL_GEMINI || envMap.AI_MODEL_GEMINI || 'gemini-flash-latest');

    stdout.write(`${target} provayderi tekshirilmoqda (1 ta minimal so‘rov, model: ${modelOverride})...\n`);
    const result = await runSingleCheapestTest({
      provider: target,
      apiKey: resolvedKey.key,
      model: modelOverride,
      ...(providerFactory ? { providerFactory } : {}),
    });

    if (result.ok) {
      stdout.write(
        `Natija: ${result.status} | provayder: ${target} | model: ${result.model} | manba: ${resolvedKey.source} | ${result.latencyMs}ms\n`,
      );
      return 0;
    }
    stderr.write(
      `Natija: ${result.status} | provayder: ${target} | model: ${result.model} | manba: ${resolvedKey.source} | http: ${result.httpStatus ?? '-'} | xato: ${result.errorDetail} | host: ${result.host} | ${result.latencyMs}ms\n`,
    );
    return 1;
  }

  if (command === 'prune') {
    stdout.write(`Faol Firebase loyiha: ${projectId ?? '(nomaʼlum)'}\n`);
    const ok = await confirmFn(
      'Ishlatilmayotgan eski Firebase secret versiyalarini tozalaysizmi (`functions:secrets:prune`)?',
      { stdin, stdout, autoYes },
    );
    if (!ok) {
      stdout.write('Bekor qilindi.\n');
      return 0;
    }
    const pruneRes = spawnSyncFn(
      'firebase',
      ['functions:secrets:prune'],
      { cwd: rootDir, encoding: 'utf8', stdio: 'inherit' },
    );
    return pruneRes.status ?? 1;
  }

  stderr.write(`Nomaʼlum buyruq: '${command}'. Yordam uchun \`npm run ai:keys -- help\` ni bajaring.\n`);
  return 1;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  runCli(process.argv.slice(2))
    .then((code) => {
      process.exitCode = code;
    })
    .catch((err) => {
      if (err?.message === 'USER_CANCELLED') {
        process.exitCode = 130;
        return;
      }
      console.error('CLI xatosi:', err?.message || 'Unknown error');
      process.exitCode = 1;
    });
}
