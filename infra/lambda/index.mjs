export function parseAllowedEmails(raw) {
  if (typeof raw !== "string" || raw.trim() === "") {
    return [];
  }

  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) {
      return [];
    }

    return parsed
      .filter((value) => typeof value === "string")
      .map((value) => value.trim().toLowerCase())
      .filter((value) => value !== "");
  } catch {
    return [];
  }
}

export const handler = async (event) => {
  const email = event?.request?.userAttributes?.email;
  const allowedEmails = parseAllowedEmails(process.env.ALLOWED_EMAILS);

  if (
    typeof email !== "string" ||
    allowedEmails.length === 0 ||
    !allowedEmails.includes(email.trim().toLowerCase())
  ) {
    throw new Error("Email is not authorized");
  }

  event.response ??= {};
  event.response.autoConfirmUser = true;
  event.response.autoVerifyEmail = true;

  return event;
};
