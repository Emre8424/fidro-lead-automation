import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{"Content-Type":"application/json","Cache-Control":"no-store"}});
const enc=new TextEncoder();

async function hmacHex(secret:string,payload:string){
  const key=await crypto.subtle.importKey("raw",enc.encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
  const sig=new Uint8Array(await crypto.subtle.sign("HMAC",key,enc.encode(payload)));
  return [...sig].map(b=>b.toString(16).padStart(2,"0")).join("");
}
function safeEqual(a:string,b:string){
  if(a.length!==b.length)return false;
  let x=0;for(let i=0;i<a.length;i++)x|=a.charCodeAt(i)^b.charCodeAt(i);return x===0;
}
async function sha256Hex(v:string){
  const h=new Uint8Array(await crypto.subtle.digest("SHA-256",enc.encode(v)));
  return [...h].map(b=>b.toString(16).padStart(2,"0")).join("");
}
async function verifyStripe(raw:string,header:string,secret:string){
  const parts=header.split(",").map(x=>x.trim());
  const t=parts.find(x=>x.startsWith("t="))?.slice(2);
  const sigs=parts.filter(x=>x.startsWith("v1=")).map(x=>x.slice(3));
  if(!t||!sigs.length)return false;
  const ts=Number(t);
  if(!Number.isFinite(ts)||Math.abs(Date.now()/1000-ts)>300)return false;
  const expected=await hmacHex(secret,t+"."+raw);
  return sigs.some(s=>safeEqual(expected,s));
}
function id(v:any){return typeof v==="string"?v:(v&&typeof v.id==="string"?v.id:null)}

Deno.serve(async(req:Request)=>{
  if(req.method!=="POST")return json({error:"Method not allowed"},405);
  const url=Deno.env.get("SUPABASE_URL");
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const webhookSecret=Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if(!url||!service||!webhookSecret)return json({error:"Webhook configuration missing"},503);

  const raw=await req.text();
  const sig=req.headers.get("stripe-signature")||"";
  if(!(await verifyStripe(raw,sig,webhookSecret)))return json({error:"Invalid signature"},400);

  let event:any;
  try{event=JSON.parse(raw)}catch{return json({error:"Invalid JSON"},400)}
  if(!event?.id||!event?.type||!event?.data?.object)return json({error:"Invalid event"},400);

  const admin=createClient(url,service,{auth:{persistSession:false}});
  const payloadHash=await sha256Hex(raw);

  try{
    const {data:eventState,error:beginError}=await admin.rpc("rf_billing_event_begin",{
      p_provider_event_id:String(event.id),
      p_event_type:String(event.type),
      p_payload_sha256:payloadHash
    });
    if(beginError)throw beginError;
    if(eventState?.applied)return json({received:true,duplicate:true});

    const obj=event.data.object;
    let markedBySubscriptionState=false;

    if(["checkout.session.completed","checkout.session.async_payment_succeeded"].includes(event.type)){
      const intentId=String(obj?.metadata?.intent_id||obj?.client_reference_id||"");
      const sessionId=String(obj?.id||"");
      if(intentId&&sessionId){
        const paid=obj.payment_status==="paid"||obj.payment_status==="no_payment_required"||event.type==="checkout.session.async_payment_succeeded";
        if(paid){
          const {error}=await admin.rpc("rf_signup_mark_paid",{
            p_intent_id:intentId,
            p_checkout_session_id:sessionId,
            p_stripe_customer_id:id(obj.customer),
            p_stripe_subscription_id:id(obj.subscription)
          });
          if(error)throw error;
        }
      }
    }else if(event.type==="checkout.session.expired"){
      const sessionId=String(obj?.id||"");
      if(sessionId){
        const {data:intent,error:ge}=await admin.rpc("rf_signup_get_by_checkout",{p_checkout_session_id:sessionId});
        if(ge)throw ge;
        if(intent?.id){
          const {error:ce}=await admin.rpc("rf_signup_cancel_intent",{p_intent_id:intent.id});
          if(ce)throw ce;
        }
      }
    }else if(["customer.subscription.updated","customer.subscription.deleted","customer.subscription.created"].includes(event.type)){
      const subId=String(obj.id||"");
      if(subId){
        const {data:billing,error:be}=await admin.from("rf_company_billing")
          .select("company_id,billing_email,plan,stripe_price_id").eq("stripe_subscription_id",subId).maybeSingle();
        if(be)throw be;

        if(billing?.company_id){
          const items=obj?.items?.data||[];
          const priceIds=items.map((x:any)=>id(x?.price)).filter(Boolean);
          let planRow:any=null;
          if(priceIds.length){
            const {data:plans,error:plansError}=await admin.from("rf_plan_catalog")
              .select("plan,stripe_price_id").in("stripe_price_id",priceIds);
            if(plansError)throw plansError;
            planRow=(plans||[])[0]||null;
          }

          const effectivePlan=planRow?.plan||billing.plan||null;
          const effectivePrice=planRow?.stripe_price_id||billing.stripe_price_id||null;
          if(effectivePlan&&effectivePrice){
            const end=obj.current_period_end?new Date(Number(obj.current_period_end)*1000).toISOString():null;
            const {error:ae}=await admin.rpc("rf_apply_subscription_state",{
              p_company_id:billing.company_id,
              p_plan:effectivePlan,
              p_stripe_customer_id:id(obj.customer),
              p_stripe_subscription_id:subId,
              p_stripe_price_id:effectivePrice,
              p_subscription_status:String(obj.status||"unknown"),
              p_current_period_end:end,
              p_cancel_at_period_end:!!obj.cancel_at_period_end,
              p_provider_event_id:String(event.id),
              p_billing_email:billing.billing_email
            });
            if(ae)throw ae;
            markedBySubscriptionState=true;

            if(["active","trialing","past_due"].includes(String(obj.status||""))){
              const {data:cfg,error:cfgError}=await admin.rpc("rf_billing_get_config");
              if(cfgError)throw cfgError;
              await fetch(url+"/functions/v1/rf-sync-seat-billing",{
                method:"POST",
                headers:{"Content-Type":"application/json","x-regieflow-billing-hook":String(cfg?.hook_secret||"")},
                body:JSON.stringify({companyId:billing.company_id})
              });
            }
          }
        }
      }
    }

    if(!markedBySubscriptionState){
      const {error:markError}=await admin.rpc("rf_billing_event_mark_applied",{
        p_provider_event_id:String(event.id),
        p_company_id:null
      });
      if(markError)throw markError;
    }

    return json({received:true});
  }catch(e){
    return json({error:e instanceof Error?e.message:String(e)},500);
  }
});