const APP="https://regieflow.pages.dev/";
const API="https://kiihabzzepoehsokglzq.supabase.co/functions/v1";

function ok(name,cond,detail=""){
  if(!cond)throw new Error("FAIL "+name+(detail?": "+detail:""));
  console.log("PASS",name);
}

const page=await fetch(APP,{redirect:"follow"});
ok("frontend HTTP 200",page.status===200,String(page.status));
const html=await page.text();
ok("frontend app shell",html.includes('id="app"'));
ok("frontend external app.js",html.includes('src="app.js"'));

const csp=page.headers.get("content-security-policy")||"";
ok("CSP present",!!csp);
ok("CSP blocks framing",csp.includes("frame-ancestors 'none'"));
ok("no unsafe-inline scripts",!csp.includes("script-src 'self' 'unsafe-inline'"));
ok("no-referrer policy",(page.headers.get("referrer-policy")||"").toLowerCase()==="no-referrer");

const js=await fetch(APP+"app.js",{cache:"no-store"});
ok("app.js HTTP 200",js.status===200,String(js.status));
ok("app.js non-empty",(await js.text()).length>50000);

const health=await fetch(API+"/rf-health",{cache:"no-store"});
const h=await health.json();
ok("API health HTTP 200",health.status===200,JSON.stringify(h));
ok("database health",h?.checks?.database===true,JSON.stringify(h));
ok("storage health",h?.checks?.storage===true,JSON.stringify(h));
ok("integrity health",h?.checks?.integrity===true,JSON.stringify(h));

const readiness=await fetch(API+"/rf-billing-readiness",{cache:"no-store"});
const rd=await readiness.json();
ok("readiness endpoint HTTP 200",readiness.status===200,JSON.stringify(rd));
console.log("READINESS",JSON.stringify(rd));

const legal=await fetch(API+"/rf-public-legal",{
  method:"POST",
  headers:{"Content-Type":"application/json"},
  body:"{}"
});
ok("public legal endpoint HTTP 200",legal.status===200,String(legal.status));
console.log("LEGAL",JSON.stringify(await legal.json()));

const manifest=await fetch(APP+"manifest.webmanifest",{cache:"no-store"});
ok("manifest HTTP 200",manifest.status===200,String(manifest.status));
const sw=await fetch(APP+"sw.js",{cache:"no-store"});
ok("service worker HTTP 200",sw.status===200,String(sw.status));

const robots=await fetch(APP+"robots.txt",{cache:"no-store"});
ok("robots HTTP 200",robots.status===200,String(robots.status));
const robotsText=await robots.text();
ok("development indexing disabled",robotsText.includes("Disallow: /"));

const pushDenied=await fetch(API+"/rf-push",{
  method:"POST",
  headers:{"Content-Type":"application/json"},
  body:JSON.stringify({notificationId:"00000000-0000-0000-0000-000000000000"})
});
ok("push private hook enforced",pushDenied.status===403,String(pushDenied.status));

const webhookDenied=await fetch(API+"/rf-stripe-webhook",{
  method:"POST",
  headers:{"Content-Type":"application/json"},
  body:"{}"
});
// Before Stripe secrets are installed the endpoint deliberately returns 503;
// after configuration, an unsigned request must be rejected as 400.
ok("Stripe webhook unavailable or signature-protected",[400,503].includes(webhookDenied.status),String(webhookDenied.status));

const retired=await Promise.all([
  fetch(API+"/rf-dev-company-setup",{method:"POST",headers:{"Content-Type":"application/json"},body:"{}"}),
  fetch(API+"/rf-app"),
  fetch(API+"/rf-publish-static")
]);
ok("retired endpoints are not anonymous",retired.every(r=>[401,403,410].includes(r.status)),retired.map(r=>r.status).join(","));

console.log("RegieFlow public smoke test complete.");
