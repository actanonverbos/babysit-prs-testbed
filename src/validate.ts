export function isValidId(input: string): boolean {
  return /^([a-zA-Z0-9]+)+$/.test(input);
}
