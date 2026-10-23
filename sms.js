var SMS_STATE=null,SMS_PREVIEW=null;
async function loadSms(){try{SMS_STATE=await call('/sms/status');var s=SMS_STATE;renderSmsDashboardTest(s.dashboard_test);renderSmsCampaign(s.campaign);renderSmsHistory(s.history);document.getElementById('smsSetup').textContent=(s.credentials_present?'Anbieterzugang hinterlegt':'Anbieterzugang fehlt')+' · '+(s.campaign&&s.campaign.paused?'SMS pausiert – Textprüfung':s.enabled&&s.sender_verified?'Versand freigegeben':'Versand noch gesperrt')+' · Reserviert CHF '+Number(s.reserved_chf).toFixed(2)+' / 30.00 · '+s.leads.filter(function(l){return !l.blocks.length}).length+' Kontakte mit SMS-Bestätigung';document.getElementById('smsLead').innerHTML='<option value="">Kontakt auswählen</option>'+s.leads.map(function(l){return '<option value="'+esc(l.id)+'">'+esc(l.name||l.phone)+' · '+esc(l.dispatch?l.dispatch.status:l.blocks.length?'Noch gesperrt':l.consent&&l.consent.evidence_kind==='operator_attestation'?'SMS bestätigt (Betreiberangabe)':'Einwilligung erfasst')+'</option>'}).join('');smsSelect()}catch(e){document.getElementById('smsSetup').textContent='SMS nicht verfügbar: '+e.message;SMS_STATE=null;document.getElementById('smsSend').disabled=true}}
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
 if(!c)return;SMS_CAMPAIGN_STATE=c;var el=document.getElementById('smsCampaign');
 if(!el){el=document.createElement('div');el.id='smsCampaign';el.className='card';document.getElementById('smsSetup').insertAdjacentElement('afterend',el);}
 var draft=c.draft,active=draft&&draft.status==='active';
 el.innerHTML='<h3>'+(c.paused?'Korrigierte V5 freigeben':'SMS-Versand · korrigierte V5 aktiv')+'</h3><p id="smsCampaignResult" role="status">Zugestellt gesamt: '+c.delivered+' · davon V5: '+(c.v5_delivered||0)+' · V5 übergeben: '+(c.v5_accepted||0)+' · Warteschlange: '+c.queued+' · In Bearbeitung: '+c.processing+' · Wegen Budget zurückgestellt: '+(c.budget_held||0)+'</p>'+
 (c.funding_paused?'<p><b>Wartet auf Anbieter-Guthaben · zuletzt '+Number(c.credits_at_pause).toFixed(2)+' Credits. Keine automatische Aufladung.</b></p>':'')+
 (draft?'<h4>'+esc(draft.version)+' · '+(active?'Aktiver Text':'Freigegebener Entwurf')+'</h4><pre>'+esc(draft.body)+'</pre><p><b>'+draft.min_segments+' SMS-Teile pro Kontakt</b> · vorsorgliche Reservierung CHF '+Number((draft.min_segments||4)*0.3).toFixed(2)+' pro Kontakt; kein bestätigter Anbieterpreis.</p>':'')+
 (c.paused?'<p>'+c.resume_count+' wartende Kontakte passen in das 30-CHF-Limit. '+c.budget_hold_after+' werden zurückgestellt. Gesamtreservierung danach CHF '+Number(c.resume_total_reserve_chf).toFixed(2)+'. Die fünf bereits angeschriebenen Kontakte werden nicht erneut angeschrieben.</p>':'')+
 '<div class="actions">'+(c.paused&&c.pending_count?'<button id="smsV5Resume" onclick="resumeSmsV5()">V5 anwenden und '+c.resume_count+' Kontakte freigeben</button>':'<button disabled>V5 aktiv</button>')+'<button class="secondary" onclick="loadSms()">Versandstatus aktualisieren</button><button class="secondary" onclick="document.getElementById(\'smsHistory\').scrollIntoView({behavior:\'smooth\'})">SMS-Verlauf ansehen</button></div><p class="muted">Kein „letzte 50“-Text. Keine erneute Nachricht an bereits angeschriebene Kontakte. Versand nur mit vorhandenem Guthaben. Die 30-CHF-Grenze bleibt bestehen.</p>';
 if(SMS_CAMPAIGN_REFRESH)clearTimeout(SMS_CAMPAIGN_REFRESH);
 if(!c.paused&&(c.queued||c.processing)&&!c.funding_paused)SMS_CAMPAIGN_REFRESH=setTimeout(loadSms,15000);
}
async function resumeSmsV5(){
 var c=SMS_CAMPAIGN_STATE;if(!c||!c.paused||!c.pending_count)return;
 if(!confirm('Korrigierte V5 mit '+c.draft.min_segments+' SMS-Teilen pro Kontakt verwenden? '+c.resume_count+' Kontakte freigeben, '+c.budget_hold_after+' wegen Budget zurückstellen. Gesamtreservierung CHF '+Number(c.resume_total_reserve_chf).toFixed(2)+' von maximal CHF 30. Die fünf bereits angeschriebenen Kontakte erhalten keine weitere SMS.'))return;
 document.getElementById('smsV5Resume').disabled=true;document.getElementById('smsCampaignResult').textContent='V5 wird angewendet und Versand fortgesetzt …';
 try{var r=await call('/sms/v5-resume',{method:'POST',body:JSON.stringify({confirm:true,expected_count:c.pending_count})});document.getElementById('smsCampaignResult').textContent=r.message;SMS_CAMPAIGN_REFRESH=setTimeout(loadSms,3000);}
 catch(e){document.getElementById('smsCampaignResult').textContent=e.message+' Status prüfen, bevor erneut gestartet wird.';}
}

async function startSmsCampaign(){
 var c=SMS_CAMPAIGN_STATE;if(!c||!c.ready||c.paused)return;
 if(!confirm(c.ready+' neue, freigegebene Leads per SMS kontaktieren? CHF '+Number(c.reserve_chf).toFixed(2)+' werden reserviert. Versand mit vorhandenem Anbieter-Guthaben; keine automatische Aufladung.'))return;
 document.getElementById('smsCampaignStart').disabled=true;
 document.getElementById('smsCampaignResult').textContent='SMS-Kampagne wird gestartet …';
 try{var r=await call('/sms/campaign-start',{method:'POST',body:JSON.stringify({confirm:true,scope:'new_ready',expected_count:c.ready})});document.getElementById('smsCampaignResult').textContent=r.message;SMS_CAMPAIGN_REFRESH=setTimeout(loadSms,5000);}
 catch(e){document.getElementById('smsCampaignResult').textContent=e.message+' Status aktualisieren, bevor erneut gestartet wird.';}
}

function renderSmsHistory(h){
 if(!h)return;var node=document.getElementById('smsHistory');
 if(!node){node=document.createElement('div');node.id='smsHistory';node.className='card';document.getElementById('smsCampaign').insertAdjacentElement('afterend',node);}
 var rows=h.messages||[],labels={accepted:'An Anbieter übergeben',claimed:'Versandversuch läuft',rejected:'Abgelehnt',unknown:'Versandstatus unklar'};
 node.innerHTML='<h3>SMS-Verlauf</h3><p>'+rows.length+' tatsächliche Versandversuche · ausgehende Nachrichten</p><p class="muted">'+esc(h.inbound_note)+'</p>'+
 (rows.length?rows.map(function(m,i){var status=m.delivered_at?'Zugestellt':labels[m.status]||m.status;var time=m.delivered_at||m.accepted_at||m.attempted_at;return '<details '+(i===0?'open':'')+'><summary><b>'+esc(m.name)+'</b> · '+esc(status)+' · '+esc(time?new Date(time).toLocaleString('de-CH'):'Zeitpunkt unbekannt')+'</summary><div class="chat-thread" style="min-height:0;max-height:none;margin:8px 0"><div class="msg out"><b>SMS an '+esc(m.phone)+'</b><br>'+esc(m.body)+'<div class="msgmeta">'+esc(status)+' · '+esc(m.id)+'</div></div></div></details>';}).join(''):'<p>Noch keine SMS versendet.</p>');
}
