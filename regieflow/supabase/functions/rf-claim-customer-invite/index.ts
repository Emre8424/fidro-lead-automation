import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"POST,OPTIONS"
};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
async function sha256Hex(input:string){
  const bytes=new TextEncoder().encode(input);
  const h=await crypto.subtle.digest("SHA-256",bytes);
  return[...new Uint8Array(h)].map(b=>b.toString(16).padStart(2,"0")).join("");
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);

  const url=Deno.env.get("SUPABASE_URL");
  const anon=Deno.env.get("SUPABASE_ANON_KEY");
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const auth=req.headers.get("Authorization");
  if(!url||!anon||!service||!auth)return json({error:"Server configuration missing"},500);

  const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
  const {data:{user},error:userError}=await userClient.auth.getUser();
  if(userError||!user)return json({error:"Nicht angemeldet"},401);

  try{
    const body=await req.json();
    const token=String(body.token||"");
    if(token.length<32)return json({error:"Ungültiger Einladungslink"},400);

    const admin=createClient(url,service,{auth:{persistSession:false}});
    const tokenHash=await sha256Hex(token);

    const {data:invite,error:inviteError}=await admin.from("rf_customer_invites")
      .select("*").eq("token_hash",tokenHash).maybeSingle();
    if(inviteError)throw inviteError;
    if(!invite)return json({error:"Einladung nicht gefunden"},404);
    if(invite.revoked_at)return json({error:"Einladung wurde widerrufen"},400);
    if(invite.used_at)return json({error:"Einladung wurde bereits verwendet"},400);
    if(new Date(invite.expires_at).getTime()<Date.now())return json({error:"Einladung ist abgelaufen"},400);

    const {data:contact,error:contactError}=await admin.from("rf_customer_contacts")
      .select("*").eq("id",invite.customer_contact_id).single();
    if(contactError)throw contactError;

    if(contact.auth_user_id && contact.auth_user_id!==user.id){
      return json({error:"Dieser Kundenkontakt ist bereits mit einem anderen Konto verknüpft"},409);
    }
    if(contact.email && user.email && String(contact.email).trim().toLowerCase()!==String(user.email).trim().toLowerCase()){
      return json({error:"Dieses Konto verwendet nicht die E-Mail-Adresse der Einladung."},403);
    }

    const updates:any={auth_user_id:user.id};
    if(!contact.email && user.email)updates.email=user.email;

    const {error:updateError}=await admin.from("rf_customer_contacts")
      .update(updates).eq("id",contact.id);
    if(updateError)throw updateError;

    const {error:inviteUpdateError}=await admin.from("rf_customer_invites")
      .update({used_at:new Date().toISOString()}).eq("id",invite.id);
    if(inviteUpdateError)throw inviteUpdateError;

    await admin.from("rf_audit_log").insert({
      company_id:invite.company_id,
      actor_customer_contact_id:contact.id,
      event_type:"customer_account_linked",
      metadata:{auth_user_id:user.id}
    });

    return json({
      status:"linked",
      companyId:invite.company_id,
      customerContactId:contact.id
    });
  }catch(e){
    return json({error:e instanceof Error?e.message:String(e)},400);
  }
});