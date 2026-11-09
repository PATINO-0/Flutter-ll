import assert from 'node:assert/strict'; // Comprueba las restricciones reales de PostgreSQL.
import { readFile } from 'node:fs/promises'; // Lee las migraciones del proyecto.
import test from 'node:test'; // Ejecuta escenarios aislados sin conectar con cuentas reales.
import { PGlite } from '@electric-sql/pglite'; // Simula Auth y Storage sobre PostgreSQL en memoria.

const admin='00000000-0000-0000-0000-000000000001';
const associate='00000000-0000-0000-0000-000000000002';
const other='00000000-0000-0000-0000-000000000003';
const worker='00000000-0000-0000-0000-000000000004';
const driver='00000000-0000-0000-0000-000000000005';
const secondDriver='00000000-0000-0000-0000-000000000006';
const freightRate='00000000-0000-0000-0000-000000000007'; // Identifica la tarifa de la tienda en estos escenarios.
const migrations=await Promise.all(['000000_registration_and_roles','020000_association_workflow','030000_commercial_operations','040000_coffee_export_requests','050000_export_dispatch_and_channels','060000_export_freight_routes'].map(name=>readFile(new URL(`../migrations/20261108${name}.sql`,import.meta.url),'utf8')));
let sequence=0; // Genera códigos de lote distintos en los escenarios.

async function session(db,id){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');}
async function database(){
  const db=new PGlite();
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create schema storage;
    create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}');
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,metadata jsonb,unique(bucket_id,name));alter table storage.objects enable row level security;
    grant usage on schema public,auth,storage to authenticated,anon,service_role;grant execute on function auth.uid() to authenticated,anon,service_role;grant select,insert,delete on storage.objects to authenticated;`);
  await db.query('insert into auth.users(id,email) values($1,$2)',[admin,'admin@example.com']);await db.exec(migrations[0]);
  for(const [id,email] of [[associate,'associate@example.com'],[other,'other@example.com'],[worker,'worker@example.com'],[driver,'driver@example.com'],[secondDriver,'driver2@example.com']])await db.query('insert into auth.users(id,email) values($1,$2)',[id,email]);
  for(const migration of migrations.slice(1))await db.exec(migration);
  await session(db,admin);
  await db.query("insert into public.freight_rates(id,title,origin,destination,amount,currency,unit,description,allows_coffee_export) values($1,'Exportación de café','Popayán','Bogotá',1200,'COP','kg','Condiciones de prueba',true)",[freightRate]);
  for(const [id,roles] of [[associate,['associate','client']],[other,['associate']],[worker,['worker']],[driver,['transporter']],[secondDriver,['transporter']]])await db.query('select public.set_user_roles($1,$2)',[id,roles]);
  return db;
}
async function lot(db,owner=associate){
  await session(db,owner);
  const cultivation=(await db.query('select public.save_coffee_cultivation(null,$1,$2,$3,$4,$5,$6) id',[owner,'Cultivo de prueba','Finca La Prueba','Popayán, finca 1','Caturra',2.5])).rows[0].id;
  return(await db.query('select public.save_coffee_export_lot(null,$1,$2,$3,$4,$5,$6) id',[cultivation,`LOTE-${++sequence}`,'Café de prueba',100,'2026-01-01','Café lavado'])).rows[0].id;
}
async function draft(db,lotId){return(await db.query('select public.start_coffee_export($1) id',[lotId])).rows[0].id;}
async function documents(db,requestId,owner=associate){
  for(const kind of ['commercial_invoice','packing_list','quality_record']){
    await db.exec('reset role');const path=`${owner}/${requestId}/${kind}.pdf`;
    await db.query('insert into storage.objects(bucket_id,name,metadata) values($1,$2,$3)',['export-documents',path,{mimetype:'application/pdf',size:120}]);
    await session(db,owner);await db.query('select public.attach_export_document($1,$2,$3,$4)',[requestId,kind,path,`${kind}.pdf`]);
  }
}
async function submit(db,requestId,{origin='Popayán, finca 1',destination='Bogotá, bodega 1',total=120000,charge=true,data=true,currency='COP',rate=1200,rateId=freightRate,routeOrigin='Popayán',routeDestination='Bogotá'}={}){
  return db.query('select public.submit_coffee_export($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) conversation',[requestId,rateId,origin,destination,'Destinatario de prueba','+573001234567',total,currency,rate,routeOrigin,routeDestination,charge,data]);
}
async function approved(db,{origin,destination}={}){
  const lotId=await lot(db);const requestId=await draft(db,lotId);await documents(db,requestId);await submit(db,requestId,{origin,destination});
  await session(db,worker);await db.query('select public.review_coffee_export($1,true)',[requestId]);
  const shipment=(await db.query('select id from public.shipments where export_request_id=$1',[requestId])).rows[0].id;
  return {lotId,requestId,shipment};
}

test('Un asociado solo ve sus cultivos y lotes; el transportador no hereda permisos del empleado',async()=>{
  const db=await database();try{
    const ownLot=await lot(db);await lot(db,other);await session(db,associate);
    assert.equal((await db.query('select * from public.coffee_cultivations')).rows.length,1);assert.equal((await db.query('select * from public.coffee_lots')).rows.length,1);
    await session(db,other);await assert.rejects(db.query('select public.start_coffee_export($1)',[ownLot]),{code:'42501'});
    await session(db,worker);assert.equal((await db.query('select * from public.coffee_lots')).rows.length,2);
    await session(db,driver);assert.equal((await db.query('select public.is_staff() allowed')).rows[0].allowed,false);assert.equal((await db.query('select * from public.coffee_lots')).rows.length,0);
  }finally{await db.close();}
});
test('El servidor calcula el costo por peso y exige cargo, datos y tres documentos',async()=>{
  const db=await database();try{
    const id=await draft(db,await lot(db));const quote=(await db.query('select public.quote_coffee_export($1,$2) quote',[id,freightRate])).rows[0].quote;assert.equal(quote.total_cost,120000);
    await assert.rejects(submit(db,id),{code:'22023'});await documents(db,id);
    await assert.rejects(submit(db,id,{charge:false}),{code:'22023'});await assert.rejects(submit(db,id,{data:false}),{code:'22023'});
    await assert.rejects(submit(db,id,{total:1}),{code:'P0001'});await assert.rejects(submit(db,id,{currency:'USD'}),{code:'P0001'});
    await submit(db,id);assert.equal((await db.query('select total_cost from public.export_requests where id=$1',[id])).rows[0].total_cost,'120000.00');
    await assert.rejects(db.query('select public.create_shipment($1,$2,$3,$4,$5)',[associate,'export','Bypass','Origen','Destino']),{code:'42501'});
  }finally{await db.close();}
});
test('El rechazo libera el mismo lote y conserva soportes para corregir; solo una aprobación puede exportarlo',async()=>{
  const db=await database();try{
    const lotId=await lot(db);const id=await draft(db,lotId);await documents(db,id);await submit(db,id);
    await assert.rejects(db.query('select public.start_coffee_export($1)',[lotId]),{code:'P0001'});
    await session(db,worker);await db.query('select public.review_coffee_export($1,false,$2)',[id,'Corrige la dirección de destino']);
    await session(db,associate);const next=await draft(db,lotId);assert.notEqual(next,id);assert.equal((await db.query('select * from public.export_documents where request_id=$1',[next])).rows.length,3);
    await submit(db,next);await session(db,worker);await db.query('select public.review_coffee_export($1,true)',[next]);
    await assert.rejects(db.query('select public.review_coffee_export($1,true)',[next]),{code:'P0001'});
    assert.equal((await db.query('select * from public.export_charges')).rows.length,1);assert.equal((await db.query('select * from public.shipments')).rows.length,1);
    await session(db,associate);await assert.rejects(db.query('select public.start_coffee_export($1)',[lotId]),{code:'P0001'});
    assert.equal((await db.query('select status from public.export_charges')).rows[0].status,'authorized');
  }finally{await db.close();}
});
test('Un transportador solo agrupa lotes con igual recogida y destino antes de iniciar la ruta',async()=>{
  const db=await database();try{
    const a=await approved(db);const b=await approved(db);const incompatible=await approved(db,{destination:'Medellín, bodega 2'});
    await session(db,driver);await db.query('select public.take_coffee_shipment($1)',[a.shipment]);
    await assert.rejects(db.query('select public.take_coffee_shipment($1)',[incompatible.shipment]),{code:'P0001'});
    await db.query('select public.take_coffee_shipment($1)',[b.shipment]);assert.equal((await db.query('select * from public.shipments')).rows.length,2);
    await session(db,secondDriver);await assert.rejects(db.query('select public.take_coffee_shipment($1)',[a.shipment]),{code:'P0001'});
    await session(db,driver);await db.query('select public.update_coffee_delivery($1,$2,$3,$4,false)',[a.shipment,'received','Lote recibido','Popayán']);
    await db.query('select public.update_coffee_delivery($1,$2,$3,$4,false)',[a.shipment,'in_transit','Salida de la finca','Popayán, vía principal']);
    const extra=await approved(db);await session(db,driver);await assert.rejects(db.query('select public.take_coffee_shipment($1)',[extra.shipment]),{code:'P0001'});
  }finally{await db.close();}
});
test('Solo el transportador asignado actualiza y debe confirmar la entrega para cerrar seguimiento',async()=>{
  const db=await database();try{
    const a=await approved(db);await session(db,driver);await db.query('select public.take_coffee_shipment($1)',[a.shipment]);
    await session(db,worker);await assert.rejects(db.query('select public.update_coffee_delivery($1,$2,$3,$4,false)',[a.shipment,'received','Nota ajena','Origen']),{code:'42501'});
    await session(db,driver);await assert.rejects(db.query('select public.update_coffee_delivery($1,$2,$3,$4,true)',[a.shipment,'delivered','Entrega anticipada','Destino']),{code:'22023'});
    await db.query('select public.update_coffee_delivery($1,$2,$3,$4,false)',[a.shipment,'received','Recibí el lote','Finca']);
    await db.query('select public.update_coffee_delivery($1,$2,$3,$4,false)',[a.shipment,'in_transit','Ruta iniciada','Cali']);
    await assert.rejects(db.query('select public.update_coffee_delivery($1,$2,$3,$4,false)',[a.shipment,'delivered','Llegamos al destino','Bogotá']),{code:'22023'});
    await db.query('select public.update_coffee_delivery($1,$2,$3,$4,true)',[a.shipment,'delivered','Recibido por el destinatario','Bogotá']);
    await session(db,associate);assert.equal((await db.query("select * from public.shipments where status in('accepted','received','in_transit')")).rows.length,0);
    assert.equal((await db.query("select * from public.shipments where status='delivered' and delivered_at is not null")).rows.length,1);
    assert((await db.query('select body from public.chat_messages')).rows.some(row=>row.body.includes('Pedido entregado')));
  }finally{await db.close();}
});
test('Los canales aíslan atención, exportaciones y transporte sin exponer documentos a transportadores',async()=>{
  const db=await database();try{
    const a=await approved(db);await session(db,worker);await db.query('select public.request_transport_pickup($1,$2,$3)',[driver,a.shipment,'Hola, toma este envío de café']);
    await session(db,driver);const before=await db.query('select * from public.list_conversations()');assert(before.rows.every(row=>row.channel==='transport'));
    assert.equal((await db.query('select * from public.export_documents')).rows.length,0);await db.query('select public.take_coffee_shipment($1)',[a.shipment]);
    const after=await db.query('select * from public.list_conversations()');assert(after.rows.some(row=>row.channel==='exports'));
    assert.equal((await db.query('select * from public.export_documents')).rows.length,0); // El chat no concede acceso a facturas ni autorizaciones de cobro.
    assert.equal((await db.query('select * from public.export_charges')).rows.length,0);
    assert((await db.query('select body from public.chat_messages')).rows.every(row=>!row.body.includes('Cargo autorizado:'))); // El importe no se publica en el canal compartido con el transportador.
    await session(db,other);assert.equal((await db.query('select * from public.list_conversations()')).rows.length,0);
  }finally{await db.close();}
});

test('Solo el titular autoriza el cargo y una tarifa posterior no cambia un importe ya autorizado',async()=>{
  const db=await database();try{
    const id=await draft(db,await lot(db));await documents(db,id);
    await session(db,worker);await assert.rejects(submit(db,id),{code:'42501'}); // El empleado revisa la solicitud, pero no firma una autorización económica por el asociado.
    await session(db,admin);await db.query('update public.freight_rates set amount=1500 where id=$1',[freightRate]);
    await session(db,associate);await assert.rejects(submit(db,id),{code:'P0001'}); // Una tarifa distinta obliga a volver a cotizar.
    await submit(db,id,{total:150000,rate:1500});
    assert.equal((await db.query('select charge_authorized_by from public.export_requests where id=$1',[id])).rows[0].charge_authorized_by,associate);
    await session(db,admin);await db.query('update public.freight_rates set amount=2000 where id=$1',[freightRate]);
    await session(db,worker);await db.query('select public.review_coffee_export($1,true)',[id]);
    const charge=(await db.query('select amount,status from public.export_charges where request_id=$1',[id])).rows[0];
    assert.equal(charge.amount,'150000.00');assert.equal(charge.status,'authorized'); // No recalcula el cargo aceptado ni afirma haber realizado un débito bancario.
  }finally{await db.close();}
});
test('Una cuenta sin roles o un transportador revocado no puede aprovechar asignaciones anteriores',async()=>{
  const db=await database();try{
    const a=await approved(db);await session(db,driver);await db.query('select public.take_coffee_shipment($1)',[a.shipment]);
    await session(db,admin);await db.query('select public.set_user_roles($1,$2)',[driver,[]]);await session(db,driver);
    await assert.rejects(db.query('select public.list_transport_shipments()'),{code:'42501'});
    await assert.rejects(db.query('select public.update_coffee_delivery($1,$2,$3,$4,false)',[a.shipment,'received','Acceso revocado','Finca']),{code:'42501'});
    assert.equal((await db.query('select * from public.list_conversations()')).rows.length,0);
  }finally{await db.close();}
});

test('Solo las tarifas activas habilitadas por kilogramo permiten cotizar y enviar',async()=>{
  const db=await database();try{
    const id=await draft(db,await lot(db));await documents(db,id);
    await session(db,admin);await db.query('update public.freight_rates set is_active=false where id=$1',[freightRate]);
    await session(db,associate);
    await assert.rejects(db.query('select public.quote_coffee_export($1,$2)',[id,freightRate]),{code:'P0001'});
    await assert.rejects(submit(db,id),{code:'P0001'});
    await session(db,admin);await db.query('update public.freight_rates set is_active=true,allows_coffee_export=false where id=$1',[freightRate]);
    await session(db,associate);await assert.rejects(submit(db,id),{code:'P0001'});
    await session(db,admin);await db.query("update public.freight_rates set allows_coffee_export=true where id=$1",[freightRate]);
    await assert.rejects(db.query("update public.freight_rates set unit='m³' where id=$1",[freightRate]),{code:'23514'});
    await session(db,associate);
    assert.equal((await db.query('update public.freight_rates set allows_coffee_export=false where id=$1 returning id',[freightRate])).rows.length,0);
    await assert.rejects(db.query('select public.quote_coffee_export($1,$2)',[id,'00000000-0000-0000-0000-000000000099']),{code:'P0001'});
    await assert.rejects(db.query('select public.quote_coffee_export($1)',[id]),{code:'42883'}); // No permite recuperar el cálculo global anterior.
    await assert.rejects(db.query("select public.submit_coffee_export($1,'Origen libre','Destino libre','Nombre','3001234567',120000,'COP',1200,true,true)",[id]),{code:'42883'});
  }finally{await db.close();}
});

test('Una ruta cambiada o una cotización manipulada requiere seleccionar y autorizar nuevamente',async()=>{
  const db=await database();try{
    const id=await draft(db,await lot(db));await documents(db,id);
    await assert.rejects(submit(db,id,{routeOrigin:'Origen inventado'}),{code:'P0001'});
    await assert.rejects(submit(db,id,{routeDestination:'Destino inventado'}),{code:'P0001'});
    await session(db,admin);await db.query("update public.freight_rates set destination='Cartagena',amount=1800,currency='USD' where id=$1",[freightRate]);
    await session(db,associate);await assert.rejects(submit(db,id),{code:'P0001'});
    const quote=(await db.query('select public.quote_coffee_export($1,$2) quote',[id,freightRate])).rows[0].quote;
    assert.equal(quote.destination,'Cartagena');assert.equal(quote.total_cost,180000);assert.equal(quote.currency,'USD');
    await submit(db,id,{routeDestination:'Cartagena',total:180000,rate:1800,currency:'USD',destination:'Bodega del puerto'});
    const row=(await db.query('select * from public.export_requests where id=$1',[id])).rows[0];
    assert.equal(row.freight_rate_id,freightRate);assert.equal(row.destination,'Cartagena · Bodega del puerto');
    assert.equal(row.tariff_snapshot.destination,'Cartagena');assert.equal(row.tariff_snapshot.rate_per_kg,1800);
    assert.equal(row.delivery_address,'Bodega del puerto'); // La dirección complementa el destino autorizado del catálogo.
  }finally{await db.close();}
});

test('El archivo conserva la tarifa y ruta autorizadas aunque se desactiven después del envío',async()=>{
  const db=await database();try{
    const id=await draft(db,await lot(db));await documents(db,id);await submit(db,id);
    await session(db,admin);await db.query("update public.freight_rates set destination='Cartagena',amount=2000,is_active=false where id=$1",[freightRate]);
    await session(db,worker);await db.query('select public.review_coffee_export($1,true)',[id]);
    const request=(await db.query('select tariff_snapshot,total_cost,destination from public.export_requests where id=$1',[id])).rows[0];
    assert.equal(request.tariff_snapshot.destination,'Bogotá');assert.equal(request.tariff_snapshot.rate_per_kg,1200);assert.equal(request.total_cost,'120000.00');
    const shipment=(await db.query('select destination from public.shipments where export_request_id=$1',[id])).rows[0];
    assert.equal(shipment.destination,request.destination);
    assert.equal((await db.query('select amount from public.export_charges where request_id=$1',[id])).rows[0].amount,'120000.00');
  }finally{await db.close();}
});
