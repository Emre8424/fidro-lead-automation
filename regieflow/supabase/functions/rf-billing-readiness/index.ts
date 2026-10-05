import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"GET,OPTIONS"
};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}});

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="GET")return json({error:"Method not allowed"},405);
  const url=Deno.env.get("SUPABASE_URL"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!service)return json({ready:false},503);
  try{
    const admin=createClient(url,service,{auth:{persistSession:false}});
    const [{data:legal},{data:plans},{data:prod}]=await Promise.all([
      admin.rpc("rf_public_legal"),
      admin.from("rf_plan_catalog").select("plan,stripe_price_id,stripe_extra_price_id,active").eq("active",true),
      admin.rpc("rf_production_readiness")
    ]);
    const priceReady=(plans||[]).length===3&&(plans||[]).every((p:any)=>p.stripe_price_id&&p.stripe_extra_price_id);
    const secretsReady=!!Deno.env.get("STRIPE_SECRET_KEY")&&!!Deno.env.get("STRIPE_WEBHOOK_SECRET");
    const legalReady=!!legal?.published;
    const emailReady=!!prod?.emailConfirmationReady;
    const leakedPasswordReady=!!prod?.leakedPasswordProtectionReady;
    const backupReady=!!prod?.backupRecoveryReady;
    const ready=priceReady&&secretsReady&&legalReady&&emailReady&&leakedPasswordReady&&backupReady;
    return json({ready,legalReady,priceReady,secretsReady,emailReady,leakedPasswordReady,backupReady});
  }catch{
    return json({ready:false},503);
  }
});