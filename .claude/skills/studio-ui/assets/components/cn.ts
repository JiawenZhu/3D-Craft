/**
 * Class joiner. Deliberately dependency-free.
 *
 * The kit ships this rather than importing clsx so that dropping the folder
 * into a project adds nothing to its package.json. If the host already has
 * clsx or tailwind-merge, delete this file and repoint the imports — the
 * signature is compatible with clsx's.
 */
export type ClassValue = string | number | null | undefined | false | ClassValue[];

export const cn = (...parts: ClassValue[]): string =>
  parts
    .flat(Infinity as 1)
    .filter((p): p is string | number => p !== null && p !== undefined && p !== false && p !== '')
    .join(' ');
