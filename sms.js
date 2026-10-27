var SMS_STATE=null,SMS_PREVIEW=null;
async function loadSms(){try{SMS_STATE=await call('/sms/status');var s=SMS_STATE;renderSmsDashboardTest(s.dashboard_test);renderSmsCampaign(s.campaign);renderSmsHistory(s.history);loadSmsInbox();document.getElementById('smsSetup').textContent=(s.credentials_present?'Anbieterzugang hinterlegt':'Anbieterzugang fehlt')+' · '+(s.campaign&&s.campaign.paused?'SMS pausiert – Textprüfung':s.enabled&&s.sender_verified?'Versand freigegeben':'Versand noch gesperrt')+' · Reserviert CHF '+Number(s.reserved_chf).toFixed(2)+' / 30.00 · '+s.leads.filter(function(l){return !l.blocks.length}).length+' Kontakte mit SMS-Bestätigung';document.getElementById('smsLead').innerHTML='<option value="">Kontakt auswählen</option>'+s.leads.map(function(l){return '<option value="'+esc(l.id)+'">'+esc(l.name||l.phone)+' · '+esc(l.dispatch?l.dispatch.status:l.blocks.length?'Noch gesperrt':l.consent&&l.consent.evidence_kind==='operator_attestation'?'SMS bestätigt (Betreiberangabe)':'Einwilligung erfasst')+'</option>'}).join('');smsSelect()}catch(e){document.getElementById('smsSetup').textContent='SMS nicht verfügbar: '+e.message;SMS_STATE=null;document.getElementById('smsSend').disabled=true}}
function smsSelected(){var id=document.getElementById('smsLead').value;return SMS_STATE&&SMS_STATE.leads.find(function(l){return l.id===id})}
function smsSelect(){SMS_PREVIEW=null;document.getElementById('smsSend').disabled=true;document.getElementById('smsPreview').textContent='Noch keine Vorschau.';var l=smsSelected();document.getElementById('smsLeadState').textContent=l?(l.blocks.join(' · ')||'SMS-Einwilligung als Operator-Angabe erfasst')+(l.dispatch?' · Versandstatus: '+l.dispatch.status:''):'';renderSmsConsentEvidence(l);document.getElementById('smsConsentText').value=l&&l.consent?(l.consent.consent_text||''):'';document.getElementById('smsConsentRef').value=l&&l.consent?l.consent.evidence_reference:'';document.getElementById('smsConsentAt').value=''}
async function saveSmsConsent(){var l=smsSelected();if(!l)return toast('Kontakt auswählen');var at=document.getElementById('smsConsentAt').value;if(!at)return toast('Ursprüngliches Zustimmungsdatum fehlt');try{await call('/sms/consent',{method:'POST',body:JSON.stringify({lead_id:l.id,text:document.getElementById('smsConsentText').value,reference:document.getElementById('smsConsentRef').value,at:new Date(at).toISOString()})});toast('SMS-Einwilligung dokumentiert');await loadSms()}catch(e){toast(e.message)}}
async function previewSms(){var l=smsSelected();if(!l)return toast('Kontakt auswählen');document.getElementById('smsSend').disabled=true;SMS_PREVIEW=null;try{var p=await call('/sms/preview',{method:'POST',body:JSON.stringify({lead_id:l.id})});if(!smsSelected()||smsSelected().id!==p.lead_id)return;SMS_PREVIEW=p;document.getElementById('smsPreview').textContent=p.body+'\n\n'+p.segments+' SMS · Reservierung CHF '+p.reserve_chf.toFixed(2)+(p.blocks.length?'\nNoch offen: '+p.blocks.join('; '):'');document.getElementById('smsSend').disabled=!!p.blocks.length}catch(e){toast(e.message)}}
async function sendSms(){var p=SMS_PREVIEW,l=smsSelected();if(!p||p.blocks.length||!l||l.id!==p.lead_id)return;if(!confirm('Diese SMS an '+p.phone+' senden? CHF '+Number(p.reserve_chf).toFixed(2)+' werden vom Budget reserviert.'))return;document.getElementById('smsSend').disabled=true;SMS_PREVIEW=null;try{var r=await call('/sms/send',{method:'POST',body:JSON.stringify({lead_id:p.lead_id,body:p.body,confirm:true})});document.getElementById('smsPreview').textContent=r.message;toast(r.message)}catch(e){document.getElementById('smsPreview').textContent=e.message+' Bei unklarem Ergebnis zuerst das Anbieterprotokoll prüfen.';toast(e.message)}}
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

var SMS_INBOX_REFRESH=null;
async function loadSmsInbox(){ var focused=document.activeElement,shown=document.getElementById('smsBridgeToken');
 if((focused&&/^smsImport/.test(focused.id))||(shown&&shown.value)){if(SMS_INBOX_REFRESH)clearTimeout(SMS_INBOX_REFRESH);SMS_INBOX_REFRESH=setTimeout(loadSmsInbox,30000);return;}
 try{var data=await call('/sms/inbox');renderSmsInbox(data);}
 catch(e){var el=document.getElementById('smsInbox');if(el)el.textContent='SMS-Posteingang: '+e.message;}
}
function renderSmsInbox(data){
 var node=document.getElementById('smsInbox');
 if(!node){node=document.createElement('div');node.id='smsInbox';node.className='card';document.getElementById('smsSetup').insertAdjacentElement('afterend',node);}
 var oldGuide=document.getElementById('smsIphoneGuide'),oldManual=document.getElementById('smsManualImport');
 var guideOpen=!!(oldGuide&&oldGuide.open),manualOpen=!!(oldManual&&oldManual.open),saved={};
 ['smsImportSender','smsImportAt','smsImportText'].forEach(function(id){var el=document.getElementById(id);if(el)saved[id]=el.value;});
 var labels={interest:'Interesse · noch keine Terminzusage',stop:'STOP · gesperrt',decline:'Ablehnung · archiviert und gesperrt',underage:'U18 · gesperrt',appointment:'Terminwunsch · bitte abstimmen',cost:'Frage zu Kosten',process:'Frage zum Ablauf',prize:'Frage zum Gewinnspiel',review:'Bitte prüfen'};
 var blocks={budget_limit:'30-CHF-Budget ausgeschöpft',manual_import:'Manuell übernommen · Antwort nicht automatisch versendet',human_review:'Manuelle Bearbeitung nötig',auto_reply_paused:'Automatische Antworten pausiert',sms_paused:'SMS pausiert',reply_limit:'Antwortlimit erreicht',contact_blocked:'Kontakt gesperrt',reply_already_pending:'Antwort wartet bereits',newer_reply_exists:'Neuere Antwort vorhanden',older_than_24h:'Antwort älter als 24 Stunden',provider_rejected:'Versand abgelehnt',provider_unknown:'Versand unklar – nicht erneut senden'};
 var devices=data.devices||[],last=devices.map(d=>d.last_received_at).filter(Boolean).sort().pop();
 node.innerHTML='<h3>SMS-Posteingang</h3><p><b>'+data.received+' empfangen · '+data.interested+' mit Interesse · '+data.review+' zu prüfen</b></p>'+
 '<p>'+(!devices.length?'iPhone-Weiterleitung noch nicht eingerichtet.':last?'Letzter Empfang vom iPhone: '+esc(new Date(last).toLocaleString('de-CH')):'Verbindungsschlüssel vorhanden · noch kein Empfang vom iPhone bestätigt.')+'</p>'+
 '<p>Automatische Bearbeitung: STOP, Ablehnungen und U18 werden gesperrt. Klare Zusagen und einfache Fragen erhalten eine passende Antwort; Terminwünsche und unklare Texte gehen an dich. Interesse zählt nicht als gebuchter Termin. Antworten laufen über ASPSMS innerhalb des gemeinsamen 30-CHF-Budgets.</p>'+
 '<div class="actions"><button class="secondary" onclick="loadSmsInbox()">Posteingang aktualisieren</button><button class="secondary" onclick="toggleSmsReplies('+(!data.auto_reply_enabled)+')">'+(data.auto_reply_enabled?'Automatische Antworten pausieren':'Automatische Antworten aktivieren')+'</button></div>'+
 '<p>Automatische Antworten sind '+(data.auto_reply_enabled?'aktiv, sobald Nachrichten vom iPhone ankommen.':'pausiert. STOP und Ablehnungen werden weiterhin verarbeitet.')+' Maximal zwei Antworten pro Kontakt in 24 Stunden, vier insgesamt. Keine automatische Terminzusage.</p>'+
 '<details id="smsIphoneGuide"><summary><b>iPhone-Weiterleitung einrichten · ohne neues Abo</b></summary><p>Nur SMS von den unten aufgeführten, bereits angeschriebenen Kontakten weiterleiten. Private Nachrichten und Einmalcodes nicht aufnehmen. Vorhandene SMS werden nicht rückwirkend geladen.</p>'+
 '<div class="actions"><button onclick="createSmsBridge()">Verbindungsschlüssel für mein iPhone erstellen</button></div><div id="smsBridgeSetup"></div>'+
 '<ol><li>Auf dem iPhone „Kurzbefehle“ → „Automation“ → „+“ → „Nachricht“ öffnen.</li>'+
 '<li>Unter „Absender“ die unten aufgeführten Telefonnummern auswählen. „Nachricht enthält“ leer lassen. „Sofort ausführen“ wählen.</li>'+
 '<li>Leere Automation erstellen. Aktion „Inhalte von URL abrufen“ hinzufügen. Die unten angezeigte Adresse einsetzen, Methode POST wählen.</li>'+
 '<li>Header <code>x-sms-bridge</code> mit deinem Verbindungsschlüssel hinzufügen. Inhaltstyp JSON wählen.</li>'+
 '<li>JSON-Felder: <code>sender</code> = Absender-Telefonnummer der eingehenden Nachricht; <code>text</code> = Inhalt der Nachricht; <code>recipient</code> = +41774022233; <code>received_at</code> = aktuelles Datum, im ISO-8601-Format formatiert. Die Variablen aus „Kurzbefehleingabe“ wählen; bei „sender“ die Telefonnummer, nicht den Kontaktnamen verwenden.</li>'+
 '<li>Speichern. Die Freigabe für den Zugriff auf die Serveradresse beim ersten Lauf bestätigen. Danach eine eigene Testnachricht über „Vorschau“ unten prüfen. Eine echte eingehende Kundenantwort zeigt anschließend den bestätigten Empfang; keine Testnachricht an Kunden senden.</li></ol>'+
 '<p>Absender für die Automation (bei neu angeschriebenen Kontakten ergänzen):</p><ul>'+data.contacts.map(c=>'<li>'+esc(c.name)+' · '+esc(c.phone)+'</li>').join('')+'</ul>'+
 devices.map(d=>'<p>'+esc(d.name)+' · erstellt '+esc(new Date(d.created_at).toLocaleString('de-CH'))+' <button class="secondary" onclick="revokeSmsBridge(\''+d.id+'\')">Diese Verbindung deaktivieren</button></p>').join('')+
 '<p><a href="https://support.apple.com/de-de/guide/shortcuts/apdd711f9dff/ios" target="_blank" rel="noopener">Apple: Nachricht als Automation-Auslöser</a></p></details>'+
 '<details id="smsManualImport"><summary><b>Antwort vom Handy übernehmen</b></summary><p>Für bereits eingegangene SMS. Die Antwort wird eingeordnet; ein Versand erfolgt erst nach deiner Freigabe.</p><label for="smsImportSender">Absender</label><select id="smsImportSender"><option value="">Kontakt auswählen</option>'+data.contacts.map(c=>'<option value="'+esc(c.phone)+'">'+esc(c.name)+' · '+esc(c.phone)+'</option>').join('')+'</select>'+
 '<label for="smsImportAt">Tatsächlicher Empfangszeitpunkt</label><input id="smsImportAt" type="datetime-local">'+
 '<label for="smsImportText">Empfangene SMS</label><textarea id="smsImportText" rows="4" maxlength="2000"></textarea><div class="actions"><button class="secondary" onclick="previewSmsInbound()">Nur Einordnung prüfen</button><button onclick="importSmsInbound()">Antwort speichern und bearbeiten</button></div><p id="smsImportResult" role="status"></p></details>'+
 '<div id="smsInboxThreads">'+(data.messages.length?data.messages.map((m,i)=>{
 var r=m.reply,j=r&&r.job,state=j?(j.delivered_at?'Zugestellt':{queued:'Wartet auf Versand/Guthaben',claimed:'Versand läuft',accepted:'Übergeben · Zustellung offen',rejected:'Abgelehnt',unknown:'Unklar – nicht wiederholen'}[j.status]||j.status):null;
 return '<details '+(i===0?'open':'')+'><summary><b>'+esc(m.name)+'</b> · '+esc(labels[m.intent]||m.intent)+' · '+esc(new Date(m.received_at).toLocaleString('de-CH'))+'</summary><div class="chat-thread" style="min-height:0;max-height:none;margin:8px 0"><div class="msg in"><b>SMS von '+esc(m.phone)+'</b><br>'+esc(m.body)+'<div class="msgmeta">'+(m.source==='iphone'?'Vom iPhone empfangen':'Manuell vom Handy übernommen')+'</div></div>'+
 (r?'<div class="msg out"><b>'+esc(state)+'</b><br>'+esc(r.body)+'</div>':m.suggested_reply?'<div class="msg out"><b>Antwortentwurf · noch nicht gesendet</b><br>'+esc(m.suggested_reply)+'</div>':'')+'</div>'+
 (m.reply_block_reason?'<p>'+esc(blocks[m.reply_block_reason]||m.reply_block_reason)+'</p>':'')+
 (!r&&m.suggested_reply?'<button onclick="approveSmsReply(\''+m.id+'\')">Antwort freigeben</button>':'')+'</details>';
 }).join(''):'<p>Noch keine SMS-Antwort im Dashboard. Ohne aktivierte iPhone-Weiterleitung ist dies keine Aussage darüber, ob Antworten auf deinem Handy liegen.</p>')+'</div>';
 document.getElementById('smsIphoneGuide').open=guideOpen;document.getElementById('smsManualImport').open=manualOpen;
 Object.keys(saved).forEach(function(id){document.getElementById(id).value=saved[id];});
 if(SMS_INBOX_REFRESH)clearTimeout(SMS_INBOX_REFRESH);
 SMS_INBOX_REFRESH=setTimeout(loadSmsInbox,30000);
}
async function createSmsBridge(){
 try{
 var r=await call('/sms/inbox-action',{method:'POST',body:JSON.stringify({action:'create_bridge'})});
 var el=document.getElementById('smsBridgeSetup');
 el.innerHTML='<p><b>Nur auf deinem iPhone verwenden. Dieser Schlüssel kann ausschließlich SMS bekannter Kontakte einliefern.</b></p><label>Serveradresse<input readonly id="smsBridgeEndpoint"></label><label>Verbindungsschlüssel · nur jetzt sichtbar<input readonly id="smsBridgeToken" type="password"></label><button class="secondary" onclick="var e=document.getElementById(\'smsBridgeToken\');e.type=e.type===\'password\'?\'text\':\'password\'">Schlüssel anzeigen/verbergen</button><p>Nach dem Einrichten die Seite neu laden. Bei Verlust einen neuen Schlüssel erstellen und die alte Verbindung deaktivieren.</p>';
 document.getElementById('smsBridgeEndpoint').value=r.endpoint;document.getElementById('smsBridgeToken').value=r.token;
 if(SMS_INBOX_REFRESH)clearTimeout(SMS_INBOX_REFRESH);
 }catch(e){toast(e.message);}
}
async function toggleSmsReplies(enabled){try{await call('/sms/inbox-action',{method:'POST',body:JSON.stringify({action:'auto_reply',enabled})});await loadSmsInbox();}catch(e){toast(e.message);}}
async function revokeSmsBridge(id){if(!confirm('Diese iPhone-Verbindung deaktivieren?'))return;try{await call('/sms/inbox-action',{method:'POST',body:JSON.stringify({action:'revoke_bridge',id})});await loadSmsInbox();}catch(e){toast(e.message);}}
async function previewSmsInbound(){try{var r=await call('/sms/inbox-action',{method:'POST',body:JSON.stringify({action:'preview',text:document.getElementById('smsImportText').value})});document.getElementById('smsImportResult').textContent='Einordnung: '+r.intent+(r.reply?' · Entwurf: '+r.reply:' · Keine automatische SMS-Antwort.');}catch(e){toast(e.message);}}
async function importSmsInbound(){
 var phone=document.getElementById('smsImportSender').value,text=document.getElementById('smsImportText').value,at=document.getElementById('smsImportAt').value;
 if(!phone||!text.trim()||!at)return toast('Absender, Nachricht und Empfangszeitpunkt ausfüllen');
 try{var r=await call('/sms/inbox-action',{method:'POST',body:JSON.stringify({action:'import',sender:phone,text,received_at:new Date(at).toISOString()})});if(!r.accepted)throw new Error('Absender wurde noch nicht per SMS kontaktiert');toast(r.duplicate?'Bereits vorhanden – nicht erneut verarbeitet':'SMS gespeichert und eingeordnet');await loadSmsInbox();}catch(e){toast(e.message);}
}
async function approveSmsReply(id){
 if(!confirm('Diesen Antwortentwurf über ASPSMS versenden? Die SMS-Teile werden im gemeinsamen 30-CHF-Budget reserviert.'))return;
 try{var r=await call('/sms/inbox-action',{method:'POST',body:JSON.stringify({action:'reply',id})});toast(r.queued?'Antwort für Versand vorgemerkt':'Nicht vorgemerkt: '+r.reason);await loadSmsInbox();}catch(e){toast(e.message);}
}
