import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-regieflow-hook",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS"
};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});

async function config(admin:any){
  const {data,error}=await admin.rpc("rf_push_get_config");
  if(error)throw error;
  let c=data;
  if(!c?.vapid_public||!c?.vapid_private){
    const keys=webpush.generateVAPIDKeys();
    const {error:setError}=await admin.rpc("rf_push_set_vapid",{p_public:keys.publicKey,p_private:keys.privateKey});
    if(setError)throw setError;
    c={...c,vapid_public:keys.publicKey,vapid_private:keys.privateKey};
  }
  return c;
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  const url=Deno.env.get("SUPABASE_URL"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!service)return json({error:"Server configuration missing"},500);
  const admin=createClient(url,service,{auth:{persistSession:false}});
  try{
    const c=await config(admin);
    if(req.method==="GET"){
      if(new URL(req.url).searchParams.get("public")==="1")return json({publicKey:c.vapid_public});
      return json({error:"Not found"},404);
    }
    if(req.method!=="POST")return json({error:"Method not allowed"},405);
    if(req.headers.get("x-regieflow-hook")!==c.hook_secret)return json({error:"Forbidden"},403);

    const body=await req.json(),id=String(body.notificationId||"");
    if(!id)return json({error:"notificationId required"},400);

    const {data:n,error:ne}=await admin.from("rf_notifications").select("*").eq("id",id).single();
    if(ne)throw ne;

    let query=admin.from("rf_push_subscriptions").select("*");
    if(n.recipient_user_id)query=query.eq("user_id",n.recipient_user_id);
    else if(n.recipient_customer_contact_id)query=query.eq("customer_contact_id",n.recipient_customer_contact_id);
    else return json({sent:0});

    const {data:subs,error:se}=await query;
    if(se)throw se;
    if(!(subs||[]).length)return json({sent:0});

    webpush.setVapidDetails("https://kiihabzzepoehsokglzq.supabase.co",c.vapid_public,c.vapid_private);
    const payload=JSON.stringify({
      title:n.title||"RegieFlow",
      body:n.body||"",
      data:{url:"https://regieflow.pages.dev/",regieId:n.regie_id}
    });
    let sent=0,removed=0,failed=0;
    for(const s of subs||[]){
      try{
        await webpush.sendNotification({
          endpoint:s.endpoint,
          keys:{p256dh:s.p256dh,auth:s.auth_key}
        },payload,{TTL:86400,urgency:"normal"});
        sent++;
      }catch(e:any){
        const status=e?.statusCode||e?.status;
        if(status===404||status===410){
          await admin.from("rf_push_subscriptions").delete().eq("id",s.id);
          removed++;
        }else failed++;
      }
    }
    return json({sent,removed,failed});
  }catch(e){return json({error:e instanceof Error?e.message:String(e)},500)}
});