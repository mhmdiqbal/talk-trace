import js from "@eslint/js";
import stylistic from "@stylistic/eslint-plugin";
import { defineConfig } from "eslint/config";
import globals from "globals";
import tseslint from "typescript-eslint";

const style = {
  // Union branches are indented by the widely used TS style; the rule disagrees.
  "@stylistic/indent": ["error", 2, { ignoredNodes: ["TSUnionType", "TSUnionType *"] }],
  "@stylistic/quotes": ["error", "double", { avoidEscape: true }],
  "@stylistic/semi": ["error", "always"],
  "@stylistic/comma-dangle": ["error", "always-multiline"],
  "@stylistic/eol-last": ["error", "always"],
  "@stylistic/no-trailing-spaces": "error",
};

const limits = {
  "complexity": ["error", { max: 10, variant: "modified" }],
  "max-depth": ["error", 3],
  "max-lines": ["error", { max: 504, skipBlankLines: false, skipComments: false }],
  "max-lines-per-function": ["error", { max: 104 }],
  "max-nested-callbacks": ["error", 3],
  "max-params": ["error", 4],
  "max-statements": ["error", 26],
};

export default defineConfig(
  {
    ignores: [
      "dist/",
      "release/",
      "node_modules/",
      "native/TalkTraceHelper/.build/",
      "native/TalkTraceTranscriber/.build/",
      "native/vendor/",
    ],
  },
  {
    files: ["src/**/*.ts"],
    extends: [
      js.configs.recommended,
      tseslint.configs.strict,
      tseslint.configs.strictTypeChecked,
    ],
    languageOptions: {
      parserOptions: {
        project: ["./tsconfig.json", "./tsconfig.renderer.json", "./tsconfig.test.json"],
        tsconfigRootDir: import.meta.dirname,
      },
    },
    plugins: { "@stylistic": stylistic },
    rules: {
      // tsc already resolves identifiers; no-undef double-reports on DOM globals.
      "no-undef": "off",
      ...style,
      ...limits,
    },
  },
  {
    files: ["tests/**/*.ts", "vitest.config.mts"],
    extends: [
      js.configs.recommended,
      tseslint.configs.strict,
      tseslint.configs.strictTypeChecked,
    ],
    languageOptions: {
      parserOptions: {
        project: ["./tsconfig.test.json"],
        tsconfigRootDir: import.meta.dirname,
      },
    },
    plugins: { "@stylistic": stylistic },
    rules: {
      "no-undef": "off",
      ...style,
      "@typescript-eslint/unbound-method": "off",
      "max-lines-per-function": "off",
      "max-nested-callbacks": "off",
      "max-statements": "off",
    },
  },
  {
    files: ["build/*.cjs"],
    extends: [js.configs.recommended, tseslint.configs.disableTypeChecked],
    languageOptions: {
      sourceType: "commonjs",
      globals: globals.node,
    },
    plugins: { "@stylistic": stylistic },
    rules: {
      // electron-builder loads the afterPack hook with require().
      "@typescript-eslint/no-require-imports": "off",
      ...style,
      ...limits,
    },
  },
  {
    files: ["eslint.config.mjs"],
    extends: [js.configs.recommended, tseslint.configs.disableTypeChecked],
    languageOptions: {
      sourceType: "module",
      globals: globals.node,
    },
    plugins: { "@stylistic": stylistic },
    rules: { ...style, ...limits },
  },
);
