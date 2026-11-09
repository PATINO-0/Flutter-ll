import assert from 'node:assert/strict'; // Comprueba las reglas de PostgreSQL con permisos reales.
import test from 'node:test'; // Aísla cada flujo sin utilizar cuentas de producción.
import {admin,associate,other,worker,database,session,lot,draft,documents,submit} from './fixtures.mjs'; // Instala todas las migraciones del MVP en memoria.

/// Adjunta los tres soportes mediante las mismas restricciones que la aplicación.
async function agreementDocuments(db,requestId,owner=associate){
  for(const kind of ['identity','agreement_letter','tax_certificate']){
    await db.exec('reset role');
    const path=`${owner}/${requestId}/${kind}.pdf`;
    await db.query('insert into storage.objects(bucket_id,name,metadata) values($1,$2,$3)',['agreement-documents',path,{mimetype:'application/pdf',size:100}]);
    await session(db,owner);
    await db.query('select public.attach_request_document($1,$2,$3,$4)',[requestId,kind,path,`${kind}.pdf`]);
  }
}

/// Prepara el expediente como titular o como trabajador para comprobar ambas procedencias.
async function proposal(db,{staffPrepared=false,owner=associate}={}){
  await session(db,staffPrepared?worker:owner);
  const requestId=(await db.query('select public.start_association_request($1) id',[owner])).rows[0].id;
  await agreementDocuments(db,requestId,owner);
  await session(db,staffPrepared?worker:owner);
  await db.query('select public.submit_association_request($1,$2,$3,$4,$5,$6,true)',[requestId,'Cliente de prueba','123456789','3001234567','Calle de prueba 123','Exportación de café de prueba']);
  if(!staffPrepared){
    await session(db,worker);
    await db.query('select public.review_association_request($1,true)',[requestId]);
  }
  const agreementId=(await db.query('select id from public.agreements where request_id=$1',[requestId])).rows[0].id;
  return {requestId,agreementId};
}

/// Activa el convenio exclusivamente con la cuenta de su titular y consentimiento explícito.
async function activate(db,options={}){
  const result=await proposal(db,options);
  await session(db,options.owner??associate);
  await db.query('select public.respond_to_agreement($1,true,true)',[result.agreementId]);
  return result;
}

test('La propuesta preparada por el empleado requiere aceptación real del titular antes de asociarlo',async()=>{
  const db=await database({finalMvp:true});try{
    const result=await proposal(db,{staffPrepared:true});
    await session(db,associate);
    assert.equal((await db.query('select public.effective_role() role')).rows[0].role,'client');
    assert.equal((await db.query('select status from public.agreements')).rows[0].status,'awaiting_acceptance');
    assert((await db.query('select body from public.chat_messages')).rows.some(row=>row.body.includes('acepta expresamente')));
    await assert.rejects(db.query('select public.respond_to_agreement($1,true,false)',[result.agreementId]),{code:'22023'});
    await session(db,worker);await assert.rejects(db.query('select public.respond_to_agreement($1,true,true)',[result.agreementId]),{code:'42501'});
    await session(db,associate);await db.query('select public.respond_to_agreement($1,true,true)',[result.agreementId]);
    assert.equal((await db.query('select public.effective_role() role')).rows[0].role,'associate');
    const agreement=(await db.query('select status,accepted_by,accepted_at,acceptance_version from public.agreements')).rows[0];
    assert.equal(agreement.status,'active');assert.equal(agreement.accepted_by,associate);assert(agreement.accepted_at);assert(agreement.acceptance_version);
    await assert.rejects(db.query('select public.respond_to_agreement($1,true,true)',[result.agreementId]),{code:'P0001'});
  }finally{await db.close();}
});

test('Un convenio pendiente de aceptación o activo bloquea otra creación para cliente, trabajador y administrador',async()=>{
  const db=await database({finalMvp:true});try{
    const result=await proposal(db);
    for(const actor of [associate,worker,admin]){
      await session(db,actor);await assert.rejects(db.query('select public.start_association_request($1)',[associate]),{code:'P0001'});
    }
    await session(db,associate);await db.query('select public.respond_to_agreement($1,true,true)',[result.agreementId]);
    await session(db,admin);await assert.rejects(db.query('select public.start_association_request($1)',[associate]),{code:'P0001'});
    assert.equal((await db.query('select count(*) count from public.agreements')).rows[0].count,1);
  }finally{await db.close();}
});

test('La revocación exige motivo, conserva documentos, notifica y permite una nueva vinculación inmediata',async()=>{
  const db=await database({finalMvp:true});try{
    const result=await activate(db);
    await assert.rejects(db.query('select public.revoke_agreement($1,$2)',[result.agreementId,'Motivo no autorizado']),{code:'42501'});
    await session(db,worker);await assert.rejects(db.query('select public.revoke_agreement($1,$2)',[result.agreementId,'']),{code:'22023'});
    await db.query('select public.revoke_agreement($1,$2)',[result.agreementId,'El cliente solicitó terminar el convenio']);
    assert.equal((await db.query('select * from public.request_documents')).rows.length,3);
    const row=(await db.query('select * from public.agreements')).rows[0];
    assert.equal(row.status,'revoked');assert.equal(row.revoked_by,worker);assert.equal(row.closure_reason,'El cliente solicitó terminar el convenio');
    await session(db,associate);assert.equal((await db.query('select public.effective_role() role')).rows[0].role,'client');
    assert((await db.query('select body from public.chat_messages')).rows.some(row=>row.body.includes('solicitó terminar')));
    assert.notEqual((await db.query('select public.start_association_request() id')).rows[0].id,result.requestId);
  }finally{await db.close();}
});

test('El vencimiento se evalúa en servidor, sincroniza roles y permite renovar sin esperar treinta días',async()=>{
  const db=await database({finalMvp:true});try{
    const result=await activate(db);
    await db.exec('reset role');await db.query("update public.agreements set expires_at=now()-interval '1 second' where id=$1",[result.agreementId]);
    await session(db,associate);
    assert.equal((await db.query('select public.has_active_agreement($1) active',[associate])).rows[0].active,false);
    await db.query('select public.refresh_my_agreement_status()');
    assert.equal((await db.query('select public.effective_role() role')).rows[0].role,'client');
    assert.equal((await db.query('select status from public.agreements')).rows[0].status,'expired');
    assert.notEqual((await db.query('select public.start_association_request() id')).rows[0].id,result.requestId);
    assert((await db.query('select body from public.chat_messages')).rows.some(row=>row.body.includes('venció')));
  }finally{await db.close();}
});

test('Rechazar una propuesta no asigna asociación y libera la vinculación para otro intento',async()=>{
  const db=await database({finalMvp:true});try{
    const result=await proposal(db);
    await session(db,other);await assert.rejects(db.query('select public.respond_to_agreement($1,false,false,$2)',[result.agreementId,'No acepto las condiciones']),{code:'42501'});
    await session(db,associate);await db.query('select public.respond_to_agreement($1,false,false,$2)',[result.agreementId,'No acepto las condiciones']);
    assert.equal((await db.query('select status from public.agreements')).rows[0].status,'declined');
    assert.equal((await db.query('select public.effective_role() role')).rows[0].role,'client');
    assert((await db.query('select public.start_association_request() id')).rows[0].id);
  }finally{await db.close();}
});

test('El trabajador observa titulares y cultivos pero no puede crear, editar ni retirar lotes',async()=>{
  const db=await database({finalMvp:true});try{
    await activate(db);const lotId=await lot(db);
    const cultivationId=(await db.query('select cultivation_id from public.coffee_lots where id=$1',[lotId])).rows[0].cultivation_id;
    await session(db,worker);
    const rows=(await db.query('select * from public.list_coffee_cultivations()')).rows;
    assert.equal(rows.length,1);assert.equal(rows[0].list_coffee_cultivations.owner_email,'associate@example.com');
    await assert.rejects(db.query('select public.save_coffee_cultivation(null,$1,$2,$3,$4,$5,$6)',[associate,'Cultivo ilegal','Finca ajena','Ubicación ajena','Caturra',1]),{code:'42501'});
    await assert.rejects(db.query('select public.save_coffee_export_lot(null,$1,$2,$3,$4,$5,$6)',[cultivationId,'NUEVO','Lote ilegal',10,'2026-01-01','']),{code:'42501'});
    await assert.rejects(db.query('select public.delete_coffee_export_lot($1)',[lotId]),{code:'42501'});
    await session(db,associate);assert.equal((await db.query('select * from public.list_coffee_lots()')).rows.length,1);
    await session(db,other);assert.equal((await db.query('select * from public.list_coffee_lots()')).rows.length,0);
    await session(db,admin);await db.query('select public.save_coffee_export_lot($1,$2,$3,$4,$5,$6,$7)',[lotId,cultivationId,'ADMIN','Lote corregido',120,'2026-01-01','Corrección administrativa']);
  }finally{await db.close();}
});

test('Revocar asociación conserva los roles laborales y administrativos que ya tenía la cuenta',async()=>{
  const db=await database({finalMvp:true});try{
    const result=await activate(db);
    await session(db,admin);await db.query('select public.set_user_roles($1,$2)',[associate,['worker','associate','client']]);
    await db.query('select public.revoke_agreement($1,$2)',[result.agreementId,'Finalización acordada con el titular']);
    await session(db,associate);assert.equal((await db.query('select public.effective_role() role')).rows[0].role,'worker');
    assert.equal((await db.query("select * from public.user_roles where user_id=$1 and role='associate'",[associate])).rows.length,0);
  }finally{await db.close();}
});

test('Un convenio vencido impide enviar una exportación incluso antes de sincronizar el rol del dispositivo',async()=>{
  const db=await database({finalMvp:true});try{
    const agreement=await activate(db);const request=await draft(db,await lot(db));await documents(db,request);
    await db.exec('reset role');await db.query("update public.agreements set expires_at=now()-interval '1 second' where id=$1",[agreement.agreementId]);
    await session(db,associate);assert.equal((await db.query('select public.effective_role() role')).rows[0].role,'associate');
    await assert.rejects(submit(db,request),{code:'42501'});
    assert.equal((await db.query('select status from public.export_requests where id=$1',[request])).rows[0].status,'draft');
  }finally{await db.close();}
});
