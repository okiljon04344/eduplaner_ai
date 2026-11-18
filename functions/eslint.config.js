export default [
  {
    files: ['**/*.js'],
    languageOptions: {
      ecmaVersion: 2024,
      sourceType: 'module',
    },
    rules: {
      'no-unused-vars': 'error',
      'semi': ['error', 'always'],
    },
  },
  {
    files: ['index.js', 'school/**/*.js'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: [
                '**/*_provider.js',
                '!**/ai_provider.js',
                '**/gemini_provider*',
                '**/claude_provider*',
                '**/privacy/gemini_client.js',
                '**/privacy/safe_gemini.js',
                '@google/genai',
                '@anthropic-ai/sdk',
              ],
              message:
                'Call AI through privacy/safe_ai.js and ai/ai_provider.js instead of importing providers or SDKs directly.',
            },
          ],
        },
      ],
    },
  },
  {
    files: ['privacy/**/*.js'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: ['@google/genai', '@anthropic-ai/sdk'],
              message: 'AI SDKs may only be imported inside functions/ai/.',
            },
          ],
        },
      ],
    },
  },
];
