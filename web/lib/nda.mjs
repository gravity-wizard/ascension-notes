import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { cleanExactClockExpression } from "./base38.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const NDA_TEMPLATE_PATH = path.resolve(__dirname, "..", "nda_template.md");

export async function loadNdaTemplate() {
  const markdown = await fs.readFile(NDA_TEMPLATE_PATH, "utf8");
  const templateSha256 = crypto.createHash("sha256").update(markdown, "utf8").digest("hex");
  return { markdown, templateSha256 };
}

export async function createSignedNdaReceipt({
  userId,
  email,
  legalName,
  typedSignature,
  companyOrRole = "",
  clientIp = "unknown",
  userAgent = "unknown",
  unixSeconds = Math.floor(Date.now() / 1000),
}) {
  const { markdown, templateSha256 } = await loadNdaTemplate();
  const signedAtIso = new Date(unixSeconds * 1000).toISOString();
  const base38Tag = cleanExactClockExpression({
    unixSeconds,
    contextWords: ["nda"],
    maxLength: 17,
    alwaysUseDifferenceFormula: true,
    favoriteOffset: "nda",
  }).expression;

  const receiptPayload = {
    receiptId: `NDA-${base38Tag.toUpperCase()}`,
    userId,
    email,
    legalName: legalName.trim(),
    typedSignature: typedSignature.trim(),
    companyOrRole: companyOrRole.trim(),
    signedAtIso,
    signedAtBase38: base38Tag,
    signedAtUnix: unixSeconds,
    templateSha256,
    clientIp,
    userAgent,
  };

  const receiptHash = crypto
    .createHash("sha256")
    .update(JSON.stringify(receiptPayload))
    .digest("hex");

  return {
    ...receiptPayload,
    receiptHash,
    agreementPreview: markdown.split("\n")[0] || "TWISTED23 NDA",
  };
}
