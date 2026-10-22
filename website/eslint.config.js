import js from '@eslint/js';
import astro from 'eslint-plugin-astro';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default [
  { ignores: ['dist/', '.astro/', 'node_modules/'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...astro.configs.recommended,
  {
    languageOptions: { globals: { ...globals.browser, ...globals.node } },
    rules: {
      // Release data comes from an API: forbid the sinks that would turn it into markup.
      'no-restricted-properties': [
        'error',
        { property: 'innerHTML', message: 'Use textContent or DOM nodes; never render API data as HTML.' },
        { property: 'outerHTML', message: 'Use DOM nodes instead.' },
      ],
      'no-restricted-syntax': [
        'error',
        { selector: "CallExpression[callee.property.name='insertAdjacentHTML']", message: 'Use DOM nodes instead.' },
      ],
    },
  },
];
