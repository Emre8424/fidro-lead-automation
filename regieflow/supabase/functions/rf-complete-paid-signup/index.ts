import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"POST,OPTIONS"
};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
async function sha256Hex(v:string){
  const h=new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(v)));
  return [...h].map(b=>b.toString(16).padStart(2,"0")).join("");
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);

  const url=Deno.env.get("SUPABASE_URL");
  const anon=Deno.env.get("SUPABASE_ANON_KEY");
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!anon||!service)return json({error:"Server configuration missing"},500);

  const admin=createClient(url,service,{auth:{persistSession:false}});
  const publicClient=createClient(url,anon,{auth:{persistSession:false}});
  let currentUser:any=null;
  const auth=req.headers.get("Authorization");
  if(auth){
    const caller=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
    const {data}=await caller.auth.getUser();
    currentUser=data?.user||null;
  }

  try{
    const body=await req.json();
    const intentId=String(body.intentId||"").trim();
    const completionToken=String(body.completionToken||"").trim();
    const password=String(body.password||"");
    if(!intentId||completionToken.length<32)return json({error:"Registrierungsfreigabe ungültig."},400);

    const ip=(req.headers.get("cf-connecting-ip")||req.headers.get("x-forwarded-for")||"unknown").split(",")[0].trim();
    const ipHash=await sha256Hex("complete-signup-ip:"+ip);
    const tokenKeyHash=await sha256Hex("complete-signup-token:"+completionToken);
    const [{data:ipAllowed,error:ipRateError},{data:tokenAllowed,error:tokenRateError}]=await Promise.all([
      admin.rpc("rf_take_rate_limit",{p_scope:"complete_signup_ip",p_key_hash:ipHash,p_limit:30,p_window_seconds:3600}),
      admin.rpc("rf_take_rate_limit",{p_scope:"complete_signup_token",p_key_hash:tokenKeyHash,p_limit:12,p_window_seconds:3600})
    ]);
    if(ipRateError)throw ipRateError;if(tokenRateError)throw tokenRateError;
    if(!ipAllowed||!tokenAllowed)return json({error:"Zu viele Versuche. Bitte später erneut versuchen.",code:"RATE_LIMITED"},429);

    const suppliedHash=await sha256Hex(completionToken);
    const {data:intent,error:ie}=await admin.rpc("rf_signup_verify_completion",{
      p_intent_id:intentId,
      p_completion_token_hash:suppliedHash
    });
    if(ie)throw ie;
    if(!intent)return json({error:"Die Registrierungsfreigabe ist ungültig oder abgelaufen. Lade die Erfolgsseite erneut.",code:"COMPLETION_EXPIRED"},410);
    if(intent.status!=="paid")return json({error:"Zahlung ist noch nicht bestätigt."},409);

    const {data:existing,error:le}=await admin.rpc("rf_find_auth_user_by_email",{p_email:intent.email});
    if(le)throw le;

    let userId=existing as string|null;
    let createdUser=false;

    if(userId){
      if(!currentUser||currentUser.id!==userId){
        return json({
          error:"Für diese E-Mail existiert bereits ein RegieFlow-Konto. Bitte melde dich mit diesem Konto an und schliesse die Registrierung erneut ab.",
          code:"LOGIN_REQUIRED",
          email:intent.email
        },409);
      }
    }else{
      if(password.length<10)return json({error:"Passwort muss mindestens 10 Zeichen lang sein."},400);
      const redirectTo="https://regieflow.pages.dev/?signup_success="+encodeURIComponent(String(intent.stripe_checkout_session_id||""));
      const {data:created,error:ce}=await publicClient.auth.signUp({
        email:intent.email,
        password,
        options:{data:{regieflow_owner:true},emailRedirectTo:redirectTo}
      });
      if(ce)throw ce;
      if(!created.user)throw new Error("Konto konnte nicht erstellt werden");
      userId=created.user.id;
      createdUser=true;

      const {error:linkError}=await admin.rpc("rf_signup_set_auth_user",{p_intent_id:intent.id,p_user_id:userId});
      if(linkError)throw linkError;

      if(!created.user.email_confirmed_at){
        return json({
          status:"verification_required",
          verificationRequired:true,
          email:intent.email
        },202);
      }
    }

    if(currentUser&&currentUser.id===userId&&!currentUser.email_confirmed_at){
      return json({status:"verification_required",verificationRequired:true,email:intent.email},202);
    }

    try{
      const {error:ue}=await admin.rpc("rf_signup_set_auth_user",{p_intent_id:intent.id,p_user_id:userId});
      if(ue)throw ue;

      const eventId="onboarding:"+String(intent.stripe_checkout_session_id||intent.id);
      const {data:companyId,error:pe}=await admin.rpc("rf_provision_paid_company",{
        p_signup_intent_id:intent.id,
        p_provider_event_id:eventId
      });
      if(pe)throw pe;

      return json({
        status:"provisioned",
        companyId,
        email:intent.email,
        createdUser,
        existingUser:!createdUser
      },201);
    }catch(e){
      if(createdUser&&userId){
        await admin.auth.admin.deleteUser(userId);
        await admin.rpc("rf_signup_clear_auth_user",{p_intent_id:intent.id,p_user_id:userId});
      }
      throw e;
    }
  }catch(e){
    return json({error:e instanceof Error?e.message:String(e)},400);
  }
});