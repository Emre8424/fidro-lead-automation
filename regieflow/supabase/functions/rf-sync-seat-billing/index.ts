import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{"Content-Type":"application/json"}});
const id=(v:any)=>typeof v==="string"?v:(v&&typeof v.id==="string"?v.id:null);

async function stripeReq(secret:string,path:string,method="GET",body?:URLSearchParams){
  const r=await fetch("https://api.stripe.com/v1"+path,{
    method,
    headers:{
      "Authorization":"Bearer "+secret,
      ...(body?{"Content-Type":"application/x-www-form-urlencoded"}:{})
    },
    body:body?.toString()
  });
  const j=await r.json();
  if(!r.ok)throw new Error(j?.error?.message||"Stripe request failed");
  return j;
}

Deno.serve(async(req:Request)=>{
  if(req.method!=="POST")return json({error:"Method not allowed"},405);
  const url=Deno.env.get("SUPABASE_URL");
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const stripe=Deno.env.get("STRIPE_SECRET_KEY");
  if(!url||!service)return json({error:"Server configuration missing"},500);
  if(!stripe)return json({error:"Stripe not configured"},503);

  const admin=createClient(url,service,{auth:{persistSession:false}});
  try{
    const {data:cfg,error:ce}=await admin.rpc("rf_billing_get_config");
    if(ce)throw ce;
    if(req.headers.get("x-regieflow-billing-hook")!==cfg?.hook_secret)return json({error:"Forbidden"},403);

    const body=await req.json();
    const companyId=String(body.companyId||"");
    if(!companyId)return json({error:"companyId required"},400);

    const {data:billing,error:be}=await admin.from("rf_company_billing")
      .select("*").eq("company_id",companyId).maybeSingle();
    if(be)throw be;
    if(!billing||billing.plan==="development")return json({skipped:true,reason:"development"});
    if(!billing.stripe_subscription_id)return json({skipped:true,reason:"no_subscription"});

    const {data:plan,error:pe}=await admin.from("rf_plan_catalog")
      .select("*").eq("plan",billing.plan).eq("active",true).maybeSingle();
    if(pe)throw pe;
    if(!plan)return json({error:"Plan not found"},409);

    const {count,error:se}=await admin.from("rf_memberships")
      .select("id",{count:"exact",head:true}).eq("company_id",companyId).eq("active",true);
    if(se)throw se;

    const seats=count||0;
    const included=Number(plan.included_internal_profiles||0);
    const extra=Math.max(seats-included,0);
    const extraPrice=plan.stripe_extra_price_id||billing.stripe_extra_price_id||null;

    if(extra>0&&!extraPrice)return json({error:"Extra-seat Stripe price is not configured",code:"EXTRA_PRICE_NOT_CONFIGURED"},409);

    const sub=await stripeReq(stripe,"/subscriptions/"+encodeURIComponent(billing.stripe_subscription_id));
    const items=sub?.items?.data||[];
    let extraItem=items.find((x:any)=>extraPrice&&id(x.price)===extraPrice);
    if(!extraItem&&billing.stripe_extra_subscription_item_id){
      extraItem=items.find((x:any)=>x.id===billing.stripe_extra_subscription_item_id);
    }

    let extraItemId:string|null=extraItem?.id||null;
    if(extra===0&&extraItemId){
      const form=new URLSearchParams();
      form.set("proration_behavior","create_prorations");
      await stripeReq(stripe,"/subscription_items/"+encodeURIComponent(extraItemId),"DELETE",form);
      extraItemId=null;
    }else if(extra>0&&extraItemId){
      const form=new URLSearchParams();
      form.set("quantity",String(extra));
      form.set("proration_behavior","create_prorations");
      await stripeReq(stripe,"/subscription_items/"+encodeURIComponent(extraItemId),"POST",form);
    }else if(extra>0&&!extraItemId){
      const form=new URLSearchParams();
      form.set("subscription",billing.stripe_subscription_id);
      form.set("price",extraPrice);
      form.set("quantity",String(extra));
      form.set("proration_behavior","create_prorations");
      const item=await stripeReq(stripe,"/subscription_items","POST",form);
      extraItemId=String(item.id);
    }

    const {error:ue}=await admin.from("rf_company_billing").update({
      stripe_extra_price_id:extraPrice,
      stripe_extra_subscription_item_id:extraItemId,
      updated_at:new Date().toISOString()
    }).eq("company_id",companyId);
    if(ue)throw ue;

    await admin.from("rf_audit_log").insert({
      company_id:companyId,
      event_type:"billing_seats_synced",
      metadata:{
        active_internal_profiles:seats,
        included_internal_profiles:included,
        extra_profiles:extra,
        stripe_extra_subscription_item_id:extraItemId
      }
    });

    return json({synced:true,seats,included,extra,extraItemId});
  }catch(e){
    return json({error:e instanceof Error?e.message:String(e)},500);
  }
});