import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const APP_URL="https://regieflow.pages.dev/";
const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"POST,OPTIONS"
};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);

  const url=Deno.env.get("SUPABASE_URL");
  const anon=Deno.env.get("SUPABASE_ANON_KEY");
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const stripe=Deno.env.get("STRIPE_SECRET_KEY");
  const auth=req.headers.get("Authorization");
  if(!url||!anon||!service||!auth)return json({error:"Server configuration missing"},500);
  if(!stripe)return json({error:"Zahlungssystem ist noch nicht verbunden.",code:"STRIPE_NOT_CONFIGURED"},503);

  const caller=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
  const {data:{user},error:ue}=await caller.auth.getUser();
  if(ue||!user)return json({error:"Nicht angemeldet"},401);

  try{
    const body=await req.json();
    const companyId=String(body.companyId||"");
    if(!companyId)return json({error:"Firma fehlt."},400);
    const {data:allowed,error:pe}=await caller.rpc("rf_has_permission",{p_company:companyId,p_permission:"billing.manage"});
    if(pe)throw pe;
    if(!allowed)return json({error:"Keine Berechtigung zur Aboverwaltung."},403);

    const admin=createClient(url,service,{auth:{persistSession:false}});
    const {data:billing,error:be}=await admin.from("rf_company_billing")
      .select("stripe_customer_id").eq("company_id",companyId).maybeSingle();
    if(be)throw be;
    if(!billing?.stripe_customer_id)return json({error:"Für diese Firma existiert noch kein Stripe-Kundenkonto."},409);

    const form=new URLSearchParams();
    form.set("customer",billing.stripe_customer_id);
    form.set("return_url",APP_URL);

    const sr=await fetch("https://api.stripe.com/v1/billing_portal/sessions",{
      method:"POST",
      headers:{
        "Authorization":"Bearer "+stripe,
        "Content-Type":"application/x-www-form-urlencoded"
      },
      body:form.toString()
    });
    const sj=await sr.json();
    if(!sr.ok||!sj?.url)return json({error:sj?.error?.message||"Aboportal konnte nicht geöffnet werden."},502);
    return json({url:sj.url});
  }catch(e){
    return json({error:e instanceof Error?e.message:String(e)},400);
  }
});