-- Completa la aceptación, vigencia y revocación de convenios sin eliminar sus documentos históricos.
begin;

alter table public.association_requests add column prepared_by uuid references public.profiles(id); -- Identifica al empleado que prepara una propuesta para un cliente.
alter table public.association_requests add column proposed_expires_at timestamptz; -- Conserva la fecha propuesta antes de que el cliente acepte.
alter table public.agreements add column status text not null default 'active' check(status in('awaiting_acceptance','active','revoked','expired','declined'));
alter table public.agreements add column expires_at timestamptz; -- Los convenios históricos sin fecha mantienen su vigencia hasta su revocación.
alter table public.agreements add column accepted_at timestamptz;
alter table public.agreements add column accepted_by uuid references public.profiles(id);
alter table public.agreements add column acceptance_version text; -- No atribuye una aceptación nueva a los convenios anteriores.
alter table public.agreements add column revoked_at timestamptz;
alter table public.agreements add column revoked_by uuid references public.profiles(id);
alter table public.agreements add column closure_reason text;

-- Si existían duplicados, mantiene el convenio más reciente y conserva los demás como historial cerrado.
with ranked as (
  select id,row_number() over(partition by owner_id order by created_at desc,agreement_number desc) position from public.agreements
)
update public.agreements set status='revoked',revoked_at=now(),closure_reason='Regularización del MVP: se conserva únicamente el convenio más reciente del titular.'
where id in(select id from ranked where position>1);
create unique index agreement_one_open_owner on public.agreements(owner_id) where status in('active','awaiting_acceptance');

-- Evalúa la fecha en el servidor aunque todavía no haya ocurrido la siguiente comprobación del perfil.
create function public.has_active_agreement(target_owner uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.agreements where owner_id=target_owner and status='active' and(expires_at is null or expires_at>now()));
$$;

-- Publica avisos auténticos con un enlace al expediente desde el chat de atención del titular.
create function public.emit_agreement_message(target_request uuid,message_body text) returns void language plpgsql security definer set search_path='' as $$
declare owner uuid;conversation uuid;
begin
  select owner_id into owner from public.association_requests where id=target_request;
  insert into public.conversations(client_id,channel) values(owner,'support')
    on conflict(client_id,channel) where export_request_id is null do update set client_id=excluded.client_id returning id into conversation;
  insert into public.chat_messages(conversation_id,sender_id,request_id,kind,body) values(conversation,auth.uid(),target_request,'system',message_body);
  update public.conversations set last_message_at=now() where id=conversation;
end;
$$;

-- Retira solo asociación cuando no queda ningún convenio vigente; conserva los roles administrativos y laborales.
create function public.sync_agreement_role(target_owner uuid) returns void language plpgsql security definer set search_path='' as $$
begin
  if not public.has_active_agreement(target_owner) then
    delete from public.user_roles where user_id=target_owner and role='associate';
    insert into public.user_roles(user_id,role) values(target_owner,'client') on conflict do nothing;
    update public.profiles set updated_at=now() where id=target_owner;
  end if;
end;
$$;

-- Se ejecuta dentro de las operaciones del titular; no depende de un temporizador del dispositivo para determinar vigencia.
create function public.expire_owner_agreements(target_owner uuid) returns void language plpgsql security definer set search_path='' as $$
declare expired public.agreements;
begin
  for expired in update public.agreements set status='expired',closure_reason='El convenio alcanzó su fecha de vencimiento.'
    where owner_id=target_owner and status in('active','awaiting_acceptance') and expires_at<=now() returning *
  loop
    perform public.emit_agreement_message(expired.request_id,'Tu convenio venció. Puedes iniciar una nueva vinculación desde la tienda o solicitar ayuda al personal.');
  end loop;
  if found then perform public.sync_agreement_role(target_owner);end if;
end;
$$;

-- Sincroniza únicamente a la cuenta autenticada al cargar sus permisos.
create function public.refresh_my_agreement_status() returns void language plpgsql security definer set search_path='' as $$
begin
  if not public.is_active_user() then return;end if;
  if exists(select 1 from public.agreements where owner_id=auth.uid() and status in('active','awaiting_acceptance') and expires_at<=now()) then
    perform pg_advisory_xact_lock(748192031);
    perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
    perform public.expire_owner_agreements(auth.uid());
  end if;
end;
$$;

-- Permite otra vinculación al finalizar la anterior y bloquea tanto convenios activos como propuestas por aceptar.
create or replace function public.start_association_request(target_owner uuid default auth.uid()) returns uuid language plpgsql security definer set search_path='' as $$
declare current_request public.association_requests;last_request public.association_requests;result_id uuid;
begin
  if not public.can_access_owner(target_owner) then raise exception 'No tienes permiso para crear esta solicitud.' using errcode='42501';end if;
  perform pg_advisory_xact_lock(748192031);
  perform pg_advisory_xact_lock(hashtextextended(target_owner::text,0));
  perform public.expire_owner_agreements(target_owner);
  if not exists(select 1 from public.profiles where id=target_owner and is_active) then raise exception 'El cliente no está activo.' using errcode='22023';end if;
  if exists(select 1 from public.agreements where owner_id=target_owner and status in('active','awaiting_acceptance')) then raise exception 'El usuario ya tiene un convenio activo o pendiente de aceptación. Debe finalizar antes de crear otro.' using errcode='P0001';end if;
  if not public.is_staff() and coalesce(public.effective_role(),'') not in('client','associate') then raise exception 'Tu cuenta no puede solicitar una vinculación comercial.' using errcode='42501';end if;
  select * into current_request from public.association_requests where owner_id=target_owner and status in('draft','pending');
  if found then
    if current_request.status='pending' then raise exception 'Ya existe una solicitud pendiente de revisión.' using errcode='P0001';end if;
    return current_request.id;
  end if;
  select * into last_request from public.association_requests where owner_id=target_owner and submitted_at is not null order by submitted_at desc,id desc limit 1;
  if found and last_request.status not in('rejected','approved') and last_request.submitted_at>now()-interval '30 days' then raise exception 'Solo puedes solicitar un convenio cada 30 días, salvo rechazo o finalización del anterior.' using errcode='P0001';end if;
  insert into public.association_requests(owner_id,full_name,prepared_by) select id,full_name,case when auth.uid()<>id then auth.uid() else null end from public.profiles where id=target_owner returning id into result_id;
  return result_id;
end;
$$;

-- La revisión prepara una propuesta: el rol asociado se asignará exclusivamente al aceptar el titular.
drop function public.review_association_request(uuid,boolean,text);
create function public.review_association_request(target_request uuid,approve boolean,reason text default '',valid_until timestamptz default null) returns void language plpgsql security definer set search_path='' as $$
declare request_row public.association_requests;expiration timestamptz;
begin
  if not public.is_staff() then raise exception 'Solo el personal puede revisar convenios.' using errcode='42501';end if;
  perform pg_advisory_xact_lock(748192031);
  select * into request_row from public.association_requests where id=target_request;
  if not found then raise exception 'La solicitud no está disponible.' using errcode='P0001';end if;
  perform pg_advisory_xact_lock(hashtextextended(request_row.owner_id::text,0));
  select * into request_row from public.association_requests where id=target_request for update;
  if request_row.status<>'pending' then raise exception 'La solicitud ya no está pendiente.' using errcode='P0001';end if;
  perform public.expire_owner_agreements(request_row.owner_id);
  if not exists(select 1 from public.profiles where id=request_row.owner_id and is_active) then raise exception 'El titular ya no está activo.' using errcode='22023';end if;
  if approve is null or(not approve and(reason is null or length(trim(reason)) not between 5 and 2000)) then raise exception 'Explica el motivo del rechazo entre 5 y 2000 caracteres.' using errcode='22023';end if;
  if approve then
    if exists(select 1 from public.agreements where owner_id=request_row.owner_id and status in('active','awaiting_acceptance')) then raise exception 'El titular ya tiene un convenio activo o pendiente de aceptación.' using errcode='P0001';end if;
    expiration=coalesce(valid_until,request_row.proposed_expires_at,now()+interval '1 year');
    if expiration<=now() or expiration>now()+interval '10 years' then raise exception 'Selecciona una vigencia futura de hasta diez años.' using errcode='22023';end if;
    insert into public.agreements(request_id,owner_id,approved_by,status,expires_at) values(target_request,request_row.owner_id,auth.uid(),'awaiting_acceptance',expiration);
  end if;
  update public.association_requests set status=case when approve then 'approved' else 'rejected' end,reviewed_at=now(),reviewed_by=auth.uid(),rejection_reason=case when approve then null else trim(reason) end where id=target_request;
  perform public.emit_agreement_message(target_request,case when approve then 'Tienes una propuesta de convenio. Abre el expediente, revisa sus documentos y vigencia, y acepta expresamente para convertirte en asociado.'
    else 'Solicitud rechazada: '||trim(reason)||'. Puedes corregirla y volver a enviarla sin esperar 30 días.' end);
end;
$$;

-- La aceptación se verifica con la identidad real del cliente y nunca con la sesión del empleado.
create function public.respond_to_agreement(target_agreement uuid,accept boolean,accepted_terms boolean,reason text default '') returns void language plpgsql security definer set search_path='' as $$
declare agreement public.agreements;
begin
  if not public.is_active_user() then raise exception 'Inicia sesión con el titular del convenio.' using errcode='42501';end if;
  perform pg_advisory_xact_lock(748192031);
  select * into agreement from public.agreements where id=target_agreement;
  if not found or agreement.owner_id<>auth.uid() then raise exception 'Solo el titular puede responder a su convenio.' using errcode='42501';end if;
  perform pg_advisory_xact_lock(hashtextextended(agreement.owner_id::text,0));
  select * into agreement from public.agreements where id=target_agreement for update;
  if agreement.status<>'awaiting_acceptance' or agreement.expires_at<=now() then raise exception 'Esta propuesta ya fue respondida, revocada o venció.' using errcode='P0001';end if;
  if accept is null or(accept and accepted_terms is distinct from true) or(not accept and(reason is null or length(trim(reason)) not between 5 and 2000)) then raise exception 'Confirma la aceptación del convenio o explica el motivo para rechazarlo.' using errcode='22023';end if;
  update public.agreements set status=case when accept then 'active' else 'declined' end,accepted_at=case when accept then now() else null end,
    accepted_by=case when accept then auth.uid() else null end,acceptance_version=case when accept then 'agreement-2026-11-09-v1' else null end,closure_reason=case when accept then null else trim(reason) end where id=target_agreement;
  if accept then
    insert into public.user_roles(user_id,role) values(auth.uid(),'associate') on conflict do nothing;
    update public.profiles set updated_at=now() where id=auth.uid();
  end if;
  perform public.emit_agreement_message(agreement.request_id,case when accept then 'El titular aceptó el convenio. Tu cuenta ya está habilitada como asociado para operar con café.' else 'El titular rechazó la propuesta: '||trim(reason)||'. Puede iniciarse una nueva vinculación.' end);
end;
$$;

-- Revocar significa cerrar el convenio y conservar su expediente, no borrar pruebas ni documentos.
create function public.revoke_agreement(target_agreement uuid,reason text) returns void language plpgsql security definer set search_path='' as $$
declare agreement public.agreements;
begin
  if not public.is_staff() then raise exception 'Solo el personal puede revocar convenios.' using errcode='42501';end if;
  if reason is null or length(trim(reason)) not between 5 and 2000 then raise exception 'Explica el motivo de revocación entre 5 y 2000 caracteres.' using errcode='22023';end if;
  perform pg_advisory_xact_lock(748192031);
  select * into agreement from public.agreements where id=target_agreement;
  if not found then raise exception 'El convenio no está disponible.' using errcode='P0001';end if;
  perform pg_advisory_xact_lock(hashtextextended(agreement.owner_id::text,0));
  select * into agreement from public.agreements where id=target_agreement for update;
  if agreement.status not in('active','awaiting_acceptance') then raise exception 'El convenio ya está cerrado.' using errcode='P0001';end if;
  update public.agreements set status='revoked',revoked_at=now(),revoked_by=auth.uid(),closure_reason=trim(reason) where id=target_agreement;
  perform public.sync_agreement_role(agreement.owner_id);
  perform public.emit_agreement_message(agreement.request_id,'El personal revocó tu convenio. Motivo: '||trim(reason)||'. Puedes solicitar atención o una nueva vinculación.');
end;
$$;

-- El alcance de lectura continúa siendo el del titular o del personal autorizado.
drop function public.submit_association_request(uuid,text,text,text,text,text,boolean);
create function public.submit_association_request(target_request uuid, applicant_name text, applicant_identity text, applicant_phone text,
  applicant_address text, applicant_business text, accepted_data_processing boolean, valid_until timestamptz default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare request_row public.association_requests; last_request public.association_requests; conversation_id uuid;
begin
  select * into request_row from public.association_requests where id=target_request;
  if not found or not public.can_access_owner(request_row.owner_id) then raise exception 'No tienes acceso a esta solicitud.' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(748192031);
  perform pg_advisory_xact_lock(hashtextextended(request_row.owner_id::text,0)); -- Vuelve a validar el plazo en el envío, no solo al abrir el formulario.
  select * into request_row from public.association_requests where id=target_request for update;
  perform public.expire_owner_agreements(request_row.owner_id);
  if exists(select 1 from public.agreements where owner_id=request_row.owner_id and status in('active','awaiting_acceptance')) then raise exception 'El titular ya tiene un convenio abierto.' using errcode='P0001';end if;
  if request_row.status <> 'draft' then raise exception 'La solicitud ya fue enviada.' using errcode='P0001'; end if;
  if accepted_data_processing is distinct from true then raise exception 'Debes aceptar el tratamiento de datos.' using errcode='22023'; end if;
  if applicant_name is null or length(trim(applicant_name)) not between 3 and 100
    or applicant_identity is null or applicant_identity !~ '^[0-9A-Za-z-]{5,25}$'
    or applicant_phone is null or applicant_phone !~ '^[+0-9 ()-]{7,25}$'
    or applicant_address is null or length(trim(applicant_address)) not between 5 and 250
    or applicant_business is null or length(trim(applicant_business)) not between 10 and 2000 then
    raise exception 'Revisa el nombre, identificación, contacto, dirección y actividad comercial.' using errcode='22023';
  end if;
  select * into last_request from public.association_requests where owner_id=request_row.owner_id and submitted_at is not null order by submitted_at desc,id desc limit 1;
  if found and last_request.status not in ('rejected','approved') and last_request.submitted_at > now()-interval '30 days' then
    raise exception 'Solo puedes enviar una solicitud cada 30 días, salvo rechazo de la anterior.' using errcode='P0001';
  end if;
  if (select count(*) from public.request_documents where request_id=target_request) <> 3 then
    raise exception 'Debes adjuntar los tres documentos obligatorios.' using errcode='22023';
  end if;
  if exists(select 1 from public.request_documents d where d.request_id=target_request and not exists(
    select 1 from storage.objects o where o.bucket_id='agreement-documents' and o.name=d.storage_path)) then
    raise exception 'Algún documento ya no está disponible. Vuelve a adjuntarlo.' using errcode='22023';
  end if;
  update public.association_requests set full_name=trim(applicant_name),identity_number=trim(applicant_identity),phone=trim(applicant_phone),
    address=trim(applicant_address),business_description=trim(applicant_business),status='pending',submitted_at=now(),
    proposed_expires_at=case when public.is_staff() and auth.uid()<>request_row.owner_id then coalesce(valid_until,now()+interval '1 year') else null end,
    prepared_by=case when auth.uid()<>request_row.owner_id then auth.uid() else prepared_by end,
    consent_at=now(),consent_version='2026-11-08-v1',consent_by=auth.uid() where id=target_request;
  conversation_id=public.open_support_conversation(request_row.owner_id);
  insert into public.chat_messages(conversation_id,sender_id,request_id,kind,body)
    values(conversation_id,auth.uid(),target_request,'system','Nueva solicitud de convenio enviada. Los tres documentos están disponibles para revisión.');
  update public.conversations set last_message_at=now() where id=conversation_id;
  if public.is_staff() and auth.uid()<>request_row.owner_id then
    perform public.review_association_request(target_request,true,'',valid_until);
  end if;
  return conversation_id;
end;
$$;
revoke all on function public.submit_association_request(uuid,text,text,text,text,text,boolean,timestamptz) from public,anon,authenticated;
grant execute on function public.submit_association_request(uuid,text,text,text,text,text,boolean,timestamptz) to authenticated;

revoke all on function public.emit_agreement_message(uuid,text),public.sync_agreement_role(uuid),public.expire_owner_agreements(uuid) from public,anon,authenticated;
revoke all on function public.has_active_agreement(uuid),public.refresh_my_agreement_status(),public.respond_to_agreement(uuid,boolean,boolean,text),public.revoke_agreement(uuid,text),public.review_association_request(uuid,boolean,text,timestamptz) from public,anon,authenticated;
grant execute on function public.has_active_agreement(uuid),public.refresh_my_agreement_status(),public.respond_to_agreement(uuid,boolean,boolean,text),public.revoke_agreement(uuid,text),public.review_association_request(uuid,boolean,text,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
