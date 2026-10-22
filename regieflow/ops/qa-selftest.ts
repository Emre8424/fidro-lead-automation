import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const COMPANY_ID="e0463b0f-94b3-4b28-84b1-56fd993953ff";
const PNG_B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
const SIG="data:image/png;base64,"+PNG_B64;
const json=(x:unknown,s=200)=>new Response(JSON.stringify(x),{status:s,headers:{"Content-Type":"application/json","Cache-Control":"no-store"}});
const ok=(r:any,label:string)=>{if(r.error)throw new Error(label+": "+(r.error.message||JSON.stringify(r.error)));return r.data};

Deno.serve(async(req:Request)=>{
  if(req.method!=="POST")return json({error:"Method not allowed"},405);
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!anon||!service)return json({error:"Server config missing"},500);
  const admin=createClient(url,service,{auth:{persistSession:false}});

  const {data:cfg,error:cfgErr}=await admin.rpc("rf_qa_get_config");
  if(cfgErr)return json({error:"QA config missing"},500);
  if(req.headers.get("x-regieflow-qa")!==cfg?.hook_secret)return json({error:"Forbidden"},403);

  const run=crypto.randomUUID().slice(0,8);
  const internalEmail=`rfqa-internal-${run}@example.invalid`;
  const customerEmail=`rfqa-customer-${run}@example.invalid`;
  const internalPass=`Ri!${crypto.randomUUID()}9Aa`;
  const customerPass=`Rc!${crypto.randomUUID()}8Bb`;
  const out:any={run,checks:[],cleanup:false};

  let internalUserId:string|null=null,customerUserId:string|null=null,roleId:string|null=null;
  let projectId:string|null=null,contactId:string|null=null,regieId:string|null=null,versionId:string|null=null;

  async function cleanup(){
    try{
      const paths:string[]=[];
      if(regieId){
        const {data:files}=await admin.from("rf_regie_files").select("storage_path").eq("regie_id",regieId);
        const {data:docs}=versionId?await admin.from("rf_documents").select("storage_path").eq("version_id",versionId):{data:[]};
        const {data:sigs}=versionId?await admin.from("rf_customer_signatures").select("signature_storage_path").eq("version_id",versionId):{data:[]};
        for(const x of [...(files||[]),...(docs||[]),...(sigs||[])])if(x.storage_path||x.signature_storage_path)paths.push(x.storage_path||x.signature_storage_path);
        if(paths.length)await admin.storage.from("rf-private").remove([...new Set(paths)]);

        await admin.from("rf_audit_log").delete().eq("regie_id",regieId);
        await admin.from("rf_notifications").delete().eq("regie_id",regieId);
        await admin.from("rf_regie_comments").delete().eq("regie_id",regieId);
        if(versionId){
          await admin.from("rf_documents").delete().eq("version_id",versionId);
          await admin.from("rf_customer_signatures").delete().eq("version_id",versionId);
          await admin.from("rf_internal_reviews").delete().eq("version_id",versionId);
          await admin.from("rf_public_approval_links").delete().eq("version_id",versionId);
        }
        await admin.from("rf_regie_files").delete().eq("regie_id",regieId);
        await admin.from("rf_regie_versions").delete().eq("regie_id",regieId);
        await admin.from("rf_regies").delete().eq("id",regieId);
      }
      if(projectId){
        await admin.from("rf_audit_log").delete().eq("project_id",projectId);
        await admin.from("rf_project_customer_access").delete().eq("project_id",projectId);
        await admin.from("rf_projects").delete().eq("id",projectId);
      }
      if(contactId){
        await admin.from("rf_customer_invites").delete().eq("customer_contact_id",contactId);
        await admin.from("rf_customer_contacts").delete().eq("id",contactId);
      }
      if(internalUserId)await admin.from("rf_memberships").delete().eq("company_id",COMPANY_ID).eq("user_id",internalUserId);
      if(roleId)await admin.from("rf_roles").delete().eq("id",roleId);
      if(internalUserId)await admin.auth.admin.deleteUser(internalUserId);
      if(customerUserId)await admin.auth.admin.deleteUser(customerUserId);
      out.cleanup=true;
    }catch(e){
      out.cleanupError=e instanceof Error?e.message:String(e);
    }
  }

  try{
    const iu=ok(await admin.auth.admin.createUser({email:internalEmail,password:internalPass,email_confirm:true,user_metadata:{regieflow_internal:true,regieflow_qa:true}}),"create internal").user;
    const cu=ok(await admin.auth.admin.createUser({email:customerEmail,password:customerPass,email_confirm:true,user_metadata:{regieflow_customer:true,regieflow_qa:true}}),"create customer").user;
    internalUserId=iu.id;customerUserId=cu.id;
    out.checks.push("auth-users");

    const role=ok(await admin.from("rf_roles").insert({
      company_id:COMPANY_ID,
      name:"__QA__ "+run,
      permissions:["projects.view","projects.manage","regies.view","regies.create","regies.review","regies.complete","regies.close","documents.view"],
      created_by:internalUserId
    }).select("id").single(),"role");
    roleId=role.id;

    ok(await admin.from("rf_memberships").insert({
      company_id:COMPANY_ID,user_id:internalUserId,display_name:"QA Internal",role_id:roleId,active:true,must_change_password:false
    }),"membership");

    const ic=createClient(url,anon,{auth:{persistSession:false}});
    const cc=createClient(url,anon,{auth:{persistSession:false}});
    const is=ok(await ic.auth.signInWithPassword({email:internalEmail,password:internalPass}),"internal login").session;
    const cs=ok(await cc.auth.signInWithPassword({email:customerEmail,password:customerPass}),"customer login").session;
    out.checks.push("auth-login");

    projectId=ok(await ic.rpc("rf_create_project",{
      p_company_id:COMPANY_ID,p_project_number:"QA-"+run,p_name:"QA Customer Request",
      p_address:"QA",p_client_name:"QA Customer",p_approval_workflow:"parallel_office_customer"
    }),"create project");

    const contact=ok(await admin.from("rf_customer_contacts").insert({
      company_id:COMPANY_ID,auth_user_id:customerUserId,full_name:"QA Customer",email:customerEmail,organization_name:"QA",active:true
    }).select("id").single(),"customer contact");
    contactId=contact.id;

    ok(await ic.rpc("rf_set_project_customer_access",{
      p_project_id:projectId,p_customer_contact_id:contactId,p_enabled:true,p_can_sign:true,p_label:"QA Signer"
    }),"customer access");
    out.checks.push("project-access");

    regieId=ok(await cc.rpc("rf_create_customer_request",{p_project_id:projectId,p_description:"QA Kundenauftrag mit echtem Upload"}),"customer request");
    ok(await ic.rpc("rf_decide_customer_request",{p_regie_id:regieId,p_decision:"approved",p_assigned_monteur_user_id:internalUserId}),"accept request");
    const prep=ok(await ic.rpc("rf_prepare_customer_request_draft",{
      p_regie_id:regieId,p_description:"QA Kundenauftrag mit echtem Upload",p_estimate_label:"ca. 30 Minuten",p_estimate_minutes:30
    }),"prepare request");
    versionId=prep.versionId;
    out.checks.push("customer-request-prepared");

    const png=Uint8Array.from(atob(PNG_B64),c=>c.charCodeAt(0));
    const fd=new FormData();
    fd.append("regieId",regieId);fd.append("versionId",versionId);fd.append("kind","before");
    fd.append("originalFilename","qa-before.png");
    fd.append("file",new File([png],"qa-before.png",{type:"image/png"}));
    const ur=await fetch(url+"/functions/v1/rf-upload-evidence",{
      method:"POST",
      headers:{apikey:anon,Authorization:"Bearer "+is.access_token},
      body:fd
    });
    const uj=await ur.json();
    if(!ur.ok||uj.error)throw new Error("upload evidence: "+JSON.stringify(uj));
    out.checks.push("before-photo-edge-upload");

    const submitted=ok(await ic.rpc("rf_submit_regie_version",{p_regie_id:regieId,p_version_id:versionId}),"submit");
    if(submitted!=="awaiting_customer")throw new Error("unexpected submit status "+submitted);
    out.checks.push("mandatory-photo-submit");

    const ar=await fetch(url+"/functions/v1/rf-auth-approval",{
      method:"POST",
      headers:{"Content-Type":"application/json",apikey:anon,Authorization:"Bearer "+cs.access_token},
      body:JSON.stringify({versionId,action:"approve",signerName:"QA Customer",signatureDataUrl:SIG,consentAccepted:true})
    });
    const aj=await ar.json();
    if(!ar.ok||aj.error)throw new Error("auth approval: "+JSON.stringify(aj));
    out.checks.push("customer-approval-pdf");

    ok(await ic.rpc("rf_start_execution",{p_regie_id:regieId}),"start");
    ok(await ic.rpc("rf_mark_work_completed",{p_regie_id:regieId}),"complete");
    ok(await ic.rpc("rf_close_regie_v2",{p_regie_id:regieId,p_rapport_number:"QA-"+run}),"close");
    const fin=ok(await admin.from("rf_regies").select("status,rapport_number").eq("id",regieId).single(),"final");
    if(fin.status!=="closed"||!fin.rapport_number)throw new Error("closeout invalid");
    out.checks.push("closeout");

    const integ=ok(await admin.rpc("rf_system_integrity_check"),"integrity");
    if(!integ?.ok)throw new Error("integrity failed "+JSON.stringify(integ));
    out.checks.push("integrity");

    out.ok=true;
    await cleanup();
    return json(out);
  }catch(e){
    out.ok=false;out.error=e instanceof Error?e.message:String(e);
    await cleanup();
    return json(out,500);
  }
});