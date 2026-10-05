import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{
  status,
  headers:{"Content-Type":"application/json","Cache-Control":"no-store"}
});

Deno.serve(async(req:Request)=>{
  if(req.method!=="GET")return reply({ok:false,error:"Method not allowed"},405);
  const url=Deno.env.get("SUPABASE_URL"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!service)return reply({ok:false,service:"RegieFlow API"},503);

  const checks={database:false,storage:false,integrity:false};
  try{
    const admin=createClient(url,service,{auth:{persistSession:false}});
    const {error:dbError}=await admin.from("rf_plan_catalog").select("plan",{head:true,count:"exact"});
    if(dbError)throw dbError;
    checks.database=true;

    const [{data:privateBucket,error:privateError},{data:brandingBucket,error:brandingError}]=await Promise.all([
      admin.storage.getBucket("rf-private"),
      admin.storage.getBucket("rf-branding")
    ]);
    if(privateError||brandingError||!privateBucket||!brandingBucket)throw privateError||brandingError||new Error("Storage bucket missing");
    checks.storage=true;

    const {data:integrity,error:integrityError}=await admin.rpc("rf_system_integrity_check");
    if(integrityError)throw integrityError;
    checks.integrity=integrity?.ok===true;
    if(!checks.integrity)return reply({ok:false,service:"RegieFlow API",checks},503);

    return reply({ok:true,service:"RegieFlow API",checks});
  }catch{
    return reply({ok:false,service:"RegieFlow API",checks},503);
  }
});