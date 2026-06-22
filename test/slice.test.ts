import { describe, it, expect } from "vitest";
import { lastN } from "../src/slice.js";

describe("lastN", () => {
  it("returns the last n items", () => {
    expect(lastN([1, 2, 3, 4, 5], 2)).toEqual([4, 5]);
  });
});
