import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { test } from "node:test";

if (!globalThis.crypto) {
  globalThis.crypto = webcrypto;
}
if (!globalThis.btoa) {
  globalThis.btoa = (value) => Buffer.from(value, "binary").toString("base64");
}
if (!globalThis.atob) {
  globalThis.atob = (value) => Buffer.from(value, "base64").toString("binary");
}

const {
  base64UrlEncode,
  buildAuthorizeUrl,
  buildLogoutUrl,
  createPkcePair,
  decodeJwtPayload,
  getDisplayName,
  pickDisplayClaims,
} = await import("./app.js");

test("base64UrlEncode removes padding and uses URL-safe characters", () => {
  const encoded = base64UrlEncode(new Uint8Array([251, 255, 191]));
  assert.equal(encoded.includes("+"), false);
  assert.equal(encoded.includes("/"), false);
  assert.equal(encoded.includes("="), false);
});

test("createPkcePair returns verifier and S256 challenge", async () => {
  const pair = await createPkcePair();
  assert.equal(typeof pair.codeVerifier, "string");
  assert.equal(typeof pair.codeChallenge, "string");
  assert.notEqual(pair.codeVerifier, pair.codeChallenge);
  assert.match(pair.codeChallenge, /^[A-Za-z0-9_-]+$/);
});

test("decodeJwtPayload returns claim object", () => {
  const payload = Buffer.from(JSON.stringify({ email: "a@example.com", sub: "123" }))
    .toString("base64url");
  const claims = decodeJwtPayload(`aaa.${payload}.bbb`);
  assert.deepEqual(claims, { email: "a@example.com", sub: "123" });
});

test("pickDisplayClaims keeps only safe demo claims", () => {
  assert.deepEqual(
    pickDisplayClaims({
      email: "a@example.com",
      name: "Ada",
      sub: "123",
      "cognito:groups": ["operator"],
      access_token: "secret",
    }),
    {
      email: "a@example.com",
      name: "Ada",
      sub: "123",
      "cognito:groups": ["operator"],
    },
  );
});

test("getDisplayName prefers name and falls back safely", () => {
  assert.equal(getDisplayName({ name: " Ada Lovelace ", email: "ada@example.com" }), "Ada Lovelace");
  assert.equal(getDisplayName({ email: "ada@example.com" }), "ada@example.com");
  assert.equal(getDisplayName({}), "there");
});

test("buildAuthorizeUrl includes PKCE and Google identity provider", () => {
  const url = new URL(buildAuthorizeUrl(
    {
      cognitoDomain: "https://example.auth.ap-southeast-2.amazoncognito.com",
      clientId: "abc",
      redirectUri: "https://d111.cloudfront.net",
    },
    { codeChallenge: "challenge", state: "state123" },
  ));

  assert.equal(url.searchParams.get("response_type"), "code");
  assert.equal(url.searchParams.get("client_id"), "abc");
  assert.equal(url.searchParams.get("redirect_uri"), "https://d111.cloudfront.net");
  assert.equal(url.searchParams.get("scope"), "openid email");
  assert.equal(url.searchParams.get("identity_provider"), "Google");
  assert.equal(url.searchParams.get("code_challenge_method"), "S256");
  assert.equal(url.searchParams.get("code_challenge"), "challenge");
  assert.equal(url.searchParams.get("state"), "state123");
});

test("buildLogoutUrl targets Cognito logout endpoint", () => {
  const url = new URL(buildLogoutUrl({
    cognitoDomain: "https://example.auth.ap-southeast-2.amazoncognito.com",
    clientId: "abc",
    logoutUri: "https://d111.cloudfront.net",
  }));

  assert.equal(url.pathname, "/logout");
  assert.equal(url.searchParams.get("client_id"), "abc");
  assert.equal(url.searchParams.get("logout_uri"), "https://d111.cloudfront.net");
});
