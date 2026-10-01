import {createClient} from "https://esm.sh/@supabase/supabase-js@2";
const SUPABASE_URL="https://kiihabzzepoehsokglzq.supabase.co";
const KEY="sb_publishable_3QZtTdjDfS2WKiSD9kaMZA_l4psZ5rn";
const sb=createClient(SUPABASE_URL,KEY);
const APP=location.origin+location.pathname;
const S={session:null,ctx:null,kind:null,companyId:null,company:null,tab:"home",channel:null,unread:0,sw:null,logoUrl:null};
const app=document.getElementById("app"),modal=document.getElementById("modal"),toastBox=document.getElementById("toast");
const esc=s=>String(s==null?"":s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
const q=k=>new URL(location.href).searchParams.get(k);
const fmt=d=>d?new Intl.DateTimeFormat("de-CH",{dateStyle:"short",timeStyle:"short"}).format(new Date(d)):"—";
const sl=s=>({draft:"Entwurf",customer_request:"Kundenanfrage",submitted:"Gesendet",internal_review:"Büroprüfung",awaiting_customer:"Wartet auf Kunde",approved:"Freigegeben",rejected:"Abgelehnt",in_execution:"In Ausführung",work_completed:"Arbeit erledigt",awaiting_rapport:"Rapport-Nr. fehlt",closed:"Abgeschlossen"})[s]||s;
const csl=s=>({draft:"In Vorbereitung",customer_request:"Angefragt",submitted:"Eingereicht",internal_review:"Wird geprüft",awaiting_customer:"Freigabe erforderlich",approved:"Freigegeben",rejected:"Abgelehnt",in_execution:"In Ausführung",work_completed:"Arbeit erledigt",awaiting_rapport:"Arbeit erledigt",closed:"Abgeschlossen"})[s]||sl(s);
const nh=s=>{let x=String(s||"");for(const k of ["draft","customer_request","submitted","internal_review","awaiting_customer","approved","rejected","in_execution","work_completed","awaiting_rapport","closed"])x=x.split(k).join(sl(k));return x};
function toast(m){toastBox.innerHTML='<div class="toast">'+esc(m)+'</div>';setTimeout(()=>toastBox.innerHTML="",3300)}
function em(e){
  if(!e)return "Fehler";
  let m="";
  if(typeof e==="string")m=e;
  else if(e.message){if(typeof e.message==="string")m=e.message;else try{m=JSON.stringify(e.message)}catch{}}
  else try{m=JSON.stringify(e)}catch{m=String(e)}
  const map={
    "Not allowed":"Keine Berechtigung.",
    "Regie not found":"Regie nicht gefunden.",
    "Version not found":"Version nicht gefunden.",
    "Description required":"Beschreibung ist erforderlich.",
    "Estimate required":"Geschätzter Aufwand ist erforderlich.",
    "Authentication required":"Bitte zuerst anmelden.",
    "Project not available to this customer":"Dieses Projekt ist für dieses Kundenkonto nicht verfügbar.",
    "Closed Regie cannot be revised":"Eine abgeschlossene Regie kann nicht mehr geändert werden.",
    "Customer contact not found":"Kundenkontakt nicht gefunden.",
    "Invalid decision":"Ungültige Auswahl.",
    "At least one before-work photo is required":"Mindestens ein Vorher-Bild ist erforderlich.",
    "Assigned Monteur is not an active internal user":"Der zugewiesene Monteur ist nicht aktiv.",
    "Customer already has an account":"Für diese Kundenperson existiert bereits ein Konto.",
    "Customer is not an active authorized signer for this project":"Diese Kundenperson ist nicht mehr freigabeberechtigt.",
    "Customer is not authorized to sign this project":"Diese Kundenperson darf dieses Projekt nicht freigeben.",
    "Customer request is not ready to be prepared":"Diese Kundenanfrage kann gerade nicht vorbereitet werden.",
    "Estimate minutes must be positive":"Die geschätzte Dauer muss grösser als 0 sein.",
    "Invalid approval workflow":"Ungültiger Freigabeablauf.",
    "Link validity must be between 1 and 720 hours":"Die Gültigkeit des Links ist ungültig.",
    "Invite validity must be between 1 and 720 hours":"Die Gültigkeit der Einladung ist ungültig.",
    "Only the current Regie version can be approved":"Diese Version ist nicht mehr aktuell.",
    "Only the current Regie version can be reviewed":"Diese Version ist nicht mehr aktuell.",
    "Only the current submitted version can be shared for approval":"Nur die aktuelle gesendete Version kann freigegeben werden.",
    "Primary Owner cannot be deactivated":"Der Primary Owner kann nicht deaktiviert werden.",
    "Primary Owner role cannot be changed here":"Die Rolle des Primary Owner kann hier nicht geändert werden.",
    "Project not found":"Projekt nicht gefunden.",
    "Project not found or inactive":"Projekt nicht gefunden oder inaktiv.",
    "Regie is not awaiting customer approval":"Diese Regie wartet nicht mehr auf eine Kundenfreigabe.",
    "Regie is not awaiting internal review":"Diese Regie wartet nicht auf eine Büroprüfung.",
    "Regie is not in an executable state":"Diese Regie kann in diesem Status nicht ausgeführt werden.",
    "Regie must be approved first":"Die Regie muss zuerst freigegeben werden.",
    "Role does not belong to this company":"Diese Rolle gehört nicht zu dieser Firma.",
    "Submitted Regie evidence cannot be changed":"Gesendete Regie-Nachweise können nicht mehr verändert werden.",
    "Version already locked":"Diese Version wurde bereits gesendet und ist gesperrt.",
    "Version is not locked/submitted":"Diese Version wurde noch nicht gesendet.",
    "You cannot change your own role":"Du kannst deine eigene Rolle nicht ändern.",
    "You cannot deactivate your own account":"Du kannst deinen eigenen Zugang nicht deaktivieren.",
    "Company subscription is read-only":"Das Firmenabo ist derzeit nur im Lesemodus.",
    "Subscription is not active":"Das Firmenabo ist nicht aktiv.",
    "Extra-seat billing is not configured":"Zusätzliche Profile sind für diesen Tarif noch nicht eingerichtet."
  };
  return map[m]||m||"Fehler";
}
function has(p){const x=(S.ctx&&S.ctx.internal||[]).find(z=>z.companyId===S.companyId);if(!x)return false;const readOnlyAllowed=["projects.view","regies.view","documents.view","documents.export","company.manage","billing.manage"];if(x.writeEnabled===false&&!readOnlyAllowed.includes(p))return false;if(x.isPrimaryOwner)return true;if(Object.prototype.hasOwnProperty.call(x.permissionOverrides||{},p))return !!x.permissionOverrides[p];return (x.rolePermissions||[]).includes(p)}
function internalArea(){
  return ["company.manage","users.manage","roles.manage","projects.manage","regies.review","documents.view","billing.manage"].some(has)?"Büro":"Monteur";
}
function closeModal(){modal.innerHTML=""}
function showModal(h){modal.innerHTML='<div class="modalbg" id="mbg"><div class="modal">'+h+'</div></div>';document.getElementById("mbg").onclick=e=>{if(e.target.id==="mbg")closeModal()}}
async function rpc(name,args){const r=await sb.rpc(name,args||{});if(r.error)throw r.error;return r.data}
async function invoke(name,body){
  const headers={"Content-Type":"application/json","apikey":KEY};
  const session=(await sb.auth.getSession()).data.session;
  if(session&&session.access_token)headers["Authorization"]="Bearer "+session.access_token;
  let res;
  try{
    res=await fetch(SUPABASE_URL+"/functions/v1/"+encodeURIComponent(name),{
      method:"POST",
      headers,
      body:JSON.stringify(body||{})
    });
  }catch(e){
    throw new Error("Verbindung zum RegieFlow-Server fehlgeschlagen: "+em(e));
  }
  const raw=await res.text();
  let data=null;
  try{data=raw?JSON.parse(raw):null}catch{data=raw}
  if(!res.ok){
    let msg="Serverfehler ("+res.status+")";
    if(typeof data==="string"&&data)msg=data;
    else if(data&&typeof data.error==="string")msg=data.error;
    else if(data&&data.error&&data.error.message)msg=String(data.error.message);
    else if(data&&data.message)msg=String(data.message);
    else if(data)try{msg=JSON.stringify(data)}catch{}
    const err=new Error(msg);if(data&&data.code)err.code=data.code;throw err;
  }
  if(data&&data.error){
    const rawErr=data.error;
    const err=new Error(typeof rawErr==="string"?rawErr:(rawErr&&rawErr.message?String(rawErr.message):JSON.stringify(rawErr)));if(data.code)err.code=data.code;throw err;
  }
  return data;
}
async function signed(path,bucket){const r=await sb.storage.from(bucket||"rf-private").createSignedUrl(path,900);if(r.error)throw r.error;return r.data.signedUrl}
async function hashFile(f){const h=await crypto.subtle.digest("SHA-256",await f.arrayBuffer());return Array.from(new Uint8Array(h)).map(b=>b.toString(16).padStart(2,"0")).join("")}
function b64key(s){const p="=".repeat((4-s.length%4)%4),b=(s+p).replace(/-/g,"+").replace(/_/g,"/"),raw=atob(b),a=new Uint8Array(raw.length);for(let i=0;i<raw.length;i++)a[i]=raw.charCodeAt(i);return a}
async function normalizeImageFile(file){
  if(!file||!String(file.type||"").startsWith("image/"))return file;
  if(["image/jpeg","image/png"].includes(file.type))return file;
  try{
    const bmp=await createImageBitmap(file);
    const canvas=document.createElement("canvas");
    canvas.width=bmp.width;canvas.height=bmp.height;
    const ctx=canvas.getContext("2d");
    ctx.drawImage(bmp,0,0);
    if(bmp.close)bmp.close();
    const blob=await new Promise((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(new Error("Bild konnte nicht konvertiert werden.")),"image/jpeg",0.9));
    const base=(file.name||"foto").replace(/\.[^.]+$/,"");
    return new File([blob],base+".jpg",{type:"image/jpeg",lastModified:file.lastModified||Date.now()});
  }catch{
    throw new Error("Dieses Bildformat wird vom Browser nicht unterstützt. Bitte JPEG oder PNG verwenden.");
  }
}
async function upload(opt){
  const f=await normalizeImageFile(opt.file);
  const session=(await sb.auth.getSession()).data.session;
  if(!session)throw new Error("Nicht angemeldet");
  const fd=new FormData();
  fd.append("regieId",opt.regieId);
  fd.append("versionId",opt.versionId||"");
  fd.append("kind",opt.kind);
  fd.append("originalFilename",f.name||"upload");
  fd.append("file",f,f.name||"upload");
  let res;
  try{
    res=await fetch(SUPABASE_URL+"/functions/v1/rf-upload-evidence",{
      method:"POST",
      headers:{apikey:KEY,Authorization:"Bearer "+session.access_token},
      body:fd
    });
  }catch(e){
    throw new Error("Datei konnte nicht zum RegieFlow-Server übertragen werden: "+em(e));
  }
  const raw=await res.text();
  let data=null;try{data=raw?JSON.parse(raw):null}catch{data=raw}
  if(!res.ok||data&&data.error)throw new Error(typeof data?.error==="string"?data.error:"Datei konnte nicht gespeichert werden");
  return data.file.storage_path;
}
function sig(id){const c=document.getElementById(id),x=c.getContext("2d"),d=devicePixelRatio||1,r=c.getBoundingClientRect();c.width=r.width*d;c.height=r.height*d;x.scale(d,d);x.lineWidth=2;x.lineCap="round";let down=false,ok=false;const pt=e=>{const a=c.getBoundingClientRect();return[e.clientX-a.left,e.clientY-a.top]};c.onpointerdown=e=>{down=true;c.setPointerCapture(e.pointerId);const p=pt(e);x.beginPath();x.moveTo(p[0],p[1])};c.onpointermove=e=>{if(!down)return;const p=pt(e);x.lineTo(p[0],p[1]);x.stroke();ok=true};c.onpointerup=()=>down=false;c.onpointercancel=()=>down=false;return{get ok(){return ok},data:()=>c.toDataURL("image/png"),clear:()=>{x.clearRect(0,0,c.width,c.height);ok=false}}}
async function registerSW(){if(!("serviceWorker"in navigator))return null;try{S.sw=await navigator.serviceWorker.register("sw.js",{scope:"./"});return S.sw}catch{return null}}
async function enablePush(){
  try{
    const reg=S.sw||await registerSW();if(!reg)throw new Error("Push wird von diesem Browser nicht unterstützt.");
    const perm=await Notification.requestPermission();if(perm!=="granted")throw new Error("Push-Benachrichtigungen wurden nicht erlaubt.");
    const k=await fetch(SUPABASE_URL+"/functions/v1/rf-push?public=1");const j=await k.json();if(!k.ok||!j.publicKey)throw new Error(j.error||"Push-Schlüssel fehlt");
    let sub=await reg.pushManager.getSubscription();if(!sub)sub=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:b64key(j.publicKey)});
    const sj=sub.toJSON(),row={endpoint:sub.endpoint,p256dh:sj.keys.p256dh,auth_key:sj.keys.auth};
    if(S.kind==="internal")row.user_id=S.session.user.id;else row.customer_contact_id=(S.ctx.customer||[]).find(x=>x.companyId===S.companyId).customerContactId;
    const r=await sb.from("rf_push_subscriptions").upsert(row,{onConflict:"endpoint"});if(r.error)throw r.error;toast("Push-Benachrichtigungen aktiviert.");renderShell()
  }catch(e){toast(em(e))}
}
function pushEnabled(){return typeof Notification!=="undefined"&&Notification.permission==="granted"}
async function init(){
  await registerSW();
  if(q("approve"))return publicApproval(q("approve"));
  if(q("invite"))return invitePage(q("invite"));
  if(q("legal"))return legalPage(q("legal"));
  if(q("signup_success"))return signupSuccessPage(q("signup_success"));
  if(q("signup"))return signupPage(q("cancelled")==="1");
  if(q("setup"))return login("Dieser Entwicklungs-Setup-Link ist nicht mehr aktiv.");
  const r=await sb.auth.getSession();S.session=r.data.session;
  if(q("recovery")){
    if(!S.session)return login("Öffne den Passwort-Link aus deiner E-Mail erneut.");
    return recoveryPage();
  }
  if(!S.session)return login();
  await context();
  await openDeepLink();
}
async function openDeepLink(){
  const deepRegie=q("regie");
  if(!deepRegie)return;
  history.replaceState({},"",APP);
  if(S.kind==="internal"){
    S.tab="regies";renderShell();await renderTab();await openRegie(deepRegie);
  }else{
    S.tab="home";renderShell();await renderTab();await customerRegie(deepRegie);
  }
}
function login(msg){
  app.innerHTML='<div class="auth"><div class="brand"><div class="mark">RF</div><div><strong>RegieFlow</strong><div class="small muted">Regie im Griff.</div></div></div><div class="card"><h2>Anmelden</h2>'+(msg?'<div class="notice">'+esc(msg)+'</div>':"")+'<div class="field"><label class="label">E-Mail</label><input id="email" class="input" type="email" autocomplete="email"></div><div class="field"><label class="label">Passwort</label><input id="pass" class="input" type="password" autocomplete="current-password"></div><button id="go" class="btn primary" style="width:100%">Anmelden</button><button id="forgot" class="btn" style="width:100%;margin-top:8px">Passwort vergessen?</button><hr style="border:0;border-top:1px solid var(--line);margin:20px 0"><div class="small muted" style="text-align:center;margin-bottom:10px">Noch keine Firma bei RegieFlow?</div><button id="signupgo" class="btn" style="width:100%">Firma registrieren</button><div class="tiny muted" style="text-align:center;margin-top:16px"><a href="?legal=imprint">Impressum</a> · <a href="?legal=privacy">Datenschutz</a> · <a href="?legal=terms">AGB</a></div></div></div>';
  document.getElementById("go").onclick=async()=>{try{const r=await sb.auth.signInWithPassword({email:document.getElementById("email").value.trim(),password:document.getElementById("pass").value});if(r.error)throw r.error;S.session=r.data.session;await context();await openDeepLink()}catch(e){toast(em(e))}};
  document.getElementById("forgot").onclick=async()=>{const email=document.getElementById("email").value.trim();if(!email)return toast("Bitte zuerst deine E-Mail eingeben.");try{const r=await sb.auth.resetPasswordForEmail(email,{redirectTo:APP+"?recovery=1"});if(r.error)throw r.error;toast("Passwort-Link wurde gesendet.")}catch(e){toast(em(e))}};
  document.getElementById("signupgo").onclick=()=>{history.pushState({},"",APP+"?signup=1");signupPage(false)};
}
function signupPage(cancelled=false){
  const plans=[
    {id:"starter",name:"Starter",price:29,seats:3,extra:6},
    {id:"team",name:"Team",price:59,seats:10,extra:5},
    {id:"business",name:"Business",price:199,seats:50,extra:4}
  ];
  app.innerHTML='<div class="auth" style="max-width:980px"><div class="brand"><div class="mark">RF</div><div><strong>RegieFlow</strong><div class="small muted">Firma registrieren</div></div></div>'+(cancelled?'<div class="notice warn" style="margin-bottom:14px">Zahlung wurde abgebrochen. Es wurde nichts aktiviert.</div>':"")+'<div class="card"><div class="between"><div><h2 style="margin:0">RegieFlow für deine Firma</h2><div class="muted">Kundenkonten, Projekte und Regien sind unbegrenzt. Bezahlt werden nur interne Profile.</div></div><button id="backlogin" class="btn">Anmelden</button></div><div class="grid g3" style="margin-top:18px">'+plans.map((p,i)=>'<label class="card click" style="margin:0;display:block"><input type="radio" name="signupplan" value="'+p.id+'" '+(i===1?"checked":"")+' style="margin-right:8px"><strong>'+p.name+'</strong><div class="metric" style="margin-top:8px">CHF '+p.price+'<span class="small muted"> / Monat</span></div><div class="small">'+p.seats+' interne Profile inklusive</div><div class="small muted">danach CHF '+p.extra+' / zusätzliches Profil</div></label>').join("")+'</div><div class="grid g2" style="margin-top:16px"><div class="field"><label class="label">Firmenname</label><input id="scompany" class="input" autocomplete="organization"></div><div class="field"><label class="label">Dein Name</label><input id="sowner" class="input" autocomplete="name"></div></div><div class="field"><label class="label">E-Mail</label><input id="semail" class="input" type="email" autocomplete="email"></div><div class="notice" style="margin-top:12px">Nach der Zahlung legst du dein RegieFlow-Passwort fest. Die Firma wird erst nach bestätigter Zahlung aktiviert.</div><div id="signupready"></div><label class="small" style="display:flex;gap:8px;align-items:flex-start;margin-top:14px"><input id="legalagree" type="checkbox" style="margin-top:3px"><span>Ich akzeptiere die <a href="?legal=terms" target="_blank" rel="noopener">AGB</a> und habe die <a href="?legal=privacy" target="_blank" rel="noopener">Datenschutzerklärung</a> gelesen.</span></label><button id="startcheckout" class="btn primary" style="width:100%;margin-top:14px">Weiter zur sicheren Zahlung</button><div class="tiny muted" style="text-align:center;margin-top:14px"><a href="?legal=imprint">Impressum</a> · <a href="?legal=privacy">Datenschutz</a> · <a href="?legal=terms">AGB</a></div></div></div>';
  document.getElementById("backlogin").onclick=()=>{history.replaceState({},"",APP);login()};
  fetch(SUPABASE_URL+"/functions/v1/rf-billing-readiness",{headers:{apikey:KEY}}).then(r=>r.json()).then(x=>{
    if(!x.ready){
      document.getElementById("signupready").innerHTML='<div class="notice warn" style="margin-top:14px">Die öffentliche Registrierung wird gerade vorbereitet und ist noch nicht freigeschaltet.</div>';
      const b=document.getElementById("startcheckout");b.disabled=true;b.textContent="Registrierung noch nicht geöffnet";
    }
  }).catch(()=>{});
  document.getElementById("startcheckout").onclick=async()=>{try{
    if(!document.getElementById("legalagree").checked)return toast("Bitte AGB und Datenschutzerklärung bestätigen.");
    const plan=document.querySelector('input[name="signupplan"]:checked')?.value;
    const o=await invoke("rf-create-checkout",{email:document.getElementById("semail").value.trim(),companyName:document.getElementById("scompany").value.trim(),ownerDisplayName:document.getElementById("sowner").value.trim(),plan,legalAccepted:true});
    if(!o.checkoutUrl)throw new Error("Checkout-Link fehlt.");
    location.href=o.checkoutUrl;
  }catch(e){toast(em(e))}}
}
async function legalPage(section){
  const names={imprint:"Impressum",privacy:"Datenschutz",terms:"Allgemeine Geschäftsbedingungen"};
  if(!names[section])section="imprint";
  app.innerHTML='<div class="auth" style="max-width:820px"><div class="brand"><div class="mark">RF</div><div><strong>RegieFlow</strong><div class="small muted">'+esc(names[section])+'</div></div></div><div class="card" id="legalcontent"><div class="muted">Laden…</div></div></div>';
  try{
    const data=await rpc("rf_public_legal");
    if(!data?.published){
      document.getElementById("legalcontent").innerHTML='<h2>'+esc(names[section])+'</h2><div class="notice warn">Diese Angaben werden vor dem öffentlichen Launch veröffentlicht.</div><button id="legalback" class="btn" style="margin-top:14px">Zurück</button>';
    }else{
      const text=section==="imprint"?data.imprint:section==="privacy"?data.privacy:data.terms;
      document.getElementById("legalcontent").innerHTML='<h2>'+esc(names[section])+'</h2>'+(section!=="imprint"?'<div class="small muted" style="margin-bottom:12px">Verantwortlich: '+esc(data.operatorLegalName||"")+(data.operatorEmail?' · '+esc(data.operatorEmail):"")+'</div>':"")+'<div style="white-space:pre-wrap;line-height:1.55">'+esc(text||"")+'</div><button id="legalback" class="btn" style="margin-top:18px">Zurück</button>';
    }
    document.getElementById("legalback").onclick=()=>{history.back()};
  }catch(e){
    document.getElementById("legalcontent").innerHTML='<div class="notice bad">'+esc(em(e))+'</div><button id="legalback" class="btn" style="margin-top:14px">Zurück</button>';
    document.getElementById("legalback").onclick=()=>history.back();
  }
}
async function signupSuccessPage(sessionId){
  app.innerHTML='<div class="auth"><div class="brand"><div class="mark">RF</div><div><strong>RegieFlow</strong><div class="small muted">Registrierung abschliessen</div></div></div><div class="card" id="signupfinish"><div class="muted">Zahlung wird geprüft…</div></div></div>';
  let state;
  try{
    state=await invoke("rf-onboarding-status",{sessionId});
  }catch(e){
    document.getElementById("signupfinish").innerHTML='<div class="notice bad"><strong>Registrierung konnte nicht geprüft werden.</strong><br>'+esc(em(e))+'</div><button id="retrysignup" class="btn" style="width:100%;margin-top:12px">Erneut prüfen</button>';
    document.getElementById("retrysignup").onclick=()=>signupSuccessPage(sessionId);
    return;
  }
  if(state.status==="pending"){
    document.getElementById("signupfinish").innerHTML='<div class="notice">Die Zahlung wird noch bestätigt. Das dauert normalerweise nur wenige Sekunden.</div><button id="retrysignup" class="btn primary" style="width:100%;margin-top:12px">Erneut prüfen</button>';
    document.getElementById("retrysignup").onclick=()=>signupSuccessPage(sessionId);
    return;
  }
  if(state.status==="provisioned"){
    document.getElementById("signupfinish").innerHTML='<div class="notice ok"><strong>Deine Firma ist bereits aktiviert.</strong></div><button id="gotologin" class="btn primary" style="width:100%;margin-top:12px">Anmelden</button>';
    document.getElementById("gotologin").onclick=()=>{history.replaceState({},"",APP);login()};
    return;
  }
  const label={starter:"Starter",team:"Team",business:"Business"}[state.plan]||state.plan;
  document.getElementById("signupfinish").innerHTML='<div class="notice ok"><strong>Zahlung bestätigt.</strong><br>'+esc(state.companyName)+' · '+esc(label)+'</div><div id="existinglogin"></div><div id="newpassword"><div class="field"><label class="label">E-Mail</label><input id="paidemail" class="input" value="'+esc(state.email)+'" disabled></div><div class="field"><label class="label">Passwort festlegen</label><input id="paidpw1" class="input" type="password" autocomplete="new-password" placeholder="mindestens 10 Zeichen"></div><div class="field"><label class="label">Passwort wiederholen</label><input id="paidpw2" class="input" type="password" autocomplete="new-password"></div><button id="finishpaid" class="btn primary" style="width:100%">Firma aktivieren</button></div>';
  const complete=async(password="")=>{
    try{
      const o=await invoke("rf-complete-paid-signup",{intentId:state.intentId,completionToken:state.completionToken,password});
      if(o.createdUser){
        const s=await sb.auth.signInWithPassword({email:o.email,password});if(s.error)throw s.error;S.session=s.data.session;
      }else{
        S.session=(await sb.auth.getSession()).data.session;
      }
      history.replaceState({},"",APP);await context();
    }catch(e){
      if(e.code==="LOGIN_REQUIRED"){
        document.getElementById("newpassword").classList.add("hidden");
        document.getElementById("existinglogin").innerHTML='<div class="notice">Für diese E-Mail existiert bereits ein RegieFlow-Konto. Melde dich an, um die neue Firma damit zu verknüpfen.</div><div class="field"><label class="label">Passwort</label><input id="existingpaidpw" class="input" type="password" autocomplete="current-password"></div><button id="existingpaidgo" class="btn primary" style="width:100%">Anmelden & Firma aktivieren</button>';
        document.getElementById("existingpaidgo").onclick=async()=>{try{const p=document.getElementById("existingpaidpw").value;const s=await sb.auth.signInWithPassword({email:state.email,password:p});if(s.error)throw s.error;S.session=s.data.session;await complete("")}catch(x){toast(em(x))}};
      }else toast(em(e));
    }
  };
  document.getElementById("finishpaid").onclick=async()=>{const p1=document.getElementById("paidpw1").value,p2=document.getElementById("paidpw2").value;if(p1.length<10)return toast("Passwort muss mindestens 10 Zeichen lang sein.");if(p1!==p2)return toast("Die Passwörter stimmen nicht überein.");await complete(p1)};
}
function recoveryPage(){
  app.innerHTML='<div class="auth"><div class="brand"><div class="mark">RF</div><div><strong>RegieFlow</strong><div class="small muted">Passwort zurücksetzen</div></div></div><div class="card"><h2>Neues Passwort</h2><div class="field"><label class="label">Neues Passwort</label><input id="rp1" class="input" type="password" autocomplete="new-password" placeholder="mindestens 10 Zeichen"></div><div class="field"><label class="label">Wiederholen</label><input id="rp2" class="input" type="password" autocomplete="new-password"></div><button id="rpg" class="btn primary" style="width:100%">Passwort speichern</button></div></div>';
  document.getElementById("rpg").onclick=async()=>{const p1=document.getElementById("rp1").value,p2=document.getElementById("rp2").value;if(p1.length<10)return toast("Passwort muss mindestens 10 Zeichen lang sein.");if(p1!==p2)return toast("Die Passwörter stimmen nicht überein.");try{const r=await sb.auth.updateUser({password:p1});if(r.error)throw r.error;history.replaceState({},"",APP);toast("Passwort geändert.");await context()}catch(e){toast(em(e))}}
}
async function setupPage(token){
  app.innerHTML='<div class="auth"><div class="brand"><div class="mark">RF</div><div><strong>RegieFlow</strong><div class="small muted">Entwicklungs-Setup</div></div></div><div class="card"><h2>Firma einrichten</h2><div class="notice">Einmaliger Setup-Link für die erste RegieFlow-Firma.</div><div class="field"><label class="label">Firmenname</label><input id="sc" class="input" placeholder="Elektro Muster AG"></div><div class="field"><label class="label">Dein Name</label><input id="sn" class="input"></div><div class="field"><label class="label">E-Mail</label><input id="se" class="input" type="email"></div><div class="field"><label class="label">Passwort</label><input id="sp" class="input" type="password" placeholder="mindestens 10 Zeichen"></div><button id="sg" class="btn primary" style="width:100%">RegieFlow starten</button></div></div>';
  document.getElementById("sg").onclick=async()=>{try{const email=document.getElementById("se").value.trim(),password=document.getElementById("sp").value;await invoke("rf-dev-company-setup",{token:token,email:email,password:password,companyName:document.getElementById("sc").value.trim(),displayName:document.getElementById("sn").value.trim()});const r=await sb.auth.signInWithPassword({email:email,password:password});if(r.error)throw r.error;S.session=r.data.session;history.replaceState({},"",APP);await context()}catch(e){toast(em(e))}}
}
async function invitePage(token){
  const ss=await sb.auth.getSession(),session=ss.data.session;
  let internal=false;
  if(session){
    try{
      const cx=await rpc("rf_my_context");
      internal=(cx.internal||[]).length>0;
    }catch{}
  }
  if(session&&internal){
    app.innerHTML='<div class="auth"><div class="brand"><div class="mark">RF</div><div><strong>RegieFlow</strong><div class="small muted">Kostenloses Kundenkonto</div></div></div><div class="card"><h2>Einladung annehmen</h2><div class="notice warn"><strong>Du bist gerade als Mitarbeiter angemeldet.</strong><br>Damit Kunden- und Mitarbeiterzugang nicht versehentlich vermischt werden, melde dich zuerst ab und öffne den Einladungslink danach erneut.</div><button id="inviteLogout" class="btn primary" style="width:100%;margin-top:12px">Abmelden</button></div></div>';
    document.getElementById("inviteLogout").onclick=async()=>{await sb.auth.signOut();location.href=location.href};
    return;
  }
  app.innerHTML='<div class="auth"><div class="brand"><div class="mark">RF</div><div><strong>RegieFlow</strong><div class="small muted">Kostenloses Kundenkonto</div></div></div><div class="card"><h2>Einladung annehmen</h2><p class="muted">Kundenkonten sind kostenlos. Du kannst Aufträge erstellen, Regien freigeben und dein Archiv jederzeit öffnen.</p>'+(session?'<div class="notice">Du bist bereits angemeldet.</div><button id="claim" class="btn primary" style="width:100%;margin-top:12px">Mit diesem Konto verknüpfen</button>':'<div class="field"><input id="ie" class="input" type="email" placeholder="E-Mail"></div><div class="field"><input id="ip" class="input" type="password" placeholder="Passwort, mind. 10 Zeichen"></div><button id="newacc" class="btn primary" style="width:100%">Kostenloses Konto erstellen</button><hr style="border:0;border-top:1px solid var(--line);margin:20px 0"><div class="field"><input id="ee" class="input" type="email" placeholder="Bestehende E-Mail"></div><div class="field"><input id="ep" class="input" type="password" placeholder="Passwort"></div><button id="existing" class="btn" style="width:100%">Anmelden & verknüpfen</button>')+'</div></div>';
  if(session)document.getElementById("claim").onclick=async()=>{try{await invoke("rf-claim-customer-invite",{token:token});S.session=session;history.replaceState({},"",APP);await context()}catch(e){toast(em(e))}};
  else{
    document.getElementById("newacc").onclick=async()=>{try{const email=document.getElementById("ie").value.trim(),password=document.getElementById("ip").value;await invoke("rf-customer-signup",{token:token,email:email,password:password});const r=await sb.auth.signInWithPassword({email:email,password:password});if(r.error)throw r.error;S.session=r.data.session;history.replaceState({},"",APP);await context()}catch(e){toast(em(e))}};
    document.getElementById("existing").onclick=async()=>{try{const r=await sb.auth.signInWithPassword({email:document.getElementById("ee").value.trim(),password:document.getElementById("ep").value});if(r.error)throw r.error;S.session=r.data.session;await invoke("rf-claim-customer-invite",{token:token});history.replaceState({},"",APP);await context()}catch(e){toast(em(e))}}
  }
}
async function publicApproval(token){
  app.innerHTML='<div class="auth"><div class="card muted">Freigabe wird geladen…</div></div>';
  try{
    const d=await invoke("rf-public-approval",{token:token,action:"view"}),r=d.regie;
    document.documentElement.style.setProperty("--accent",r.accentColor||"#111827");
    const pmark=d.logoUrl?'<img src="'+esc(d.logoUrl)+'" alt="">':"RF";
    app.innerHTML='<div class="auth" style="max-width:720px"><div class="brand"><div class="mark">'+pmark+'</div><div><strong>'+esc(r.companyName)+'</strong><div class="small muted">Digitale Regiefreigabe</div></div></div><div class="card"><div class="between"><div><div class="small muted">'+esc(r.projectNumber)+'</div><h2>'+esc(r.code)+'</h2></div><span class="status awaiting_customer">Freigabe</span></div><p>'+esc(r.description)+'</p><div class="notice warn"><strong>Schätzung:</strong> '+esc(r.estimate)+'<br>'+esc(r.estimateDisclaimer)+'</div><p><strong>Monteur:</strong> '+esc(r.monteurName)+'<br><strong>Freigabeberechtigt:</strong> '+esc(r.authorizedSigner)+'</p><div class="photo-grid">'+(d.photos||[]).map(x=>'<img src="'+esc(x.url)+'">').join("")+'</div><div class="field"><label class="label">Unterzeichnende Person</label><input id="pn" class="input" readonly value="'+esc(r.authorizedSigner)+'"></div><div class="field"><div class="between"><label class="label">Unterschrift</label><button id="pc" class="btn">Löschen</button></div><canvas id="ps" class="sig"></canvas></div><div class="notice">Du bestätigst genau diese Version. Danach bleibt sie unveränderbar archiviert.</div><label class="small" style="display:flex;gap:8px;align-items:flex-start;margin-top:12px"><input id="pconsent" type="checkbox" style="margin-top:3px"><span>'+esc(d.regie.consentText||"Ich bestätige die Freigabe dieser Regie.")+'</span></label><div class="grid g2" style="margin-top:14px"><button id="pr" class="btn">Ablehnen</button><button id="pa" class="btn primary">Bestätigen & unterschreiben</button></div></div></div>';
    const s=sig("ps");document.getElementById("pc").onclick=()=>s.clear();
    document.getElementById("pr").onclick=async()=>{try{await invoke("rf-public-approval",{token:token,action:"reject",signerName:document.getElementById("pn").value});app.innerHTML='<div class="auth"><div class="card"><div class="notice ok"><strong>Auftrag abgelehnt.</strong><br>Die Firma wurde informiert.</div></div></div>'}catch(e){toast(em(e))}};
    document.getElementById("pa").onclick=async()=>{if(!s.ok)return toast("Bitte unterschreiben.");try{if(!document.getElementById("pconsent").checked)return toast("Bitte die Freigabeerklärung bestätigen.");const o=await invoke("rf-public-approval",{token:token,action:"approve",signerName:document.getElementById("pn").value,signatureDataUrl:s.data(),consentAccepted:true});app.innerHTML='<div class="auth"><div class="card"><div class="notice ok"><strong>Freigabe bestätigt.</strong><br>PDF und Nachweis wurden gesperrt und archiviert.</div>'+(o.pdfUrl?'<p><a class="btn primary" href="'+esc(o.pdfUrl)+'" target="_blank" style="display:inline-block;text-decoration:none">PDF öffnen</a></p>':"")+'</div></div>'}catch(e){toast(em(e))}}
  }catch(e){app.innerHTML='<div class="auth"><div class="card"><div class="notice bad"><strong>Freigabe nicht verfügbar.</strong><br>'+esc(em(e))+'</div></div></div>'}
}
async function context(){
  S.ctx=await rpc("rf_my_context");
  if((S.ctx.internal||[]).length){S.kind="internal";S.companyId=S.ctx.internal[0].companyId}
  else if((S.ctx.customer||[]).length){S.kind="customer";S.companyId=S.ctx.customer[0].companyId}
  else{app.innerHTML='<div class="auth"><div class="card"><h2>Kein RegieFlow-Zugang</h2><p class="muted">Das Konto ist noch keiner Firma oder Kundenbeziehung zugeordnet.</p><button id="lo" class="btn">Abmelden</button></div></div>';document.getElementById("lo").onclick=logout;return}
  if(S.kind==="internal"){
    const access=(S.ctx.internal||[]).find(x=>x.companyId===S.companyId);
    if(access&&access.mustChangePassword){
      return forcePasswordChange();
    }
  }
  const r=await sb.from("rf_companies").select("*").eq("id",S.companyId).single();if(r.error)throw r.error;S.company=r.data;
  document.documentElement.style.setProperty("--accent",S.company.accent_color||"#111827");
  S.logoUrl=null;if(S.company.logo_path){try{S.logoUrl=await signed(S.company.logo_path,"rf-branding")}catch{}}
  const pendingRegie=q("regie");
  await realtime();
  S.tab=pendingRegie&&S.kind==="internal"?"regies":"home";
  renderShell();await renderTab();
  if(pendingRegie){
    history.replaceState({},"",APP);
    if(S.kind==="internal")await openRegie(pendingRegie);
    else await customerRegie(pendingRegie);
  }
}
async function forcePasswordChange(){
  app.innerHTML='<div class="auth"><div class="brand"><div class="mark">RF</div><div><strong>RegieFlow</strong><div class="small muted">Sicherheitsprüfung</div></div></div><div class="card"><h2>Neues Passwort festlegen</h2><p class="muted">Du meldest dich mit einem temporären Passwort an. Lege jetzt dein persönliches Passwort fest.</p><div class="field"><label class="label">Neues Passwort</label><input id="npw1" class="input" type="password" autocomplete="new-password" placeholder="mindestens 10 Zeichen"></div><div class="field"><label class="label">Passwort wiederholen</label><input id="npw2" class="input" type="password" autocomplete="new-password"></div><button id="npwgo" class="btn primary" style="width:100%">Passwort speichern</button></div></div>';
  document.getElementById("npwgo").onclick=async()=>{
    const p1=document.getElementById("npw1").value,p2=document.getElementById("npw2").value;
    if(p1.length<10)return toast("Passwort muss mindestens 10 Zeichen lang sein.");
    if(p1!==p2)return toast("Die Passwörter stimmen nicht überein.");
    try{
      const u=await sb.auth.updateUser({password:p1});if(u.error)throw u.error;
      await rpc("rf_ack_password_changed",{p_company_id:S.companyId});
      toast("Passwort geändert.");
      await context();
    }catch(e){toast(em(e))}
  };
}
async function realtime(){
  if(S.channel)await sb.removeChannel(S.channel);
  const n=await sb.from("rf_notifications").select("*",{count:"exact",head:true}).is("read_at",null);S.unread=n.count||0;
  S.channel=sb.channel("rf-"+S.companyId).on("postgres_changes",{event:"INSERT",schema:"public",table:"rf_notifications"},()=>{S.unread++;toast("Neue RegieFlow-Aktivität");renderShell()}).on("postgres_changes",{event:"UPDATE",schema:"public",table:"rf_regies"},()=>{if(S.tab==="home"||S.tab==="regies"||S.tab==="archive")renderTab()}).subscribe()
}
async function logout(){await sb.auth.signOut();if(S.channel)await sb.removeChannel(S.channel);Object.assign(S,{session:null,ctx:null,kind:null,companyId:null,company:null,tab:"home",channel:null,unread:0});login()}
function nav(){
  if(S.kind==="customer"){const x=(S.ctx?.customer||[]).find(z=>z.companyId===S.companyId);const n=[["home","Übersicht"]];if(x?.writeEnabled!==false)n.push(["request","Auftrag"]);n.push(["archive","Archiv"],["notifications","Mitteilungen"],["account","Konto"]);return n}
  const x=[["home","Übersicht"]];
  if(has("projects.view")||has("projects.manage"))x.push(["projects","Projekte"]);
  if(has("regies.view")||has("regies.create")||has("regies.review")||has("regies.complete")||has("regies.close"))x.push(["regies","Regien"]);
  if(has("regies.create"))x.push(["new","Neue Regie"]);
  if(has("users.manage")||has("roles.manage"))x.push(["team","Benutzer & Rechte"]);
  if(has("company.manage")||has("billing.manage"))x.push(["settings","Einstellungen"]);
  x.push(["notifications","Mitteilungen"]);
  return x;
}
function mark(){return S.logoUrl?'<img src="'+esc(S.logoUrl)+'">':"RF"}
function renderShell(){
  const items=nav();
  const access=S.kind==="internal"?(S.ctx?.internal||[]).find(x=>x.companyId===S.companyId):(S.ctx?.customer||[]).find(x=>x.companyId===S.companyId);
  const readOnly=access?.writeEnabled===false;
  app.innerHTML='<div class="shell"><aside class="side"><div class="brand"><div class="mark">'+mark()+'</div><div><strong>'+esc(S.company.name)+'</strong><div class="small muted">RegieFlow</div></div></div><div class="nav">'+items.map(x=>'<button data-tab="'+x[0]+'" class="'+(S.tab===x[0]?"active":"")+'">'+esc(x[1])+(x[0]==="notifications"&&S.unread?' <span class="badge">'+S.unread+'</span>':"")+'</button>').join("")+'</div><div style="position:absolute;left:14px;right:14px;bottom:18px"><button id="push" class="btn" style="width:100%;margin-bottom:7px">'+(pushEnabled()?"Push aktiviert":"Push aktivieren")+'</button><button id="logout" class="btn" style="width:100%">Abmelden</button></div></aside><main class="main"><header class="top"><strong>'+esc((items.find(x=>x[0]===S.tab)||["","RegieFlow"])[1])+'</strong><div class="row"><span class="small muted">'+esc(S.kind==="customer"?"Kunde":internalArea())+'</span><button id="pushTop" class="btn">'+(pushEnabled()?"🔔":"Push")+'</button><button id="logoutTop" class="btn">Abmelden</button></div></header>'+(readOnly?'<div class="content" style="padding-bottom:0"><div class="notice warn"><strong>Nur-Lesen-Modus</strong><br>Das Firmenabo ist derzeit nicht aktiv. Bestehende Projekte, Regien und Dokumente bleiben verfügbar.</div></div>':"")+'<div id="content" class="content"></div></main></div><div class="mobilebar">'+items.slice(0,5).map(x=>'<button data-tab="'+x[0]+'">'+esc(x[1])+'</button>').join("")+'</div>';
  document.querySelectorAll("[data-tab]").forEach(b=>b.onclick=async()=>{S.tab=b.dataset.tab;renderShell();await renderTab()});
  document.getElementById("logout").onclick=logout;document.getElementById("logoutTop").onclick=logout;document.getElementById("push").onclick=enablePush;document.getElementById("pushTop").onclick=enablePush
}
async function renderTab(){
  const c=document.getElementById("content");if(!c)return;c.innerHTML='<div class="card muted">Laden…</div>';
  try{
    if(S.kind==="customer"){if(S.tab==="home")return customerHome(c);if(S.tab==="request")return customerRequest(c);if(S.tab==="archive")return customerArchive(c);if(S.tab==="notifications")return notifications(c);if(S.tab==="account")return accountPage(c)}
    else{if(S.tab==="home")return internalHome(c);if(S.tab==="projects")return projects(c);if(S.tab==="regies")return regies(c);if(S.tab==="new")return newRegie(c);if(S.tab==="team")return team(c);if(S.tab==="settings")return settings(c);if(S.tab==="notifications")return notifications(c)}
  }catch(e){c.innerHTML='<div class="notice bad">'+esc(em(e))+'</div>'}
}
async function getRegies(){const r=await sb.from("rf_regie_overview").select("*").eq("company_id",S.companyId).order("updated_at",{ascending:false});if(r.error)throw r.error;return r.data||[]}
function regieTable(rows){if(!rows.length)return'<div class="empty">Noch keine Regien.</div>';return'<div class="tablewrap"><table class="table"><thead><tr><th>Regie</th><th>Projekt</th><th>Status</th><th>Aktualisiert</th></tr></thead><tbody>'+rows.map(r=>'<tr class="click" data-r="'+r.id+'"><td><strong>'+esc(r.regie_code)+'</strong><div class="small muted">'+esc((r.description||"").slice(0,80))+'</div></td><td>'+esc(r.project_number)+'<div class="small muted">'+esc(r.project_name)+'</div></td><td><span class="status '+esc(r.status)+'">'+esc(sl(r.status))+'</span></td><td class="small">'+fmt(r.updated_at)+'</td></tr>').join("")+'</tbody></table></div>'}
function bindRows(){document.querySelectorAll("[data-r]").forEach(x=>x.onclick=()=>openRegie(x.dataset.r))}
function commentPanel(rows,readonly){
  const list=(rows||[]).length?(rows||[]).map(x=>'<div style="padding:8px 0;border-bottom:1px solid var(--line)"><div class="between"><strong class="small">'+esc(x.actorName||"")+'</strong><span class="tiny muted">'+fmt(x.createdAt)+'</span></div><div class="small" style="margin-top:3px;white-space:pre-wrap">'+esc(x.body||"")+'</div></div>').join(""):'<div class="small muted" style="padding:8px 0">Noch keine Notizen.</div>';
  return '<div class="card" style="margin-top:14px;padding:14px"><strong>Notizen</strong>'+list+(readonly?'<div class="tiny muted" style="margin-top:8px">Archivierte Regien sind schreibgeschützt.</div>':'<div class="row" style="margin-top:10px"><input id="commentText" class="input" maxlength="4000" placeholder="Kurze Notiz…"><button id="commentAdd" class="btn">Senden</button></div>')+'</div>';
}
function bindComment(regieId,reopen){
  const b=document.getElementById("commentAdd");if(!b)return;
  b.onclick=async()=>{const el=document.getElementById("commentText"),body=el.value.trim();if(!body)return toast("Notiz darf nicht leer sein.");try{await rpc("rf_add_regie_comment",{p_regie_id:regieId,p_body:body});toast("Notiz gespeichert");await reopen(regieId)}catch(e){toast(em(e))}};
}

async function internalHome(c){
  const rows=await getRegies(),pr=await sb.from("rf_projects").select("id",{count:"exact",head:true}).eq("company_id",S.companyId).eq("active",true);
  c.innerHTML='<div class="hero"><h2 style="margin:0 0 6px">Regie im Griff.</h2><div style="opacity:.8">Zusatzarbeiten sauber dokumentieren, freigeben und abschliessen.</div></div><div class="grid g4" style="margin-top:14px"><div class="card"><div class="small muted">Aktive Projekte</div><div class="metric">'+(pr.count||0)+'</div></div><div class="card"><div class="small muted">Warten</div><div class="metric">'+rows.filter(r=>["internal_review","awaiting_customer"].includes(r.status)).length+'</div></div><div class="card"><div class="small muted">Freigegeben</div><div class="metric">'+rows.filter(r=>["approved","in_execution","awaiting_rapport"].includes(r.status)).length+'</div></div><div class="card"><div class="small muted">Abgeschlossen</div><div class="metric">'+rows.filter(r=>r.status==="closed").length+'</div></div></div><div class="card" style="margin-top:14px"><div class="between"><h3>Letzte Regien</h3>'+(has("regies.create")?'<button id="hn" class="btn primary">+ Neue Regie</button>':"")+'</div>'+regieTable(rows.slice(0,8))+'</div>';
  if(document.getElementById("hn"))document.getElementById("hn").onclick=async()=>{S.tab="new";renderShell();await renderTab()};bindRows()
}
async function projects(c){
  const r=await sb.from("rf_projects").select("*").eq("company_id",S.companyId).order("created_at",{ascending:false});if(r.error)throw r.error;
  c.innerHTML='<div class="card"><div class="between"><div><h3 style="margin:0">Projekte</h3><div class="small muted">Projekte und Baustellen zentral verwalten.</div></div>'+(has("projects.manage")?'<button id="ap" class="btn primary">+ Projekt</button>':"")+'</div></div><div class="grid g2" style="margin-top:14px">'+(r.data||[]).map(p=>'<div class="card"><div class="between"><div><strong>'+esc(p.project_number)+' · '+esc(p.name)+'</strong><div class="small muted">'+esc(p.address||"")+'</div></div><span class="status">'+(p.approval_workflow==="office_then_customer"?"Mit Büroprüfung":"Direkt zum Kunden")+'</span></div><p class="small"><strong>Bauherr:</strong> '+esc(p.client_name||"—")+'</p>'+(has("projects.manage")?'<div class="row wrap"><button class="btn" data-pc="'+p.id+'">Kunden & Freigabe</button><button class="btn" data-pe="'+p.id+'">Bearbeiten</button></div>':"")+'</div>').join("")+'</div>';
  if(document.getElementById("ap"))document.getElementById("ap").onclick=addProject;
  document.querySelectorAll("[data-pc]").forEach(b=>b.onclick=()=>projectCustomers(b.dataset.pc));
  document.querySelectorAll("[data-pe]").forEach(b=>{const p=(r.data||[]).find(x=>x.id===b.dataset.pe);if(p)b.onclick=()=>editProject(p)});
}
function editProject(p){
  showModal('<div class="between"><h3>Projekt bearbeiten</h3><button id="x" class="btn">✕</button></div><div class="field"><label class="label">Projektnummer *</label><input id="ep1" class="input" value="'+esc(p.project_number)+'"></div><div class="field"><label class="label">Projektname *</label><input id="ep3" class="input" value="'+esc(p.name)+'"></div><div class="field"><label class="label">Adresse</label><input id="ep4" class="input" value="'+esc(p.address||"")+'"></div><div class="field"><label class="label">Bauherr / Kunde</label><input id="ep5" class="input" value="'+esc(p.client_name||"")+'"></div><div class="field"><label class="label">Freigabeablauf</label><select id="ep6" class="select"><option value="office_then_customer" '+(p.approval_workflow==="office_then_customer"?"selected":"")+'>Mit Büroprüfung – Büro prüft zuerst</option><option value="parallel_office_customer" '+(p.approval_workflow==="parallel_office_customer"?"selected":"")+'>Direkt zum Kunden – Büro wird informiert</option></select></div><label class="small" style="display:flex;gap:8px;align-items:center;margin:12px 0"><input id="epa" type="checkbox" '+(p.active?"checked":"")+'> Projekt aktiv</label><button id="eps" class="btn primary" style="width:100%">Speichern</button>');
  document.getElementById("x").onclick=closeModal;
  document.getElementById("eps").onclick=async()=>{try{
    await rpc("rf_update_project",{
      p_project_id:p.id,
      p_project_number:document.getElementById("ep1").value.trim(),
      p_name:document.getElementById("ep3").value.trim(),
      p_address:document.getElementById("ep4").value.trim()||null,
      p_client_name:document.getElementById("ep5").value.trim()||null,
      p_approval_workflow:document.getElementById("ep6").value,
      p_active:document.getElementById("epa").checked
    });
    closeModal();toast("Projekt gespeichert");await renderTab();
  }catch(e){toast(em(e))}}
}
function addProject(){
  showModal('<div class="between"><h3>Projekt anlegen</h3><button id="x" class="btn">✕</button></div><div class="field"><label class="label">Projektnummer *</label><input id="p1" class="input"></div><div class="field"><label class="label">Projektname *</label><input id="p3" class="input"></div><div class="field"><label class="label">Adresse</label><input id="p4" class="input"></div><div class="field"><label class="label">Bauherr / Kunde</label><input id="p5" class="input"></div><div class="field"><div class="labelrow"><label class="label">Freigabeablauf</label><button type="button" id="p6info" class="info-btn" aria-label="Freigabeablauf erklären" title="Freigabeablauf erklären">i</button></div><select id="p6" class="select"><option value="office_then_customer">Mit Büroprüfung – Büro prüft zuerst, danach unterschreibt der Kunde</option><option value="parallel_office_customer">Direkt zum Kunden – Kunde kann sofort unterschreiben, Büro wird informiert</option></select><div id="p6help" class="field-help hidden"><strong>Mit Büroprüfung:</strong> Das Büro muss die Regie zuerst bestätigen. Erst danach kann der Kunde unterschreiben.<br><br><strong>Direkt zum Kunden:</strong> Der Kunde kann sofort unterschreiben. Das Büro wird informiert, muss aber nicht zuerst bestätigen.</div></div><button id="ps" class="btn primary" style="width:100%">Speichern</button>');
  document.getElementById("x").onclick=closeModal;document.getElementById("p6info").onclick=()=>document.getElementById("p6help").classList.toggle("hidden");document.getElementById("ps").onclick=async()=>{try{const r=await sb.from("rf_projects").insert({company_id:S.companyId,project_number:document.getElementById("p1").value.trim(),name:document.getElementById("p3").value.trim(),address:document.getElementById("p4").value.trim()||null,client_name:document.getElementById("p5").value.trim()||null,approval_workflow:document.getElementById("p6").value,created_by:S.session.user.id});if(r.error)throw r.error;closeModal();toast("Projekt erstellt");await renderTab()}catch(e){toast(em(e))}}
}
async function projectCustomers(pid){
  const a=await Promise.all([sb.from("rf_projects").select("*").eq("id",pid).single(),sb.from("rf_customer_contacts").select("*").eq("company_id",S.companyId).order("active",{ascending:false}).order("full_name"),sb.from("rf_project_customer_access").select("*").eq("project_id",pid)]),p=a[0].data,contacts=a[1].data||[],access=a[2].data||[],map=new Map(access.map(x=>[x.customer_contact_id,x]));
  showModal('<div class="between"><div><h3 style="margin:0">Kunden & Freigabe</h3><div class="small muted">'+esc(p.name)+'</div></div><button id="x" class="btn">✕</button></div>' + contacts.map(x=>{const z=map.get(x.id);return'<div class="card" style="margin-top:10px;opacity:'+(x.active?"1":".62")+'"><div class="between"><div><strong>'+esc(x.full_name)+'</strong>'+(x.active?"":' <span class="status">Inaktiv</span>')+'<div class="small muted">'+esc(x.organization_name||x.email||"")+'</div></div><label class="small"><input type="checkbox" data-a="'+x.id+'" '+(z?"checked":"")+' '+(!x.active?"disabled":"")+'> Projekt</label></div><div class="row wrap" style="margin-top:8px"><label class="small"><input type="checkbox" data-s="'+x.id+'" '+(z&&z.can_sign?"checked":"")+' '+(!z||!x.active?"disabled":"")+'> Darf unterschreiben</label>'+(z&&!x.auth_user_id&&x.active?' <button class="btn" data-i="'+x.id+'">Konto einladen</button>':"")+'<button class="btn" data-ce="'+x.id+'">Bearbeiten</button></div></div>'}).join("")+'<hr style="border:0;border-top:1px solid var(--line);margin:18px 0"><h4>Neue Kundenperson</h4><div class="grid g2"><input id="cn" class="input" placeholder="Name"><input id="co" class="input" placeholder="Firma / Funktion"><input id="ce" class="input" type="email" placeholder="E-Mail"><input id="cp" class="input" placeholder="Telefon optional"></div><button id="ca" class="btn primary" style="margin-top:12px">Erstellen</button>');
  document.getElementById("x").onclick=closeModal;
  document.querySelectorAll("[data-a]").forEach(ch=>ch.onchange=async()=>{const id=ch.dataset.a,z=map.get(id);try{if(ch.checked&&!z){const r=await sb.from("rf_project_customer_access").insert({project_id:pid,customer_contact_id:id,can_sign:false});if(r.error)throw r.error}else if(!ch.checked&&z){const r=await sb.from("rf_project_customer_access").delete().eq("id",z.id);if(r.error)throw r.error}closeModal();await projectCustomers(pid)}catch(e){toast(em(e))}});
  document.querySelectorAll("[data-s]").forEach(ch=>ch.onchange=async()=>{const z=map.get(ch.dataset.s);if(!z)return;const r=await sb.from("rf_project_customer_access").update({can_sign:ch.checked}).eq("id",z.id);if(r.error)toast(em(r.error));else toast("Freigaberecht gespeichert")});
  document.querySelectorAll("[data-i]").forEach(b=>b.onclick=async()=>{try{const t=await rpc("rf_create_customer_invite",{p_customer_contact_id:b.dataset.i,p_valid_hours:168});share("Kundenkonto-Einladung",APP+"?invite="+encodeURIComponent(t))}catch(e){toast(em(e))}});
  document.querySelectorAll("[data-ce]").forEach(b=>b.onclick=()=>editCustomerContact(contacts.find(x=>x.id===b.dataset.ce),pid));
  document.getElementById("ca").onclick=async()=>{try{const r=await sb.from("rf_customer_contacts").insert({company_id:S.companyId,full_name:document.getElementById("cn").value.trim(),organization_name:document.getElementById("co").value.trim()||null,email:document.getElementById("ce").value.trim()||null,phone:document.getElementById("cp").value.trim()||null}).select("id").single();if(r.error)throw r.error;const z=await sb.from("rf_project_customer_access").insert({project_id:pid,customer_contact_id:r.data.id,can_sign:false});if(z.error)throw z.error;closeModal();await projectCustomers(pid)}catch(e){toast(em(e))}}
}
function editCustomerContact(x,pid){
  if(!x)return;
  showModal('<div class="between"><h3>Kundenperson bearbeiten</h3><button id="x" class="btn">✕</button></div><div class="field"><label class="label">Name</label><input id="ecn" class="input" value="'+esc(x.full_name||"")+'"></div><div class="field"><label class="label">Firma / Funktion</label><input id="eco" class="input" value="'+esc(x.organization_name||"")+'"></div><div class="field"><label class="label">E-Mail</label><input id="ece" class="input" type="email" value="'+esc(x.email||"")+'"></div><div class="field"><label class="label">Telefon</label><input id="ecp" class="input" value="'+esc(x.phone||"")+'"></div><label class="small"><input id="eca" type="checkbox" '+(x.active?"checked":"")+'> Aktiv</label><div class="notice warn" style="margin-top:12px">Wenn du eine Kundenperson deaktivierst, werden offene Freigabe- und Einladungslinks sofort ungültig. Historische Regien bleiben erhalten.</div><button id="ecs" class="btn primary" style="width:100%;margin-top:12px">Speichern</button>');
  document.getElementById("x").onclick=closeModal;
  document.getElementById("ecs").onclick=async()=>{try{
    await rpc("rf_update_customer_contact",{p_customer_contact_id:x.id,p_full_name:document.getElementById("ecn").value.trim(),p_organization_name:document.getElementById("eco").value.trim()||null,p_email:document.getElementById("ece").value.trim()||null,p_phone:document.getElementById("ecp").value.trim()||null,p_active:document.getElementById("eca").checked});
    closeModal();toast("Kundenperson gespeichert");await projectCustomers(pid)
  }catch(e){toast(em(e))}}
}
function share(title,link){showModal('<div class="between"><h3>'+esc(title)+'</h3><button id="x" class="btn">✕</button></div><p class="muted">Link kopieren und über deinen gewünschten Kanal senden.</p><div class="code">'+esc(link)+'</div><button id="copy" class="btn primary" style="margin-top:12px">Link kopieren</button>');document.getElementById("x").onclick=closeModal;document.getElementById("copy").onclick=async()=>{await navigator.clipboard.writeText(link);toast("Link kopiert")}}
async function newRegie(c){
  const p=await sb.from("rf_projects").select("id,project_number,name").eq("company_id",S.companyId).eq("active",true).order("project_number");if(p.error)throw p.error;
  c.innerHTML='<div class="card" style="max-width:720px;margin:auto"><h3>Neue Regie</h3><div class="field"><label class="label">Projekt *</label><select id="np" class="select">'+(p.data||[]).map(x=>'<option value="'+x.id+'">'+esc(x.project_number)+' · '+esc(x.name)+'</option>').join("")+'</select></div><div class="field"><label class="label">Vorher-Bild(er) *</label><input id="nf" class="input" type="file" accept="image/*" multiple capture="environment"><div class="small muted">Mindestens ein Bild von dem, was verändert werden muss.</div></div><div class="field"><label class="label">Beschreibung *</label><textarea id="nd" class="area"></textarea></div><div class="grid g2"><div class="field"><label class="label">Geschätzter Aufwand *</label><input id="ne" class="input" placeholder="z. B. ca. 1 Stunde"></div><div class="field"><label class="label">Minuten optional</label><input id="nm" class="input" type="number" min="1"></div></div><div class="notice warn">Nur eine unverbindliche Schätzung. Abrechnung nach effektivem Aufwand.</div><button id="ng" class="btn primary" style="width:100%;margin-top:14px">Absenden</button></div>';
  document.getElementById("ng").onclick=async()=>{const files=Array.from(document.getElementById("nf").files);if(!files.length)return toast("Mindestens ein Vorher-Bild ist Pflicht.");try{const o=await rpc("rf_create_internal_regie",{p_project_id:document.getElementById("np").value,p_description:document.getElementById("nd").value.trim(),p_estimate_label:document.getElementById("ne").value.trim(),p_estimate_minutes:Number(document.getElementById("nm").value)||null,p_assigned_monteur_user_id:null});for(const f of files)await upload({regieId:o.regieId,versionId:o.versionId,kind:"before",folder:"before",file:f});const st=await rpc("rf_submit_regie_version",{p_regie_id:o.regieId,p_version_id:o.versionId});toast("Gesendet: "+sl(st));S.tab="regies";renderShell();await renderTab()}catch(e){toast(em(e))}}
}
async function regies(c){
  const rows=await getRegies();
  const groups={
    open:rows.filter(r=>["customer_request","draft","submitted","internal_review","awaiting_customer"].includes(r.status)),
    running:rows.filter(r=>["approved","in_execution","work_completed","awaiting_rapport"].includes(r.status)),
    archive:rows.filter(r=>["closed","rejected"].includes(r.status))
  };
  const draw=key=>{
    document.querySelectorAll("[data-rfilt]").forEach(b=>b.classList.toggle("primary",b.dataset.rfilt===key));
    const box=document.getElementById("regieList");
    if(box){box.innerHTML=regieTable(groups[key]||rows);bindRows()}
  };
  c.innerHTML='<div class="card"><div class="between"><div><h3 style="margin:0">Regien</h3><div class="small muted">Offene, laufende und abgeschlossene Regien getrennt.</div></div>'+(has("regies.create")?'<button id="rn" class="btn primary">+ Neue Regie</button>':"")+'</div><div class="row wrap" style="margin-top:14px"><button class="btn primary" data-rfilt="open">Offen · '+groups.open.length+'</button><button class="btn" data-rfilt="running">Laufend · '+groups.running.length+'</button><button class="btn" data-rfilt="archive">Archiv · '+groups.archive.length+'</button></div><div id="regieList" style="margin-top:8px">'+regieTable(groups.open)+'</div></div>';
  document.querySelectorAll("[data-rfilt]").forEach(b=>b.onclick=()=>draw(b.dataset.rfilt));
  if(document.getElementById("rn"))document.getElementById("rn").onclick=async()=>{S.tab="new";renderShell();await renderTab()};
  bindRows();
}
async function openRegie(id){
  const r0=await sb.from("rf_regie_overview").select("*").eq("id",id).single();if(r0.error)return toast(em(r0.error));const r=r0.data;
  const a=await Promise.all([sb.from("rf_regie_versions").select("*").eq("regie_id",id).order("version_no",{ascending:false}),sb.from("rf_regie_files").select("*").eq("regie_id",id).order("created_at")]),vers=a[0].data||[],files=a[1].data||[],vids=vers.map(v=>v.id);let docs=[];if(vids.length){const d=await sb.from("rf_documents").select("*").in("version_id",vids).order("created_at",{ascending:false});docs=d.data||[]}
  const comments=await rpc("rf_get_regie_comments",{p_regie_id:id});
  const accessRes=await sb.from("rf_project_customer_access").select("customer_contact_id,can_sign,label").eq("project_id",r.project_id);
  const accessRows=accessRes.data||[],customerIds=accessRows.map(x=>x.customer_contact_id);
  let customerContacts=[];
  if(customerIds.length){
    const cr=await sb.from("rf_customer_contacts").select("id,full_name,organization_name,email").in("id",customerIds);
    customerContacts=cr.data||[];
  }
  let signatures=[];
  if(vids.length&&has("documents.view")){
    const sr=await sb.from("rf_customer_signatures").select("version_id,customer_contact_id,signer_name,decision,signed_at").in("version_id",vids).order("signed_at",{ascending:false});
    signatures=sr.data||[];
  }
  const pics=[];for(const f of files){try{pics.push({f:f,url:await signed(f.storage_path)})}catch{}}
  let acts="";if(r.status==="customer_request"&&has("regies.review"))acts+='<button id="reqok" class="btn primary">Anfrage übernehmen</button><button id="reqno" class="btn">Ablehnen</button>';
  if(r.status==="draft"&&has("regies.create")&&!r.current_version_id)acts+='<button id="prepare" class="btn primary">Regie aus Anfrage vorbereiten</button>';
  if(r.status==="draft"&&has("regies.create")&&r.current_version_id)acts+='<button id="editDraft" class="btn">Entwurf bearbeiten</button><button id="draftPhoto" class="btn">Vorher-Bild hinzufügen</button><button id="draftSubmit" class="btn primary">Zur Freigabe senden</button>';
  if(r.status==="internal_review"&&has("regies.review"))acts+='<button id="irok" class="btn primary">Büro bestätigt</button><button id="irno" class="btn">Ablehnen</button>';
  if(r.status==="awaiting_customer"&&has("regies.create"))acts+='<button id="link" class="btn primary">Kundenlink</button>';
  if(r.status==="approved"&&(has("regies.create")||has("regies.complete")))acts+='<button id="start" class="btn">Ausführung starten</button>';
  if(["approved","in_execution"].includes(r.status)&&has("regies.complete"))acts+='<button id="after" class="btn">Nachher-Bild</button><button id="donework" class="btn primary">Arbeit erledigt</button>';
  if(r.status==="awaiting_rapport"&&has("regies.close"))acts+='<button id="closeR" class="btn primary">Rapport-Nr. & abschliessen</button>';
  if(r.status!=="closed"&&r.status!=="customer_request"&&r.status!=="draft"&&has("regies.create"))acts+='<button id="rev" class="btn">Neue Version</button>';
  showModal('<div class="between"><div><div class="small muted">'+esc(r.project_number)+' · '+esc(r.project_name)+'</div><h2 style="margin:3px 0">'+esc(r.regie_code)+'</h2></div><span class="status '+esc(r.status)+'">'+esc(sl(r.status))+'</span></div><div class="tiny muted" style="margin-top:4px">Version '+esc(r.current_version_no||"—")+'</div><p>'+esc(r.description||"")+'</p>'+(r.rapport_number?'<p class="small"><strong>Rapportnummer:</strong> '+esc(r.rapport_number)+'</p>':"")+(r.estimate_label?'<div class="notice warn"><strong>Schätzung:</strong> '+esc(r.estimate_label)+'<br>'+esc(r.estimate_disclaimer||"")+'</div>':"")+'<div class="card" style="margin-top:14px;padding:14px"><div class="between"><strong>Kunde & Freigabe</strong><span class="small muted">'+esc(r.client_name||"")+'</span></div>'+(signatures.length?'<div class="notice ok" style="margin-top:10px"><strong>Freigegeben von '+esc(signatures[0].signer_name)+'</strong><div class="small">'+fmt(signatures[0].signed_at)+'</div></div>':"")+(customerContacts.length?'<div style="margin-top:8px">'+customerContacts.map(ct=>{const a=accessRows.find(x=>x.customer_contact_id===ct.id)||{};return '<div class="between" style="padding:8px 0;border-bottom:1px solid var(--line)"><div><strong>'+esc(ct.full_name)+'</strong><div class="small muted">'+esc(ct.organization_name||a.label||"Kontakt")+'</div></div><span class="status">'+(a.can_sign?"Freigabeberechtigt":"Kontakt")+'</span></div>'}).join("")+'</div>':'<div class="small muted" style="margin-top:8px">Keine Kontaktperson hinterlegt.</div>')+'</div>'+commentPanel(comments,["closed","rejected"].includes(r.status))+'<div class="photo-grid" style="margin-top:14px">'+pics.map(x=>'<div><img src="'+esc(x.url)+'"><div class="tiny muted">'+esc(x.f.kind)+'</div></div>').join("")+'</div><div class="row wrap" style="margin-top:15px">'+acts+'<button id="x" class="btn">Schliessen</button></div>'+(docs.length?'<hr style="border:0;border-top:1px solid var(--line);margin:18px 0"><h4>Dokumente</h4>'+docs.map(d=>'<button class="btn" data-doc="'+esc(d.storage_path)+'">'+esc(d.file_name)+'</button>').join(" "):""));
  document.getElementById("x").onclick=closeModal;document.querySelectorAll("[data-doc]").forEach(b=>b.onclick=async()=>window.open(await signed(b.dataset.doc),"_blank"));
  bindComment(id,openRegie);
  const click=async(id2,fn)=>{const el=document.getElementById(id2);if(el)el.onclick=fn};
  click("reqok",async()=>{try{await rpc("rf_decide_customer_request",{p_regie_id:id,p_decision:"approved",p_assigned_monteur_user_id:S.session.user.id});closeModal();toast("Anfrage übernommen");await renderTab()}catch(e){toast(em(e))}});
  click("reqno",async()=>{try{await rpc("rf_decide_customer_request",{p_regie_id:id,p_decision:"rejected",p_assigned_monteur_user_id:null});closeModal();toast("Abgelehnt");await renderTab()}catch(e){toast(em(e))}});
  click("prepare",()=>prepareCustomerDraft(r));
  click("editDraft",()=>editDraftDialog(r));
  click("draftPhoto",()=>beforePhotoDialog(r));
  click("draftSubmit",async()=>{try{const st=await rpc("rf_submit_regie_version",{p_regie_id:r.id,p_version_id:r.current_version_id});closeModal();toast("Gesendet: "+sl(st));await renderTab()}catch(e){toast(em(e))}});
  click("irok",async()=>{try{await rpc("rf_review_regie_version",{p_version_id:r.current_version_id,p_decision:"approved",p_note:null});closeModal();toast("Büroprüfung bestätigt");await renderTab()}catch(e){toast(em(e))}});
  click("irno",async()=>{try{await rpc("rf_review_regie_version",{p_version_id:r.current_version_id,p_decision:"rejected",p_note:null});closeModal();toast("Abgelehnt");await renderTab()}catch(e){toast(em(e))}});
  click("link",()=>approvalLink(r));click("start",async()=>{try{await rpc("rf_start_execution",{p_regie_id:id});closeModal();toast("Ausführung gestartet");await renderTab()}catch(e){toast(em(e))}});
  click("after",()=>afterDialog(r));click("donework",async()=>{try{await rpc("rf_mark_work_completed",{p_regie_id:id});closeModal();toast("Arbeit erledigt");await renderTab()}catch(e){toast(em(e))}});
  click("closeR",()=>closeDialog(r));click("rev",()=>revisionDialog(r))
}
async function approvalLink(r){
  const a=await sb.from("rf_project_customer_access").select("*").eq("project_id",r.project_id).eq("can_sign",true),ids=(a.data||[]).map(x=>x.customer_contact_id);
  if(!ids.length)return toast("Keine freigabeberechtigte Person hinterlegt.");
  const cr=await sb.from("rf_customer_contacts").select("id,full_name,organization_name").in("id",ids).eq("active",true);
  const contacts=cr.data||[];
  if(!contacts.length)return toast("Keine aktive freigabeberechtigte Person hinterlegt.");
  const lr=await sb.from("rf_public_approval_links").select("id,customer_contact_id,expires_at,created_at").eq("version_id",r.current_version_id).is("used_at",null).is("revoked_at",null).gt("expires_at",new Date().toISOString()).order("created_at",{ascending:false});
  const links=lr.data||[];
  showModal('<div class="between"><h3>Freigabelink</h3><button id="x" class="btn">✕</button></div><div class="field"><label class="label">Freigabeberechtigte Person</label><select id="who" class="select">'+contacts.map(x=>'<option value="'+x.id+'">'+esc(x.full_name)+' · '+esc(x.organization_name||"")+'</option>').join("")+'</select></div><button id="mk" class="btn primary" style="width:100%">Sicheren Link erstellen</button>'+(links.length?'<div class="notice warn" style="margin-top:12px"><strong>'+links.length+' aktiver Freigabelink</strong><br><span class="small">Falls ein Link falsch versendet wurde, kannst du alle noch unbenutzten Links dieser Version sofort ungültig machen.</span></div><button id="rvlinks" class="btn" style="width:100%;margin-top:8px">Aktive Links widerrufen</button>':""));
  document.getElementById("x").onclick=closeModal;
  document.getElementById("mk").onclick=async()=>{try{const t=await rpc("rf_create_public_approval_link",{p_version_id:r.current_version_id,p_customer_contact_id:document.getElementById("who").value,p_valid_hours:168});share("Freigabelink",APP+"?approve="+encodeURIComponent(t))}catch(e){toast(em(e))}};
  if(document.getElementById("rvlinks"))document.getElementById("rvlinks").onclick=async()=>{try{const n=await rpc("rf_revoke_public_approval_links",{p_version_id:r.current_version_id,p_customer_contact_id:null});closeModal();toast((n||0)+" Link(s) widerrufen.")}catch(e){toast(em(e))}}
}
function prepareCustomerDraft(r){showModal('<div class="between"><h3>Kundenanfrage vorbereiten</h3><button id="x" class="btn">✕</button></div><p class="muted">Beschreibung prüfen, Aufwand schätzen und danach mindestens ein Vorher-Bild aufnehmen.</p><div class="field"><label class="label">Beschreibung</label><textarea id="pd" class="area">'+esc(r.description||"")+'</textarea></div><div class="field"><label class="label">Geschätzter Aufwand</label><input id="pe" class="input" placeholder="z. B. ca. 1 Stunde"></div><div class="field"><label class="label">Minuten optional</label><input id="pm" class="input" type="number" min="1"></div><button id="pg" class="btn primary" style="width:100%">Version 1 erstellen</button>');document.getElementById("x").onclick=closeModal;document.getElementById("pg").onclick=async()=>{try{await rpc("rf_prepare_customer_request_draft",{p_regie_id:r.id,p_description:document.getElementById("pd").value.trim(),p_estimate_label:document.getElementById("pe").value.trim(),p_estimate_minutes:Number(document.getElementById("pm").value)||null});closeModal();toast("Entwurf vorbereitet");await openRegie(r.id)}catch(e){toast(em(e))}}}
function editDraftDialog(r){showModal('<div class="between"><h3>Entwurf bearbeiten</h3><button id="x" class="btn">✕</button></div><div class="field"><label class="label">Beschreibung</label><textarea id="ed" class="area">'+esc(r.description||"")+'</textarea></div><div class="field"><label class="label">Geschätzter Aufwand</label><input id="ee2" class="input" value="'+esc(r.estimate_label||"")+'"></div><button id="eg" class="btn primary" style="width:100%">Speichern</button>');document.getElementById("x").onclick=closeModal;document.getElementById("eg").onclick=async()=>{try{const z=await sb.from("rf_regie_versions").update({description:document.getElementById("ed").value.trim(),estimate_label:document.getElementById("ee2").value.trim()}).eq("id",r.current_version_id);if(z.error)throw z.error;closeModal();toast("Entwurf gespeichert");await openRegie(r.id)}catch(e){toast(em(e))}}}
function beforePhotoDialog(r){showModal('<div class="between"><h3>Vorher-Bild hinzufügen</h3><button id="x" class="btn">✕</button></div><p class="muted">Mindestens ein Bild von dem, was verändert werden muss, ist vor dem Absenden Pflicht.</p><input id="bf" class="input" type="file" accept="image/*" multiple capture="environment"><button id="bu" class="btn primary" style="margin-top:12px">Hochladen</button>');document.getElementById("x").onclick=closeModal;document.getElementById("bu").onclick=async()=>{const fs=Array.from(document.getElementById("bf").files);if(!fs.length)return toast("Bitte mindestens ein Bild wählen.");try{for(const f of fs)await upload({regieId:r.id,versionId:r.current_version_id,kind:"before",folder:"before",file:f});closeModal();toast("Vorher-Bild gespeichert");await openRegie(r.id)}catch(e){toast(em(e))}}}
function afterDialog(r){showModal('<div class="between"><h3>Nachher-Bild</h3><button id="x" class="btn">✕</button></div><input id="af" class="input" type="file" accept="image/*" capture="environment"><button id="au" class="btn primary" style="margin-top:12px">Hochladen</button>');document.getElementById("x").onclick=closeModal;document.getElementById("au").onclick=async()=>{const f=document.getElementById("af").files[0];if(!f)return;try{await upload({regieId:r.id,versionId:null,kind:"after",folder:"after",file:f});toast("Nachher-Bild gespeichert");closeModal();await openRegie(r.id)}catch(e){toast(em(e))}}}
function closeDialog(r){showModal('<div class="between"><h3>Abschliessen</h3><button id="x" class="btn">✕</button></div><p class="muted">Vor dem Abschluss ist die Rapportnummer des ausgeführten Arbeitsrapports erforderlich.</p><input id="rap" class="input" placeholder="Rapportnummer"><button id="cg" class="btn primary" style="margin-top:12px">Abschliessen</button>');document.getElementById("x").onclick=closeModal;document.getElementById("cg").onclick=async()=>{try{await rpc("rf_close_regie_v2",{p_regie_id:r.id,p_rapport_number:document.getElementById("rap").value});closeModal();toast("Abgeschlossen");await renderTab()}catch(e){toast(em(e))}}}
function revisionDialog(r){showModal('<div class="between"><h3>Neue Version</h3><button id="x" class="btn">✕</button></div><div class="notice">Die alte Version bleibt erhalten und die neue Version braucht eine neue Freigabe.</div><div class="field"><textarea id="rd" class="area">'+esc(r.description||"")+'</textarea></div><div class="field"><input id="re" class="input" value="'+esc(r.estimate_label||"")+'"></div><label class="small"><input id="rc" type="checkbox" checked> Vorher-Bilder übernehmen</label><button id="rg" class="btn primary" style="width:100%;margin-top:12px">Neue Version erstellen</button>');document.getElementById("x").onclick=closeModal;document.getElementById("rg").onclick=async()=>{try{await rpc("rf_create_regie_revision",{p_regie_id:r.id,p_description:document.getElementById("rd").value,p_estimate_label:document.getElementById("re").value,p_estimate_minutes:null,p_copy_before_photos:document.getElementById("rc").checked});closeModal();toast("Neue Version erstellt");await renderTab()}catch(e){toast(em(e))}}}
async function team(c){
  const a=await Promise.all([sb.from("rf_roles").select("*").eq("company_id",S.companyId).order("name"),sb.from("rf_memberships").select("*").eq("company_id",S.companyId).order("display_name"),sb.from("rf_permission_catalog").select("*").order("sort_order")]),roles=a[0].data||[],members=a[1].data||[],perms=a[2].data||[];
  const me=(S.ctx.internal||[]).find(x=>x.companyId===S.companyId),canTransfer=!!me?.isPrimaryOwner&&members.some(m=>m.active&&m.user_id!==S.session.user.id);
  c.innerHTML='<div class="grid g2"><div class="card"><div class="between"><h3>Benutzer</h3>'+(has("users.manage")?'<button id="addU" class="btn primary">+ Benutzer</button>':"")+'</div>'+members.map(m=>'<div style="padding:11px 0;border-bottom:1px solid var(--line)"><div class="between"><div><strong>'+esc(m.display_name)+'</strong><div class="small muted">'+(m.user_id===S.company.primary_owner_user_id?'Primary Owner · ':'')+esc((roles.find(r=>r.id===m.role_id)||{}).name||"Keine Rolle")+(m.active?"":" · Inaktiv")+'</div></div>'+(has("users.manage")&&m.user_id!==S.company.primary_owner_user_id?'<div class="row"><select class="select" style="width:auto" data-ur="'+m.id+'"><option value="">Keine Rolle</option>'+roles.map(r=>'<option value="'+r.id+'" '+(r.id===m.role_id?"selected":"")+'>'+esc(r.name)+'</option>').join("")+'</select>'+(m.user_id!==S.session.user.id?'<button class="btn" data-ua="'+m.id+'" data-active="'+(m.active?"1":"0")+'">'+(m.active?"Deaktivieren":"Aktivieren")+'</button>':"")+'</div>':"")+'</div></div>').join("")+(canTransfer?'<button id="ownerTransfer" class="btn" style="margin-top:14px">Primary Owner übertragen</button>':"")+'</div><div class="card"><div class="between"><h3>Rollen & Rechte</h3>'+(has("roles.manage")?'<button id="addR" class="btn">+ Rolle</button>':"")+'</div>'+roles.map(r=>'<div style="padding:11px 0;border-bottom:1px solid var(--line)"><div class="between"><strong>'+esc(r.name)+'</strong>'+(has("roles.manage")?'<button class="btn" data-er="'+r.id+'">Bearbeiten</button>':"")+'</div><div class="small muted" style="margin-top:4px">'+(r.permissions||[]).map(p=>esc((perms.find(x=>x.key===p)||{}).label_de||p)).join(" · ")+'</div></div>').join("")+'</div></div>';
  document.querySelectorAll("[data-ur]").forEach(s=>s.onchange=async()=>{try{await rpc("rf_set_member_role",{p_membership_id:s.dataset.ur,p_role_id:s.value||null});toast("Rolle gespeichert");await renderTab()}catch(e){toast(em(e));await renderTab()}});
  document.querySelectorAll("[data-ua]").forEach(b=>b.onclick=async()=>{try{const next=b.dataset.active!=="1";await rpc("rf_set_member_active",{p_membership_id:b.dataset.ua,p_active:next});toast(next?"Benutzer aktiviert":"Benutzer deaktiviert");await renderTab()}catch(e){toast(em(e))}});
  document.querySelectorAll("[data-er]").forEach(b=>{const role=roles.find(r=>r.id===b.dataset.er);if(role)b.onclick=()=>editRoleDialog(role,perms)});
  if(document.getElementById("addR"))document.getElementById("addR").onclick=()=>roleDialog(perms);
  if(document.getElementById("addU"))document.getElementById("addU").onclick=()=>userDialog(roles);
  if(document.getElementById("ownerTransfer"))document.getElementById("ownerTransfer").onclick=()=>ownerTransferDialog(members);
}
function roleDialog(perms){showModal('<div class="between"><h3>Neue Rolle</h3><button id="x" class="btn">✕</button></div><input id="rname" class="input" placeholder="z. B. Projektleiter">'+perms.map(p=>'<label style="display:block;padding:8px 0"><input type="checkbox" data-perm="'+esc(p.key)+'"> <strong>'+esc(p.label_de)+'</strong><div class="small muted" style="margin-left:22px">'+esc(p.description_de)+'</div></label>').join("")+'<button id="rsave" class="btn primary" style="width:100%">Erstellen</button>');document.getElementById("x").onclick=closeModal;document.getElementById("rsave").onclick=async()=>{try{const ps=Array.from(document.querySelectorAll("[data-perm]:checked")).map(x=>x.dataset.perm),r=await sb.from("rf_roles").insert({company_id:S.companyId,name:document.getElementById("rname").value.trim(),permissions:ps,created_by:S.session.user.id});if(r.error)throw r.error;closeModal();toast("Rolle erstellt");await renderTab()}catch(e){toast(em(e))}}}
function editRoleDialog(role,perms){
  showModal('<div class="between"><h3>Rolle bearbeiten</h3><button id="x" class="btn">✕</button></div><input id="ername" class="input" value="'+esc(role.name)+'">'+perms.map(p=>'<label style="display:block;padding:8px 0"><input type="checkbox" data-eperm="'+esc(p.key)+'" '+((role.permissions||[]).includes(p.key)?"checked":"")+'> <strong>'+esc(p.label_de)+'</strong><div class="small muted" style="margin-left:22px">'+esc(p.description_de)+'</div></label>').join("")+'<button id="ersave" class="btn primary" style="width:100%">Speichern</button>');
  document.getElementById("x").onclick=closeModal;
  document.getElementById("ersave").onclick=async()=>{try{
    const ps=Array.from(document.querySelectorAll("[data-eperm]:checked")).map(x=>x.dataset.eperm);
    const r=await sb.from("rf_roles").update({name:document.getElementById("ername").value.trim(),permissions:ps}).eq("id",role.id);
    if(r.error)throw r.error;closeModal();toast("Rolle gespeichert");await renderTab();
  }catch(e){toast(em(e))}}
}
function ownerTransferDialog(members){
  const targets=members.filter(m=>m.active&&m.user_id!==S.session.user.id);
  if(!targets.length)return toast("Kein anderer aktiver Benutzer verfügbar.");
  showModal('<div class="between"><h3>Primary Owner übertragen</h3><button id="x" class="btn">✕</button></div><div class="notice warn"><strong>Wichtig:</strong> Der ausgewählte Benutzer wird neuer Primary Owner und ist technisch geschützt. Dein Konto behält danach nur seine bereits zugewiesene Rolle und Rechte.</div><div class="field"><label class="label">Neuer Primary Owner</label><select id="newOwner" class="select">'+targets.map(m=>'<option value="'+m.user_id+'">'+esc(m.display_name)+'</option>').join("")+'</select></div><button id="ownerGo" class="btn primary" style="width:100%">Eigentümerschaft übertragen</button>');
  document.getElementById("x").onclick=closeModal;
  document.getElementById("ownerGo").onclick=async()=>{try{await rpc("rf_transfer_primary_owner",{p_company_id:S.companyId,p_new_owner_user_id:document.getElementById("newOwner").value});closeModal();toast("Primary Owner übertragen");await context()}catch(e){toast(em(e))}}
}
function userDialog(roles){showModal('<div class="between"><h3>Benutzer erstellen</h3><button id="x" class="btn">✕</button></div><div class="field"><input id="un" class="input" placeholder="Name"></div><div class="field"><input id="ue" class="input" type="email" placeholder="E-Mail"></div><div class="field"><select id="ur" class="select"><option value="">Keine Rolle</option>'+roles.map(r=>'<option value="'+r.id+'">'+esc(r.name)+'</option>').join("")+'</select></div><button id="ug" class="btn primary" style="width:100%">Konto erstellen</button>');document.getElementById("x").onclick=closeModal;document.getElementById("ug").onclick=async()=>{try{const o=await invoke("rf-create-internal-user",{companyId:S.companyId,email:document.getElementById("ue").value.trim(),displayName:document.getElementById("un").value.trim(),roleId:document.getElementById("ur").value||null});if(o.temporaryPassword){showModal('<h3>Benutzer erstellt</h3><p>Temporäres Passwort einmalig weitergeben:</p><div class="code">'+esc(o.temporaryPassword)+'</div><button id="ud" class="btn primary" style="margin-top:12px">Fertig</button>');document.getElementById("ud").onclick=async()=>{closeModal();await renderTab()}}else{closeModal();toast("Bestehendes Konto hinzugefügt");await renderTab()}}catch(e){toast(em(e))}}}
async function settings(c){
  c.innerHTML='<div class="grid g2"><div class="card"><h3>Firma & Branding</h3><div class="field"><label class="label">Anzeigename</label><input id="bn" class="input" value="'+esc(S.company.name)+'"></div><div class="field"><label class="label">Rechtlicher Firmenname</label><input id="blegal" class="input" value="'+esc(S.company.legal_name||"")+'" placeholder="z. B. Muster Elektro AG"></div><div class="field"><label class="label">Firmenadresse</label><input id="baddr" class="input" value="'+esc(S.company.address||"")+'"></div><div class="field"><label class="label">Akzentfarbe</label><input id="bc" class="input" type="color" value="'+esc(S.company.accent_color||"#111827")+'"></div><div class="field"><label class="label">Logo</label><input id="bl" class="input" type="file" accept="image/*"></div><button id="bs" class="btn primary">Speichern</button></div><div class="card"><h3>Abo</h3><div id="bill">Laden…</div></div><div class="card"><h3>Mein Konto</h3><div class="small muted" style="margin-bottom:12px">'+esc(S.session?.user?.email||"")+'</div><button id="mypw" class="btn">Passwort ändern</button></div></div>';
  try{const x=(await rpc("rf_billing_preview",{p_company_id:S.companyId})||[])[0];if(x){const pl={development:"Entwicklung",starter:"Starter",team:"Team",business:"Business",enterprise:"Enterprise"}[x.plan]||x.plan;document.getElementById("bill").innerHTML='<div class="metric">'+(x.plan==="development"?"CHF 0":"CHF "+x.estimated_monthly_chf)+'</div><div class="muted">'+esc(pl)+' · '+x.active_internal_profiles+' interne Profile</div><div class="small muted">Kundenkonten, Projekte und Regien werden nicht pro Stück verrechnet.</div>'+(x.plan!=="development"?'<button id="billingportal" class="btn" style="margin-top:12px">Abo & Rechnungen verwalten</button>':"");if(document.getElementById("billingportal"))document.getElementById("billingportal").onclick=async()=>{try{const o=await invoke("rf-billing-portal",{companyId:S.companyId});if(!o.url)throw new Error("Aboportal konnte nicht geöffnet werden.");location.href=o.url}catch(e){toast(em(e))}}}else document.getElementById("bill").innerHTML="Entwicklungsmodus"}catch{}
  document.getElementById("bs").onclick=async()=>{try{let lp=S.company.logo_path;const f=document.getElementById("bl").files[0];if(f){const ext=(f.name.split(".").pop()||"png").toLowerCase(),path=S.companyId+"/"+crypto.randomUUID()+"."+ext,r=await sb.storage.from("rf-branding").upload(path,f,{contentType:f.type,upsert:false});if(r.error)throw r.error;lp=path}const r=await sb.from("rf_companies").update({name:document.getElementById("bn").value.trim(),legal_name:document.getElementById("blegal").value.trim()||null,address:document.getElementById("baddr").value.trim()||null,accent_color:document.getElementById("bc").value,logo_path:lp}).eq("id",S.companyId).select().single();if(r.error)throw r.error;S.company=r.data;document.documentElement.style.setProperty("--accent",S.company.accent_color);S.logoUrl=lp?await signed(lp,"rf-branding"):null;toast("Gespeichert");renderShell();await renderTab()}catch(e){toast(em(e))}}
  document.getElementById("mypw").onclick=passwordDialog;
}
function passwordDialog(){
  showModal('<div class="between"><h3>Passwort ändern</h3><button id="x" class="btn">✕</button></div><div class="field"><label class="label">Neues Passwort</label><input id="pw1" class="input" type="password" autocomplete="new-password" placeholder="mindestens 10 Zeichen"></div><div class="field"><label class="label">Passwort wiederholen</label><input id="pw2" class="input" type="password" autocomplete="new-password"></div><button id="pws" class="btn primary" style="width:100%">Passwort speichern</button>');
  document.getElementById("x").onclick=closeModal;
  document.getElementById("pws").onclick=async()=>{
    const p1=document.getElementById("pw1").value,p2=document.getElementById("pw2").value;
    if(p1.length<10)return toast("Passwort muss mindestens 10 Zeichen lang sein.");
    if(p1!==p2)return toast("Die Passwörter stimmen nicht überein.");
    try{
      const r=await sb.auth.updateUser({password:p1});
      if(r.error)throw r.error;
      closeModal();toast("Passwort geändert.");
    }catch(e){toast(em(e))}
  };
}
async function accountPage(c){
  const cc=(S.ctx.customer||[]).find(x=>x.companyId===S.companyId);
  c.innerHTML='<div class="card" style="max-width:680px;margin:auto"><h3>Konto</h3><div class="field"><label class="label">Name</label><div>'+esc(cc?.fullName||"—")+'</div></div><div class="field"><label class="label">E-Mail</label><div>'+esc(S.session?.user?.email||"—")+'</div></div><button id="cpw" class="btn">Passwort ändern</button></div>';
  document.getElementById("cpw").onclick=passwordDialog;
}
async function notifications(c){
  const r=await sb.from("rf_notifications").select("*").order("created_at",{ascending:false}).limit(100);
  if(r.error)throw r.error;
  const rows=r.data||[],groups=[],byKey=new Map();
  for(const n of rows){
    const key=n.regie_id?"r:"+n.regie_id:"n:"+n.id;
    let g=byKey.get(key);
    if(!g){g={key,latest:n,count:0,unread:0,ids:[]};byKey.set(key,g);groups.push(g)}
    g.count++;g.ids.push(n.id);if(!n.read_at)g.unread++;
  }
  c.innerHTML='<div class="card"><div class="between"><h3 style="margin:0">Mitteilungen</h3><button id="read" class="btn">Alle gelesen</button></div><div class="notif-list">'+(groups.length?groups.map(g=>{const n=g.latest,title=nh(n.title),body=nh(n.body||""),showBody=body&&!body.startsWith("Status:")&&!body.startsWith("Der Status wurde");return '<button class="notif-item '+(g.unread?"unread":"")+'" data-ng="'+esc(g.key)+'" data-nregie="'+(n.regie_id||"")+'"><div class="notif-row"><div><div class="notif-title"><strong>'+esc(title)+'</strong></div>'+(showBody?'<div class="small muted" style="margin-top:3px">'+esc(body)+'</div>':"")+'<div class="tiny muted" style="margin-top:4px">'+fmt(n.created_at)+(g.count>1?' · '+g.count+' Ereignisse':"")+'</div></div>'+(n.regie_id?'<span class="notif-arrow">›</span>':"")+'</div></button>'}).join(""):'<div class="empty">Keine Mitteilungen.</div>')+'</div>';
  document.querySelectorAll("[data-ng]").forEach(el=>el.onclick=async()=>{
    const key=el.dataset.ng,rid=el.dataset.nregie,g=byKey.get(key);
    if(g&&g.unread){
      let q=sb.from("rf_notifications").update({read_at:new Date().toISOString()}).is("read_at",null);
      if(rid)q=q.eq("regie_id",rid);else q=q.in("id",g.ids);
      const z=await q;if(z.error)return toast(em(z.error));
      S.unread=Math.max(0,S.unread-g.unread);
    }
    if(!rid)return renderTab();
    if(S.kind==="internal"){
      S.tab="regies";renderShell();await renderTab();await openRegie(rid);
    }else{
      S.tab="home";renderShell();await renderTab();await customerRegie(rid);
    }
  });
  document.getElementById("read").onclick=async()=>{
    const z=await sb.from("rf_notifications").update({read_at:new Date().toISOString()}).is("read_at",null);
    if(z.error)return toast(em(z.error));
    S.unread=0;renderShell();await renderTab();
  };
}
async function customerRows(){const r=await sb.from("rf_regie_overview").select("*").eq("company_id",S.companyId).order("updated_at",{ascending:false});if(r.error)throw r.error;return r.data||[]}
function cards(rows){if(!rows.length)return'<div class="empty">Keine Aufträge.</div>';return rows.map(r=>'<div class="click" data-cr="'+r.id+'" style="padding:12px 0;border-bottom:1px solid var(--line)"><div class="between"><strong>'+esc(r.regie_code)+'</strong><span class="status '+esc(r.status)+'">'+esc(csl(r.status))+'</span></div><div class="small">'+esc(r.description||"")+'</div><div class="tiny muted">'+esc(r.project_number)+' · '+fmt(r.updated_at)+'</div></div>').join("")}
function bindCards(){document.querySelectorAll("[data-cr]").forEach(x=>x.onclick=()=>customerRegie(x.dataset.cr))}
async function customerHome(c){const rows=await customerRows(),o=rows.filter(r=>["customer_request","draft","internal_review","awaiting_customer"].includes(r.status)),p=rows.filter(r=>["approved","in_execution","awaiting_rapport"].includes(r.status));c.innerHTML='<div class="hero"><h2 style="margin:0 0 6px">Meine Aufträge</h2><div style="opacity:.8">Freigaben, laufende Arbeiten und Dokumente an einem Ort.</div></div><div class="grid g2" style="margin-top:14px"><div class="card"><h3>Offen</h3>'+cards(o)+'</div><div class="card"><h3>In Bearbeitung</h3>'+cards(p)+'</div></div>';bindCards()}
async function customerArchive(c){const rows=(await customerRows()).filter(r=>["closed","rejected"].includes(r.status));c.innerHTML='<div class="card"><h3>Archiv</h3>'+cards(rows)+'</div>';bindCards()}
async function customerRequest(c){
  const p=await sb.from("rf_projects").select("id,project_number,name").eq("company_id",S.companyId).eq("active",true).order("project_number");if(p.error)throw p.error;
  c.innerHTML='<div class="card" style="max-width:680px;margin:auto"><h3>Auftrag erstellen</h3><div class="field"><label class="label">Projekt</label><select id="cpj" class="select">'+(p.data||[]).map(x=>'<option value="'+x.id+'">'+esc(x.project_number)+' · '+esc(x.name)+'</option>').join("")+'</select></div><div class="field"><label class="label">Was soll gemacht werden?</label><textarea id="cd" class="area"></textarea></div><div class="field"><label class="label">Foto optional</label><input id="cf" class="input" type="file" accept="image/*" capture="environment"></div><button id="cs" class="btn primary" style="width:100%">Anfrage senden</button></div>';
  document.getElementById("cs").onclick=async()=>{try{const id=await rpc("rf_create_customer_request",{p_project_id:document.getElementById("cpj").value,p_description:document.getElementById("cd").value.trim()}),f=document.getElementById("cf").files[0];if(f)await upload({regieId:id,versionId:null,kind:"customer_request",folder:"customer-request",file:f});toast("Anfrage gesendet");S.tab="home";renderShell();await renderTab()}catch(e){toast(em(e))}}
}
async function customerRegie(id){
  const a=await Promise.all([sb.from("rf_regie_overview").select("*").eq("id",id).single(),sb.from("rf_regie_files").select("*").eq("regie_id",id).order("created_at"),sb.from("rf_regie_versions").select("*").eq("regie_id",id).order("version_no",{ascending:false})]),r=a[0].data,files=a[1].data||[],vers=a[2].data||[],vids=vers.map(v=>v.id);if(a[0].error)return toast(em(a[0].error));let docs=[];if(vids.length){const d=await sb.from("rf_documents").select("*").in("version_id",vids).order("created_at",{ascending:false});docs=d.data||[]}
  const comments=await rpc("rf_get_regie_comments",{p_regie_id:id});
  const pics=[];for(const f of files){try{pics.push({f:f,url:await signed(f.storage_path)})}catch{}}
  const cc=(S.ctx.customer||[]).find(x=>x.companyId===S.companyId);let can=false;if(r.status==="awaiting_customer"&&cc){const z=await sb.from("rf_project_customer_access").select("can_sign").eq("project_id",r.project_id).eq("customer_contact_id",cc.customerContactId).eq("can_sign",true).maybeSingle();can=!!z.data}
  showModal('<div class="between"><div><div class="small muted">'+esc(r.project_number)+' · '+esc(r.project_name)+'</div><h2 style="margin:3px 0">'+esc(r.regie_code)+'</h2></div><span class="status '+esc(r.status)+'">'+esc(csl(r.status))+'</span></div><div class="tiny muted" style="margin-top:4px">Version '+esc(r.current_version_no||"—")+'</div><p>'+esc(r.description||"")+'</p>'+(r.rapport_number?'<p class="small"><strong>Rapportnummer:</strong> '+esc(r.rapport_number)+'</p>':"")+(r.estimate_label?'<div class="notice warn"><strong>Schätzung:</strong> '+esc(r.estimate_label)+'<br>'+esc(r.estimate_disclaimer||"")+'</div>':"")+commentPanel(comments,["closed","rejected"].includes(r.status))+'<div class="photo-grid" style="margin-top:14px">'+pics.map(x=>'<div><img src="'+esc(x.url)+'"><div class="tiny muted">'+esc(x.f.kind)+'</div></div>').join("")+'</div><div class="row wrap" style="margin-top:15px">'+(can?'<button id="sign" class="btn primary">Freigeben / ablehnen</button>':"")+'<button id="x" class="btn">Schliessen</button></div>'+(docs.length?'<hr style="border:0;border-top:1px solid var(--line);margin:18px 0"><h4>PDF-Archiv</h4>'+docs.map(d=>'<button class="btn" data-cdoc="'+esc(d.storage_path)+'">'+esc(d.file_name)+'</button>').join(" "):""));
  document.getElementById("x").onclick=closeModal;document.querySelectorAll("[data-cdoc]").forEach(b=>b.onclick=async()=>window.open(await signed(b.dataset.cdoc),"_blank"));bindComment(id,customerRegie);if(document.getElementById("sign"))document.getElementById("sign").onclick=()=>signDialog(r)
}
function signDialog(r){const cc=(S.ctx.customer||[]).find(x=>x.companyId===S.companyId);showModal('<div class="between"><h3>Regie freigeben</h3><button id="x" class="btn">✕</button></div><p>'+esc(r.description||"")+'</p><div class="field"><label class="label">Unterzeichnende Person</label><input id="csn" class="input" readonly value="'+esc(cc?cc.fullName:"")+'"></div><div class="field"><div class="between"><label class="label">Unterschrift</label><button id="clr" class="btn">Löschen</button></div><canvas id="css" class="sig"></canvas></div><label class="small" style="display:flex;gap:8px;align-items:flex-start;margin-bottom:12px"><input id="csconsent" type="checkbox" style="margin-top:3px"><span>Ich bestätige, dass ich für dieses Projekt zur Freigabe berechtigt bin und die dargestellte Regie in dieser Version freigebe.</span></label><div class="grid g2"><button id="rej" class="btn">Ablehnen</button><button id="appv" class="btn primary">Bestätigen & unterschreiben</button></div>');document.getElementById("x").onclick=closeModal;const s=sig("css");document.getElementById("clr").onclick=()=>s.clear();document.getElementById("rej").onclick=async()=>{try{await invoke("rf-auth-approval",{versionId:r.current_version_id,action:"reject",signerName:document.getElementById("csn").value});closeModal();toast("Abgelehnt");await renderTab()}catch(e){toast(em(e))}};document.getElementById("appv").onclick=async()=>{if(!s.ok)return toast("Bitte unterschreiben.");try{if(!document.getElementById("csconsent").checked)return toast("Bitte die Freigabeerklärung bestätigen.");const o=await invoke("rf-auth-approval",{versionId:r.current_version_id,action:"approve",signerName:document.getElementById("csn").value,signatureDataUrl:s.data(),consentAccepted:true});closeModal();toast("Freigabe bestätigt");if(o.pdfUrl)window.open(o.pdfUrl,"_blank");await renderTab()}catch(e){toast(em(e))}}}
init().catch(e=>{app.innerHTML='<div class="auth"><div class="notice bad">'+esc(em(e))+'</div></div>'});
