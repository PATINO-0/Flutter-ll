-- Habilita operaciones propias de asociados y la gestión interna de café y seguimiento.
begin;
create table public.shipments(
  id uuid primary key default gen_random_uuid(),owner_id uuid not null references public.profiles(id),
  tracking_code text not null unique default ('RIT-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,16))),
  operation_type text not null check(operation_type in ('import','export')),
  description text not null check(length(trim(description)) between 3 and 500),origin text not null,destination text not null,
  status text not null default 'pending' check(status in ('pending','in_transit','customs','delivered','cancelled')),
  created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index shipments_owner_created on public.shipments(owner_id,created_at desc);
create table public.shipment_events(
  id uuid primary key default gen_random_uuid(),shipment_id uuid not null references public.shipments(id),
  status text not null,notes text not null,created_by uuid not null references public.profiles(id),created_at timestamptz not null default now()
);
create table public.coffee_lots(
  id uuid primary key default gen_random_uuid(),name text not null check(length(trim(name)) between 3 and 100),
  origin text not null check(length(trim(origin)) between 3 and 150),weight_kg numeric(12,2) not null check(weight_kg>0),
  notes text not null default '',updated_at timestamptz not null default now()
);

-- El cliente todavía no puede consultar ni registrar operaciones de importación o exportación.
create function public.can_access_shipment(target_shipment uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.shipments s where s.id=target_shipment and public.is_active_user()
    and (public.is_staff() or (s.owner_id=auth.uid() and public.effective_role()='associate')));
$$;
create function public.create_shipment(target_owner uuid,shipment_type text,shipment_description text,shipment_origin text,shipment_destination text) returns uuid
language plpgsql security definer set search_path='' as $$
declare result_id uuid;
begin
  if not public.is_active_user() or not(public.is_staff() or(public.effective_role()='associate' and target_owner=auth.uid())) then
    raise exception 'Solo un asociado o el personal puede registrar operaciones.' using errcode='42501'; end if;
  if not exists(select 1 from public.profiles p where p.id=target_owner and p.is_active and
    (public.has_role('admin') or exists(select 1 from public.user_roles r where r.user_id=p.id and r.role in ('associate','admin','worker')))) then
    raise exception 'La cuenta seleccionada necesita un convenio aprobado.' using errcode='22023'; end if;
  if shipment_type is null or shipment_type not in ('import','export') or shipment_description is null or length(trim(shipment_description)) not between 3 and 500
    or shipment_origin is null or length(trim(shipment_origin)) not between 3 and 150 or shipment_destination is null or length(trim(shipment_destination)) not between 3 and 150 then
    raise exception 'Completa el tipo, descripción, origen y destino.' using errcode='22023'; end if;
  insert into public.shipments(owner_id,operation_type,description,origin,destination,created_by)
    values(target_owner,shipment_type,trim(shipment_description),trim(shipment_origin),trim(shipment_destination),auth.uid()) returning id into result_id;
  insert into public.shipment_events(shipment_id,status,notes,created_by) values(result_id,'pending','Operación registrada y pendiente de gestión.',auth.uid());
  return result_id;
end;
$$;

-- Registra cada cambio de estado para que el seguimiento conserve su historial.
create function public.update_shipment_status(target_shipment uuid,new_status text,event_notes text) returns void
language plpgsql security definer set search_path='' as $$
declare previous_status text;
begin
  if not public.is_staff() then raise exception 'Solo el personal puede modificar el seguimiento.' using errcode='42501'; end if;
  select status into previous_status from public.shipments where id=target_shipment for update;
  if not found then raise exception 'La operación no existe.' using errcode='22023'; end if;
  if new_status is null or new_status not in ('pending','in_transit','customs','delivered','cancelled') or event_notes is null or length(trim(event_notes)) not between 3 and 2000 then
    raise exception 'Selecciona un estado y describe la actualización.' using errcode='22023'; end if;
  if not public.has_role('admin') and not((previous_status='pending' and new_status in ('in_transit','cancelled'))
    or(previous_status='in_transit' and new_status in ('customs','delivered','cancelled'))
    or(previous_status='customs' and new_status in ('in_transit','delivered','cancelled'))) then
    raise exception 'La transición de seguimiento no es válida para el estado actual.' using errcode='22023'; end if;
  update public.shipments set status=new_status,updated_at=now() where id=target_shipment;
  insert into public.shipment_events(shipment_id,status,notes,created_by) values(target_shipment,new_status,trim(event_notes),auth.uid());
end;
$$;

alter table public.shipments enable row level security;
alter table public.shipment_events enable row level security;
alter table public.coffee_lots enable row level security;
create policy shipments_read on public.shipments for select to authenticated using(public.is_active_user() and(public.is_staff() or(owner_id=auth.uid() and public.effective_role()='associate')));
create policy shipment_events_read on public.shipment_events for select to authenticated using(public.can_access_shipment(shipment_id));
create policy coffee_staff on public.coffee_lots for all to authenticated using(public.is_staff()) with check(public.is_staff());
revoke all on public.shipments,public.shipment_events,public.coffee_lots from public,anon,authenticated;
grant select on public.shipments,public.shipment_events to authenticated;
grant select,insert,update,delete on public.coffee_lots to authenticated;
grant all on public.shipments,public.shipment_events,public.coffee_lots to service_role;
revoke all on function public.can_access_shipment(uuid),public.create_shipment(uuid,text,text,text,text),public.update_shipment_status(uuid,text,text) from public,anon,authenticated;
grant execute on function public.can_access_shipment(uuid),public.create_shipment(uuid,text,text,text,text),public.update_shipment_status(uuid,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
