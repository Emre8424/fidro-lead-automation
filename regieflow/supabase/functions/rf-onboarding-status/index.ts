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
function id(v:any){return typeof v==="string"?v:(v&&typeof v.id==="string"?v.id:null)}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);

  const url=Deno.env.get("SUPABASE_URL");
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const stripe=Deno.env.get("STRIPE_SECRET_KEY");
  if(!url||!service)return json({error:"Server configuration missing"},500);
  if(!stripe)return json({error:"Zahlungssystem ist noch nicht verbunden.",code:"STRIPE_NOT_CONFIGURED"},503);

  try{
    const body=await req.json();
    const sessionId=String(body.sessionId||"").trim();
    if(!sessionId.startsWith("cs_"))return json({error:"Ungültige Checkout-Sitzung."},400);

    const admin=createClient(url,service,{auth:{persistSession:false}});
    const ip=(req.headers.get("cf-connecting-ip")||req.headers.get("x-forwarded-for")||"unknown").split(",")[0].trim();
    const ipHash=await sha256Hex("onboarding-status-ip:"+ip);
    const sessionHash=await sha256Hex("onboarding-status-session:"+sessionId);
    const [{data:ipAllowed,error:ipRateError},{data:sessionAllowed,error:sessionRateError}]=await Promise.all([
      admin.rpc("rf_take_rate_limit",{p_scope:"onboarding_status_ip",p_key_hash:ipHash,p_limit:120,p_window_seconds:3600}),
      admin.rpc("rf_take_rate_limit",{p_scope:"onboarding_status_session",p_key_hash:sessionHash,p_limit:30,p_window_seconds:3600})
    ]);
    if(ipRateError)throw ipRateError;if(sessionRateError)throw sessionRateError;
    if(!ipAllowed||!sessionAllowed)return json({error:"Zu viele Abfragen. Bitte kurz warten.",code:"RATE_LIMITED"},429);

    const {data:intent,error:ie}=await admin.rpc("rf_signup_get_by_checkout",{p_checkout_session_id:sessionId});
    if(ie)throw ie;
    if(!intent)return json({error:"Registrierung nicht gefunden."},404);
    if(intent.status==="provisioned"){
      return json({status:"provisioned",email:intent.email,companyName:intent.company_name,plan:intent.plan});
    }

    const sr=await fetch("https://api.stripe.com/v1/checkout/sessions/"+encodeURIComponent(sessionId),{
      headers:{"Authorization":"Bearer "+stripe}
    });
    const s=await sr.json();
    if(!sr.ok)return json({error:s?.error?.message||"Checkout konnte nicht geprüft werden."},502);

    const stripeIntentId=String(s?.metadata?.intent_id||s?.client_reference_id||"");
    if(stripeIntentId!==String(intent.id))return json({error:"Checkout-Zuordnung stimmt nicht überein."},400);

    const paid=s.payment_status==="paid"||s.payment_status==="no_payment_required";
    if(!paid||s.status!=="complete")return json({status:"pending"});

    const {data:paidIntent,error:me}=await admin.rpc("rf_signup_mark_paid",{
      p_intent_id:intent.id,
      p_checkout_session_id:sessionId,
      p_stripe_customer_id:id(s.customer),
      p_stripe_subscription_id:id(s.subscription)
    });
    if(me)throw me;
    if(paidIntent?.status==="provisioned"){
      return json({status:"provisioned",email:paidIntent.email,companyName:paidIntent.company_name,plan:paidIntent.plan});
    }

    const {data:completion,error:ce}=await admin.rpc("rf_signup_issue_completion",{p_intent_id:intent.id});
    if(ce)throw ce;
    return json(completion);
  }catch(e){
    return json({error:e instanceof Error?e.message:String(e)},400);
  }
});