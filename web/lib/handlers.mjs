import crypto from "node:crypto";
import {
  cleanExactClockExpression,
  sanitizeFavorite3LetterOffset,
} from "./base38.mjs";
import {
  clearSessionCookie,
  mintTierBase38Password,
  normalizePasswordInput,
  passwordLookupIndex,
  serializeSessionCookie,
  signSessionToken,
  verifyPasswordHash,
} from "./auth.mjs";
import {
  devOutboxEnabled,
  getClientIp,
  isHttpsRequest,
  readJsonBody,
  resolveAuthenticatedUser,
  sanitizePublicUser,
  sendJson,
} from "./http.mjs";
import { deliverAccessPasswordEmail } from "./mailer.mjs";
import { createSignedNdaReceipt, loadNdaTemplate } from "./nda.mjs";
import { defaultStore } from "./store.mjs";

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function getAdminKey() {
  return process.env.TWISTED23_ADMIN_KEY || "";
}

function isAdminAuthorized(req) {
  const configured = getAdminKey();
  if (!configured) return false;
  const provided = String(req.headers["x-admin-key"] || "").trim();
  if (!provided || provided.length !== configured.length) return false;
  return crypto.timingSafeEqual(Buffer.from(provided), Buffer.from(configured));
}

export async function handleHealth(req, res) {
  const nowSec = Math.floor(Date.now() / 1000);
  const tag = cleanExactClockExpression({
    unixSeconds: nowSec,
    contextWords: ["sun"],
    alwaysUseDifferenceFormula: true,
  }).expression;
  sendJson(res, 200, {
    ok: true,
    brand: "Twisted23.com",
    service: "Photo Naming Demo",
    clockBase38: tag,
    unixSeconds: nowSec,
    devOutbox: devOutboxEnabled(req),
  });
}

export async function handleSession(req, res, store = defaultStore) {
  const user = await resolveAuthenticatedUser(req, store);
  sendJson(res, 200, {
    ok: true,
    user: sanitizePublicUser(user),
    devOutboxAvailable: devOutboxEnabled(req),
  });
}

export async function handleRegister(req, res, store = defaultStore) {
  if (req.method !== "POST") {
    return sendJson(res, 405, { ok: false, error: "Method not allowed" });
  }
  const body = await readJsonBody(req);
  const name = String(body.name || "").trim();
  const email = String(body.email || "").trim().toLowerCase();
  const rawFav = String(body.favoriteOffset || "").trim();

  if (name.length < 2) {
    return sendJson(res, 400, { ok: false, error: "Please enter your name (at least 2 characters)." });
  }
  if (!isValidEmail(email)) {
    return sendJson(res, 400, { ok: false, error: "Please enter a valid email address." });
  }
  if (rawFav && !sanitizeFavorite3LetterOffset(rawFav)) {
    return sendJson(res, 400, {
      ok: false,
      error: "Favorite 3-letter offset must be 3 clean lowercase letters (a–z, e.g. joy, sun, or your initials).",
    });
  }

  const favoriteOffset = sanitizeFavorite3LetterOffset(rawFav) || "";
  const nowUnix = Math.floor(Date.now() / 1000);

  let minted;
  let userRecord;

  const outcome = await store.updateState((state) => {
    const existingId = state.userIdByEmail[email];
    const existingUser = existingId ? state.usersById[existingId] : null;
    if (existingUser && existingUser.revokedAt) {
      return { blocked: true, status: 403, error: "Access for this email has been revoked." };
    }

    minted = mintTierBase38Password({
      tier: 1,
      favoriteOffset: favoriteOffset || existingUser?.favoriteOffset || null,
      existingIndexes: state.credentialByIndex,
      unixSeconds: nowUnix,
    });

    const userId = existingUser ? existingUser.id : `usr_${crypto.randomUUID().slice(0, 12)}`;

    // Revoke previous active L1 credential index for this user if re-issuing
    for (const [idxKey, cred] of Object.entries(state.credentialByIndex)) {
      if (cred.userId === userId && cred.tier === 1) {
        delete state.credentialByIndex[idxKey];
      }
    }

    state.credentialByIndex[minted.indexKey] = {
      userId,
      tier: 1,
      hash: minted.hash,
      mintedUnix: minted.mintedUnix,
      suffixUsed: minted.suffixUsed,
      prefixPreview: minted.password.slice(0, 4),
    };

    userRecord = existingUser || {
      id: userId,
      email,
      name,
      tier: 1,
      emailVerified: false,
      favoriteOffset: favoriteOffset || "",
      createdAtIso: new Date(nowUnix * 1000).toISOString(),
      ndaReceipt: null,
      revokedAt: null,
      issuedHistory: [],
    };
    userRecord.name = name;
    if (favoriteOffset) userRecord.favoriteOffset = favoriteOffset;
    userRecord.issuedHistory.push({
      tier: 1,
      issuedAtIso: new Date(nowUnix * 1000).toISOString(),
      mintedUnix: minted.mintedUnix,
      suffixUsed: minted.suffixUsed,
      passwordFingerprint: minted.indexKey.slice(0, 12),
    });

    state.usersById[userId] = userRecord;
    state.userIdByEmail[email] = userId;
    return { blocked: false };
  });

  if (outcome.blocked) {
    return sendJson(res, outcome.status, { ok: false, error: outcome.error });
  }

  const mailResult = await deliverAccessPasswordEmail({
    toEmail: email,
    recipientName: name,
    tier: 1,
    base38Password: minted.password,
  });

  if (mailResult.outboxEntry) {
    await store.updateState((state) => {
      state.devOutbox.unshift(mailResult.outboxEntry);
      state.devOutbox = state.devOutbox.slice(0, 30);
    });
  }

  return sendJson(res, 200, {
    ok: true,
    message:
      mailResult.mode === "resend"
        ? `Sent your personal Level 1 Base-38 access password to ${email}. Enter it to verify your email and unlock Level 1.`
        : `Generated your Level 1 Base-38 password in Dev Outbox for ${email}. Paste it to verify & unlock Level 1.`,
    deliveryMode: mailResult.mode,
    emailVerified: userRecord.emailVerified,
  });
}

export async function handleLogin(req, res, store = defaultStore) {
  if (req.method !== "POST") {
    return sendJson(res, 405, { ok: false, error: "Method not allowed" });
  }
  const body = await readJsonBody(req);
  const emailFilter = String(body.email || "").trim().toLowerCase();
  const rawPassword = String(body.password || "");
  const normalizedPwd = normalizePasswordInput(rawPassword);

  if (!normalizedPwd) {
    return sendJson(res, 400, { ok: false, error: "Enter your emailed Base-38 access password." });
  }

  const indexKey = passwordLookupIndex(normalizedPwd);

  const authResult = await store.updateState((state) => {
    const cred = state.credentialByIndex[indexKey];
    if (!cred || !verifyPasswordHash(normalizedPwd, cred.hash)) {
      return { ok: false, status: 401, error: "Invalid Base-38 access password." };
    }
    const user = state.usersById[cred.userId];
    if (!user) {
      return { ok: false, status: 401, error: "Account not found." };
    }
    if (user.revokedAt) {
      return { ok: false, status: 403, error: "Access has been revoked by admin." };
    }
    if (emailFilter && user.email !== emailFilter) {
      return { ok: false, status: 401, error: "Password does not match that email address." };
    }

    user.emailVerified = true;
    user.lastLoginAtIso = new Date().toISOString();
    if (cred.tier > user.tier) {
      user.tier = cred.tier;
    }
    state.usersById[user.id] = user;

    return { ok: true, user, matchedTier: cred.tier };
  });

  if (!authResult.ok) {
    return sendJson(res, authResult.status, { ok: false, error: authResult.error });
  }

  const token = signSessionToken({
    userId: authResult.user.id,
    tier: authResult.user.tier,
  });

  return sendJson(
    res,
    200,
    {
      ok: true,
      user: sanitizePublicUser(authResult.user),
      matchedTier: authResult.matchedTier,
    },
    {
      setCookie: serializeSessionCookie(token, { secure: isHttpsRequest(req) }),
    }
  );
}

export async function handleLogout(req, res) {
  if (req.method !== "POST") {
    return sendJson(res, 405, { ok: false, error: "Method not allowed" });
  }
  return sendJson(
    res,
    200,
    { ok: true, user: sanitizePublicUser(null) },
    { setCookie: clearSessionCookie({ secure: isHttpsRequest(req) }) }
  );
}

export async function handlePreferences(req, res, store = defaultStore) {
  if (req.method !== "POST") {
    return sendJson(res, 405, { ok: false, error: "Method not allowed" });
  }
  const authed = await resolveAuthenticatedUser(req, store);
  if (!authed || authed.tier < 1) {
    return sendJson(res, 401, { ok: false, error: "Sign in at Level 1 or higher to save preferences." });
  }
  const body = await readJsonBody(req);
  const rawFav = String(body.favoriteOffset || "").trim();
  const sanitized = rawFav ? sanitizeFavorite3LetterOffset(rawFav) : "";
  if (rawFav && !sanitized) {
    return sendJson(res, 400, {
      ok: false,
      error: "Favorite 3-letter offset must be 3 clean lowercase letters (a–z).",
    });
  }

  const updated = await store.updateState((state) => {
    const user = state.usersById[authed.id];
    if (!user) return null;
    user.favoriteOffset = sanitized || "";
    state.usersById[user.id] = user;
    return user;
  });

  return sendJson(res, 200, { ok: true, user: sanitizePublicUser(updated) });
}

export async function handleGetNda(req, res, store = defaultStore) {
  const authed = await resolveAuthenticatedUser(req, store);
  const template = await loadNdaTemplate();
  return sendJson(res, 200, {
    ok: true,
    markdown: template.markdown,
    templateSha256: template.templateSha256,
    user: sanitizePublicUser(authed),
  });
}

export async function handleSignNda(req, res, store = defaultStore) {
  if (req.method !== "POST") {
    return sendJson(res, 405, { ok: false, error: "Method not allowed" });
  }
  const authed = await resolveAuthenticatedUser(req, store);
  if (!authed || authed.tier < 1 || !authed.emailVerified) {
    return sendJson(res, 401, {
      ok: false,
      error: "Please register and sign in with your Level 1 Base-38 password before signing the NDA.",
    });
  }

  const body = await readJsonBody(req);
  const legalName = String(body.legalName || authed.name || "").trim();
  const typedSignature = String(body.typedSignature || "").trim();
  const companyOrRole = String(body.companyOrRole || "").trim();
  const agreed = Boolean(body.agreed);

  if (!agreed) {
    return sendJson(res, 400, { ok: false, error: "Please check the NDA agreement box." });
  }
  if (legalName.length < 2 || typedSignature.length < 2) {
    return sendJson(res, 400, {
      ok: false,
      error: "Please enter your legal name and typed electronic signature.",
    });
  }

  const nowUnix = Math.floor(Date.now() / 1000);
  const receipt = await createSignedNdaReceipt({
    userId: authed.id,
    email: authed.email,
    legalName,
    typedSignature,
    companyOrRole,
    clientIp: getClientIp(req),
    userAgent: String(req.headers["user-agent"] || "unknown"),
    unixSeconds: nowUnix,
  });

  let mintedL2;
  let updatedUser;

  await store.updateState((state) => {
    const user = state.usersById[authed.id];
    mintedL2 = mintTierBase38Password({
      tier: 2,
      favoriteOffset: user.favoriteOffset || null,
      existingIndexes: state.credentialByIndex,
      unixSeconds: nowUnix,
    });

    for (const [idxKey, cred] of Object.entries(state.credentialByIndex)) {
      if (cred.userId === user.id && cred.tier === 2) {
        delete state.credentialByIndex[idxKey];
      }
    }

    state.credentialByIndex[mintedL2.indexKey] = {
      userId: user.id,
      tier: 2,
      hash: mintedL2.hash,
      mintedUnix: mintedL2.mintedUnix,
      suffixUsed: mintedL2.suffixUsed,
      prefixPreview: mintedL2.password.slice(0, 4),
    };

    user.tier = 2;
    user.ndaReceipt = receipt;
    user.issuedHistory.push({
      tier: 2,
      issuedAtIso: receipt.signedAtIso,
      mintedUnix: mintedL2.mintedUnix,
      suffixUsed: mintedL2.suffixUsed,
      ndaReceiptId: receipt.receiptId,
      passwordFingerprint: mintedL2.indexKey.slice(0, 12),
    });

    state.usersById[user.id] = user;
    state.ndaReceipts.unshift(receipt);
    updatedUser = user;
  });

  const mailResult = await deliverAccessPasswordEmail({
    toEmail: updatedUser.email,
    recipientName: updatedUser.name,
    tier: 2,
    base38Password: mintedL2.password,
    ndaReceiptHash: receipt.receiptHash,
  });

  if (mailResult.outboxEntry) {
    await store.updateState((state) => {
      state.devOutbox.unshift(mailResult.outboxEntry);
      state.devOutbox = state.devOutbox.slice(0, 30);
    });
  }

  const newToken = signSessionToken({
    userId: updatedUser.id,
    tier: 2,
  });

  return sendJson(
    res,
    200,
    {
      ok: true,
      user: sanitizePublicUser(updatedUser),
      level2Password: mintedL2.password,
      ndaReceipt: receipt,
      deliveryMode: mailResult.mode,
    },
    {
      setCookie: serializeSessionCookie(newToken, { secure: isHttpsRequest(req) }),
    }
  );
}

export async function handleDevOutbox(req, res, store = defaultStore) {
  if (!devOutboxEnabled(req)) {
    return sendJson(res, 404, { ok: false, error: "Not found" });
  }
  const url = new URL(req.url, "http://localhost");
  const emailFilter = (url.searchParams.get("email") || "").trim().toLowerCase();
  const state = await store.readState();
  const messages = emailFilter
    ? state.devOutbox.filter((m) => m.toEmail === emailFilter)
    : state.devOutbox;
  return sendJson(res, 200, { ok: true, messages });
}

export async function handleAdminAudit(req, res, store = defaultStore) {
  if (!isAdminAuthorized(req)) {
    return sendJson(res, 403, { ok: false, error: "Admin key missing or invalid." });
  }
  const state = await store.readState();
  const users = Object.values(state.usersById).map((u) => ({
    ...sanitizePublicUser(u),
    createdAtIso: u.createdAtIso,
    lastLoginAtIso: u.lastLoginAtIso || null,
    revokedAt: u.revokedAt || null,
    issuedHistory: u.issuedHistory || [],
  }));
  return sendJson(res, 200, {
    ok: true,
    users,
    ndaReceipts: state.ndaReceipts,
  });
}

export async function handleAdminRevoke(req, res, store = defaultStore) {
  if (req.method !== "POST") {
    return sendJson(res, 405, { ok: false, error: "Method not allowed" });
  }
  if (!isAdminAuthorized(req)) {
    return sendJson(res, 403, { ok: false, error: "Admin key missing or invalid." });
  }
  const body = await readJsonBody(req);
  const email = String(body.email || "").trim().toLowerCase();
  const revoke = body.revoke !== false;

  const updated = await store.updateState((state) => {
    const uid = state.userIdByEmail[email];
    const user = uid ? state.usersById[uid] : null;
    if (!user) return null;
    user.revokedAt = revoke ? new Date().toISOString() : null;
    if (revoke) {
      for (const [idxKey, cred] of Object.entries(state.credentialByIndex)) {
        if (cred.userId === uid) {
          delete state.credentialByIndex[idxKey];
        }
      }
    }
    state.usersById[uid] = user;
    return user;
  });

  if (!updated) {
    return sendJson(res, 404, { ok: false, error: "User not found." });
  }
  return sendJson(res, 200, { ok: true, email, revokedAt: updated.revokedAt });
}
