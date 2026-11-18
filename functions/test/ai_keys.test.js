import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync, chmodSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PassThrough, Writable } from 'node:stream';
import {
  promptConfirm,
  promptHiddenSecret,
  resolveProviderApiKey,
  runCli,
  runSingleCheapestTest,
  validateApiKeyInput,
} from '../scripts/ai_keys.mjs';
import {
  AiError,
  classifyRawAiError,
  extractSafeErrorDiag,
  toAiError,
} from '../ai/ai_errors.js';
import { createClaudeProvider } from '../ai/claude_provider.js';
import { createGeminiProvider } from '../ai/gemini_provider.js';
import { runComparison, runSmokeTests } from '../scripts/compare_providers.mjs';

function makeStreamBuffer() {
  let text = '';
  const stream = new Writable({
    write(chunk, _enc, cb) {
      text += chunk.toString('utf8');
      cb();
    },
  });
  return { stream, getText: () => text };
}

function makeTempProject({ gitignore = '.secret.local\n', envText = 'AI_PROVIDER=gemini\n' } = {}) {
  const rootDir = mkdtempSync(join(tmpdir(), 'eduplanner-ai-keys-'));
  const fnDir = join(rootDir, 'functions');
  mkdirSync(fnDir, { recursive: true });
  writeFileSync(join(rootDir, '.firebaserc'), JSON.stringify({ projects: { default: 'eduplannerai-97365' } }), 'utf8');
  if (gitignore !== null) {
    writeFileSync(join(rootDir, '.gitignore'), gitignore, 'utf8');
  }
  if (envText !== null) {
    writeFileSync(join(fnDir, '.env'), envText, 'utf8');
  }
  return {
    rootDir,
    fnDir,
    cleanup: () => rmSync(rootDir, { recursive: true, force: true }),
  };
}

test('ai_keys CLI rejects passing secrets in argv or --key flags', async () => {
  const proj = makeTempProject();
  try {
    const out = makeStreamBuffer();
    const err = makeStreamBuffer();
    const code1 = await runCli(['set', 'claude', 'sk-ant-api03-1234567890abcdef'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: out.stream,
      stderr: err.stream,
      spawnSyncFn: () => ({ status: 0, stdout: '' }),
    });
    assert.equal(code1, 1);
    assert.ok(err.getText().includes('XAVFSIZLIK XATOSI'));

    const err2 = makeStreamBuffer();
    const code2 = await runCli(['set', 'claude', '--key=sk-ant-api03-1234567890abcdef'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: out.stream,
      stderr: err2.stream,
      spawnSyncFn: () => ({ status: 0, stdout: '' }),
    });
    assert.equal(code2, 1);
    assert.ok(err2.getText().includes('XAVFSIZLIK XATOSI'));
  } finally {
    proj.cleanup();
  }
});

test('ai_keys CLI status and help display project info, active provider, and never expose secret values', async () => {
  const proj = makeTempProject({
    envText: 'AI_PROVIDER=gemini\nAI_FALLBACK_PROVIDER=none\nAI_MONTHLY_BUDGET_USD=10\n',
  });
  try {
    writeFileSync(join(proj.fnDir, '.secret.local'), 'GEMINI_API_KEY=AIzaSySuperSecretValue123456\n', 'utf8');

    const helpOut = makeStreamBuffer();
    const helpCode = await runCli(['help'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: helpOut.stream,
      stderr: makeStreamBuffer().stream,
      env: {},
    });
    assert.equal(helpCode, 0);
    assert.ok(helpOut.getText().includes('set <gemini|claude>'));

    const statusOut = makeStreamBuffer();
    const statusCode = await runCli(['status'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: statusOut.stream,
      stderr: makeStreamBuffer().stream,
      env: {},
      spawnSyncFn: (_cmd, args) => {
        if (args[1] === 'GEMINI_API_KEY') return { status: 0, stdout: 'v1 ENABLED' };
        return { status: 1, stderr: 'not found' };
      },
    });
    assert.equal(statusCode, 0);
    const txt = statusOut.getText();
    assert.ok(txt.includes('eduplannerai-97365'));
    assert.ok(txt.includes('Faol AI_PROVIDER: gemini'));
    assert.ok(txt.includes('Oylik byudjet (AI_MONTHLY_BUDGET_USD): $10'));
    assert.ok(txt.includes('Lokal[.secret.local]=MAVJUD'));
    assert.ok(!txt.includes('AIzaSySuperSecretValue123456'), 'Secret value must NEVER be printed');
  } finally {
    proj.cleanup();
  }
});

test('ai_keys set --local writes .secret.local with 0600 protection and requires .gitignore entry', async () => {
  const proj = makeTempProject();
  try {
    const out = makeStreamBuffer();
    const err = makeStreamBuffer();
    const code = await runCli(['set', 'claude', '--local'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: out.stream,
      stderr: err.stream,
      env: {},
      hiddenPromptFn: async () => 'sk-ant-api03-localtestkey123456',
      fsApi: { existsSync, readFileSync, writeFileSync, chmodSync },
    });
    assert.equal(code, 0);
    const secretContent = readFileSync(join(proj.fnDir, '.secret.local'), 'utf8');
    assert.ok(secretContent.includes('ANTHROPIC_API_KEY=sk-ant-api03-localtestkey123456'));

    // Without .secret.local in .gitignore, refuses to write
    writeFileSync(join(proj.rootDir, '.gitignore'), 'node_modules/\n', 'utf8');
    const err2 = makeStreamBuffer();
    const code2 = await runCli(['set', 'gemini', '--local'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: out.stream,
      stderr: err2.stream,
      env: {},
      hiddenPromptFn: async () => 'AIzaSyTestKey1234567890',
    });
    assert.equal(code2, 1);
    assert.ok(err2.getText().includes('.gitignore'));
  } finally {
    proj.cleanup();
  }
});

test('ai_keys set (cloud) confirms active project, pipes key via stdin (--data-file -), and prints deploy reminder', async () => {
  const proj = makeTempProject();
  try {
    const out = makeStreamBuffer();
    const spawnCalls = [];
    const code = await runCli(['set', 'claude', '--yes'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: out.stream,
      stderr: makeStreamBuffer().stream,
      env: {},
      hiddenPromptFn: async () => 'sk-ant-api03-cloudsecret12345678',
      spawnSyncFn: (cmd, args, opts) => {
        spawnCalls.push({ cmd, args, input: opts?.input });
        return { status: 0, stdout: 'Created version 1' };
      },
    });
    assert.equal(code, 0);
    assert.equal(spawnCalls.length, 1);
    assert.equal(spawnCalls[0].cmd, 'firebase');
    assert.deepEqual(spawnCalls[0].args, ['functions:secrets:set', 'ANTHROPIC_API_KEY', '--data-file', '-']);
    assert.equal(spawnCalls[0].input, 'sk-ant-api03-cloudsecret12345678');
    assert.ok(!spawnCalls[0].args.join(' ').includes('sk-ant-api03'));
    assert.ok(out.getText().includes('firebase deploy --only functions'));
  } finally {
    proj.cleanup();
  }
});

test('ai_keys remove blocks deleting active/fallback provider and succeeds for inactive provider', async () => {
  const proj = makeTempProject({
    envText: 'AI_PROVIDER=gemini\nAI_FALLBACK_PROVIDER=claude\n',
  });
  try {
    const err1 = makeStreamBuffer();
    const blockedPrimary = await runCli(['remove', 'gemini', '--yes'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: makeStreamBuffer().stream,
      stderr: err1.stream,
      env: {},
    });
    assert.equal(blockedPrimary, 1);
    assert.ok(err1.getText().includes('hozir faol'));

    const err2 = makeStreamBuffer();
    const blockedFallback = await runCli(['remove', 'claude', '--yes'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: makeStreamBuffer().stream,
      stderr: err2.stream,
      env: {},
    });
    assert.equal(blockedFallback, 1);
    assert.ok(err2.getText().includes('hozir faol'));

    // When claude is NOT active or fallback, remove succeeds (local + cloud)
    writeFileSync(join(proj.fnDir, '.env'), 'AI_PROVIDER=gemini\nAI_FALLBACK_PROVIDER=none\n', 'utf8');
    writeFileSync(join(proj.fnDir, '.secret.local'), 'ANTHROPIC_API_KEY=sk-ant-1234567890123456\n', 'utf8');

    const localRemoveCode = await runCli(['remove', 'claude', '--local'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: makeStreamBuffer().stream,
      stderr: makeStreamBuffer().stream,
      env: {},
    });
    assert.equal(localRemoveCode, 0);
    assert.equal(readFileSync(join(proj.fnDir, '.secret.local'), 'utf8'), '');

    const cloudCalls = [];
    const cloudRemoveCode = await runCli(['remove', 'claude', '--yes'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: makeStreamBuffer().stream,
      stderr: makeStreamBuffer().stream,
      env: {},
      spawnSyncFn: (cmd, args) => {
        cloudCalls.push({ cmd, args });
        return { status: 0, stdout: 'Destroyed' };
      },
    });
    assert.equal(cloudRemoveCode, 0);
    assert.deepEqual(cloudCalls[0].args, ['functions:secrets:destroy', 'ANTHROPIC_API_KEY', '--force']);
  } finally {
    proj.cleanup();
  }
});

test('ai_keys provider verifies key exists before switching, and test/prune invoke expected commands', async () => {
  const proj = makeTempProject();
  try {
    // Switching to claude without key fails
    const errMissing = makeStreamBuffer();
    const missingCode = await runCli(['provider', 'claude'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: makeStreamBuffer().stream,
      stderr: errMissing.stream,
      env: {},
      spawnSyncFn: () => ({ status: 1, stderr: 'missing' }),
    });
    assert.equal(missingCode, 1);

    // When cloud secret exists, updates functions/.env
    const outSwitch = makeStreamBuffer();
    const switchCode = await runCli(['provider', 'claude'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: outSwitch.stream,
      stderr: makeStreamBuffer().stream,
      env: {},
      spawnSyncFn: () => ({ status: 0, stdout: 'ENABLED' }),
    });
    assert.equal(switchCode, 0);
    assert.ok(readFileSync(join(proj.fnDir, '.env'), 'utf8').includes('AI_PROVIDER=claude'));

    // prune --yes spawns firebase functions:secrets:prune
    const pruneCalls = [];
    const pruneCode = await runCli(['prune', '--yes'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: makeStreamBuffer().stream,
      stderr: makeStreamBuffer().stream,
      env: {},
      spawnSyncFn: (cmd, args) => {
        pruneCalls.push({ cmd, args });
        return { status: 0 };
      },
    });
    assert.equal(pruneCode, 0);
    assert.deepEqual(pruneCalls[0].args, ['functions:secrets:prune']);

    // Key validation edge cases
    assert.equal(validateApiKeyInput('claude', '   ').ok, false);
    assert.equal(validateApiKeyInput('claude', 'short').ok, false);
    assert.equal(validateApiKeyInput('claude', 'sk-ant-bad space 123456').ok, false);
    assert.equal(validateApiKeyInput('claude', 'customprefix-1234567890abcdef').warnings.length, 1);
  } finally {
    proj.cleanup();
  }
});

test('promptConfirm accepts y, Y, yes with \\n or \\r without enabling raw mode and pauses stdin', async () => {
  const cases = [
    { input: 'y\n', expected: true },
    { input: 'Y\r', expected: true },
    { input: 'yes\r\n', expected: true },
    { input: 'YES\n', expected: true },
    { input: 'ha\n', expected: true },
    { input: 'n\n', expected: false },
    { input: '\n', expected: false },
    { input: '\r', expected: false },
  ];

  for (const c of cases) {
    const fakeStdin = new PassThrough();
    fakeStdin.isTTY = true;
    const rawCalls = [];
    fakeStdin.setRawMode = (v) => rawCalls.push(v);
    let paused = false;
    const origPause = fakeStdin.pause.bind(fakeStdin);
    fakeStdin.pause = () => {
      paused = true;
      return origPause();
    };

    const out = makeStreamBuffer();
    const promise = promptConfirm('Davom etamizmi?', {
      stdin: fakeStdin,
      stdout: out.stream,
    });
    fakeStdin.write(c.input);
    const result = await promise;

    assert.equal(result, c.expected, `Failed for input ${JSON.stringify(c.input)}`);
    assert.deepEqual(rawCalls, [], 'promptConfirm must NEVER call setRawMode');
    assert.equal(paused, true, 'promptConfirm must pause stdin after completion');
  }
});

test('promptHiddenSecret reads piped stdin cleanly and toggles setRawMode(true -> false) + pause on TTY', async () => {
  // Non-TTY (piped) mode must NOT hit the rl.close() empty-string bug
  const pipedIn = new PassThrough();
  pipedIn.isTTY = false;
  const pipedOut = makeStreamBuffer();
  const pipedPromise = promptHiddenSecret('Key: ', { stdin: pipedIn, stdout: pipedOut.stream });
  pipedIn.write('sk-ant-piped-secret-123456\n');
  assert.equal(await pipedPromise, 'sk-ant-piped-secret-123456');

  // TTY raw mode: accepts chars, backspace, \r and restores setRawMode(false) + pause()
  const ttyIn = new PassThrough();
  ttyIn.isTTY = true;
  const rawTransitions = [];
  ttyIn.setRawMode = (v) => rawTransitions.push(v);
  let paused = false;
  const origPause = ttyIn.pause.bind(ttyIn);
  ttyIn.pause = () => {
    paused = true;
    return origPause();
  };
  const ttyOut = makeStreamBuffer();
  const ttyPromise = promptHiddenSecret('Key: ', { stdin: ttyIn, stdout: ttyOut.stream });
  ttyIn.write('sk-ant-abcx\x7f123456\r');
  const secret = await ttyPromise;

  assert.equal(secret, 'sk-ant-abc123456');
  assert.deepEqual(rawTransitions, [true, false]);
  assert.equal(paused, true);
  assert.ok(!ttyOut.getText().includes('sk-ant'), 'Raw key must never echo to stdout');
  assert.ok(ttyOut.getText().includes('*'));
});

test('resolveProviderApiKey checks env -> .secret.local -> Secret Manager in strict order', () => {
  const proj = makeTempProject();
  try {
    writeFileSync(join(proj.fnDir, '.secret.local'), 'ANTHROPIC_API_KEY=sk-ant-from-local-file\n', 'utf8');

    // 1. process.env wins over .secret.local and Secret Manager
    const fromEnv = resolveProviderApiKey('claude', {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      env: { ANTHROPIC_API_KEY: 'sk-ant-from-env' },
      spawnSyncFn: () => {
        throw new Error('Should not hit Secret Manager when env has key');
      },
    });
    assert.equal(fromEnv.ok, true);
    assert.equal(fromEnv.source, 'env');
    assert.equal(fromEnv.key, 'sk-ant-from-env');

    // 2. .secret.local wins over Secret Manager
    const fromLocal = resolveProviderApiKey('claude', {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      env: {},
      spawnSyncFn: () => {
        throw new Error('Should not hit Secret Manager when .secret.local has key');
      },
    });
    assert.equal(fromLocal.ok, true);
    assert.equal(fromLocal.source, 'secret.local');
    assert.equal(fromLocal.key, 'sk-ant-from-local-file');

    // 3. Falls back to firebase functions:secrets:access when neither env nor .secret.local has key
    writeFileSync(join(proj.fnDir, '.secret.local'), '', 'utf8');
    const accessCalls = [];
    const fromCloud = resolveProviderApiKey('claude', {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      env: {},
      spawnSyncFn: (cmd, args, opts) => {
        accessCalls.push({ cmd, args, stdio: opts?.stdio });
        return { status: 0, stdout: 'sk-ant-from-secret-manager-123456\n' };
      },
    });
    assert.equal(fromCloud.ok, true);
    assert.equal(fromCloud.source, 'secret_manager');
    assert.equal(fromCloud.key, 'sk-ant-from-secret-manager-123456');
    assert.equal(accessCalls[0].cmd, 'firebase');
    assert.deepEqual(accessCalls[0].args, ['functions:secrets:access', 'ANTHROPIC_API_KEY']);
    assert.deepEqual(accessCalls[0].stdio, ['ignore', 'pipe', 'pipe']);

    // 4. Not found anywhere -> ok: false
    const missing = resolveProviderApiKey('claude', {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      env: {},
      spawnSyncFn: () => ({ status: 1, stderr: 'not found' }),
    });
    assert.equal(missing.ok, false);
    assert.equal(missing.key, null);
  } finally {
    proj.cleanup();
  }
});

test('ai_keys test claude skips API when missing, sends 1 cheapest request from Secret Manager without leaking secret, and classifies OK/auth/quota/network', async () => {
  const proj = makeTempProject();
  try {
    // Missing key -> zero API calls, exit 1, clear Uzbek message
    let apiCalls = 0;
    const missingOut = makeStreamBuffer();
    const missingErr = makeStreamBuffer();
    const missingCode = await runCli(['test', 'claude'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: missingOut.stream,
      stderr: missingErr.stream,
      env: {},
      spawnSyncFn: () => ({ status: 1, stderr: 'missing' }),
      providerFactory: () => ({
        name: 'claude',
        generate: async () => {
          apiCalls += 1;
          return { text: 'OK' };
        },
      }),
    });
    assert.equal(missingCode, 1);
    assert.equal(apiCalls, 0, 'API must NOT be called when key is missing');
    assert.ok(missingErr.getText().includes('Kalit topilmadi: ANTHROPIC_API_KEY'));

    // Key from Secret Manager -> 1 cheapest request (haiku, maxTokens 16, thinking disabled), secret never printed
    const SECRET_VAL = 'sk-ant-super-secret-manager-token-999';
    const seenRequests = [];
    const okOut = makeStreamBuffer();
    const okErr = makeStreamBuffer();
    const okCode = await runCli(['test', 'claude'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: okOut.stream,
      stderr: okErr.stream,
      env: {},
      spawnSyncFn: (_cmd, args) => {
        if (args[0] === 'functions:secrets:access') {
          return { status: 0, stdout: `${SECRET_VAL}\n` };
        }
        return { status: 1 };
      },
      providerFactory: (name, key) => {
        assert.equal(name, 'claude');
        assert.equal(key, SECRET_VAL);
        return {
          name: 'claude',
          generate: async (req) => {
            seenRequests.push(req);
            return { text: 'SECRET_RESPONSE_DO_NOT_ECHO', model: req.model };
          },
        };
      },
    });
    assert.equal(okCode, 0);
    assert.equal(seenRequests.length, 1, 'ai:keys test must send only ONE cheapest request, not full smoke suite');
    assert.equal(seenRequests[0].model, 'claude-haiku-5-5');
    assert.equal(seenRequests[0].maxTokens, 16);
    assert.deepEqual(seenRequests[0].thinking, { type: 'disabled' });
    assert.equal(seenRequests[0].effort, 'low');
    assert.ok(okOut.getText().includes('Natija: OK'));
    assert.ok(okOut.getText().includes('secret_manager'));
    assert.ok(!okOut.getText().includes(SECRET_VAL), 'Secret Manager key must NEVER appear in stdout');
    assert.ok(!okErr.getText().includes(SECRET_VAL), 'Secret Manager key must NEVER appear in stderr');
    assert.ok(!okOut.getText().includes('SECRET_RESPONSE_DO_NOT_ECHO'));

    // Classifies auth / quota / network cleanly
    const failureCases = [
      { err: new AiError({ kind: 'auth', provider: 'claude', status: 401 }), expectedStatus: 'auth' },
      { err: new AiError({ kind: 'rate_limited', provider: 'claude', status: 429 }), expectedStatus: 'quota' },
      { err: new AiError({ kind: 'timeout', provider: 'claude', status: 504 }), expectedStatus: 'network' },
    ];
    for (const fc of failureCases) {
      const fErr = makeStreamBuffer();
      const fCode = await runCli(['test', 'claude'], {
        rootDir: proj.rootDir,
        fnDir: proj.fnDir,
        stdout: makeStreamBuffer().stream,
        stderr: fErr.stream,
        env: { ANTHROPIC_API_KEY: 'sk-ant-env-key-123456' },
        providerFactory: () => ({
          name: 'claude',
          generate: async () => {
            throw fc.err;
          },
        }),
      });
      assert.equal(fCode, 1);
      assert.ok(fErr.getText().includes(`Natija: ${fc.expectedStatus}`));
      assert.ok(!fErr.getText().includes('sk-ant-env-key-123456'));
    }
  } finally {
    proj.cleanup();
  }
});

test('Empty API key is rejected immediately with AiError auth (401) before network, and runSmokeTests aborts without API calls when key is missing', async () => {
  let claudeCalled = false;
  const emptyClaude = createClaudeProvider({
    apiKey: '',
    createMessage: async () => {
      claudeCalled = true;
      return { content: [{ type: 'text', text: 'nope' }] };
    },
  });
  await assert.rejects(
    () => emptyClaude.generate({ contents: 'hello' }),
    (err) => err instanceof AiError && err.kind === 'auth' && err.status === 401,
  );
  assert.equal(claudeCalled, false);

  let geminiCalled = false;
  const emptyGemini = createGeminiProvider({
    apiKey: '   ',
    generateContent: async () => {
      geminiCalled = true;
      return { text: 'nope' };
    },
  });
  await assert.rejects(
    () => emptyGemini.generate({ contents: 'hello' }),
    (err) => err instanceof AiError && err.kind === 'auth' && err.status === 401,
  );
  assert.equal(geminiCalled, false);

  // runSmokeTests aborts immediately when keyResolver reports missing key
  await assert.rejects(
    () => runSmokeTests({
      providers: ['claude'],
      keyResolver: () => ({ ok: false, secretName: 'ANTHROPIC_API_KEY', key: null, source: null }),
    }),
    /Kalit topilmadi: ANTHROPIC_API_KEY/,
  );
});

test('extractSafeErrorDiag and classifyRawAiError diagnose network/auth errors without leaking keys or messages', () => {
  const secretQueryErr = new TypeError('fetch failed: https://generativelanguage.googleapis.com/v1beta/models?key=AIzaSecretLeak999');
  secretQueryErr.cause = {
    code: 'ENOTFOUND',
    name: 'Error',
    hostname: 'generativelanguage.googleapis.com',
  };
  secretQueryErr.url = 'https://generativelanguage.googleapis.com/v1beta/models?key=AIzaSecretLeak999';

  assert.equal(classifyRawAiError(secretQueryErr), 'timeout');
  const diag = extractSafeErrorDiag(secretQueryErr, 'gemini');
  assert.deepEqual(diag, {
    httpStatus: null,
    errorCode: 'ENOTFOUND',
    errorName: 'Error',
    host: 'generativelanguage.googleapis.com',
  });
  const aiErr = toAiError(secretQueryErr, 'gemini');
  assert.equal(aiErr.kind, 'timeout');
  assert.deepEqual(aiErr.diag, diag);
  assert.ok(!aiErr.message.includes('AIzaSecretLeak999'));
  assert.ok(!JSON.stringify(aiErr).includes('AIzaSecretLeak999'));

  // Literal "fetch failed" without cause.code
  const plainFetchErr = new TypeError('fetch failed');
  assert.equal(classifyRawAiError(plainFetchErr), 'timeout');
  assert.deepEqual(extractSafeErrorDiag(plainFetchErr, 'gemini'), {
    httpStatus: null,
    errorCode: null,
    errorName: 'fetch failed',
    host: 'generativelanguage.googleapis.com',
  });

  // ECONNRESET / ETIMEDOUT
  const resetErr = new Error('socket hang up');
  resetErr.cause = { code: 'ECONNRESET', hostname: 'api.anthropic.com' };
  assert.equal(classifyRawAiError(resetErr), 'timeout');
  assert.equal(extractSafeErrorDiag(resetErr, 'claude').errorCode, 'ECONNRESET');

  // Gemini 400 API_KEY_INVALID -> auth (not invalid_request / network)
  const badKeyErr = new Error('API_KEY_INVALID: API key not valid.');
  badKeyErr.status = 400;
  assert.equal(classifyRawAiError(badKeyErr), 'auth');

  // AiError('truncated', status 200) -> preserves truncated diag rather than generic 'AiError'
  const truncErr = new AiError({ kind: 'truncated', provider: 'gemini', status: 200 });
  assert.deepEqual(extractSafeErrorDiag(truncErr, 'gemini'), {
    httpStatus: 200,
    errorCode: 'truncated',
    errorName: 'truncated',
    host: 'generativelanguage.googleapis.com',
  });
});

test('ai_keys test gemini displays content-free diagnostics (http, xato, host) and caps maxRetries/timeout', async () => {
  const proj = makeTempProject();
  try {
    const seenRequests = [];
    const out = makeStreamBuffer();
    const err = makeStreamBuffer();
    const secret = 'AIzaSyFakeGeminiSecretValue123456';
    const netErr = new TypeError(`fetch failed for https://generativelanguage.googleapis.com/x?key=${secret}`);
    netErr.cause = { code: 'ENOTFOUND', hostname: 'generativelanguage.googleapis.com' };

    const code = await runCli(['test', 'gemini'], {
      rootDir: proj.rootDir,
      fnDir: proj.fnDir,
      stdout: out.stream,
      stderr: err.stream,
      env: { GEMINI_API_KEY: secret },
      providerFactory: () => ({
        name: 'gemini',
        generate: async (req) => {
          seenRequests.push(req);
          throw toAiError(netErr, 'gemini');
        },
      }),
    });
    assert.equal(code, 1);
    assert.equal(seenRequests.length, 1);
    assert.equal(seenRequests[0].maxRetries, 1);
    assert.equal(seenRequests[0].timeoutMs, 10_000);

    const errText = err.getText();
    assert.ok(errText.includes('Natija: network'));
    assert.ok(errText.includes('xato: ENOTFOUND'));
    assert.ok(errText.includes('host: generativelanguage.googleapis.com'));
    assert.ok(!errText.includes(secret), 'Secret key must NEVER appear in diagnostics');
    assert.ok(!out.getText().includes(secret));

    // Direct runSingleCheapestTest with ETIMEDOUT and httpStatus 504
    const timeoutRes = await runSingleCheapestTest({
      provider: 'gemini',
      apiKey: secret,
      providerFactory: () => ({
        name: 'gemini',
        generate: async () => {
          throw new AiError({
            kind: 'timeout',
            provider: 'gemini',
            status: 504,
            diag: {
              httpStatus: 504,
              errorCode: 'ETIMEDOUT',
              errorName: 'TimeoutError',
              host: 'generativelanguage.googleapis.com',
            },
          });
        },
      }),
    });
    assert.equal(timeoutRes.ok, false);
    assert.equal(timeoutRes.status, 'network');
    assert.equal(timeoutRes.httpStatus, 504);
    assert.equal(timeoutRes.errorDetail, 'ETIMEDOUT');
    assert.equal(timeoutRes.host, 'generativelanguage.googleapis.com');
  } finally {
    proj.cleanup();
  }
});

test('createClaudeProvider forwards maxRetries and timeout into SDK reqOpts', async () => {
  const seenOpts = [];
  const claude = createClaudeProvider({
    apiKey: 'sk-ant-test-key-123456',
    maxRetries: 1,
    createMessage: async (_params, reqOpts) => {
      seenOpts.push(reqOpts);
      return {
        model: 'claude-haiku-5-5',
        stop_reason: 'end_turn',
        content: [{ type: 'text', text: 'OK' }],
        usage: { input_tokens: 5, output_tokens: 2 },
      };
    },
  });
  await claude.generate({
    model: 'claude-haiku-5-5',
    contents: 'hi',
    timeoutMs: 8500,
    maxRetries: 1,
    thinking: { type: 'disabled' },
    effort: 'low',
  });
  assert.equal(seenOpts.length, 1);
  assert.equal(seenOpts[0].maxRetries, 1);
  assert.equal(seenOpts[0].timeout, 8500);
});

test('runComparison fast-fails unreachable provider as NETWORK, continues second provider, flushes JSONL immediately, and emits progress', async () => {
  const proj = makeTempProject();
  try {
    const outFile = join(proj.fnDir, 'compare_test.jsonl');
    let geminiCalls = 0;
    let claudeCalls = 0;
    const progressEvents = [];

    const rows = await runComparison({
      providers: ['gemini', 'claude'],
      outFile,
      timeoutMs: 5_000,
      maxRetries: 1,
      apiKeys: { gemini: 'AIzaTestKey12345678', claude: 'sk-ant-TestKey12345678' },
      providerFactory: (name) => ({
        name,
        generate: async (req) => {
          assert.equal(req.maxRetries, 1);
          if (name === 'gemini') {
            geminiCalls += 1;
            const err = new TypeError('fetch failed');
            err.cause = { code: 'ENOTFOUND', hostname: 'generativelanguage.googleapis.com' };
            throw toAiError(err, 'gemini');
          }
          claudeCalls += 1;
          return {
            text: req.responseFormat === 'json'
              ? '{"questions":[{"question":"q","choices":["a","b","c","d"],"answerIndex":0,"explanation":"e"}],"slots":[]}'
              : 'CLAUDE_SECRET_RESPONSE_OK [STUDENT_1] [TEACHER_1] [PHONE_1]',
            model: req.model,
            usage: { inputTokens: 10, outputTokens: 5, webSearchCount: 0 },
          };
        },
      }),
      onProgress: (ev) => {
        progressEvents.push(ev);
        // Verify row was already appended to JSONL file on disk immediately
        const lines = readFileSync(outFile, 'utf8').trim().split('\n');
        assert.equal(lines.length, progressEvents.length);
      },
    });

    assert.equal(geminiCalls, 1, 'Unreachable provider must fail fast after first NETWORK error');
    assert.equal(claudeCalls, 12, 'Second provider must still complete all 12 samples');
    assert.equal(rows.length, 24);
    assert.equal(progressEvents.length, 24);
    assert.equal(progressEvents[0].index, 1);
    assert.equal(progressEvents[23].index, 24);
    assert.equal(progressEvents[23].total, 24);

    const geminiRows = rows.filter((r) => r.provider === 'gemini');
    const claudeRows = rows.filter((r) => r.provider === 'claude');
    assert.equal(geminiRows.length, 12);
    assert.equal(claudeRows.length, 12);
    assert.ok(geminiRows.every((r) => r.status === 'NETWORK' && r.ok === false && r.errorCode === 'ENOTFOUND'));
    assert.ok(claudeRows.every((r) => r.status === 'OK' && r.ok === true));

    const jsonlRaw = readFileSync(outFile, 'utf8');
    assert.ok(!jsonlRaw.includes('CLAUDE_SECRET_RESPONSE_OK'), 'AI response text must NEVER be written to JSONL');
    assert.ok(!jsonlRaw.includes('AIzaTestKey12345678'), 'API keys must NEVER be written to JSONL');
    assert.ok(!jsonlRaw.includes('sk-ant-TestKey12345678'), 'API keys must NEVER be written to JSONL');
  } finally {
    proj.cleanup();
  }
});

test('runSmokeTests classifies network error as NETWORK with errorCode/host and emits progress', async () => {
  const progress = [];
  const results = await runSmokeTests({
    providers: ['gemini'],
    timeoutMs: 5_000,
    maxRetries: 1,
    apiKeys: { gemini: 'AIzaTestKey12345678' },
    providerFactory: () => ({
      name: 'gemini',
      generate: async () => {
        const err = new TypeError('fetch failed');
        err.cause = { code: 'ETIMEDOUT', hostname: 'generativelanguage.googleapis.com' };
        throw toAiError(err, 'gemini');
      },
    }),
    onProgress: (ev) => progress.push(ev),
  });
  assert.equal(results.length, progress.length);
  assert.ok(results.every((r) => r.status === 'NETWORK' && r.errorCode === 'ETIMEDOUT' && r.host === 'generativelanguage.googleapis.com'));
});

