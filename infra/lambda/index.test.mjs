import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import { handler, parseAllowedEmails } from "./index.mjs";

const makeEvent = (email) => ({
  triggerSource: "PreSignUp_ExternalProvider",
  request: {
    userAttributes: email === undefined ? {} : { email },
  },
  response: {},
});

afterEach(() => {
  delete process.env.ALLOWED_EMAILS;
});

test("parses a JSON list of emails", () => {
  assert.deepEqual(
    parseAllowedEmails('["operator@gmail.com", " admin@Example.com "]'),
    ["operator@gmail.com", "admin@example.com"],
  );
});

test("allows any email in the configured list", async () => {
  process.env.ALLOWED_EMAILS = JSON.stringify([
    "operator@gmail.com",
    "admin@gmail.com",
  ]);

  const result = await handler(makeEvent("admin@gmail.com"));

  assert.equal(result.response.autoConfirmUser, true);
  assert.equal(result.response.autoVerifyEmail, true);
});

test("rejects a non-matching email with a generic error", async () => {
  process.env.ALLOWED_EMAILS = JSON.stringify(["operator@gmail.com"]);

  await assert.rejects(
    handler(makeEvent("someone-else@gmail.com")),
    new Error("Email is not authorized"),
  );
});

test("rejects a missing email attribute", async () => {
  process.env.ALLOWED_EMAILS = JSON.stringify(["operator@gmail.com"]);

  await assert.rejects(
    handler(makeEvent(undefined)),
    new Error("Email is not authorized"),
  );
});

test("normalizes case and surrounding whitespace", async () => {
  process.env.ALLOWED_EMAILS = JSON.stringify([" Operator@Gmail.com "]);

  const result = await handler(makeEvent("operator@gmail.COM"));

  assert.equal(result.response.autoConfirmUser, true);
  assert.equal(result.response.autoVerifyEmail, true);
});

test("creates a response object when absent", async () => {
  process.env.ALLOWED_EMAILS = JSON.stringify(["operator@gmail.com"]);
  const event = makeEvent("operator@gmail.com");
  delete event.response;

  const result = await handler(event);

  assert.equal(result.response.autoConfirmUser, true);
  assert.equal(result.response.autoVerifyEmail, true);
});
