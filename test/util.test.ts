import { describe, it, expect } from "vitest";
import { greet, shout } from "../src/util.js";

describe("util", () => {
  it("greets by name", () => {
    expect(greet("Iz")).toBe("Hello, Iz!");
  });

  it("shouts in uppercase", () => {
    expect(shout("hi")).toBe("HI");
  });
});
