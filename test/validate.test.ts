import { describe, it, expect } from "vitest";
import { isValidId } from "../src/validate.js";

describe("isValidId", () => {
  it("accepts alphanumeric ids", () => {
    expect(isValidId("abc123")).toBe(true);
  });

  it("rejects punctuation", () => {
    expect(isValidId("abc!")).toBe(false);
  });
});
