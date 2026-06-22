export function lastN<T>(items: T[], n: number): T[] {
  return items.slice(items.length - n);
}
