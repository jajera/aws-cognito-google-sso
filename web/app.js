const PKCE_STORAGE_KEY = "cognito-google-sso-pkce";
const DISPLAY_CLAIMS = ["email", "name", "sub", "cognito:groups"];

export function getWebCrypto() {
  if (globalThis.crypto?.subtle) {
    return globalThis.crypto;
  }
  throw new Error("Web Crypto API is required");
}

export function base64UrlEncode(bytes) {
  const binary = String.fromCharCode(...new Uint8Array(bytes));
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

export function generateRandomString(byteLength = 32) {
  const bytes = new Uint8Array(byteLength);
  getWebCrypto().getRandomValues(bytes);
  return base64UrlEncode(bytes);
}

export async function createPkcePair() {
  const codeVerifier = generateRandomString(32);
  const digest = await getWebCrypto().subtle.digest(
    "SHA-256",
    new TextEncoder().encode(codeVerifier),
  );
  return {
    codeVerifier,
    codeChallenge: base64UrlEncode(digest),
  };
}

export function decodeJwtPayload(token) {
  if (typeof token !== "string" || token.split(".").length < 2) {
    throw new Error("Invalid token");
  }

  const payload = token.split(".")[1]
    .replace(/-/g, "+")
    .replace(/_/g, "/");
  const padded = payload + "=".repeat((4 - (payload.length % 4)) % 4);
  return JSON.parse(atob(padded));
}

export function pickDisplayClaims(claims) {
  const selected = {};
  for (const key of DISPLAY_CLAIMS) {
    if (claims?.[key] !== undefined) {
      selected[key] = claims[key];
    }
  }
  return selected;
}

export function getDisplayName(claims) {
  if (typeof claims?.name === "string" && claims.name.trim()) {
    return claims.name.trim();
  }
  if (typeof claims?.email === "string" && claims.email.trim()) {
    return claims.email.trim();
  }
  return "there";
}

export function buildAuthorizeUrl(config, { codeChallenge, state }) {
  const url = new URL(`${config.cognitoDomain}/oauth2/authorize`);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", config.clientId);
  url.searchParams.set("redirect_uri", config.redirectUri);
  url.searchParams.set("scope", "openid email");
  url.searchParams.set("identity_provider", "Google");
  url.searchParams.set("code_challenge_method", "S256");
  url.searchParams.set("code_challenge", codeChallenge);
  url.searchParams.set("state", state);
  return url.toString();
}

export function buildLogoutUrl(config) {
  const url = new URL(`${config.cognitoDomain}/logout`);
  url.searchParams.set("client_id", config.clientId);
  url.searchParams.set("logout_uri", config.logoutUri);
  return url.toString();
}

export async function exchangeAuthorizationCode(config, { code, codeVerifier }) {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    code,
    code_verifier: codeVerifier,
  });

  const response = await fetch(`${config.cognitoDomain}/oauth2/token`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error("Token exchange failed");
  }
  if (typeof payload.id_token !== "string") {
    throw new Error("Token exchange failed");
  }
  return payload;
}

function requireConfig() {
  const config = globalThis.APP_CONFIG;
  if (
    !config?.cognitoDomain ||
    !config?.clientId ||
    !config?.redirectUri ||
    !config?.logoutUri
  ) {
    throw new Error("Application configuration is missing");
  }
  return config;
}

function setStatus(message, kind = "") {
  const status = document.getElementById("status");
  status.textContent = message;
  status.className = kind ? `status ${kind}` : "status";
}

function renderSignedInView(claims) {
  const signedOutView = document.getElementById("signed-out-view");
  const signedInView = document.getElementById("signed-in-view");
  const list = document.getElementById("claims-list");
  list.replaceChildren();

  const selected = pickDisplayClaims(claims);
  for (const [key, value] of Object.entries(selected)) {
    const dt = document.createElement("dt");
    dt.textContent = key;
    const dd = document.createElement("dd");
    dd.textContent = Array.isArray(value) ? value.join(", ") : String(value);
    list.append(dt, dd);
  }

  const email = typeof claims?.email === "string" ? claims.email : "";
  document.getElementById("account-email").textContent = email;
  document.getElementById("welcome-heading").textContent =
    `Welcome, ${getDisplayName(claims)}`;

  signedOutView.hidden = true;
  signedInView.hidden = false;
}

function clearSession() {
  sessionStorage.removeItem(PKCE_STORAGE_KEY);
}

async function startSignIn() {
  const config = requireConfig();
  const { codeVerifier, codeChallenge } = await createPkcePair();
  const state = generateRandomString(16);
  sessionStorage.setItem(
    PKCE_STORAGE_KEY,
    JSON.stringify({ codeVerifier, state }),
  );
  window.location.assign(buildAuthorizeUrl(config, { codeChallenge, state }));
}

function startSignOut() {
  const config = requireConfig();
  clearSession();
  window.location.assign(buildLogoutUrl(config));
}

async function handleRedirect() {
  const params = new URLSearchParams(window.location.search);
  const error = params.get("error");
  const code = params.get("code");
  const state = params.get("state");

  if (!error && !code) {
    setStatus("Ready to sign in.");
    return;
  }

  window.history.replaceState({}, document.title, window.location.pathname);

  if (error) {
    clearSession();
    setStatus("Sign-in failed. Try again.", "error");
    return;
  }

  const stored = sessionStorage.getItem(PKCE_STORAGE_KEY);
  clearSession();
  if (!stored) {
    setStatus("Sign-in session expired. Try again.", "error");
    return;
  }

  let pkce;
  try {
    pkce = JSON.parse(stored);
  } catch {
    setStatus("Sign-in session expired. Try again.", "error");
    return;
  }

  if (!state || state !== pkce.state || !pkce.codeVerifier) {
    setStatus("Sign-in session expired. Try again.", "error");
    return;
  }

  try {
    setStatus("Completing sign-in...");
    const tokens = await exchangeAuthorizationCode(requireConfig(), {
      code,
      codeVerifier: pkce.codeVerifier,
    });
    const claims = decodeJwtPayload(tokens.id_token);
    renderSignedInView(claims);
  } catch {
    setStatus("Sign-in failed. Try again.", "error");
  }
}

function wireUi() {
  document.getElementById("sign-in").addEventListener("click", () => {
    startSignIn().catch(() => {
      setStatus("Sign-in failed. Try again.", "error");
    });
  });
  document.getElementById("sign-out").addEventListener("click", startSignOut);
}

if (typeof document !== "undefined" && document.getElementById("sign-in")) {
  wireUi();
  handleRedirect();
}
