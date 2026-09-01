/// <reference types="vite/client" />

/*
 * Declared explicitly, and read property-by-property in the code, because of a
 * real leak this prevents.
 *
 * `import.meta.env?.VITE_API_BASE` looks harmless but the optional chain means
 * Vite cannot see which property is wanted, so its dev transform substitutes
 * the ENTIRE env object — every VITE_* variable in .env, inlined into a module
 * the browser downloads. A key that was only ever meant for the server then
 * ships to the page. `import.meta.env.VITE_API_BASE` is replaced with just that
 * one string instead.
 *
 * Nothing secret belongs behind a VITE_ prefix in the first place; this keeps a
 * mistake in .env from becoming a mistake in the bundle.
 */
interface ImportMetaEnv {
  readonly VITE_API_BASE?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
