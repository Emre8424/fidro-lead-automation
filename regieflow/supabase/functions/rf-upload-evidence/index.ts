import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"POST,OPTIONS"
};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const sha=async(b:Uint8Array)=>[...new Uint8Array(await crypto.subtle.digest("SHA-256",b))].map(x=>x.toString(16).padStart(2,"0")).join("");
function matchesMagic(bytes:Uint8Array,mime:string){
  if(mime==="image/jpeg")return bytes.length>=3&&bytes[0]===0xff&&bytes[1]===0xd8&&bytes[2]===0xff;
  if(mime==="image/png")return bytes.length>=8&&bytes[0]===0x89&&bytes[1]===0x50&&bytes[2]===0x4e&&bytes[3]===0x47&&bytes[4]===0x0d&&bytes[5]===0x0a&&bytes[6]===0x1a&&bytes[7]===0x0a;
  if(mime==="application/pdf")return bytes.length>=5&&bytes[0]===0x25&&bytes[1]===0x50&&bytes[2]===0x44&&bytes[3]===0x46&&bytes[4]===0x2d;
  return false;
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);

  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const auth=req.headers.get("Authorization");
  if(!url||!anon||!service||!auth)return json({error:"Server configuration missing"},500);

  const caller=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
  const {data:{user},error:ue}=await caller.auth.getUser();
  if(ue||!user)return json({error:"Nicht angemeldet"},401);

  const admin=createClient(url,service,{auth:{persistSession:false}});
  let uploadedPath:string|null=null;

  try{
    const form=await req.formData();
    const regieId=String(form.get("regieId")||"");
    const versionIdRaw=String(form.get("versionId")||"").trim();
    let versionId=versionIdRaw||null;
    const kind=String(form.get("kind")||"");
    const originalFilename=String(form.get("originalFilename")||"upload");
    const file=form.get("file");

    if(!regieId||!["before","after","attachment","customer_request"].includes(kind))return json({error:"Ungültige Datei-Anfrage"},400);
    if(!(file instanceof File))return json({error:"Datei fehlt"},400);
    if(file.size<1||file.size>20*1024*1024)return json({error:"Datei muss zwischen 1 Byte und 20 MB gross sein"},400);

    const allowed=kind==="attachment"
      ?["image/jpeg","image/png","application/pdf"]
      :["image/jpeg","image/png"];
    if(!allowed.includes(file.type))return json({error:"Dateityp nicht erlaubt"},400);

    const {data:regie,error:re}=await admin.from("rf_regies").select("*").eq("id",regieId).single();
    if(re)throw re;

    let uploaderCustomer:string|null=null;
    let internal=false;

    const {data:isInternal}=await caller.rpc("rf_is_internal_member",{p_company:regie.company_id});
    internal=!!isInternal;

    if(kind==="before"||kind==="attachment"){
      const {data:can}=await caller.rpc("rf_has_permission",{p_company:regie.company_id,p_permission:"regies.create"});
      if(!can||regie.status!=="draft")return json({error:"Datei kann in diesem Status nicht hinzugefügt werden"},403);
      if(!versionId)return json({error:"Version fehlt"},400);
      const {data:v,error:ve}=await admin.from("rf_regie_versions").select("id,regie_id,version_no,locked_at").eq("id",versionId).single();
      if(ve)throw ve;
      if(v.regie_id!==regieId||v.locked_at||v.version_no!==regie.current_version_no)return json({error:"Version ist gesperrt, nicht aktuell oder gehört nicht zur Regie"},403);
    }else if(kind==="after"){
      const {data:canComplete}=await caller.rpc("rf_has_permission",{p_company:regie.company_id,p_permission:"regies.complete"});
      if(!canComplete||!["approved","in_execution","awaiting_rapport"].includes(regie.status))return json({error:"Nachher-Bild kann in diesem Status nicht hinzugefügt werden"},403);
      if(!versionId){
        const {data:v,error:ve}=await admin.from("rf_regie_versions").select("id").eq("regie_id",regieId).eq("version_no",regie.current_version_no).single();
        if(ve)throw ve;
        versionId=v.id;
      }else{
        const {data:v,error:ve}=await admin.from("rf_regie_versions").select("id,regie_id,version_no").eq("id",versionId).single();
        if(ve)throw ve;
        if(v.regie_id!==regieId||v.version_no!==regie.current_version_no)return json({error:"Version gehört nicht zur aktuellen Regie-Version"},400);
      }
    }else{
      const {data:contact,error:ce}=await admin.from("rf_customer_contacts").select("id").eq("company_id",regie.company_id).eq("auth_user_id",user.id).eq("active",true).maybeSingle();
      if(ce)throw ce;
      if(!contact||regie.source!=="customer"||regie.status!=="customer_request"||regie.requested_by_customer_contact_id!==contact.id)return json({error:"Keine Berechtigung für dieses Kundenbild"},403);
      const {data:access,error:ae}=await admin.from("rf_project_customer_access").select("id").eq("project_id",regie.project_id).eq("customer_contact_id",contact.id).maybeSingle();
      if(ae)throw ae;
      if(!access)return json({error:"Projekt nicht freigegeben"},403);
      uploaderCustomer=contact.id;
    }

    const ext=file.type==="image/jpeg"?"jpg":file.type==="image/png"?"png":"pdf";
    const folder=kind==="customer_request"?"customer-request":kind==="attachment"?"attachments":kind;
    const path=`${regie.company_id}/${regie.id}/${folder}/${crypto.randomUUID()}.${ext}`;
    const bytes=new Uint8Array(await file.arrayBuffer());
    if(!matchesMagic(bytes,file.type))return json({error:"Dateiinhalt stimmt nicht mit dem Dateityp überein"},400);
    const digest=await sha(bytes);

    const {error:upErr}=await admin.storage.from("rf-private").upload(path,bytes,{contentType:file.type,upsert:false});
    if(upErr)throw upErr;
    uploadedPath=path;

    const {data:row,error:ie}=await admin.from("rf_regie_files").insert({
      regie_id:regie.id,
      version_id:versionId,
      kind,
      storage_path:path,
      original_filename:originalFilename.slice(0,255),
      mime_type:file.type,
      byte_size:bytes.length,
      sha256:digest,
      uploaded_by_user_id:internal?user.id:null,
      uploaded_by_customer_contact_id:uploaderCustomer
    }).select("id,storage_path,sha256,byte_size,mime_type").single();
    if(ie)throw ie;

    await admin.from("rf_audit_log").insert({
      company_id:regie.company_id,
      project_id:regie.project_id,
      regie_id:regie.id,
      actor_user_id:internal?user.id:null,
      actor_customer_contact_id:uploaderCustomer,
      event_type:"regie_evidence_uploaded",
      metadata:{
        file_id:row.id,
        version_id:versionId,
        kind,
        sha256:row.sha256,
        byte_size:row.byte_size,
        mime_type:row.mime_type
      }
    });

    return json({status:"stored",file:row},201);
  }catch(e){
    if(uploadedPath)await admin.storage.from("rf-private").remove([uploadedPath]);
    return json({error:e instanceof Error?e.message:String(e)},400);
  }
});