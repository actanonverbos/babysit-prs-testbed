import { describe, it, expect } from "vitest";
import { stackTop } from "../src/stack.js";

describe("stack", () => {
  it("returns base plus one", () => {
    expect(stackTop()).toBe(2);
  });
});
