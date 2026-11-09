-- El trabajador supervisa cultivos y lotes; únicamente su titular asociado o administración pueden modificarlos.
begin;
create function public.can_edit_coffee_owner(target_owner uuid) returns boolean language sql stable security definer set search_path='' as $$
  select coalesce(public.is_active_user() and(public.has_role('admin') or(target_owner=auth.uid() and public.effective_role()='associate' and public.has_active_agreement(target_owner))),false);
$$;

-- Devuelve identidad del titular solo dentro del inventario que esta sesión puede consultar.
create function public.list_coffee_cultivations() returns setof jsonb language sql stable security definer set search_path='' as $$
  select to_jsonb(c)||jsonb_build_object('owner_name',p.full_name,'owner_email',p.email)
  from public.coffee_cultivations c join public.profiles p on p.id=c.owner_id
  where public.can_manage_coffee_owner(c.owner_id) order by c.name,c.id;
$$;
create function public.list_coffee_lots() returns setof jsonb language sql stable security definer set search_path='' as $$
  select to_jsonb(l)||jsonb_build_object('owner_name',coalesce(p.full_name,'Sin asignar'),'owner_email',coalesce(p.email,''),'cultivation_name',coalesce(c.name,'Sin cultivo asignado'),
    'exports',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'status',r.status)),'[]'::jsonb) from public.export_requests r where r.lot_id=l.id))
  from public.coffee_lots l left join public.profiles p on p.id=l.owner_id left join public.coffee_cultivations c on c.id=l.cultivation_id
  where public.can_manage_coffee_owner(l.owner_id) or(l.owner_id is null and public.is_staff()) order by l.name,l.id;
$$;

create or replace function public.save_coffee_cultivation(target_id uuid,target_owner uuid,cultivation_name text,farm text,cultivation_location text,coffee_variety text,hectares numeric) returns uuid
language plpgsql security definer set search_path='' as $$
declare previous public.coffee_cultivations;result_id uuid;
begin
  if not public.can_edit_coffee_owner(target_owner) or not exists(select 1 from public.profiles p where p.id=target_owner and p.is_active
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

create or replace function public.save_coffee_export_lot(target_id uuid,target_cultivation uuid,code text,lot_name text,weight numeric,harvest date,lot_notes text) returns uuid
language plpgsql security definer set search_path='' as $$
declare cultivation public.coffee_cultivations;previous public.coffee_lots;result_id uuid;
begin
  select * into cultivation from public.coffee_cultivations where id=target_cultivation;
  if not found or not public.can_edit_coffee_owner(cultivation.owner_id) then raise exception 'No tienes acceso al cultivo seleccionado.' using errcode='42501';end if;
  if code is null or length(trim(code)) not between 2 and 50 or lot_name is null or length(trim(lot_name)) not between 3 and 100
    or weight is null or not(weight>0 and weight<10000000000) or harvest is null or harvest>current_date or length(coalesce(lot_notes,''))>2000 then raise exception 'Revisa código, nombre, peso y fecha de cosecha del lote.' using errcode='22023';end if;
  if target_id is not null then
    select * into previous from public.coffee_lots where id=target_id for update;
    if not found or not(public.can_edit_coffee_owner(previous.owner_id) or(previous.owner_id is null and public.has_role('admin'))) then raise exception 'No tienes acceso al lote.' using errcode='42501';end if;
    if exists(select 1 from public.export_requests where lot_id=target_id and status in('draft','pending','approved')) then raise exception 'El lote está reservado por una solicitud o ya fue exportado.' using errcode='P0001';end if;
    update public.coffee_lots set owner_id=cultivation.owner_id,cultivation_id=cultivation.id,lot_code=trim(code),name=trim(lot_name),origin=cultivation.location,weight_kg=weight,harvest_date=harvest,notes=coalesce(lot_notes,''),updated_at=now() where id=target_id returning id into result_id;
  else insert into public.coffee_lots(owner_id,cultivation_id,lot_code,name,origin,weight_kg,harvest_date,notes) values(cultivation.owner_id,cultivation.id,trim(code),trim(lot_name),cultivation.location,weight,harvest,coalesce(lot_notes,'')) returning id into result_id;end if;
  return result_id;
end;
$$;

create or replace function public.delete_coffee_export_lot(target_lot uuid) returns void language plpgsql security definer set search_path='' as $$
declare lot public.coffee_lots;
begin
  select * into lot from public.coffee_lots where id=target_lot for update;
  if not found or not(public.can_edit_coffee_owner(lot.owner_id) or(lot.owner_id is null and public.has_role('admin'))) then raise exception 'No tienes acceso al lote.' using errcode='42501';end if;
  if exists(select 1 from public.export_requests where lot_id=target_lot) then raise exception 'El lote forma parte de un expediente y debe conservarse.' using errcode='P0001';end if;
  delete from public.coffee_lots where id=target_lot;
end;
$$;

create or replace function public.start_coffee_export(target_lot uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare lot public.coffee_lots;existing public.export_requests;last_rejected public.export_requests;result_id uuid;
begin
  select * into lot from public.coffee_lots where id=target_lot for update;
  if not found or not public.can_edit_coffee_owner(lot.owner_id) or lot.cultivation_id is null or lot.lot_code is null then raise exception 'Selecciona un lote propio con cultivo y código registrados.' using errcode='42501';end if;
  if not exists(select 1 from public.profiles where id=lot.owner_id and is_active) then raise exception 'El titular del lote no está activo.' using errcode='42501';end if;
  select * into existing from public.export_requests where lot_id=target_lot and status in('draft','pending','approved');
  if found then
    if existing.status='draft' then return existing.id;end if;
    raise exception 'El lote ya tiene una solicitud pendiente o una exportación aprobada.' using errcode='P0001';
  end if;
  insert into public.export_requests(owner_id,lot_id) values(lot.owner_id,lot.id) returning id into result_id;
  select * into last_rejected from public.export_requests where lot_id=target_lot and status='rejected' order by created_at desc,id desc limit 1;
  if found then
    update public.export_requests set freight_rate_id=last_rejected.freight_rate_id,pickup_address=last_rejected.pickup_address,delivery_address=last_rejected.delivery_address,
      origin=last_rejected.origin,destination=last_rejected.destination,recipient_name=last_rejected.recipient_name,recipient_phone=last_rejected.recipient_phone where id=result_id;
    insert into public.export_documents(request_id,kind,storage_path,original_name) select result_id,kind,storage_path,original_name from public.export_documents where request_id=last_rejected.id;
  end if;
  return result_id;
end;
$$;

-- Comprueba la vigencia al enviar, incluso si el perfil del dispositivo todavía no ha detectado un vencimiento.
create function public.require_export_agreement() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.status in('draft','pending') and not public.has_role('admin') and not public.has_active_agreement(new.owner_id) then
    raise exception 'Necesitas un convenio activo y aceptado para solicitar una exportación.' using errcode='42501';
  end if;
  return new;
end;
$$;
create trigger coffee_export_active_agreement before insert or update of status on public.export_requests for each row execute function public.require_export_agreement();

revoke all on function public.require_export_agreement() from public,anon,authenticated;
revoke all on function public.can_edit_coffee_owner(uuid),public.list_coffee_cultivations(),public.list_coffee_lots() from public,anon,authenticated;
grant execute on function public.can_edit_coffee_owner(uuid),public.list_coffee_cultivations(),public.list_coffee_lots() to authenticated;
notify pgrst,'reload schema';
commit;
