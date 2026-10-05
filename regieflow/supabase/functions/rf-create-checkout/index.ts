import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const APP_URL="https://regieflow.pages.dev/";
const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"POST,OPTIONS"
};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});

function clean(v:unknown,max=160){return String(v??"").trim().slice(0,max)}
function validEmail(v:string){return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)}
async function sha256Hex(v:string){
  const h=new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(v)));
  return [...h].map(b=>b.toString(16).padStart(2,"0")).join("");
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);

  const url=Deno.env.get("SUPABASE_URL");
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const stripe=Deno.env.get("STRIPE_SECRET_KEY");
  const stripeWebhook=Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if(!url||!service)return json({error:"Server configuration missing"},500);
  if(!stripe||!stripeWebhook)return json({error:"Zahlungssystem ist noch nicht vollständig verbunden.",code:"STRIPE_NOT_CONFIGURED"},503);

  try{
    const body=await req.json();
    const email=clean(body.email,254).toLowerCase();
    const companyName=clean(body.companyName,160);
    const ownerDisplayName=clean(body.ownerDisplayName,160);
    const plan=clean(body.plan,20).toLowerCase();
    const legalAccepted=body.legalAccepted===true;

    if(!legalAccepted)return json({error:"Bitte AGB und Datenschutzerklärung bestätigen."},400);
    if(!validEmail(email))return json({error:"Bitte eine gültige E-Mail-Adresse eingeben."},400);
    if(companyName.length<2)return json({error:"Firmenname ist erforderlich."},400);
    if(ownerDisplayName.length<2)return json({error:"Name ist erforderlich."},400);
    if(!["starter","team","business"].includes(plan))return json({error:"Ungültiger Tarif."},400);

    const admin=createClient(url,service,{auth:{persistSession:false}});
    const ip=(req.headers.get("cf-connecting-ip")||req.headers.get("x-forwarded-for")||"unknown").split(",")[0].trim();
    const ipHash=await sha256Hex("checkout-ip:"+ip);
    const emailHash=await sha256Hex("checkout-email:"+email);
    const [{data:ipAllowed,error:ipRateError},{data:emailAllowed,error:emailRateError}]=await Promise.all([
      admin.rpc("rf_take_rate_limit",{p_scope:"checkout_ip",p_key_hash:ipHash,p_limit:30,p_window_seconds:3600}),
      admin.rpc("rf_take_rate_limit",{p_scope:"checkout_email",p_key_hash:emailHash,p_limit:6,p_window_seconds:3600})
    ]);
    if(ipRateError)throw ipRateError;if(emailRateError)throw emailRateError;
    if(!ipAllowed||!emailAllowed)return json({error:"Zu viele Registrierungsversuche. Bitte später erneut versuchen.",code:"RATE_LIMITED"},429);

    const [{data:legal,error:legalError},{data:prod,error:prodError},{data:allPlans,error:allPlansError}]=await Promise.all([
      admin.rpc("rf_public_legal"),
      admin.rpc("rf_production_readiness"),
      admin.from("rf_plan_catalog").select("plan,stripe_price_id,stripe_extra_price_id,active").eq("active",true)
    ]);
    if(legalError)throw legalError;
    if(prodError)throw prodError;
    if(allPlansError)throw allPlansError;

    const productionReady=!!prod?.emailConfirmationReady&&!!prod?.leakedPasswordProtectionReady&&!!prod?.backupRecoveryReady;
    const priceReady=(allPlans||[]).length===3&&(allPlans||[]).every((p:any)=>p.stripe_price_id&&p.stripe_extra_price_id);
    if(!legal?.published||!productionReady||!priceReady){
      return json({
        error:"RegieFlow ist noch nicht für öffentliche Registrierungen freigeschaltet.",
        code:"PRODUCTION_NOT_READY"
      },503);
    }
    const legalVersionHash=await sha256Hex(String(legal.updatedAt||"")+"|"+String(legal.terms||"")+"|"+String(legal.privacy||""));

    const {data:planRow,error:pe}=await admin.from("rf_plan_catalog")
      .select("plan,label,stripe_price_id,stripe_extra_price_id,active")
      .eq("plan",plan).eq("active",true).maybeSingle();
    if(pe)throw pe;
    if(!planRow)return json({error:"Tarif ist nicht verfügbar."},400);
    if(!planRow.stripe_price_id||!planRow.stripe_extra_price_id)return json({error:"Dieser Tarif ist in Stripe noch nicht vollständig konfiguriert.",code:"STRIPE_PRICE_NOT_CONFIGURED"},503);

    const {data:open,error:oe}=await admin.rpc("rf_signup_find_open",{p_email:email});
    if(oe)throw oe;

    if(open?.status==="checkout_created"&&open.stripe_checkout_url&&new Date(open.expires_at).getTime()>Date.now()){
      return json({checkoutUrl:open.stripe_checkout_url,resumed:true});
    }
    if(open?.status==="paid"){
      return json({error:"Für diese E-Mail wurde bereits bezahlt. Bitte schliesse die Registrierung über den Zahlungs-Erfolgslink ab.",code:"PAYMENT_ALREADY_COMPLETED"},409);
    }
    if(open?.id){
      const {error:cancelError}=await admin.rpc("rf_signup_cancel_intent",{p_intent_id:open.id});
      if(cancelError)throw cancelError;
    }

    const {data:intentId,error:ie}=await admin.rpc("rf_signup_create_intent",{
      p_email:email,
      p_company_name:companyName,
      p_owner_display_name:ownerDisplayName,
      p_plan:plan,
      p_legal_version_hash:legalVersionHash
    });
    if(ie)throw ie;

    const form=new URLSearchParams();
    form.set("mode","subscription");
    form.set("customer_email",email);
    form.set("line_items[0][price]",planRow.stripe_price_id);
    form.set("line_items[0][quantity]","1");
    form.set("success_url",APP_URL+"?signup_success={CHECKOUT_SESSION_ID}");
    form.set("cancel_url",APP_URL+"?signup=1&cancelled=1");
    form.set("client_reference_id",intentId);
    form.set("metadata[intent_id]",intentId);
    form.set("metadata[plan]",plan);
    form.set("subscription_data[metadata][intent_id]",intentId);
    form.set("subscription_data[metadata][plan]",plan);

    const sr=await fetch("https://api.stripe.com/v1/checkout/sessions",{
      method:"POST",
      headers:{
        "Authorization":"Bearer "+stripe,
        "Content-Type":"application/x-www-form-urlencoded"
      },
      body:form.toString()
    });
    const sj=await sr.json();
    if(!sr.ok||!sj?.id||!sj?.url){
      await admin.rpc("rf_signup_cancel_intent",{p_intent_id:intentId});
      return json({error:sj?.error?.message||"Stripe Checkout konnte nicht erstellt werden."},502);
    }

    const {error:ue}=await admin.rpc("rf_signup_set_checkout",{
      p_intent_id:intentId,
      p_checkout_session_id:String(sj.id),
      p_checkout_url:String(sj.url),
      p_stripe_price_id:planRow.stripe_price_id
    });
    if(ue)throw ue;

    return json({checkoutUrl:sj.url,resumed:false});
  }catch(e){
    return json({error:e instanceof Error?e.message:String(e)},400);
  }
});