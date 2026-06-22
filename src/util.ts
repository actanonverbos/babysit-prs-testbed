export function greet(name: string): string {
  return `Hello, ${name}!`;
}

export function shout(value: string): string {
  const tmp = value;
  return value.toUpperCase();
}
