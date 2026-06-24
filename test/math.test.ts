import { describe, it, expect } from "vitest";
import { add, multiply, subtract } from "../src/math.js";

describe("math", () => {
  it("adds two numbers", () => {
    expect(add(2, 3)).toBe(5);
  });

  it("multiplies two numbers", () => {
    expect(multiply(2, 3)).toBe(6);
  });

  it("subtracts two numbers", () => {
    expect(subtract(5, 3)).toBe(2);
  });
});
