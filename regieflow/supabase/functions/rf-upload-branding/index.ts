import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"POST,OPTIONS"
};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});

function matchesMagic(bytes:Uint8Array,mime:string){
  if(mime==="image/jpeg")return bytes.length>=3&&bytes[0]===0xff&&bytes[1]===0xd8&&bytes[2]===0xff;
  if(mime==="image/png")return bytes.length>=8&&bytes[0]===0x89&&bytes[1]===0x50&&bytes[2]===0x4e&&bytes[3]===0x47&&bytes[4]===0x0d&&bytes[5]===0x0a&&bytes[6]===0x1a&&bytes[7]===0x0a;
  return false;
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);

  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const auth=req.headers.get("Authorization");
  if(!url||!anon||!service)return json({error:"Server configuration missing"},500);
  if(!auth)return json({error:"Nicht angemeldet"},401);

  const caller=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
  const {data:{user},error:ue}=await caller.auth.getUser();
  if(ue||!user)return json({error:"Nicht angemeldet"},401);

  const admin=createClient(url,service,{auth:{persistSession:false}});
  let uploaded:string|null=null;

  try{
    const form=await req.formData();
    const companyId=String(form.get("companyId")||"").trim();
    const file=form.get("file");
    if(!companyId)return json({error:"Firma fehlt"},400);
    if(!(file instanceof File))return json({error:"Logo-Datei fehlt"},400);
    if(file.size<1||file.size>5*1024*1024)return json({error:"Logo darf maximal 5 MB gross sein"},400);
    if(!["image/jpeg","image/png"].includes(file.type))return json({error:"Logo muss PNG oder JPEG sein"},400);

    const {data:allowed,error:pe}=await caller.rpc("rf_has_permission",{p_company:companyId,p_permission:"company.manage"});
    if(pe)throw pe;
    if(!allowed)return json({error:"Keine Berechtigung zur Firmenverwaltung"},403);

    const {data:company,error:ce}=await admin.from("rf_companies").select("id,logo_path").eq("id",companyId).maybeSingle();
    if(ce)throw ce;
    if(!company)return json({error:"Firma nicht gefunden"},404);

    const bytes=new Uint8Array(await file.arrayBuffer());
    if(!matchesMagic(bytes,file.type))return json({error:"Dateiinhalt stimmt nicht mit dem Bildformat überein"},400);

    const ext=file.type==="image/png"?"png":"jpg";
    const path=`${companyId}/${crypto.randomUUID()}.${ext}`;
    const {error:up}=await admin.storage.from("rf-branding").upload(path,bytes,{contentType:file.type,upsert:false});
    if(up)throw up;
    uploaded=path;

    const {error:cu}=await admin.from("rf_companies").update({logo_path:path}).eq("id",companyId);
    if(cu)throw cu;

    const old=company.logo_path as string|null;
    if(old&&old!==path&&old.startsWith(companyId+"/")){
      await admin.storage.from("rf-branding").remove([old]);
    }

    await admin.from("rf_audit_log").insert({
      company_id:companyId,
      actor_user_id:user.id,
      event_type:"company_logo_updated",
      metadata:{old_logo_path:old,new_logo_path:path,mime_type:file.type,byte_size:bytes.length}
    });

    return json({status:"stored",logoPath:path},201);
  }catch(e){
    if(uploaded)await admin.storage.from("rf-branding").remove([uploaded]);
    return json({error:e instanceof Error?e.message:String(e)},400);
  }
});