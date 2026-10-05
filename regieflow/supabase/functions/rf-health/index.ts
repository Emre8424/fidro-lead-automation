import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async(req:Request)=>{
  if(req.method!=="GET")return new Response(JSON.stringify({ok:false,error:"Method not allowed"}),{status:405,headers:{"Content-Type":"application/json"}});
  const url=Deno.env.get("SUPABASE_URL"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!service)return new Response(JSON.stringify({ok:false}),{status:503,headers:{"Content-Type":"application/json","Cache-Control":"no-store"}});
  try{
    const admin=createClient(url,service,{auth:{persistSession:false}});
    const {error}=await admin.from("rf_plan_catalog").select("plan",{head:true,count:"exact"});
    if(error)throw error;
    return new Response(JSON.stringify({ok:true,service:"RegieFlow API"}),{
      status:200,
      headers:{"Content-Type":"application/json","Cache-Control":"no-store"}
    });
  }catch{
    return new Response(JSON.stringify({ok:false,service:"RegieFlow API"}),{
      status:503,
      headers:{"Content-Type":"application/json","Cache-Control":"no-store"}
    });
  }
});