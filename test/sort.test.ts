import { describe, it, expect } from "vitest";
import { sortAsc } from "../src/sort.js";

describe("sortAsc", () => {
  it("sorts ascending", () => {
    expect(sortAsc([3, 1, 2])).toEqual([1, 2, 3]);
  });
});
