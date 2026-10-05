import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"POST,OPTIONS"
};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
async function sha256Hex(v:string){
  const h=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(v));
  return[...new Uint8Array(h)].map(b=>b.toString(16).padStart(2,"0")).join("");
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!anon||!service)return json({error:"Server configuration missing"},500);
  try{
    const body=await req.json();
    const token=String(body.token||"");
    const email=String(body.email||"").trim().toLowerCase();
    const password=String(body.password||"");
    if(token.length<32||!email.includes("@")||password.length<10)return json({error:"Einladung, E-Mail oder Passwort ungültig"},400);

    const admin=createClient(url,service,{auth:{persistSession:false}});
    const tokenHash=await sha256Hex(token);
    const ip=(req.headers.get("cf-connecting-ip")||req.headers.get("x-forwarded-for")||"unknown").split(",")[0].trim();
    const ipHash=await sha256Hex("customer-signup-ip:"+ip);
    const [{data:ipAllowed,error:ipRateError},{data:tokenAllowed,error:tokenRateError}]=await Promise.all([
      admin.rpc("rf_take_rate_limit",{p_scope:"customer_signup_ip",p_key_hash:ipHash,p_limit:30,p_window_seconds:3600}),
      admin.rpc("rf_take_rate_limit",{p_scope:"customer_signup_token",p_key_hash:tokenHash,p_limit:12,p_window_seconds:3600})
    ]);
    if(ipRateError)throw ipRateError;if(tokenRateError)throw tokenRateError;
    if(!ipAllowed||!tokenAllowed)return json({error:"Zu viele Versuche. Bitte später erneut versuchen.",code:"RATE_LIMITED"},429);

    const {data:invite,error:ie}=await admin.from("rf_customer_invites").select("*").eq("token_hash",tokenHash).maybeSingle();
    if(ie)throw ie;
    if(!invite)return json({error:"Einladung nicht gefunden"},404);
    if(invite.revoked_at||invite.used_at||new Date(invite.expires_at).getTime()<Date.now())return json({error:"Einladung ist nicht mehr gültig"},400);

    const {data:contact,error:ce}=await admin.from("rf_customer_contacts").select("*").eq("id",invite.customer_contact_id).single();
    if(ce)throw ce;
    if(contact.auth_user_id)return json({error:"Für diesen Kundenkontakt existiert bereits ein Konto"},409);
    if(contact.email && String(contact.email).trim().toLowerCase()!==email){
      return json({error:"Bitte verwenden Sie die E-Mail-Adresse, an die diese Einladung gerichtet ist."},403);
    }

    const {data:existing,error:le}=await admin.rpc("rf_find_auth_user_by_email",{p_email:email});
    if(le)throw le;
    if(existing)return json({error:"Diese E-Mail hat bereits ein Konto. Bitte anmelden und die Einladung dort verknüpfen.",code:"LOGIN_AND_CLAIM"},409);

    const publicClient=createClient(url,anon,{auth:{persistSession:false}});
    const redirectTo="https://regieflow.pages.dev/?invite="+encodeURIComponent(token);
    const {data:created,error:createError}=await publicClient.auth.signUp({
      email,
      password,
      options:{
        data:{regieflow_customer:true},
        emailRedirectTo:redirectTo
      }
    });
    if(createError)throw createError;
    if(!created.user)throw new Error("Konto konnte nicht erstellt werden");

    // With production email confirmation enabled, the invite remains unused until
    // the user returns with a verified session and rf-claim-customer-invite links it.
    if(!created.user.email_confirmed_at||!created.session){
      return json({
        status:"verification_required",
        verificationRequired:true,
        email
      },202);
    }

    // Development configurations may confirm immediately. Preserve the same
    // identity checks and complete the invite atomically in that case.
    try{
      const {error:ue}=await admin.from("rf_customer_contacts").update({
        auth_user_id:created.user.id,
        email:contact.email||email
      }).eq("id",contact.id);
      if(ue)throw ue;

      const {error:ie2}=await admin.from("rf_customer_invites").update({used_at:new Date().toISOString()}).eq("id",invite.id);
      if(ie2)throw ie2;

      await admin.from("rf_audit_log").insert({
        company_id:invite.company_id,
        actor_customer_contact_id:contact.id,
        event_type:"customer_account_created",
        metadata:{auth_user_id:created.user.id,email_verified:true}
      });
    }catch(e){
      await admin.auth.admin.deleteUser(created.user.id);
      throw e;
    }

    return json({status:"created",email},201);
  }catch(e){
    return json({error:e instanceof Error?e.message:String(e)},400);
  }
});