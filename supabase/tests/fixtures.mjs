import { readFile } from 'node:fs/promises'; // Lee las migraciones del proyecto.
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
async function database({finalMvp=false}={}){
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
  if(finalMvp){
    await db.exec('reset role'); // Las migraciones se instalan como propietario del esquema, igual que en el despliegue.
    for(const name of ['20261109000000_agreement_lifecycle.sql','20261109010000_coffee_supervision.sql']){
      await db.exec(await readFile(new URL(`../migrations/${name}`,import.meta.url),'utf8'));
    }
    await session(db,admin);
    for(const id of [associate,other])await db.query('select public.set_user_roles($1,$2)',[id,['client']]);
  }
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


export {admin,associate,other,worker,driver,secondDriver,freightRate,database,session,lot,draft,documents,submit,approved};
