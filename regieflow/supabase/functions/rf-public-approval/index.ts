import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb } from "npm:pdf-lib@1.17.1";

const CONSENT_TEXT = "Ich bestätige, dass ich für dieses Projekt zur Freigabe berechtigt bin und die dargestellte Regie in dieser Version freigebe.";
const CONSENT_VERSION = "v1";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

async function sha256Hex(input: string | Uint8Array) {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function dataUrlToBytes(dataUrl: string) {
  const match = dataUrl.match(/^data:(image\/(?:png|jpeg));base64,(.+)$/);
  if (!match) throw new Error("Invalid signature image");
  const binary = atob(match[2]);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return { mime: match[1], bytes };
}

function pdfSafe(v:string){
  return String(v??"")
    .replace(/ı/g,"i").replace(/İ/g,"I")
    .replace(/[–—]/g,"-").replace(/[“”]/g,'"').replace(/[‘’]/g,"'")
    .normalize("NFKD").replace(/[\u0300-\u036f]/g,"")
    .replace(/[^\x20-\x7E\u00A0-\u00FF€]/g,"?");
}

function fit(width: number, height: number, maxW: number, maxH: number) {
  const scale = Math.min(maxW / width, maxH / height, 1);
  return { width: width * scale, height: height * scale };
}

async function loadApproval(admin: ReturnType<typeof createClient>, token: string) {
  const tokenHash = await sha256Hex(token);
  const { data: link, error: linkError } = await admin
    .from("rf_public_approval_links")
    .select("*")
    .eq("token_hash", tokenHash)
    .maybeSingle();

  if (linkError) throw linkError;
  if (!link) throw new Error("Ungültiger Freigabelink");
  if (link.revoked_at) throw new Error("Dieser Freigabelink wurde widerrufen");
  if (link.used_at) throw new Error("Dieser Freigabelink wurde bereits verwendet");
  if (new Date(link.expires_at).getTime() < Date.now()) throw new Error("Dieser Freigabelink ist abgelaufen");

  const { data: version, error: versionError } = await admin
    .from("rf_regie_versions")
    .select("*")
    .eq("id", link.version_id)
    .single();
  if (versionError) throw versionError;

  const { data: regie, error: regieError } = await admin
    .from("rf_regies")
    .select("*")
    .eq("id", version.regie_id)
    .single();
  if (regieError) throw regieError;
  if (regie.status !== "awaiting_customer") throw new Error("Diese Regie wartet nicht mehr auf eine Freigabe");

  const [{ data: project, error: projectError }, { data: company, error: companyError }, { data: contact, error: contactError }] =
    await Promise.all([
      admin.from("rf_projects").select("*").eq("id", regie.project_id).single(),
      admin.from("rf_companies").select("*").eq("id", regie.company_id).single(),
      admin.from("rf_customer_contacts").select("*").eq("id", link.customer_contact_id).single(),
    ]);
  if (projectError) throw projectError;
  if (companyError) throw companyError;
  if (contactError) throw contactError;
  if (!contact.active || contact.company_id !== regie.company_id) throw new Error("Freigabeberechtigung ist nicht mehr aktiv");

  const { data: access, error: accessError } = await admin
    .from("rf_project_customer_access")
    .select("can_sign")
    .eq("project_id", regie.project_id)
    .eq("customer_contact_id", link.customer_contact_id)
    .maybeSingle();
  if (accessError) throw accessError;
  if (!access?.can_sign) throw new Error("Keine Freigabeberechtigung für dieses Projekt");

  const { data: files, error: filesError } = await admin
    .from("rf_regie_files")
    .select("*")
    .eq("regie_id", regie.id)
    .eq("version_id", version.id)
    .eq("kind", "before")
    .order("sort_order", { ascending: true });
  if (filesError) throw filesError;

  let monteurName = "—";
  const monteurId = regie.assigned_monteur_user_id || version.created_by_user_id || regie.created_by_user_id;
  if (monteurId) {
    const { data: member } = await admin
      .from("rf_memberships")
      .select("display_name")
      .eq("company_id", regie.company_id)
      .eq("user_id", monteurId)
      .maybeSingle();
    if (member?.display_name) monteurName = member.display_name;
  }

  return { link, version, regie, project, company, contact, files: files ?? [], monteurName };
}

async function signedUrls(admin: ReturnType<typeof createClient>, ctx: Awaited<ReturnType<typeof loadApproval>>) {
  const photos = [];
  for (const f of ctx.files) {
    const { data } = await admin.storage.from("rf-private").createSignedUrl(f.storage_path, 1800);
    if (data?.signedUrl) photos.push({ id: f.id, url: data.signedUrl, filename: f.original_filename });
  }

  let logoUrl: string | null = null;
  if (ctx.company.logo_path) {
    const { data } = await admin.storage.from("rf-branding").createSignedUrl(ctx.company.logo_path, 1800);
    logoUrl = data?.signedUrl ?? null;
  }
  return { photos, logoUrl };
}

async function buildPdf(
  admin: ReturnType<typeof createClient>,
  ctx: Awaited<ReturnType<typeof loadApproval>>,
  signerName: string,
  signatureBytes: Uint8Array,
  signatureMime: string,
) {
  const pdf = await PDFDocument.create();
  pdf.setTitle(`Regie ${ctx.regie.regie_code}`);
  pdf.setAuthor(ctx.company.legal_name || ctx.company.name);
  pdf.setSubject("Digitale Regiefreigabe");
  pdf.setCreator("RegieFlow");
  pdf.setProducer("RegieFlow");

  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const pageSize: [number, number] = [595.28, 841.89];
  let page = pdf.addPage(pageSize);
  let y = 790;
  const left = 46;
  const width = 503;

  const drawText = (text: string, size = 10, weight = font, gap = 17) => {
    const safe = pdfSafe(String(text ?? "—"));
    page.drawText(safe, { x: left, y, size, font: weight, color: rgb(0.09,0.1,0.12), maxWidth: width });
    y -= gap;
  };

  if (ctx.company.logo_path) {
    try {
      const { data: blob } = await admin.storage.from("rf-branding").download(ctx.company.logo_path);
      if (blob) {
        const bytes = new Uint8Array(await blob.arrayBuffer());
        let logo;
        if ((blob.type || "").includes("png")) logo = await pdf.embedPng(bytes);
        else if ((blob.type || "").includes("jpeg") || (blob.type || "").includes("jpg")) logo = await pdf.embedJpg(bytes);
        if (logo) {
          const d = fit(logo.width, logo.height, 110, 55);
          page.drawImage(logo, { x: 438, y: 754, width: d.width, height: d.height });
        }
      }
    } catch (_) {}
  }

  drawText(ctx.company.name, 18, bold, 24);
  if (ctx.company.legal_name && ctx.company.legal_name !== ctx.company.name) drawText(ctx.company.legal_name, 9, font, 14);
  if (ctx.company.address) drawText(ctx.company.address, 9, font, 16);
  drawText("Digitale Regiefreigabe", 11, font, 24);
  page.drawLine({ start:{x:left,y:y+5}, end:{x:548,y:y+5}, thickness:1, color:rgb(0.85,0.86,0.88) });
  y -= 12;

  drawText(`Regie-ID: ${ctx.regie.regie_code}`, 11, bold);
  drawText(`Dokumentversion: ${ctx.version.version_no}`);
  drawText(`Projekt: ${ctx.project.project_number} · ${ctx.project.name}`);
  if (ctx.project.external_project_reference) drawText(`Externe Projektreferenz: ${ctx.project.external_project_reference}`);
  if (ctx.project.address) drawText(`Adresse: ${ctx.project.address}`);
  drawText(`Monteur: ${ctx.monteurName}`);
  drawText(`Kunde/Freigabe: ${signerName}`);
  y -= 8;

  drawText("Beschreibung", 12, bold, 20);
  const desc = pdfSafe(String(ctx.version.description || ""));
  const words = desc.split(/\s+/);
  let line = "";
  for (const word of words) {
    const test = line ? line + " " + word : word;
    if (font.widthOfTextAtSize(test, 10) > width) {
      drawText(line, 10, font, 14);
      line = word;
    } else line = test;
  }
  if (line) drawText(line, 10, font, 14);
  y -= 8;

  drawText("Geschätzter Aufwand", 12, bold, 20);
  drawText(ctx.version.estimate_label, 10, bold, 16);
  drawText(ctx.version.estimate_disclaimer, 9, font, 20);

  drawText("Freigabe", 12, bold, 20);
  drawText(`Freigegeben am: ${new Date().toLocaleString("de-CH", { timeZone: "Europe/Zurich" })}`);
  drawText("Die oben beschriebene Regiearbeit wurde digital freigegeben.", 10, font, 18);
  drawText("Freigabeerklärung", 9, bold, 15);
  const consentWords = pdfSafe(CONSENT_TEXT).split(/\s+/);
  let consentLine = "";
  for (const word of consentWords) {
    const test = consentLine ? consentLine + " " + word : word;
    if (font.widthOfTextAtSize(test, 8.5) > width) {
      drawText(consentLine, 8.5, font, 12);
      consentLine = word;
    } else consentLine = test;
  }
  if (consentLine) drawText(consentLine, 8.5, font, 14);
  y -= 4;

  const sig = signatureMime === "image/png"
    ? await pdf.embedPng(signatureBytes)
    : await pdf.embedJpg(signatureBytes);
  const sd = fit(sig.width, sig.height, 220, 90);
  page.drawImage(sig, { x:left, y:Math.max(80, y-sd.height), width:sd.width, height:sd.height });
  y -= sd.height + 18;
  drawText(`Unterschrift: ${signerName}`, 9, font, 14);

  page.drawText("Dieses Dokument wurde nach der Freigabe in RegieFlow gesperrt. Integritätsnachweis und Audit-Trail werden separat gespeichert.", {
    x:left, y:42, size:7.5, font, color:rgb(0.35,0.37,0.4), maxWidth:width
  });

  for (let i = 0; i < ctx.files.length; i++) {
    const f = ctx.files[i];
    try {
      const { data: blob } = await admin.storage.from("rf-private").download(f.storage_path);
      if (!blob) continue;
      const bytes = new Uint8Array(await blob.arrayBuffer());
      let img;
      const type = blob.type || f.mime_type || "";
      if (type.includes("png")) img = await pdf.embedPng(bytes);
      else if (type.includes("jpeg") || type.includes("jpg")) img = await pdf.embedJpg(bytes);
      else continue;

      page = pdf.addPage(pageSize);
      page.drawText(`Vorher-Bild ${i+1} · ${ctx.regie.regie_code} · Version ${ctx.version.version_no}`, {
        x:left, y:790, size:11, font:bold, color:rgb(0.09,0.1,0.12)
      });
      const d = fit(img.width, img.height, 503, 690);
      page.drawImage(img, { x:left + (503-d.width)/2, y:70 + (690-d.height)/2, width:d.width, height:d.height });
    } catch (_) {}
  }

  return new Uint8Array(await pdf.save({ useObjectStreams: false }));
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const url = new URL(req.url);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return json({ error: "Server configuration missing" }, 500);
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  try {
    let token = url.searchParams.get("token") || "";
    let body: any = {};
    if (req.method === "POST") {
      body = await req.json();
      token = body.token || token;
    }
    if (!token || token.length < 32) return json({ error: "Ungültiger Freigabelink" }, 400);

    const ip=(req.headers.get("cf-connecting-ip")||req.headers.get("x-forwarded-for")||req.headers.get("x-real-ip")||"unknown").split(",")[0].trim();
    const ipHash=await sha256Hex("public-approval-ip:"+ip);
    const tokenRateHash=await sha256Hex("public-approval-token:"+token);
    const [{data:ipAllowed,error:ipRateError},{data:tokenAllowed,error:tokenRateError}]=await Promise.all([
      admin.rpc("rf_take_rate_limit",{p_scope:"public_approval_ip",p_key_hash:ipHash,p_limit:180,p_window_seconds:3600}),
      admin.rpc("rf_take_rate_limit",{p_scope:"public_approval_token",p_key_hash:tokenRateHash,p_limit:90,p_window_seconds:3600})
    ]);
    if(ipRateError)throw ipRateError;if(tokenRateError)throw tokenRateError;
    if(!ipAllowed||!tokenAllowed)return json({error:"Zu viele Zugriffe. Bitte später erneut versuchen.",code:"RATE_LIMITED"},429);

    const ctx = await loadApproval(admin, token);

    if (req.method === "GET" || body.action === "view") {
      if (!ctx.link.first_viewed_at) {
        const ipRaw = req.headers.get("cf-connecting-ip") || req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for") || req.headers.get("x-real-ip") || req.headers.get("x-real-ip");
        const {data:viewed}=await admin.from("rf_public_approval_links").update({
          first_viewed_at: new Date().toISOString(),
          first_view_ip: ipRaw ? ipRaw.split(",")[0].trim() : null,
          first_view_user_agent: req.headers.get("user-agent")
        }).eq("id", ctx.link.id).is("first_viewed_at", null).select("id").maybeSingle();
        if(viewed){
          await admin.from("rf_audit_log").insert({
            company_id:ctx.regie.company_id,
            project_id:ctx.regie.project_id,
            regie_id:ctx.regie.id,
            actor_customer_contact_id:ctx.contact.id,
            event_type:"public_approval_link_viewed",
            metadata:{version_id:ctx.version.id,version_no:ctx.version.version_no,auth_method:"secure_link"}
          });
        }
      }
      const media = await signedUrls(admin, ctx);
      return json({
        regie: {
          id: ctx.regie.id,
          code: ctx.regie.regie_code,
          description: ctx.version.description,
          estimate: ctx.version.estimate_label,
          estimateDisclaimer: ctx.version.estimate_disclaimer,
          version: ctx.version.version_no,
          projectNumber: ctx.project.project_number,
          projectName: ctx.project.name,
          projectAddress: ctx.project.address,
          companyName: ctx.company.name,
          accentColor: ctx.company.accent_color || "#111827",
          monteurName: ctx.monteurName,
          authorizedSigner: ctx.contact.full_name,
          expiresAt: ctx.link.expires_at,
          consentText: CONSENT_TEXT,
        },
        ...media,
      });
    }

    const decision = body.action;
    if (!["approve","reject"].includes(decision)) return json({ error: "Ungültige Aktion" }, 400);
    const signerName = String(ctx.contact.full_name || "").trim();
    if (!signerName) return json({ error: "Name ist erforderlich" }, 400);
    if (decision === "approve" && body.consentAccepted !== true) {
      return json({ error: "Bitte bestätigen Sie die Freigabeerklärung." }, 400);
    }

    if (decision === "reject") {
      const { error } = await admin.rpc("rf_finalize_customer_decision_v2", {
        p_version_id: ctx.version.id,
        p_customer_contact_id: ctx.contact.id,
        p_signer_user_id: null,
        p_signer_name: signerName,
        p_decision: "rejected",
        p_signature_storage_path: null,
        p_signature_sha256: null,
        p_document_storage_path: null,
        p_document_file_name: null,
        p_document_sha256: null,
        p_document_byte_size: null,
        p_auth_method: "secure_link",
        p_ip_address: req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for") || req.headers.get("x-real-ip"),
        p_user_agent: req.headers.get("user-agent"),
        p_consent_text: null,
        p_consent_version: null,
      });
      if (error) throw error;
      return json({ status: "rejected" });
    }

    if (typeof body.signatureDataUrl !== "string" || body.signatureDataUrl.length > 3_000_000) {
      return json({ error: "Unterschrift fehlt oder ist zu gross" }, 400);
    }
    const signature = dataUrlToBytes(body.signatureDataUrl);
    const signatureHash = await sha256Hex(signature.bytes);
    const signatureExt = signature.mime === "image/png" ? "png" : "jpg";
    const signaturePath = `${ctx.company.id}/${ctx.regie.id}/signatures/${ctx.version.id}-${crypto.randomUUID()}.${signatureExt}`;

    const { error: sigUploadError } = await admin.storage
      .from("rf-private")
      .upload(signaturePath, signature.bytes, { contentType: signature.mime, upsert: false });
    if (sigUploadError) throw sigUploadError;

    let documentPath: string | null = null;
    try {
      const pdfBytes = await buildPdf(admin, ctx, signerName, signature.bytes, signature.mime);
      const pdfHash = await sha256Hex(pdfBytes);
      const safeCode = String(ctx.regie.regie_code || "regie").replace(/[^A-Za-z0-9_-]/g, "_");
      const fileName = `${safeCode}-v${ctx.version.version_no}-freigegeben.pdf`;
      documentPath = `${ctx.company.id}/${ctx.regie.id}/documents/${ctx.version.id}-${crypto.randomUUID()}.pdf`;

      const { error: pdfUploadError } = await admin.storage
        .from("rf-private")
        .upload(documentPath, pdfBytes, { contentType: "application/pdf", upsert: false });
      if (pdfUploadError) throw pdfUploadError;

      const { error: finalizeError } = await admin.rpc("rf_finalize_customer_decision_v2", {
        p_version_id: ctx.version.id,
        p_customer_contact_id: ctx.contact.id,
        p_signer_user_id: null,
        p_signer_name: signerName,
        p_decision: "approved",
        p_signature_storage_path: signaturePath,
        p_signature_sha256: signatureHash,
        p_document_storage_path: documentPath,
        p_document_file_name: fileName,
        p_document_sha256: pdfHash,
        p_document_byte_size: pdfBytes.length,
        p_auth_method: "secure_link",
        p_ip_address: req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for") || req.headers.get("x-real-ip"),
        p_user_agent: req.headers.get("user-agent"),
        p_consent_text: CONSENT_TEXT,
        p_consent_version: CONSENT_VERSION,
      });
      if (finalizeError) throw finalizeError;

      const { data: signed } = await admin.storage.from("rf-private").createSignedUrl(documentPath, 3600);
      return json({ status: "approved", documentSha256: pdfHash, pdfUrl: signed?.signedUrl ?? null });
    } catch (e) {
      await admin.storage.from("rf-private").remove([signaturePath, ...(documentPath ? [documentPath] : [])]);
      throw e;
    }
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return json({ error: message }, 400);
  }
});