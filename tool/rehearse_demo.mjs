// Ensayo contra el backend real, exclusivamente con cuentas y registros DEMO.
// Requiere RITECH_ADMIN_PASSWORD; nunca guarda tokens ni la clave administrativa.
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';

const config = Object.fromEntries((await readFile('.env', 'utf8')).split(/\r?\n/)
  .filter(line => line.includes('=')).map(line => {
    const i = line.indexOf('='); return [line.slice(0,i),line.slice(i+1).trim()];
  }));
const base = config.SUPABASE_URL;
const key = config.SUPABASE_PUBLISHABLE_KEY;
if (!process.env.RITECH_ADMIN_PASSWORD) throw new Error('Falta RITECH_ADMIN_PASSWORD.');
await mkdir('.demo', {recursive:true});
const statePath = '.demo/state.json';
let state;
try { state = JSON.parse(await readFile(statePath,'utf8')); }
catch (error) { if(error.code!=='ENOENT') throw error; state={run:'DEMO-20261109',accounts:{},steps:[],ids:{}}; }
const save = () => writeFile(statePath,JSON.stringify(state,null,2));
async function api(session,path,body,method = body===undefined?'GET':'POST',extra={}) {
  const response=await fetch(base+path,{method,headers:{apikey:key,
    ...(session?{Authorization:`Bearer ${session.access_token}`} : {}),
    'Content-Type':'application/json',...extra},body:body===undefined?undefined:JSON.stringify(body)});
  const text=await response.text(); let result;
  try {result=JSON.parse(text);} catch {result=text;}
  if(!response.ok) throw new Error(`${method} ${path}: HTTP ${response.status}: ${JSON.stringify(result)}`);
  return result;
}
const login=(email,password)=>api(null,'/auth/v1/token?grant_type=password',{email,password});
const rpc=(session,name,args={})=>api(session,`/rest/v1/rpc/${name}`,args);
const admin=await login('usuarioprueba@gmail.com',process.env.RITECH_ADMIN_PASSWORD);
const users=[];
for(let offset=0;;offset+=100){
  const page=await rpc(admin,'list_users',{page_offset:offset,page_size:100});
  users.push(...page);if(page.length<100)break;
}
state.knownAccounts=users.map(({email,roles})=>({email,roles}));
async function account(role,label) {
  if(!state.accounts[label]) {
    const email=`ritech.demo.${label}.20261109@example.com`;
    if(users.some(user=>user.email.toLowerCase()===email)) {
      throw new Error(`La cuenta DEMO ${label} ya existe pero no hay credenciales locales. No se modifica.`);
    }
    state.accounts[label]={email,password:`Demo!${randomBytes(10).toString('hex')}`,role};
    await save();
    const result=await api(admin,'/functions/v1/create-user',{
      fullName:`DEMO Café ${label}`, ...state.accounts[label], roles:[role],
    });
    state.accounts[label].created=true;
    await save();
    console.log(`Cuenta DEMO ${label}: creada`);
  } else if(!state.accounts[label].created) {
    const credentials=state.accounts[label];
    // Si la petición anterior perdió la respuesta, verifica primero el acceso.
    try {await login(credentials.email,credentials.password);}
    catch {await api(admin,'/functions/v1/create-user',{
      fullName:`DEMO Café ${label}`,email:credentials.email,password:credentials.password,roles:[role],
    });}
    credentials.created=true;await save();
  }
  return login(state.accounts[label].email,state.accounts[label].password);
}
const owner=await account('client','asociado');
await account('client','cliente');
const worker=await account('worker','trabajador');
const driver=await account('transporter','transportador');
async function step(name,operation) {
  if(state.steps.some(row=>row.name===name)){console.log(`${name}: conservado`);return;}
  await operation();state.steps.push({name,passed:true,at:new Date().toISOString()});await save();console.log(`${name}: OK`);
}
async function documents(session,bucket,requestId,kinds,attachRpc) {
  // Imagen sintética del proyecto: no contiene identidad ni certificados reales.
  const bytes=await readFile('web/icons/Icon-192.png');
  for(const kind of kinds) {
    const path=`${session.user.id}/${requestId}/DEMO_${kind}.png`;
    const response=await fetch(`${base}/storage/v1/object/${bucket}/${path}`,{
      method:'POST',headers:{apikey:key,Authorization:`Bearer ${session.access_token}`,
        'Content-Type':'image/png','x-upsert':'false'},body:bytes,
    });
    if(!response.ok && response.status!==409 && !(await response.text()).includes('Duplicate'))
      throw new Error(`Carga de soporte DEMO: ${response.status}`);
    await rpc(session,attachRpc,{target_request:requestId,document_kind:kind,object_path:path,file_name:`DEMO_${kind}.png`});
    await writeFile(`.demo/DEMO_${kind}.png`,bytes);
  }
}
await step('01 Cliente inicia convenio',async()=>{
  state.ids.association=await rpc(owner,'start_association_request',{target_owner:owner.user.id});
});
await step('02 Carga de tres soportes del convenio',()=>documents(owner,'agreement-documents',state.ids.association,
  ['identity','agreement_letter','tax_certificate'],'attach_request_document'));
await step('03 Cliente remite solicitud y consentimiento DEMO',()=>rpc(owner,'submit_association_request',{
  target_request:state.ids.association,applicant_name:'DEMO Café Asociado',applicant_identity:'DEMO20261109',
  applicant_phone:'+573000000000',applicant_address:'Dirección sintética DEMO, Popayán',
  applicant_business:'DEMOSTRACIÓN ACADÉMICA de exportación de café; sin operación comercial real.',accepted_data_processing:true,valid_until:null,
}));
await step('04 Trabajador revisa y propone convenio',async()=>{
  await rpc(worker,'review_association_request',{target_request:state.ids.association,approve:true,reason:'Revisión de soportes sintéticos DEMO',valid_until:null});
  const rows=await api(owner,`/rest/v1/agreements?select=id&request_id=eq.${state.ids.association}`);
  state.ids.agreement=rows[0].id;
});
await step('05 Titular acepta convenio y recibe asociación',async()=>{
  await rpc(owner,'respond_to_agreement',{target_agreement:state.ids.agreement,accept:true,accepted_terms:true,reason:''});
  const roles=await api(owner,`/rest/v1/user_roles?select=role&user_id=eq.${owner.user.id}`);
  if(!roles.some(row=>row.role==='associate'))throw new Error('No se asignó asociación.');
});
await step('06 Asociado registra cultivo de café',async()=>{
  state.ids.cultivation=await rpc(owner,'save_coffee_cultivation',{target_id:null,target_owner:owner.user.id,
    cultivation_name:'DEMO Café Caturra',farm:'Finca DEMO académica',cultivation_location:'Popayán, ubicación sintética DEMO',coffee_variety:'Caturra',hectares:2.5});
});
await step('07 Asociado registra lote de 100 kg',async()=>{
  state.ids.lot=await rpc(owner,'save_coffee_export_lot',{target_id:null,target_cultivation:state.ids.cultivation,
    code:state.run,lot_name:'DEMO Café lavado 100 kg',weight:100,harvest:'2026-11-01',lot_notes:'SOLO DEMOSTRACIÓN: café y documentos sintéticos.'});
});
await step('08 Ruta disponible para exportación de café',async()=>{
  const rates=await api(owner,'/rest/v1/freight_rates?select=*&is_active=eq.true&allows_coffee_export=eq.true&unit=eq.kg&limit=1');
  if(!rates.length)throw new Error('No existe tarifa de café habilitada; configure una tarifa DEMO antes de continuar.');
  state.rate=rates[0];
});
await step('09 Asociado prepara exportación',async()=>{
  state.ids.export=await rpc(owner,'start_coffee_export',{target_lot:state.ids.lot});
});
await step('10 Carga de tres documentos de exportación',()=>documents(owner,'export-documents',state.ids.export,
  ['commercial_invoice','packing_list','quality_record'],'attach_export_document'));
await step('11 Cotización y autorización del titular DEMO',async()=>{
  const quote=await rpc(owner,'quote_coffee_export',{target_request:state.ids.export,target_rate:state.rate.id});
  state.quote=quote;
  await rpc(owner,'submit_coffee_export',{target_request:state.ids.export,target_rate:state.rate.id,
    pickup_location:`${state.rate.origin}, recogida sintética DEMO`,delivery_destination:`${state.rate.destination}, entrega sintética DEMO`,
    recipient:'Destinatario ficticio DEMO',contact_phone:'+573000000000',expected_total:quote.total_cost,
    expected_currency:quote.currency,expected_rate:quote.rate_per_kg,expected_origin:quote.origin,expected_destination:quote.destination,
    accept_charge:true,accept_data_processing:true});
});
await step('12 Trabajador aprueba exportación',async()=>{
  await rpc(worker,'review_coffee_export',{target_request:state.ids.export,approve:true,reason:'Ensayo académico DEMO'});
  const rows=await api(owner,`/rest/v1/shipments?select=id,tracking_code&export_request_id=eq.${state.ids.export}`);
  state.ids.shipment=rows[0].id;state.trackingCode=rows[0].tracking_code;
});
await step('13 Transportador toma carga',()=>rpc(driver,'take_coffee_shipment',{target_shipment:state.ids.shipment}));
for(const [status,location,confirmed] of [['received','Recogida DEMO',false],['in_transit','Punto de ruta DEMO',false],['delivered','Destino DEMO',true]]) {
  await step(`14 Transporte ${status}`,()=>rpc(driver,'update_coffee_delivery',{
    target_shipment:state.ids.shipment,new_status:status,update_notes:`Ensayo académico DEMO: ${status}`,
    new_location:location,confirm_delivery:confirmed,
  }));
}
await step('15 Persistencia y acceso documental',async()=>{
  const [shipment]=await api(owner,`/rest/v1/shipments?select=id,status,delivered_at& id=eq.${state.ids.shipment}`.replace('& id','&id'));
  if(shipment.status!=='delivered'||!shipment.delivered_at)throw new Error('Entrega no persistida.');
  const docs=await api(owner,`/rest/v1/export_documents?select=storage_path&request_id=eq.${state.ids.export}`);
  if(docs.length!==3)throw new Error('Faltan documentos.');
  for(const doc of docs)await api(owner,`/storage/v1/object/sign/export-documents/${doc.storage_path}`,{expiresIn:60});
  state.result={delivered:true,documents:docs.length,checkedAt:new Date().toISOString()};
});
const publicEvidence={run:state.run,steps:state.steps,ids:state.ids,trackingCode:state.trackingCode,result:state.result};
await writeFile('.demo/evidence.json',JSON.stringify(publicEvidence,null,2));
console.log('Ensayo finalizado. Credenciales locales: .demo/state.json (ignorado por Git). Evidencia: .demo/evidence.json.');
