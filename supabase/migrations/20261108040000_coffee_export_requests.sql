-- Introduce cultivos propios, solicitudes de exportación de café y autorización de cargos.
begin;

-- El transportador es un perfil operativo limitado y no hereda la administración de clientes.
alter table public.user_roles drop constraint user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check(role in('admin','worker','transporter','associate','client'));
create or replace function public.effective_role() returns text language sql stable security definer set search_path='' as $$
  select r.role from public.user_roles r join public.profiles p on p.id=r.user_id where r.user_id=auth.uid() and p.is_active
  order by case r.role when 'admin' then 5 when 'worker' then 4 when 'transporter' then 3 when 'associate' then 2 else 1 end desc limit 1;
$$;
create or replace function public.set_user_roles(target_user_id uuid,new_roles text[]) returns void language plpgsql security definer set search_path='' as $$
begin
  perform pg_advisory_xact_lock(748192031);
  if not public.has_role('admin') then raise exception 'Necesitas administración.' using errcode='42501';end if;
  if new_roles is null or array_position(new_roles,null) is not null or not(new_roles<@array['admin','worker','transporter','associate','client']::text[]) then raise exception 'Los roles no son válidos.' using errcode='22023';end if;
  if not exists(select 1 from public.profiles where id=target_user_id and is_active) then raise exception 'El usuario no está activo.' using errcode='22023';end if;
  if exists(select 1 from public.user_roles where user_id=target_user_id and role='admin') and not('admin'=any(new_roles))
    and(select count(*) from public.user_roles r join public.profiles p on p.id=r.user_id where r.role='admin' and p.is_active)<=1 then raise exception 'Debe permanecer al menos un administrador activo.' using errcode='23514';end if;
  delete from public.user_roles where user_id=target_user_id;
  insert into public.user_roles(user_id,role) select target_user_id,selected_role from(select distinct unnest(new_roles) selected_role) selected;
  update public.profiles set updated_at=now() where id=target_user_id;
end;
$$;

create table public.coffee_cultivations(
  id uuid primary key default gen_random_uuid(),owner_id uuid not null references public.profiles(id),
  name text not null,farm_name text not null,location text not null,variety text not null,
  area_hectares numeric(10,2) not null check(area_hectares>0 and area_hectares<100000000),
  created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
-- Los lotes anteriores permanecen sin titular hasta que el personal los asigne explícitamente; no se atribuyen a otro usuario.
alter table public.coffee_lots add column owner_id uuid references public.profiles(id);
alter table public.coffee_lots add column cultivation_id uuid references public.coffee_cultivations(id);
alter table public.coffee_lots add column lot_code text;
alter table public.coffee_lots add column harvest_date date;
create unique index coffee_lot_owner_code on public.coffee_lots(owner_id,lower(lot_code)) where owner_id is not null;
create index coffee_cultivations_owner on public.coffee_cultivations(owner_id);
create index coffee_lots_owner on public.coffee_lots(owner_id);

-- La tarifa inicial es un ejemplo configurable; el costo se calcula con el peso guardado en el servidor.
create table public.coffee_export_pricing(
  id boolean primary key default true check(id),rate_per_kg numeric(12,2) not null check(rate_per_kg>0 and rate_per_kg<10000000000),
  currency text not null check(currency in('COP','USD')),is_reference boolean not null default true,updated_at timestamptz not null default now()
);
insert into public.coffee_export_pricing(id,rate_per_kg,currency) values(true,1200,'COP');
create table public.export_requests(
  id uuid primary key default gen_random_uuid(),request_number bigint generated always as identity unique,
  owner_id uuid not null references public.profiles(id),lot_id uuid not null references public.coffee_lots(id),
  status text not null default 'draft' check(status in('draft','pending','approved','rejected')),
  origin text not null default '',destination text not null default '',recipient_name text not null default '',recipient_phone text not null default '',
  lot_snapshot jsonb,weight_kg numeric(12,2),rate_per_kg numeric(12,2),currency text,total_cost numeric(18,2),pricing_reference boolean,
  charge_authorized_at timestamptz,data_consent_at timestamptz,consent_version text,
  submitted_at timestamptz,reviewed_at timestamptz,reviewed_by uuid references public.profiles(id),rejection_reason text,
  created_at timestamptz not null default now()
);
-- Un rechazo libera el lote; una aprobación lo reserva de forma permanente para esa exportación.
create unique index export_one_reserved_lot on public.export_requests(lot_id) where status in('draft','pending','approved');
create index export_requests_owner_date on public.export_requests(owner_id,created_at desc);
create table public.export_documents(
  request_id uuid not null references public.export_requests(id),kind text not null check(kind in('commercial_invoice','packing_list','quality_record')),
  storage_path text not null,original_name text not null check(length(original_name) between 1 and 200),uploaded_at timestamptz not null default now(),
  primary key(request_id,kind),unique(request_id,storage_path)
);
create table public.export_charges(
  id uuid primary key default gen_random_uuid(),request_id uuid not null unique references public.export_requests(id),
  owner_id uuid not null references public.profiles(id),amount numeric(18,2) not null,currency text not null,
  status text not null default 'authorized' check(status='authorized'),authorized_at timestamptz not null,created_at timestamptz not null default now()
); -- Registra cargos autorizados dentro de Ritech; no ejecuta débitos bancarios ni marca pagos ficticios.

create function public.can_manage_coffee_owner(target_owner uuid) returns boolean language sql stable security definer set search_path='' as $$
  select coalesce(public.is_active_user() and(public.is_staff() or(target_owner=auth.uid() and public.effective_role()='associate')),false);
$$;
create function public.save_coffee_cultivation(target_id uuid,target_owner uuid,cultivation_name text,farm text,cultivation_location text,coffee_variety text,hectares numeric) returns uuid
language plpgsql security definer set search_path='' as $$
declare previous public.coffee_cultivations;result_id uuid;
begin
  if not public.can_manage_coffee_owner(target_owner) or not exists(select 1 from public.profiles p where p.id=target_owner and p.is_active
    and(public.has_role('admin') or exists(select 1 from public.user_roles r where r.user_id=p.id and r.role in('associate','worker','admin')))) then raise exception 'No puedes registrar cultivos para esta cuenta.' using errcode='42501';end if;
  if cultivation_name is null or length(trim(cultivation_name)) not between 3 and 100 or farm is null or length(trim(farm)) not between 3 and 150
    or cultivation_location is null or length(trim(cultivation_location)) not between 5 and 250 or coffee_variety is null or length(trim(coffee_variety)) not between 3 and 100
    or hectares is null or not(hectares>0 and hectares<100000000) then raise exception 'Completa nombre, finca, ubicación, variedad y área del cultivo.' using errcode='22023';end if;
  if target_id is not null then
    select * into previous from public.coffee_cultivations where id=target_id for update;
    if not found or previous.owner_id<>target_owner then raise exception 'El cultivo no corresponde a esta cuenta.' using errcode='42501';end if;
    update public.coffee_cultivations set name=trim(cultivation_name),farm_name=trim(farm),location=trim(cultivation_location),variety=trim(coffee_variety),area_hectares=hectares,updated_at=now() where id=target_id returning id into result_id;
  else insert into public.coffee_cultivations(owner_id,name,farm_name,location,variety,area_hectares) values(target_owner,trim(cultivation_name),trim(farm),trim(cultivation_location),trim(coffee_variety),hectares) returning id into result_id;end if;
  return result_id;
end;
$$;
create function public.save_coffee_export_lot(target_id uuid,target_cultivation uuid,code text,lot_name text,weight numeric,harvest date,lot_notes text) returns uuid
language plpgsql security definer set search_path='' as $$
declare cultivation public.coffee_cultivations;previous public.coffee_lots;result_id uuid;
begin
  select * into cultivation from public.coffee_cultivations where id=target_cultivation;
  if not found or not public.can_manage_coffee_owner(cultivation.owner_id) then raise exception 'No tienes acceso al cultivo seleccionado.' using errcode='42501';end if;
  if code is null or length(trim(code)) not between 2 and 50 or lot_name is null or length(trim(lot_name)) not between 3 and 100
    or weight is null or not(weight>0 and weight<10000000000) or harvest is null or harvest>current_date or length(coalesce(lot_notes,''))>2000 then raise exception 'Revisa código, nombre, peso y fecha de cosecha del lote.' using errcode='22023';end if;
  if target_id is not null then
    select * into previous from public.coffee_lots where id=target_id for update;
    if not found or not(public.can_manage_coffee_owner(previous.owner_id) or(previous.owner_id is null and public.is_staff())) then raise exception 'No tienes acceso al lote.' using errcode='42501';end if;
    if exists(select 1 from public.export_requests where lot_id=target_id and status in('draft','pending','approved')) then raise exception 'El lote está reservado por una solicitud o ya fue exportado.' using errcode='P0001';end if;
    update public.coffee_lots set owner_id=cultivation.owner_id,cultivation_id=cultivation.id,lot_code=trim(code),name=trim(lot_name),origin=cultivation.location,weight_kg=weight,harvest_date=harvest,notes=coalesce(lot_notes,''),updated_at=now() where id=target_id returning id into result_id;
  else insert into public.coffee_lots(owner_id,cultivation_id,lot_code,name,origin,weight_kg,harvest_date,notes) values(cultivation.owner_id,cultivation.id,trim(code),trim(lot_name),cultivation.location,weight,harvest,coalesce(lot_notes,'')) returning id into result_id;end if;
  return result_id;
end;
$$;
create function public.delete_coffee_export_lot(target_lot uuid) returns void language plpgsql security definer set search_path='' as $$
declare lot public.coffee_lots;
begin
  select * into lot from public.coffee_lots where id=target_lot for update;
  if not found or not(public.can_manage_coffee_owner(lot.owner_id) or(lot.owner_id is null and public.is_staff())) then raise exception 'No tienes acceso al lote.' using errcode='42501';end if;
  if exists(select 1 from public.export_requests where lot_id=target_lot) then raise exception 'El lote forma parte de un expediente y debe conservarse.' using errcode='P0001';end if;
  delete from public.coffee_lots where id=target_lot;
end;
$$;

create function public.start_coffee_export(target_lot uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare lot public.coffee_lots;existing public.export_requests;last_rejected public.export_requests;result_id uuid;
begin
  select * into lot from public.coffee_lots where id=target_lot for update; -- Serializa la reserva del mismo lote entre dos solicitudes.
  if not found or not public.can_manage_coffee_owner(lot.owner_id) or lot.cultivation_id is null or lot.lot_code is null then raise exception 'Selecciona un lote propio con cultivo y código registrados.' using errcode='42501';end if;
  if not exists(select 1 from public.profiles where id=lot.owner_id and is_active) then raise exception 'El titular del lote no está activo.' using errcode='42501';end if;
  select * into existing from public.export_requests where lot_id=target_lot and status in('draft','pending','approved');
  if found then
    if existing.status='draft' then return existing.id;end if;
    raise exception 'El lote ya tiene una solicitud pendiente o una exportación aprobada.' using errcode='P0001';
  end if;
  insert into public.export_requests(owner_id,lot_id,origin) values(lot.owner_id,lot.id,lot.origin) returning id into result_id;
  select * into last_rejected from public.export_requests where lot_id=target_lot and status='rejected' order by created_at desc,id desc limit 1;
  if found then
    update public.export_requests set origin=last_rejected.origin,destination=last_rejected.destination,recipient_name=last_rejected.recipient_name,recipient_phone=last_rejected.recipient_phone where id=result_id;
    insert into public.export_documents(request_id,kind,storage_path,original_name) select result_id,kind,storage_path,original_name from public.export_documents where request_id=last_rejected.id; -- Conserva soportes inmutables y permite reemplazar únicamente los que necesiten corrección.
  end if;
  return result_id;
end;
$$;
create function public.quote_coffee_export(target_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare request_row public.export_requests;lot public.coffee_lots;pricing public.coffee_export_pricing;
begin
  select * into request_row from public.export_requests where id=target_request;
  if not found or not public.can_manage_coffee_owner(request_row.owner_id) then raise exception 'No tienes acceso a esta solicitud.' using errcode='42501';end if;
  select * into lot from public.coffee_lots where id=request_row.lot_id;
  select * into pricing from public.coffee_export_pricing where id=true;
  if round(lot.weight_kg*pricing.rate_per_kg,2)<=0 or round(lot.weight_kg*pricing.rate_per_kg,2)>=10000000000000000 then raise exception 'El peso y la tarifa no producen un importe válido. Solicita revisión del costo al administrador.' using errcode='22023';end if;
  return jsonb_build_object('weight_kg',lot.weight_kg,'rate_per_kg',pricing.rate_per_kg,'currency',pricing.currency,'total_cost',round(lot.weight_kg*pricing.rate_per_kg,2),'is_reference',pricing.is_reference);
end;
$$;

-- Los soportes de exportación permanecen en otro depósito privado, separados del convenio de vinculación.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('export-documents','export-documents',false,10485760,array['application/pdf','image/jpeg','image/png'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;
create function public.can_access_export_file(object_name text,writing boolean default false) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.export_requests r where r.id::text=split_part(object_name,'/',2) and r.owner_id::text=split_part(object_name,'/',1)
    and public.can_manage_coffee_owner(r.owner_id) and(not writing or r.status='draft') and object_name~'\.(pdf|jpg|jpeg|png)$');
$$;
create policy export_files_read on storage.objects for select to authenticated using(bucket_id='export-documents' and public.can_access_export_file(name,false));
create policy export_files_insert on storage.objects for insert to authenticated with check(bucket_id='export-documents' and public.can_access_export_file(name,true));
create function public.attach_export_document(target_request uuid,document_kind text,object_path text,file_name text) returns void language plpgsql security definer set search_path='' as $$
declare request_row public.export_requests;
begin
  select * into request_row from public.export_requests where id=target_request for update;
  if not found or not public.can_manage_coffee_owner(request_row.owner_id) then raise exception 'No tienes acceso a esta solicitud.' using errcode='42501';end if;
  if request_row.status<>'draft' or document_kind is null or document_kind not in('commercial_invoice','packing_list','quality_record')
    or object_path is null or split_part(object_path,'/',2)<>target_request::text or not public.can_access_export_file(object_path,true)
    or file_name is null or length(trim(file_name)) not between 1 and 200 then raise exception 'El documento no corresponde a un borrador válido.' using errcode='22023';end if;
  if not exists(select 1 from storage.objects where bucket_id='export-documents' and name=object_path and metadata->>'mimetype' in('application/pdf','image/jpeg','image/png')
    and coalesce((metadata->>'size')::bigint,0) between 1 and 10485760) then raise exception 'El soporte no está disponible o su formato o tamaño no es válido.' using errcode='22023';end if;
  insert into public.export_documents(request_id,kind,storage_path,original_name) values(target_request,document_kind,object_path,file_name)
  on conflict(request_id,kind) do update set storage_path=excluded.storage_path,original_name=excluded.original_name,uploaded_at=now();
end;
$$;

alter table public.coffee_cultivations enable row level security;
alter table public.coffee_export_pricing enable row level security;
alter table public.export_requests enable row level security;
alter table public.export_documents enable row level security;
alter table public.export_charges enable row level security;
drop policy coffee_staff on public.coffee_lots;
create policy coffee_lots_read on public.coffee_lots for select to authenticated using(public.can_manage_coffee_owner(owner_id) or(owner_id is null and public.is_staff()));
create policy cultivations_read on public.coffee_cultivations for select to authenticated using(public.can_manage_coffee_owner(owner_id));
create policy coffee_pricing_read on public.coffee_export_pricing for select to authenticated using(public.is_active_user() and(public.is_staff() or public.effective_role()='associate'));
create policy coffee_pricing_admin on public.coffee_export_pricing for update to authenticated using(public.has_role('admin')) with check(public.has_role('admin'));
create policy export_requests_read on public.export_requests for select to authenticated using(public.can_manage_coffee_owner(owner_id));
create policy export_documents_read on public.export_documents for select to authenticated using(exists(select 1 from public.export_requests r where r.id=request_id and public.can_manage_coffee_owner(r.owner_id)));
create policy export_charges_read on public.export_charges for select to authenticated using(public.can_manage_coffee_owner(owner_id));
revoke all on public.coffee_cultivations,public.coffee_export_pricing,public.export_requests,public.export_documents,public.export_charges,public.coffee_lots from public,anon,authenticated;
grant select on public.coffee_cultivations,public.coffee_export_pricing,public.export_requests,public.export_documents,public.export_charges,public.coffee_lots to authenticated;
grant update on public.coffee_export_pricing to authenticated;
grant all on public.coffee_cultivations,public.coffee_export_pricing,public.export_requests,public.export_documents,public.export_charges to service_role;

-- Retira el antiguo registro directo de envíos para que ninguna cuenta eluda documentos, revisión y autorización.
revoke execute on function public.create_shipment(uuid,text,text,text,text) from authenticated,anon,public;
do $$declare item record;begin
  for item in select oid::regprocedure signature from pg_proc where pronamespace='public'::regnamespace and proname in
    ('can_manage_coffee_owner','save_coffee_cultivation','save_coffee_export_lot','delete_coffee_export_lot','start_coffee_export','quote_coffee_export','can_access_export_file','attach_export_document')
  loop execute format('revoke all on function %s from public,anon,authenticated',item.signature);execute format('grant execute on function %s to authenticated',item.signature);end loop;
end $$;
notify pgrst,'reload schema';
commit;
