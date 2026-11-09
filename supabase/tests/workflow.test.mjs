import assert from 'node:assert/strict'; // Comprueba reglas y códigos reales de PostgreSQL.
import { readFile } from 'node:fs/promises'; // Ejecuta las migraciones de producción sin duplicar sus funciones.
import test from 'node:test'; // Utiliza el ejecutor de pruebas de Node.
import { PGlite } from '@electric-sql/pglite'; // Aísla los datos y las políticas del proyecto remoto.

const admin = '00000000-0000-0000-0000-000000000001'; // Identifica al administrador inicial.
const client = '00000000-0000-0000-0000-000000000002'; // Identifica al solicitante.
const worker = '00000000-0000-0000-0000-000000000003'; // Identifica al revisor.
const outsider = '00000000-0000-0000-0000-000000000004'; // Identifica a otro cliente sin acceso al expediente.
const migrations = await Promise.all(['20261108000000_registration_and_roles.sql','20261108020000_association_workflow.sql'].map(name => readFile(new URL(`../migrations/${name}`,import.meta.url),'utf8')));
const operationsMigration=await readFile(new URL('../migrations/20261108030000_commercial_operations.sql',import.meta.url),'utf8'); // Comprueba también las operaciones habilitadas por el convenio.

async function database() {
  const db = new PGlite(); // Crea una instancia de PostgreSQL independiente por escenario.
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create schema storage;
    create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}');
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,metadata jsonb,unique(bucket_id,name));
    alter table storage.objects enable row level security;
    grant usage on schema public,auth,storage to authenticated,anon,service_role;
    grant execute on function auth.uid() to authenticated,anon,service_role;
    grant select,insert,delete on storage.objects to authenticated;
  `); // Simula únicamente las interfaces de Auth y Storage que proporciona Supabase.
  await db.query('insert into auth.users(id,email) values($1,$2)',[admin,'admin@example.com']);
  await db.exec(migrations[0]); // Da administración a la única cuenta inicial.
  for(const [id,email] of [[client,'client@example.com'],[worker,'worker@example.com'],[outsider,'outsider@example.com']]) {
    await db.query('insert into auth.users(id,email) values($1,$2)',[id,email]); // Ejecuta el disparador real de alta de clientes.
  }
  await db.exec(migrations[1]); // Instala el flujo completo, incluidas políticas y funciones.
  await db.exec(operationsMigration); // Instala envíos y seguimiento con los mismos permisos efectivos.
  await session(db,admin); // Configura los permisos del trabajador desde la cuenta autorizada.
  await db.query('select public.set_user_roles($1,$2)',[worker,['worker','client']]);
  return db;
}

async function session(db,id) {
  await db.exec('reset role'); // Sale del rol anterior sin cambiar los datos de prueba.
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]); // Reproduce la identidad de un JWT verificado.
  await db.exec('set role authenticated'); // Activa las restricciones reales del cliente.
}

async function draft(db) {
  await session(db,client); // Crea la solicitud como el propio cliente.
  const {rows}=await db.query('select public.start_association_request() id');
  return rows[0].id; // Devuelve el identificador generado por PostgreSQL.
}

async function attach(db,id) {
  for(const kind of ['identity','agreement_letter','tax_certificate']) {
    await db.exec('reset role'); // Simula la carga que realiza la API de Storage al guardar el archivo.
    const path=`${client}/${id}/${kind}.pdf`; // Conserva la estructura de carpetas exigida por las políticas.
    await db.query('insert into storage.objects(bucket_id,name,metadata) values($1,$2,$3)', ['agreement-documents',path,{mimetype:'application/pdf',size:100}]);
    await session(db,client); // Registra el documento con los permisos del solicitante.
    await db.query('select public.attach_request_document($1,$2,$3,$4)',[id,kind,path,`${kind}.pdf`]);
  }
}

async function submit(db,id,consent=true) {
  return db.query('select public.submit_association_request($1,$2,$3,$4,$5,$6,$7) conversation_id',
    [id,'Persona solicitante','123456789','+57 3001234567','Calle 10 número 20','Importación y distribución de productos',consent]);
}

test('El envío exige tres documentos y autorización; notifica al personal en un chat privado',async()=>{
  const db=await database();
  try {
    const id=await draft(db);
    await assert.rejects(submit(db,id),{code:'22023'}); // No permite solicitudes sin sus tres soportes.
    await attach(db,id);
    await assert.rejects(submit(db,id,false),{code:'22023'}); // No permite enviar sin aceptar el tratamiento de datos.
    const sent=await submit(db,id);
    const conversation=sent.rows[0].conversation_id;
    const request=await db.query('select status,consent_version from public.association_requests where id=$1',[id]);
    assert.equal(request.rows[0].status,'pending');
    assert.equal(request.rows[0].consent_version,'2026-11-08-v1');
    await assert.rejects(db.query('select public.start_association_request()'),{code:'P0001'}); // Rechaza otra solicitud mientras hay revisión pendiente.
    await session(db,worker);
    const inbox=await db.query('select * from public.list_conversations()');
    assert.equal(inbox.rows[0].unread_count,1); // El envío aparece como una notificación no leída para el trabajador.
    await session(db,outsider);
    assert.equal((await db.query('select * from public.association_requests')).rows.length,0); // Oculta expedientes ajenos.
    assert.equal((await db.query('select * from public.chat_messages')).rows.length,0); // Oculta conversaciones ajenas.
    await assert.rejects(db.query('select public.send_chat_message($1,$2)',[conversation,'Mensaje ajeno']),{code:'42501'});
  } finally {await db.close();}
});

test('El rechazo exige motivo, lo comunica por chat y permite corregir inmediatamente',async()=>{
  const db=await database();
  try {
    const id=await draft(db); await attach(db,id); await submit(db,id);
    await session(db,worker);
    await assert.rejects(db.query('select public.review_association_request($1,false,$2)',[id,'']),{code:'22023'});
    await db.query('select public.review_association_request($1,false,$2)',[id,'La identificación no es legible']);
    await session(db,client);
    const messages=await db.query('select body from public.chat_messages order by created_at');
    assert(messages.rows.some(row=>row.body.includes('identificación no es legible')));
    const next=await db.query('select public.start_association_request() id');
    assert.notEqual(next.rows[0].id,id); // Conserva el expediente rechazado y crea un intento nuevo.
    assert.equal((await db.query("select public.effective_role() role")).rows[0].role,'client');
  } finally {await db.close();}
});

test('La aprobación crea un solo convenio, conserva documentos y promueve al cliente a asociado',async()=>{
  const db=await database();
  try {
    const id=await draft(db); await attach(db,id); await submit(db,id);
    await session(db,outsider);
    await assert.rejects(db.query('select public.review_association_request($1,true)',[id]),{code:'42501'});
    await session(db,worker);
    await db.query('select public.review_association_request($1,true)',[id]);
    await assert.rejects(db.query('select public.review_association_request($1,true)',[id]),{code:'P0001'}); // Evita resolver dos veces la misma solicitud.
    await session(db,client);
    assert.equal((await db.query('select public.effective_role() role')).rows[0].role,'associate');
    assert.equal((await db.query('select * from public.agreements')).rows.length,1);
    assert.equal((await db.query('select * from public.request_documents')).rows.length,3);
    await assert.rejects(db.query('select public.start_association_request()'),{code:'42501'}); // Un asociado ya no necesita solicitar su vinculación como cliente.
    const path=`${client}/${id}/identity.pdf`;
    assert.equal((await db.query('select public.can_access_request_file($1,true) allowed',[path])).rows[0].allowed,false); // Los documentos enviados quedan inmutables.
  } finally {await db.close();}
});

test('El plazo de 30 días también se verifica en servidor para solicitudes iniciadas por personal',async()=>{
  const db=await database();
  try {
    const id=await draft(db); await attach(db,id); await submit(db,id);
    await session(db,worker); await db.query('select public.review_association_request($1,true)',[id]);
    await assert.rejects(db.query('select public.start_association_request($1)',[client]),{code:'P0001'});
    await db.exec('reset role');
    await db.query("update public.association_requests set submitted_at=now()-interval '31 days' where id=$1",[id]);
    await session(db,worker);
    assert((await db.query('select public.start_association_request($1) id',[client])).rows[0].id);
  } finally {await db.close();}
});

test('Eliminar el acceso bloquea datos y funciones aunque el token anterior siga vigente',async()=>{
  const db=await database();
  try {
    const id=await draft(db); await attach(db,id); await submit(db,id);
    await session(db,admin);
    await assert.rejects(db.query('select public.admin_deactivate_user($1)',[admin]),{code:'23514'});
    await db.query('select public.admin_update_user($1,$2,$3,$4)',[client,'Nombre corregido','updated@example.com',['client']]);
    await db.query('select public.admin_deactivate_user($1)',[client]);
    await assert.rejects(db.query('select public.set_user_roles($1,$2)',[client,['admin']]),{code:'22023'}); // Una cuenta desactivada no cuenta como administrador de respaldo.
    await session(db,client);
    assert.equal((await db.query('select public.is_active_user() allowed')).rows[0].allowed,false);
    assert.equal((await db.query('select * from public.association_requests')).rows.length,0);
    assert.equal((await db.query('select * from public.freight_rates')).rows.length,0);
    await assert.rejects(db.query('select public.open_support_conversation()'),{code:'42501'});
    await session(db,worker);
    assert.equal((await db.query('select * from public.agreements')).rows.length,0);
    assert.equal((await db.query('select * from public.association_requests')).rows.length,1); // Conserva el historial para el personal autorizado.
  } finally {await db.close();}
});

test('Solo los asociados registran operaciones propias y solo el personal actualiza el seguimiento',async()=>{
  const db=await database();
  try {
    await session(db,client);
    const create=()=>db.query('select public.create_shipment($1,$2,$3,$4,$5) id',[client,'export','Carga comercial','Bogotá','Madrid']);
    await assert.rejects(create(),{code:'42501'}); // Un cliente no opera antes de aprobarse su convenio.
    const id=await draft(db);await attach(db,id);await submit(db,id);
    await session(db,worker);await db.query('select public.review_association_request($1,true)',[id]);
    await session(db,client);const shipment=(await create()).rows[0].id;
    assert.equal((await db.query('select * from public.shipments')).rows.length,1);
    await assert.rejects(db.query('select public.update_shipment_status($1,$2,$3)',[shipment,'delivered','Entrega directa']),{code:'42501'});
    await session(db,outsider);assert.equal((await db.query('select * from public.shipments')).rows.length,0); // Otro cliente no ve el envío ni sus eventos.
    await session(db,worker);await db.query('select public.update_shipment_status($1,$2,$3)',[shipment,'in_transit','Salida confirmada del origen']);
    await db.query('select public.update_shipment_status($1,$2,$3)',[shipment,'delivered','Recepción confirmada en destino']);
    await assert.rejects(db.query('select public.update_shipment_status($1,$2,$3)',[shipment,'pending','Reapertura inválida']),{code:'22023'});
    await session(db,client);assert.equal((await db.query('select * from public.shipment_events')).rows.length,3); // El asociado puede consultar todo el historial de su operación.
  } finally{await db.close();}
});

test('El chat actualiza lecturas y no permite fabricar avisos del sistema desde el cliente',async()=>{
  const db=await database();
  try{
    const id=await draft(db);await attach(db,id);const sent=await submit(db,id);const conversation=sent.rows[0].conversation_id;
    await session(db,worker);
    const last=(await db.query('select id from public.chat_messages where conversation_id=$1',[conversation])).rows[0].id;
    await db.query('select public.mark_conversation_read($1,$2)',[conversation,last]);
    assert.equal((await db.query('select unread_count from public.list_conversations()')).rows[0].unread_count,0);
    await db.query('select public.send_chat_message($1,$2)',[conversation,'Estamos revisando tus documentos.']);
    await session(db,client);
    assert.equal((await db.query('select unread_count from public.list_conversations()')).rows[0].unread_count,1);
    await assert.rejects(db.query("insert into public.chat_messages(conversation_id,sender_id,kind,body) values($1,$2,'system','Aprobación falsa')",[conversation,client]),{code:'42501'});
    await session(db,outsider);
    await assert.rejects(db.query('select public.mark_conversation_read($1,$2)',[conversation,last]),{code:'42501'});
  }finally{await db.close();}
});

test('Las políticas de Storage aíslan archivos y no permiten eliminar soportes enviados',async()=>{
  const db=await database();
  try{
    const id=await draft(db);await attach(db,id);
    assert.equal((await db.query("select * from storage.objects where bucket_id='agreement-documents'")).rows.length,3);
    await session(db,outsider);
    assert.equal((await db.query("select * from storage.objects where bucket_id='agreement-documents'")).rows.length,0);
    await assert.rejects(db.query('insert into storage.objects(bucket_id,name,metadata) values($1,$2,$3)',['agreement-documents',`${client}/${id}/injected.pdf`,{size:10,mimetype:'application/pdf'}]),{code:'42501'});
    await session(db,client);await submit(db,id);
    await db.query("delete from storage.objects where bucket_id='agreement-documents'"); // No hay una política que permita retirar documentos después de enviarlos.
    assert.equal((await db.query("select * from storage.objects where bucket_id='agreement-documents'")).rows.length,3);
    await assert.rejects(db.query('select public.attach_request_document($1,$2,$3,$4)',[id,'identity',`${client}/${id}/identity.pdf`,'changed.pdf']),{code:'22023'});
  }finally{await db.close();}
});
