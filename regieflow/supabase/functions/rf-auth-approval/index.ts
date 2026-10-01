import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb } from "npm:pdf-lib@1.17.1";

const CONSENT_TEXT = "Ich bestätige, dass ich für dieses Projekt zur Freigabe berechtigt bin und die dargestellte Regie in dieser Version freigebe.";
const CONSENT_VERSION = "v1";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"POST,OPTIONS"
};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const fit=(w:number,h:number,mw:number,mh:number)=>{const s=Math.min(mw/w,mh/h,1);return{width:w*s,height:h*s}};
function pdfSafe(v:string){
  let s=String(v??"").replaceAll("ı","i").replaceAll("İ","I").replaceAll("–","-").replaceAll("—","-");
  s=s.normalize("NFKD");
  let out="";
  for(const ch of s){
    const cp=ch.codePointAt(0)||0;
    if(cp>=768&&cp<=879)continue;
    if((cp>=32&&cp<=126)||(cp>=160&&cp<=255))out+=ch;
    else out+="?";
  }
  return out;
}
async function hash(bytes:Uint8Array){const h=await crypto.subtle.digest("SHA-256",bytes);return[...new Uint8Array(h)].map(b=>b.toString(16).padStart(2,"0")).join("")}
function sigBytes(v:string){const m=v.match(/^data:(image\/(?:png|jpeg));base64,(.+)$/);if(!m)throw new Error("Ungültige Unterschrift");const b=atob(m[2]);const u=new Uint8Array(b.length);for(let i=0;i<b.length;i++)u[i]=b.charCodeAt(i);return{mime:m[1],bytes:u}}

async function load(admin:any,versionId:string,userId:string){
  const {data:version,error:e1}=await admin.from("rf_regie_versions").select("*").eq("id",versionId).single();if(e1)throw e1;
  const {data:regie,error:e2}=await admin.from("rf_regies").select("*").eq("id",version.regie_id).single();if(e2)throw e2;
  if(regie.status!=="awaiting_customer")throw new Error("Diese Regie wartet nicht mehr auf eine Freigabe");
  const [{data:project,error:e3},{data:company,error:e4},{data:contact,error:e5}]=await Promise.all([
    admin.from("rf_projects").select("*").eq("id",regie.project_id).single(),
    admin.from("rf_companies").select("*").eq("id",regie.company_id).single(),
    admin.from("rf_customer_contacts").select("*").eq("company_id",regie.company_id).eq("auth_user_id",userId).eq("active",true).maybeSingle()
  ]);
  if(e3)throw e3;if(e4)throw e4;if(e5)throw e5;if(!contact)throw new Error("Kein RegieFlow-Kundenkonto für diese Firma");
  const {data:access,error:e6}=await admin.from("rf_project_customer_access").select("can_sign").eq("project_id",regie.project_id).eq("customer_contact_id",contact.id).maybeSingle();if(e6)throw e6;
  if(!access?.can_sign)throw new Error("Sie sind für dieses Projekt nicht freigabeberechtigt");
  const {data:files,error:e7}=await admin.from("rf_regie_files").select("*").eq("regie_id",regie.id).eq("version_id",version.id).eq("kind","before").order("sort_order",{ascending:true});if(e7)throw e7;
  let monteurName="—";const mid=regie.assigned_monteur_user_id||version.created_by_user_id||regie.created_by_user_id;
  if(mid){const {data:m}=await admin.from("rf_memberships").select("display_name").eq("company_id",regie.company_id).eq("user_id",mid).maybeSingle();if(m?.display_name)monteurName=m.display_name}
  return{version,regie,project,company,contact,files:files??[],monteurName};
}

async function makePdf(admin:any,c:any,signer:string,sig:Uint8Array,mime:string){
  const pdf=await PDFDocument.create();pdf.setTitle("Regie "+c.regie.regie_code);pdf.setAuthor(c.company.name);pdf.setCreator("RegieFlow");pdf.setProducer("RegieFlow");
  const f=await pdf.embedFont(StandardFonts.Helvetica),b=await pdf.embedFont(StandardFonts.HelveticaBold);
  const sz:[number,number]=[595.28,841.89],L=46,W=503;let p=pdf.addPage(sz),y=790;
  const t=(x:string,s=10,ff=f,g=17)=>{p.drawText(pdfSafe(String(x??"—")),{x:L,y,size:s,font:ff,color:rgb(.09,.1,.12),maxWidth:W});y-=g};
  if(c.company.logo_path){try{const {data:bl}=await admin.storage.from("rf-branding").download(c.company.logo_path);if(bl){const u=new Uint8Array(await bl.arrayBuffer());let im:any;if((bl.type||"").includes("png"))im=await pdf.embedPng(u);else if((bl.type||"").match(/jpe?g/))im=await pdf.embedJpg(u);if(im){const d=fit(im.width,im.height,110,55);p.drawImage(im,{x:438,y:754,width:d.width,height:d.height})}}}catch{}}
  t(c.company.name,18,b,28);t("Digitale Regiefreigabe",11,f,28);p.drawLine({start:{x:L,y:y+5},end:{x:548,y:y+5},thickness:1,color:rgb(.85,.86,.88)});y-=12;
  t("Regie-ID: "+c.regie.regie_code,11,b);t("Dokumentversion: "+c.version.version_no);t("Projekt: "+c.project.project_number+" · "+c.project.name);
  if(c.project.external_project_reference)t("Externe Projektreferenz: "+c.project.external_project_reference);if(c.project.address)t("Adresse: "+c.project.address);t("Monteur: "+c.monteurName);t("Kunde/Freigabe: "+signer);y-=8;
  t("Beschreibung",12,b,20);
  let line="";for(const w of pdfSafe(String(c.version.description||"")).split(/\s+/)){const q=line?line+" "+w:w;if(f.widthOfTextAtSize(q,10)>W){t(line,10,f,14);line=w}else line=q}if(line)t(line,10,f,14);y-=8;
  t("Geschätzter Aufwand",12,b,20);t(c.version.estimate_label,10,b,16);t(c.version.estimate_disclaimer,9,f,20);t("Freigabe",12,b,20);
  t("Freigegeben am: "+new Date().toLocaleString("de-CH",{timeZone:"Europe/Zurich"}));t("Die oben beschriebene Regiearbeit wurde digital freigegeben.",10,f,18);
  const si=mime==="image/png"?await pdf.embedPng(sig):await pdf.embedJpg(sig),d=fit(si.width,si.height,220,90);p.drawImage(si,{x:L,y:Math.max(80,y-d.height),width:d.width,height:d.height});y-=d.height+18;t("Unterschrift: "+signer,9,f,14);
  p.drawText("Nach der Freigabe in RegieFlow gesperrt. Integritätsnachweis und Audit-Trail werden separat gespeichert.",{x:L,y:42,size:7.5,font:f,color:rgb(.35,.37,.4),maxWidth:W});
  for(let i=0;i<c.files.length;i++){const x=c.files[i];try{const {data:bl}=await admin.storage.from("rf-private").download(x.storage_path);if(!bl)continue;const u=new Uint8Array(await bl.arrayBuffer());let im:any;const ty=bl.type||x.mime_type||"";if(ty.includes("png"))im=await pdf.embedPng(u);else if(ty.match(/jpe?g/))im=await pdf.embedJpg(u);else continue;p=pdf.addPage(sz);p.drawText(`Vorher-Bild ${i+1} · ${c.regie.regie_code} · Version ${c.version.version_no}`,{x:L,y:790,size:11,font:b,color:rgb(.09,.1,.12)});const dd=fit(im.width,im.height,503,690);p.drawImage(im,{x:L+(503-dd.width)/2,y:70+(690-dd.height)/2,width:dd.width,height:dd.height})}catch{}}
  return new Uint8Array(await pdf.save({useObjectStreams:false}));
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),auth=req.headers.get("Authorization");
  if(!url||!anon||!service||!auth)return json({error:"Server configuration missing"},500);
  const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
  const {data:{user},error:ue}=await userClient.auth.getUser();if(ue||!user)return json({error:"Nicht angemeldet"},401);
  const admin=createClient(url,service,{auth:{persistSession:false}});
  try{
    const body=await req.json(),versionId=String(body.versionId||""),action=String(body.action||"");
    if(!versionId||!["approve","reject"].includes(action))return json({error:"Ungültige Anfrage"},400);
    const c=await load(admin,versionId,user.id),signer=String(body.signerName||c.contact.full_name||"").trim();if(!signer)return json({error:"Name ist erforderlich"},400);
    if(action==="approve"&&body.consentAccepted!==true)return json({error:"Bitte bestätigen Sie die Freigabeerklärung."},400);
    if(action==="reject"){
      const {error}=await admin.rpc("rf_finalize_customer_decision_v2",{p_version_id:c.version.id,p_customer_contact_id:c.contact.id,p_signer_user_id:user.id,p_signer_name:signer,p_decision:"rejected",p_signature_storage_path:null,p_signature_sha256:null,p_document_storage_path:null,p_document_file_name:null,p_document_sha256:null,p_document_byte_size:null,p_auth_method:"account",p_ip_address:req.headers.get("x-forwarded-for"),p_user_agent:req.headers.get("user-agent"),p_consent_text:null,p_consent_version:null});if(error)throw error;return json({status:"rejected"});
    }
    if(typeof body.signatureDataUrl!=="string"||body.signatureDataUrl.length>3000000)return json({error:"Unterschrift fehlt oder ist zu gross"},400);
    const s=sigBytes(body.signatureDataUrl),sh=await hash(s.bytes),ext=s.mime==="image/png"?"png":"jpg",sp=`${c.company.id}/${c.regie.id}/signatures/${c.version.id}-${crypto.randomUUID()}.${ext}`;
    const {error:se}=await admin.storage.from("rf-private").upload(sp,s.bytes,{contentType:s.mime,upsert:false});if(se)throw se;
    let dp:string|null=null;
    try{
      const pb=await makePdf(admin,c,signer,s.bytes,s.mime),ph=await hash(pb),fn=String(c.regie.regie_code||"regie").replace(/[^A-Za-z0-9_-]/g,"_")+`-v${c.version.version_no}-freigegeben.pdf`;
      dp=`${c.company.id}/${c.regie.id}/documents/${c.version.id}-${crypto.randomUUID()}.pdf`;const {error:pe}=await admin.storage.from("rf-private").upload(dp,pb,{contentType:"application/pdf",upsert:false});if(pe)throw pe;
      const {error:fe}=await admin.rpc("rf_finalize_customer_decision_v2",{p_version_id:c.version.id,p_customer_contact_id:c.contact.id,p_signer_user_id:user.id,p_signer_name:signer,p_decision:"approved",p_signature_storage_path:sp,p_signature_sha256:sh,p_document_storage_path:dp,p_document_file_name:fn,p_document_sha256:ph,p_document_byte_size:pb.length,p_auth_method:"account",p_ip_address:req.headers.get("x-forwarded-for"),p_user_agent:req.headers.get("user-agent"),p_consent_text:CONSENT_TEXT,p_consent_version:CONSENT_VERSION});if(fe)throw fe;
      const {data:su}=await admin.storage.from("rf-private").createSignedUrl(dp,3600);return json({status:"approved",documentSha256:ph,pdfUrl:su?.signedUrl??null});
    }catch(e){await admin.storage.from("rf-private").remove([sp,...(dp?[dp]:[])]);throw e}
  }catch(e){return json({error:e instanceof Error?e.message:String(e)},400)}
});