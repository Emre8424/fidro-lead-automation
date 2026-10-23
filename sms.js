var SMS_STATE=null,SMS_PREVIEW=null;
async function loadSms(){try{SMS_STATE=await call('/sms/status');var s=SMS_STATE;renderSmsDashboardTest(s.dashboard_test);renderSmsCampaign(s.campaign);document.getElementById('smsSetup').textContent=(s.credentials_present?'Anbieterzugang hinterlegt':'Anbieterzugang fehlt')+' · '+(s.enabled&&s.sender_verified?'Versand freigegeben':'Versand noch gesperrt')+' · Reserviert CHF '+Number(s.reserved_chf).toFixed(2)+' / 30.00 · '+s.leads.filter(function(l){return !l.blocks.length&&!l.dispatch}).length+' Kontakte mit SMS-Bestätigung';document.getElementById('smsLead').innerHTML='<option value="">Kontakt auswählen</option>'+s.leads.map(function(l){return '<option value="'+esc(l.id)+'">'+esc(l.name||l.phone)+' · '+esc(l.dispatch?l.dispatch.status:l.blocks.length?'Noch gesperrt':l.consent&&l.consent.evidence_kind==='operator_attestation'?'SMS bestätigt (Betreiberangabe)':'Einwilligung erfasst')+'</option>'}).join('');smsSelect()}catch(e){document.getElementById('smsSetup').textContent='SMS nicht verfügbar: '+e.message;SMS_STATE=null;document.getElementById('smsSend').disabled=true}}
function smsSelected(){var id=document.getElementById('smsLead').value;return SMS_STATE&&SMS_STATE.leads.find(function(l){return l.id===id})}
function smsSelect(){SMS_PREVIEW=null;document.getElementById('smsSend').disabled=true;document.getElementById('smsPreview').textContent='Noch keine Vorschau.';var l=smsSelected();document.getElementById('smsLeadState').textContent=l?(l.blocks.join(' · ')||'SMS-Einwilligung als Operator-Angabe erfasst')+(l.dispatch?' · Versandstatus: '+l.dispatch.status:''):'';renderSmsConsentEvidence(l);document.getElementById('smsConsentText').value=l&&l.consent?(l.consent.consent_text||''):'';document.getElementById('smsConsentRef').value=l&&l.consent?l.consent.evidence_reference:'';document.getElementById('smsConsentAt').value=''}
async function saveSmsConsent(){var l=smsSelected();if(!l)return toast('Kontakt auswählen');var at=document.getElementById('smsConsentAt').value;if(!at)return toast('Ursprüngliches Zustimmungsdatum fehlt');try{await call('/sms/consent',{method:'POST',body:JSON.stringify({lead_id:l.id,text:document.getElementById('smsConsentText').value,reference:document.getElementById('smsConsentRef').value,at:new Date(at).toISOString()})});toast('SMS-Einwilligung dokumentiert');await loadSms()}catch(e){toast(e.message)}}
async function previewSms(){var l=smsSelected();if(!l)return toast('Kontakt auswählen');document.getElementById('smsSend').disabled=true;SMS_PREVIEW=null;try{var p=await call('/sms/preview',{method:'POST',body:JSON.stringify({lead_id:l.id})});if(!smsSelected()||smsSelected().id!==p.lead_id)return;SMS_PREVIEW=p;document.getElementById('smsPreview').textContent=p.body+'\n\n'+p.segments+' SMS · Reservierung CHF '+p.reserve_chf.toFixed(2)+(p.blocks.length?'\nNoch offen: '+p.blocks.join('; '):'');document.getElementById('smsSend').disabled=!!p.blocks.length}catch(e){toast(e.message)}}
async function sendSms(){var p=SMS_PREVIEW,l=smsSelected();if(!p||p.blocks.length||!l||l.id!==p.lead_id)return;if(!confirm('Diese SMS an '+p.phone+' senden? CHF 0.30 werden vom Budget reserviert.'))return;document.getElementById('smsSend').disabled=true;SMS_PREVIEW=null;try{var r=await call('/sms/send',{method:'POST',body:JSON.stringify({lead_id:p.lead_id,body:p.body,confirm:true})});document.getElementById('smsPreview').textContent=r.message;toast(r.message)}catch(e){document.getElementById('smsPreview').textContent=e.message+' Bei unklarem Ergebnis zuerst das Anbieterprotokoll prüfen.';toast(e.message)}}
async function smsOptOut(){var l=smsSelected();if(!l)return toast('Kontakt auswählen');if(!confirm('Kontakt kanalübergreifend abmelden und sperren?'))return;try{await call('/lead-status',{method:'POST',body:JSON.stringify({id:l.id,status:'opted_out'})});await loadSms();toast('Abmeldung gespeichert')}catch(e){toast(e.message)}}


var SMS_TEST_REFRESH=null;
function smsRelayLabel(t){
 var r=t.relay;
 if(r&&r.delivered_at)return 'Zugestellt · '+new Date(r.delivered_at).toLocaleString('de-CH');
 if(r)return ({queued:'Wartet auf Versandprozess · Start kann einige Minuten dauern.',claimed:'Versandprozess arbeitet · bitte nicht erneut senden.',accepted:'An ASPSMS übergeben · Zustellung noch nicht bestätigt.',rejected:'Versand abgelehnt · bitte Protokoll prüfen.',unknown:'Versandergebnis unklar · Anbieterprotokoll prüfen. Nicht erneut senden.'})[r.status]||r.status;
 return t.attempt?'Test bereits protokolliert.':'Bereit für deinen Verbindungstest. Kundenversand bleibt gesperrt.';
}
function renderSmsDashboardTest(t){
 if(!t)return;var el=document.getElementById('smsDashboardTest');
 if(!el){el=document.createElement('div');el.id='smsDashboardTest';el.className='card';document.getElementById('smsSetup').parentNode.insertBefore(el,document.getElementById('smsSetup').nextSibling);}
 el.innerHTML='<h3>Test an eigene Nummer</h3><p>+41 76 769 38 38 · geschützte Serveranbindung</p><pre>'+esc(t.body)+'</pre><div class="actions"><button id="smsDashboardTestSend" onclick="sendSmsDashboardTest()" '+(t.attempt||!t.available?'disabled':'')+'>Test-SMS an meine Nummer senden</button><button class="secondary" onclick="loadSms()">Versandstatus aktualisieren</button></div><p id="smsDashboardTestResult" role="status">'+esc(smsRelayLabel(t))+'</p>';
 if(SMS_TEST_REFRESH)clearTimeout(SMS_TEST_REFRESH);
 if(t.relay&&['queued','claimed'].includes(t.relay.status))SMS_TEST_REFRESH=setTimeout(loadSms,15000);
}

async function sendSmsDashboardTest(){
 var t=SMS_STATE&&SMS_STATE.dashboard_test;if(!t||t.attempt||!t.available)return;
 document.getElementById('smsDashboardTestSend').disabled=true;
 document.getElementById('smsDashboardTestResult').textContent='Test wird gesendet …';
 try{var r=await call('/sms/test',{method:'POST',body:JSON.stringify({phone:t.phone,body:t.body,confirm:true})});document.getElementById('smsDashboardTestResult').textContent=r.message;t.attempt={status:r.status};SMS_TEST_REFRESH=setTimeout(loadSms,10000);}
 catch(e){document.getElementById('smsDashboardTestResult').textContent=e.message+' Bitte Anbieterprotokoll prüfen, bevor ein weiterer Versuch erfolgt.';}
}


function renderSmsConsentEvidence(l){
 var node=document.getElementById('smsConsentEvidence');
 if(!node){node=document.createElement('p');node.id='smsConsentEvidence';node.className='muted';document.getElementById('smsLeadState').insertAdjacentElement('afterend',node);}
 var c=l&&l.consent;
 if(!c){node.textContent='';return;}
 if(c.evidence_kind==='operator_attestation')node.textContent='Betreiberbestätigung, erfasst am '+new Date(c.attested_at||c.recorded_at).toLocaleString('de-CH')+'. '+c.attestation_text+' Quelle: '+c.evidence_reference;
 else node.textContent='Einwilligung als Operator-Angabe dokumentiert. Ursprüngliches Datum: '+(c.consent_at?new Date(c.consent_at).toLocaleString('de-CH'):'nicht angegeben')+'. Quelle: '+c.evidence_reference;
}

var SMS_CAMPAIGN_STATE=null,SMS_CAMPAIGN_REFRESH=null;
function renderSmsCampaign(c){
 if(!c)return;SMS_CAMPAIGN_STATE=c;
 var el=document.getElementById('smsCampaign');
 if(!el){el=document.createElement('div');el.id='smsCampaign';el.className='card';document.getElementById('smsSetup').insertAdjacentElement('afterend',el);}
 el.innerHTML='<h3>SMS-Erstkontakt starten</h3><p>'+c.ready+' freigegebene, noch nicht kontaktierte Leads · Reservierung CHF '+Number(c.reserve_chf).toFixed(2)+'</p>'+(c.example?'<pre>'+esc(c.example)+'</pre>':'')+'<div class="actions"><button id="smsCampaignStart" onclick="startSmsCampaign()" '+(!c.ready?'disabled':'')+'>SMS-Versand an '+c.ready+' neue Leads starten</button><button class="secondary" onclick="loadSms()">Kampagnenstatus aktualisieren</button></div><p id="smsCampaignResult" role="status">Warteschlange: '+c.queued+' · In Bearbeitung: '+c.processing+' · Übergeben: '+c.accepted+' · Zugestellt: '+c.delivered+' · Abgelehnt: '+c.rejected+' · Unklar: '+c.unknown+(c.funding_paused?'<br><b>Wartet auf Guthaben · zuletzt '+Number(c.credits_at_pause).toFixed(2)+' Anbieter-Credits.</b>':'')+'</p><p class="muted">Versand nur mit vorhandenem Guthaben. Keine automatische Aufladung. Bestehende Gespräche bleiben unberührt. Antworten und STOP am Absender-Handy sowie Abmeldungen an ed@fidro.ch manuell bearbeiten und im Dashboard sperren.</p>';
 if(SMS_CAMPAIGN_REFRESH)clearTimeout(SMS_CAMPAIGN_REFRESH);
 if((c.queued||c.processing)&&!c.funding_paused)SMS_CAMPAIGN_REFRESH=setTimeout(loadSms,15000);
}
async function startSmsCampaign(){
 var c=SMS_CAMPAIGN_STATE;if(!c||!c.ready)return;
 if(!confirm(c.ready+' neue, freigegebene Leads per SMS kontaktieren? CHF '+Number(c.reserve_chf).toFixed(2)+' werden reserviert. Versand mit vorhandenem Anbieter-Guthaben; keine automatische Aufladung.'))return;
 document.getElementById('smsCampaignStart').disabled=true;
 document.getElementById('smsCampaignResult').textContent='SMS-Kampagne wird gestartet …';
 try{var r=await call('/sms/campaign-start',{method:'POST',body:JSON.stringify({confirm:true,scope:'new_ready',expected_count:c.ready})});document.getElementById('smsCampaignResult').textContent=r.message;SMS_CAMPAIGN_REFRESH=setTimeout(loadSms,5000);}
 catch(e){document.getElementById('smsCampaignResult').textContent=e.message+' Status aktualisieren, bevor erneut gestartet wird.';}
}
