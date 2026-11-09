-- Integra solicitudes, documentos privados, convenios, atención y revocación de acceso.
begin;

-- Conserva el historial de convenios cuando se elimina el acceso de una cuenta.
alter table public.profiles add column is_active boolean not null default true;
alter table public.profiles add column disabled_at timestamptz;

-- Comprueba en cada operación que la cuenta todavía tiene acceso al sistema.
create function public.is_active_user() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and is_active);
$$;

-- Determina el rol predominante sin confiar en datos editables por el usuario.
create function public.effective_role() returns text language sql stable security definer set search_path = '' as $$
  select r.role from public.user_roles r join public.profiles p on p.id = r.user_id
  where r.user_id = auth.uid() and p.is_active
  order by case r.role when 'admin' then 4 when 'worker' then 3 when 'associate' then 2 else 1 end desc limit 1;
$$;

-- Identifica al personal que atiende clientes y revisa convenios.
create function public.is_staff() returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.effective_role() in ('admin', 'worker'), false);
$$;

-- Mantiene la compatibilidad de las funciones anteriores y bloquea las cuentas desactivadas.
create or replace function public.has_role(requested_role text) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_roles r join public.profiles p on p.id = r.user_id
    where r.user_id = auth.uid() and r.role = requested_role and p.is_active);
$$;

-- Guarda tarifas ilustrativas que el administrador puede sustituir por sus precios reales.
create table public.freight_rates (
  id uuid primary key default gen_random_uuid(), -- Identifica la tarifa del catálogo.
  title text not null check (length(trim(title)) between 3 and 120), -- Describe el servicio ofertado.
  origin text not null, destination text not null, -- Define la ruta de importación.
  amount numeric(12,2) not null check (amount > 0), currency text not null default 'USD' check (currency in ('USD','COP')),
  unit text not null, description text not null, -- Explica qué incluye la referencia y su unidad.
  is_reference boolean not null default true, is_active boolean not null default true, -- Distingue ejemplos de tarifas comerciales activas.
  updated_at timestamptz not null default now() -- Registra la actualización de la información comercial.
);
insert into public.freight_rates (title, origin, destination, amount, unit, description) values
 ('Carga marítima consolidada', 'Shanghái', 'Buenaventura', 180, 'm³', 'Ejemplo ilustrativo. No incluye impuestos, aduana ni transporte nacional. Solicita una cotización.'),
 ('Carga aérea', 'Miami', 'Bogotá', 9.50, 'kg', 'Ejemplo ilustrativo sujeto a peso, volumen y disponibilidad. No constituye una cotización.'),
 ('Carga marítima desde Europa', 'Hamburgo', 'Cartagena', 220, 'm³', 'Ejemplo ilustrativo. El valor final requiere revisar origen, mercancía, documentos y condiciones del envío.');

-- Conserva una solicitud editable hasta que el cliente confirma su envío.
create table public.association_requests (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.profiles(id),
  status text not null default 'draft' check (status in ('draft','pending','approved','rejected')),
  full_name text not null default '', identity_number text not null default '', phone text not null default '',
  address text not null default '', business_description text not null default '', -- Conserva los datos declarados en cada solicitud.
  consent_at timestamptz, consent_version text, consent_by uuid references public.profiles(id), -- Registra la autorización y su responsable.
  submitted_at timestamptz, reviewed_at timestamptz, reviewed_by uuid references public.profiles(id),
  rejection_reason text, created_at timestamptz not null default now() -- Preserva la respuesta y el historial de cada intento.
);
create unique index association_one_open_request on public.association_requests(owner_id) where status in ('draft','pending');
create index association_requests_owner_date on public.association_requests(owner_id, submitted_at desc);

-- Enumera los tres soportes obligatorios sin permitir cambios después del envío.
create table public.request_documents (
  request_id uuid not null references public.association_requests(id) on delete cascade,
  kind text not null check (kind in ('identity','agreement_letter','tax_certificate')),
  storage_path text not null unique, original_name text not null check (length(original_name) between 1 and 200),
  uploaded_at timestamptz not null default now(), primary key (request_id, kind)
);

-- Crea el convenio únicamente al aprobar una solicitud completa.
create table public.agreements (
  id uuid primary key default gen_random_uuid(), agreement_number bigint generated always as identity unique,
  request_id uuid not null unique references public.association_requests(id), owner_id uuid not null references public.profiles(id),
  approved_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);

-- Mantiene una conversación de atención por cliente, compartida con el personal autorizado.
create table public.conversations (
  id uuid primary key default gen_random_uuid(), client_id uuid not null unique references public.profiles(id),
  last_message_at timestamptz not null default now(), created_at timestamptz not null default now()
);
create table public.chat_messages (
  id uuid primary key default gen_random_uuid(), conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id), request_id uuid references public.association_requests(id),
  kind text not null default 'text' check (kind in ('text','system')),
  body text not null check (length(trim(body)) between 1 and 4000), created_at timestamptz not null default now()
);
create index chat_messages_conversation_date on public.chat_messages(conversation_id, created_at desc, id);
create table public.conversation_reads (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id), read_at timestamptz not null,
  primary key (conversation_id, user_id)
);

-- Autoriza al titular activo y al personal; ninguna cuenta desactivada conserva acceso.
create function public.can_access_owner(target_owner uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_active_user() and (target_owner = auth.uid() or public.is_staff());
$$;
create function public.can_access_conversation(target_conversation uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.conversations where id = target_conversation and public.can_access_owner(client_id));
$$;

-- Un borrador no consume el plazo, pero una solicitud enviada sí se valida contra la última respuesta.
create function public.start_association_request(target_owner uuid default auth.uid()) returns uuid
language plpgsql security definer set search_path = '' as $$
declare current_request public.association_requests; last_request public.association_requests; result_id uuid;
begin
  if not public.can_access_owner(target_owner) then raise exception 'No tienes permiso para crear esta solicitud.' using errcode='42501'; end if;
  if not public.is_staff() and public.effective_role() <> 'client' then raise exception 'Tu cuenta ya tiene un rol de mayor acceso.' using errcode='42501'; end if;
  if not exists(select 1 from public.profiles where id=target_owner and is_active) then raise exception 'El cliente no está activo.' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(target_owner::text, 0)); -- Evita dos solicitudes simultáneas del mismo cliente.
  select * into current_request from public.association_requests where owner_id=target_owner and status in ('draft','pending');
  if found then
    if current_request.status='pending' then raise exception 'Ya tienes una solicitud pendiente de revisión.' using errcode='P0001'; end if;
    return current_request.id; -- Recupera el borrador y sus documentos cuando se vuelve al formulario.
  end if;
  select * into last_request from public.association_requests where owner_id=target_owner and submitted_at is not null order by submitted_at desc, id desc limit 1;
  if found and last_request.status <> 'rejected' and last_request.submitted_at > now()-interval '30 days' then
    raise exception 'Solo puedes enviar una solicitud cada 30 días, salvo que la anterior haya sido rechazada.' using errcode='P0001';
  end if;
  insert into public.association_requests(owner_id,full_name) select id,full_name from public.profiles where id=target_owner returning id into result_id;
  return result_id;
end;
$$;

-- Comprueba rutas sin convertir texto no confiable a UUID y sin exponer documentos ajenos.
create function public.can_access_request_file(object_name text, writing boolean default false) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.association_requests r where r.id::text=split_part(object_name,'/',2)
    and r.owner_id::text=split_part(object_name,'/',1) and public.can_access_owner(r.owner_id)
    and (not writing or r.status='draft') and object_name ~ '\.(pdf|jpg|jpeg|png)$');
$$;

-- Crea un depósito privado y limita los archivos a PDF e imágenes de hasta 10 MiB.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('agreement-documents','agreement-documents',false,10485760,array['application/pdf','image/jpeg','image/png'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;
create policy agreement_files_read on storage.objects for select to authenticated
using(bucket_id='agreement-documents' and public.can_access_request_file(name,false));
create policy agreement_files_insert on storage.objects for insert to authenticated
with check(bucket_id='agreement-documents' and public.can_access_request_file(name,true));
-- Los archivos no se sobrescriben ni eliminan desde el cliente; un borrador reemplaza su referencia por otra carga.

-- Registra un archivo solo si existe en Storage y pertenece al borrador correcto.
create function public.attach_request_document(target_request uuid, document_kind text, object_path text, file_name text) returns void
language plpgsql security definer set search_path = '' as $$
declare request_row public.association_requests;
begin
  select * into request_row from public.association_requests where id=target_request for update;
  if not found or not public.can_access_owner(request_row.owner_id) then raise exception 'No tienes acceso a esta solicitud.' using errcode='42501'; end if;
  if request_row.status <> 'draft' or document_kind not in ('identity','agreement_letter','tax_certificate') or document_kind is null
    or length(trim(file_name)) not between 1 and 200 or file_name is null
    or split_part(object_path,'/',2) <> target_request::text or not public.can_access_request_file(object_path,true) then
    raise exception 'El documento no corresponde a un borrador válido.' using errcode='22023';
  end if;
  if not exists(select 1 from storage.objects where bucket_id='agreement-documents' and name=object_path
    and metadata->>'mimetype' in ('application/pdf','image/jpeg','image/png')
    and coalesce((metadata->>'size')::bigint,0) between 1 and 10485760) then
    raise exception 'El archivo no existe o supera los formatos y tamaños permitidos.' using errcode='22023';
  end if;
  insert into public.request_documents(request_id,kind,storage_path,original_name) values(target_request,document_kind,object_path,file_name)
  on conflict(request_id,kind) do update set storage_path=excluded.storage_path,original_name=excluded.original_name,uploaded_at=now();
end;
$$;

-- Abre o recupera la conversación propia; el personal puede abrir la de un cliente.
create function public.open_support_conversation(target_owner uuid default auth.uid()) returns uuid
language plpgsql security definer set search_path = '' as $$
declare result_id uuid;
begin
  if not public.can_access_owner(target_owner) then raise exception 'No tienes acceso a esta conversación.' using errcode='42501'; end if;
  insert into public.conversations(client_id) values(target_owner) on conflict(client_id) do update set client_id=excluded.client_id returning id into result_id;
  return result_id;
end;
$$;

-- Envía la solicitud, registra la autorización y notifica al personal en una única transacción.
create function public.submit_association_request(target_request uuid, applicant_name text, applicant_identity text, applicant_phone text,
  applicant_address text, applicant_business text, accepted_data_processing boolean) returns uuid
language plpgsql security definer set search_path = '' as $$
declare request_row public.association_requests; last_request public.association_requests; conversation_id uuid;
begin
  select * into request_row from public.association_requests where id=target_request;
  if not found or not public.can_access_owner(request_row.owner_id) then raise exception 'No tienes acceso a esta solicitud.' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(request_row.owner_id::text,0)); -- Vuelve a validar el plazo en el envío, no solo al abrir el formulario.
  select * into request_row from public.association_requests where id=target_request for update;
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
  if found and last_request.status <> 'rejected' and last_request.submitted_at > now()-interval '30 days' then
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
    consent_at=now(),consent_version='2026-11-08-v1',consent_by=auth.uid() where id=target_request;
  conversation_id=public.open_support_conversation(request_row.owner_id);
  insert into public.chat_messages(conversation_id,sender_id,request_id,kind,body)
    values(conversation_id,auth.uid(),target_request,'system','Nueva solicitud de convenio enviada. Los tres documentos están disponibles para revisión.');
  update public.conversations set last_message_at=now() where id=conversation_id;
  return conversation_id;
end;
$$;

-- Resuelve una solicitud una sola vez y convierte al cliente en asociado al aprobarla.
create function public.review_association_request(target_request uuid, approve boolean, reason text default '') returns void
language plpgsql security definer set search_path = '' as $$
declare request_row public.association_requests; conversation_id uuid;
begin
  perform pg_advisory_xact_lock(748192031); -- Comparte la exclusión con los cambios administrativos de roles.
  if not public.is_staff() then raise exception 'Solo el personal puede revisar convenios.' using errcode='42501'; end if;
  select * into request_row from public.association_requests where id=target_request for update;
  if not found or request_row.status <> 'pending' then raise exception 'La solicitud ya no está pendiente.' using errcode='P0001'; end if;
  if not exists(select 1 from public.profiles where id=request_row.owner_id and is_active) then raise exception 'El cliente ya no tiene acceso activo.' using errcode='22023'; end if;
  if approve is null or (not approve and (reason is null or length(trim(reason)) not between 5 and 2000)) then
    raise exception 'Debes explicar el motivo del rechazo (entre 5 y 2000 caracteres).' using errcode='22023';
  end if;
  update public.association_requests set status=case when approve then 'approved' else 'rejected' end,
    reviewed_at=now(),reviewed_by=auth.uid(),rejection_reason=case when approve then null else trim(reason) end where id=target_request;
  if approve then
    insert into public.agreements(request_id,owner_id,approved_by) values(target_request,request_row.owner_id,auth.uid());
    insert into public.user_roles(user_id,role) values(request_row.owner_id,'associate') on conflict do nothing; -- Conserva otros roles y aplica la jerarquía.
    update public.profiles set updated_at=now() where id=request_row.owner_id;
  end if;
  conversation_id=public.open_support_conversation(request_row.owner_id);
  insert into public.chat_messages(conversation_id,sender_id,request_id,kind,body) values(conversation_id,auth.uid(),target_request,'system',
    case when approve then 'Convenio aprobado. Ahora eres asociado y puedes acceder a exportaciones, seguimiento y mis envíos.'
      else 'Solicitud rechazada: '||trim(reason)||'. Puedes corregirla y enviar una nueva solicitud sin esperar 30 días.' end);
  update public.conversations set last_message_at=now() where id=conversation_id;
end;
$$;

-- Escribe mensajes de atención sin permitir que el cliente simule notificaciones del sistema.
create function public.send_chat_message(target_conversation uuid, message_body text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.can_access_conversation(target_conversation) then raise exception 'No tienes acceso a esta conversación.' using errcode='42501'; end if;
  if message_body is null or length(trim(message_body)) not between 1 and 4000 then raise exception 'El mensaje debe contener entre 1 y 4000 caracteres.' using errcode='22023'; end if;
  insert into public.chat_messages(conversation_id,sender_id,body) values(target_conversation,auth.uid(),trim(message_body));
  update public.conversations set last_message_at=now() where id=target_conversation;
end;
$$;
create function public.mark_conversation_read(target_conversation uuid, last_message uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare seen_at timestamptz;
begin
  if not public.can_access_conversation(target_conversation) then raise exception 'No tienes acceso a esta conversación.' using errcode='42501'; end if;
  select created_at into seen_at from public.chat_messages where id=last_message and conversation_id=target_conversation;
  if found then insert into public.conversation_reads values(target_conversation,auth.uid(),seen_at)
    on conflict(conversation_id,user_id) do update set read_at=greatest(public.conversation_reads.read_at,excluded.read_at); end if;
end;
$$;
create function public.list_conversations() returns table(id uuid,client_id uuid,client_name text,last_message_at timestamptz,unread_count bigint)
language sql stable security definer set search_path = '' as $$
  select c.id,c.client_id,p.full_name,c.last_message_at,
    (select count(*) from public.chat_messages m where m.conversation_id=c.id and m.sender_id<>auth.uid()
      and m.created_at>coalesce(r.read_at,'epoch'::timestamptz))
  from public.conversations c join public.profiles p on p.id=c.client_id
  left join public.conversation_reads r on r.conversation_id=c.id and r.user_id=auth.uid()
  where public.can_access_owner(c.client_id) order by c.last_message_at desc,c.id;
$$;

-- Permite al personal consultar únicamente las cuentas comerciales activas.
create function public.list_customers() returns table(id uuid,full_name text,email text,created_at timestamptz,updated_at timestamptz,roles text[])
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_staff() then raise exception 'Solo el personal puede consultar clientes.' using errcode='42501'; end if;
  return query select p.id,p.full_name::text,p.email::text,p.created_at,p.updated_at,array_agg(r.role order by r.role)
    from public.profiles p join public.user_roles r on r.user_id=p.id where p.is_active
    and not exists(select 1 from public.user_roles elevated where elevated.user_id=p.id and elevated.role in ('admin','worker'))
    group by p.id,p.full_name,p.email,p.created_at,p.updated_at order by p.full_name,p.id;
end;
$$;

-- Guarda nombre, correo y roles en una transacción después de actualizar Supabase Auth desde el servidor.
create or replace function public.set_user_roles(target_user_id uuid,new_roles text[]) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(748192031); -- Serializa cambios y revocaciones de acceso.
  if not public.has_role('admin') then raise exception 'Necesitas administración.' using errcode='42501'; end if;
  if new_roles is null or array_position(new_roles,null) is not null or not(new_roles <@ array['admin','client','associate','worker']::text[]) then
    raise exception 'Los roles no son válidos.' using errcode='22023'; end if;
  if not exists(select 1 from public.profiles where id=target_user_id and is_active) then raise exception 'El usuario no está activo.' using errcode='22023'; end if;
  if exists(select 1 from public.user_roles where user_id=target_user_id and role='admin') and not('admin'=any(new_roles))
    and (select count(*) from public.user_roles r join public.profiles p on p.id=r.user_id where r.role='admin' and p.is_active)<=1 then
    raise exception 'Debe permanecer al menos un administrador activo.' using errcode='23514'; end if;
  delete from public.user_roles where user_id=target_user_id;
  insert into public.user_roles(user_id,role) select target_user_id,selected_role from(select distinct unnest(new_roles) selected_role) selected;
  update public.profiles set updated_at=now() where id=target_user_id;
end;
$$;

create function public.admin_update_user(target_user_id uuid,new_name text,new_email text,new_roles text[]) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_role('admin') then raise exception 'Necesitas administración.' using errcode='42501'; end if;
  if new_name is null or length(trim(new_name)) not between 3 and 100 or new_email is null or new_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'El nombre o el correo no son válidos.' using errcode='22023'; end if;
  perform public.set_user_roles(target_user_id,new_roles); -- Conserva la protección del último administrador.
  update public.profiles set full_name=trim(new_name),email=lower(trim(new_email)),updated_at=now() where id=target_user_id and is_active;
  if not found then raise exception 'El usuario no está activo.' using errcode='22023'; end if;
end;
$$;
create function public.admin_deactivate_user(target_user_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_role('admin') then raise exception 'Necesitas administración.' using errcode='42501'; end if;
  perform public.set_user_roles(target_user_id,'{}'::text[]); -- Impide eliminar el acceso del último administrador.
  update public.profiles set is_active=false,disabled_at=now(),updated_at=now() where id=target_user_id;
end;
$$;

-- Excluye usuarios eliminados del listado administrativo sin borrar documentos históricos.
drop function public.list_users(integer,integer);
create function public.list_users(page_offset integer default 0,page_size integer default 20)
returns table(id uuid,full_name text,email text,created_at timestamptz,updated_at timestamptz,roles text[])
language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_role('admin') then raise exception 'Necesitas administración.' using errcode='42501'; end if;
  if page_offset is null or page_size is null or page_offset<0 or page_size not between 1 and 100 then raise exception 'La paginación no es válida.' using errcode='22023'; end if;
  return query select p.id,p.full_name::text,p.email::text,p.created_at,p.updated_at,
    coalesce(array_agg(r.role order by r.role) filter(where r.role is not null),'{}'::text[])
    from public.profiles p left join public.user_roles r on r.user_id=p.id where p.is_active
    group by p.id,p.full_name,p.email,p.created_at,p.updated_at order by p.created_at desc,p.id limit page_size offset page_offset;
end;
$$;

-- Protege todas las tablas; las escrituras del flujo se realizan únicamente mediante funciones validadas.
alter table public.freight_rates enable row level security;
alter table public.association_requests enable row level security;
alter table public.request_documents enable row level security;
alter table public.agreements enable row level security;
alter table public.conversations enable row level security;
alter table public.chat_messages enable row level security;
alter table public.conversation_reads enable row level security;
create policy freight_read on public.freight_rates for select to authenticated using(public.is_active_user() and (is_active or public.has_role('admin')));
create policy freight_admin on public.freight_rates for all to authenticated using(public.has_role('admin')) with check(public.has_role('admin'));
create policy requests_read on public.association_requests for select to authenticated using(public.can_access_owner(owner_id) and (owner_id=auth.uid() or status<>'draft' or public.is_staff()));
create policy documents_read on public.request_documents for select to authenticated using(exists(select 1 from public.association_requests r where r.id=request_id and public.can_access_owner(r.owner_id)));
create policy agreements_read on public.agreements for select to authenticated using(public.can_access_owner(owner_id));
create policy conversations_read on public.conversations for select to authenticated using(public.can_access_owner(client_id));
create policy messages_read on public.chat_messages for select to authenticated using(public.can_access_conversation(conversation_id));
create policy reads_read on public.conversation_reads for select to authenticated using(user_id=auth.uid() and public.is_active_user());
revoke all on public.freight_rates,public.association_requests,public.request_documents,public.agreements,public.conversations,public.chat_messages,public.conversation_reads from public,anon,authenticated;
grant select on public.freight_rates,public.association_requests,public.request_documents,public.agreements,public.conversations,public.chat_messages,public.conversation_reads to authenticated;
grant insert,update,delete on public.freight_rates to authenticated; -- Las políticas anteriores restringen estas operaciones al administrador.
grant all on public.freight_rates,public.association_requests,public.request_documents,public.agreements,public.conversations,public.chat_messages,public.conversation_reads to service_role;

-- Retira la ejecución anónima predeterminada de todas las funciones incorporadas por este módulo.
do $$ declare item record; begin
  for item in select oid::regprocedure as signature from pg_proc where pronamespace='public'::regnamespace and proname in
    ('is_active_user','effective_role','is_staff','has_role','can_access_owner','can_access_conversation','can_access_request_file',
     'start_association_request','attach_request_document','open_support_conversation','submit_association_request','review_association_request',
     'send_chat_message','mark_conversation_read','list_conversations','list_customers','admin_update_user','admin_deactivate_user','list_users')
  loop execute format('revoke all on function %s from public,anon,authenticated',item.signature);
    execute format('grant execute on function %s to authenticated',item.signature); end loop;
end $$;
notify pgrst,'reload schema'; -- Actualiza la API publicada al completar la migración.
commit;
