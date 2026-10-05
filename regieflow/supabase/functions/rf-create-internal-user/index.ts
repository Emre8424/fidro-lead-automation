import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"POST,OPTIONS"
};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
function tempPassword(){
  const bytes=crypto.getRandomValues(new Uint8Array(18));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g,"A").replace(/\//g,"b").replace(/=/g,"").slice(0,18)+"!7a";
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);

  const url=Deno.env.get("SUPABASE_URL");
  const anon=Deno.env.get("SUPABASE_ANON_KEY");
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const auth=req.headers.get("Authorization");
  if(!url||!anon||!service||!auth)return json({error:"Server configuration missing"},500);

  const caller=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
  const {data:{user},error:userError}=await caller.auth.getUser();
  if(userError||!user)return json({error:"Nicht angemeldet"},401);

  try{
    const body=await req.json();
    const companyId=String(body.companyId||"");
    const email=String(body.email||"").trim().toLowerCase();
    const displayName=String(body.displayName||"").trim();
    const roleId=body.roleId?String(body.roleId):null;
    if(!companyId||!email||!displayName)return json({error:"Firma, E-Mail und Name sind erforderlich"},400);

    const {data:allowed,error:permError}=await caller.rpc("rf_has_permission",{p_company:companyId,p_permission:"users.manage"});
    if(permError)throw permError;
    if(!allowed)return json({error:"Keine Berechtigung zur Benutzerverwaltung"},403);

    const admin=createClient(url,service,{auth:{persistSession:false}});

    const {data:billing,error:billingError}=await admin.from("rf_company_billing")
      .select("plan,subscription_status").eq("company_id",companyId).maybeSingle();
    if(billingError)throw billingError;
    if(billing&&billing.plan!=="development"){
      if(!["active","trialing"].includes(String(billing.subscription_status||""))){
        return json({error:"Das Firmenabo ist nicht aktiv.",code:"SUBSCRIPTION_INACTIVE"},402);
      }
      const {data:plan,error:planError}=await admin.from("rf_plan_catalog")
        .select("included_internal_profiles,stripe_extra_price_id").eq("plan",billing.plan).eq("active",true).maybeSingle();
      if(planError)throw planError;
      if(!plan)return json({error:"Tarif ist nicht aktiv."},409);
      const {count,error:countError}=await admin.from("rf_memberships")
        .select("id",{count:"exact",head:true}).eq("company_id",companyId).eq("active",true);
      if(countError)throw countError;
      if((count||0)+1>Number(plan.included_internal_profiles||0)&&!plan.stripe_extra_price_id){
        return json({error:"Zusätzliche Profile sind für diesen Tarif in Stripe noch nicht konfiguriert.",code:"EXTRA_PRICE_NOT_CONFIGURED"},409);
      }
    }

    if(roleId){
      const {data:role,error:roleError}=await admin.from("rf_roles").select("id").eq("id",roleId).eq("company_id",companyId).maybeSingle();
      if(roleError)throw roleError;
      if(!role)return json({error:"Rolle gehört nicht zu dieser Firma"},400);
    }

    const {data:existing,error:lookupError}=await admin.rpc("rf_find_auth_user_by_email",{p_email:email});
    if(lookupError)throw lookupError;

    let targetUserId=existing as string|null;
    let generatedPassword:string|null=null;
    let existingAccount=!!targetUserId;
    let createdNewUser=false;

    if(!targetUserId){
      generatedPassword=tempPassword();
      const {data:created,error:createError}=await admin.auth.admin.createUser({
        email,
        password:generatedPassword,
        email_confirm:true,
        user_metadata:{regieflow_internal:true}
      });
      if(createError)throw createError;
      if(!created.user)throw new Error("Benutzer konnte nicht erstellt werden");
      targetUserId=created.user.id;
      createdNewUser=true;
    }

    const {data:already}=await admin.from("rf_memberships")
      .select("id").eq("company_id",companyId).eq("user_id",targetUserId).maybeSingle();
    if(already){
      if(createdNewUser&&targetUserId)await admin.auth.admin.deleteUser(targetUserId);
      return json({error:"Dieser Benutzer gehört bereits zur Firma"},409);
    }

    const {error:membershipError}=await admin.from("rf_memberships").insert({
      company_id:companyId,
      user_id:targetUserId,
      display_name:displayName,
      role_id:roleId,
      active:true,
      created_by:user.id,
      must_change_password:!existingAccount
    });
    if(membershipError){
      if(createdNewUser&&targetUserId)await admin.auth.admin.deleteUser(targetUserId);
      throw membershipError;
    }

    await admin.from("rf_audit_log").insert({
      company_id:companyId,
      actor_user_id:user.id,
      event_type:"internal_user_created",
      metadata:{
        user_id:targetUserId,
        email,
        display_name:displayName,
        role_id:roleId,
        existing_auth_account:existingAccount
      }
    });

    return json({
      userId:targetUserId,
      existingAccount,
      temporaryPassword:generatedPassword,
      mustChangePassword:!existingAccount
    },201);
  }catch(e){
    return json({error:e instanceof Error?e.message:String(e)},400);
  }
});