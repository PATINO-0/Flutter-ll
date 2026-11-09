-- Conecta las exportaciones con las rutas y tarifas habilitadas de la tienda.
begin;

alter table public.freight_rates add column allows_coffee_export boolean not null default false; -- La administración habilita explícitamente los servicios de café.
alter table public.freight_rates add constraint freight_coffee_route_valid check (
  not allows_coffee_export or (
    lower(trim(unit))='kg' and length(trim(origin)) between 3 and 120 and length(trim(destination)) between 3 and 120
    and lower(trim(origin))<>lower(trim(destination)) and amount<10000000000
  )
); -- Una tarifa por volumen no puede convertirse implícitamente en una tarifa por peso.
alter table public.export_requests add column freight_rate_id uuid references public.freight_rates(id);
alter table public.export_requests add column tariff_snapshot jsonb; -- Conserva ruta y condiciones aunque cambie la tienda.
alter table public.export_requests add column pickup_address text not null default '';
alter table public.export_requests add column delivery_address text not null default '';
update public.export_requests set pickup_address=origin,delivery_address=destination; -- Mantiene utilizables las solicitudes anteriores sin inventar una tarifa.

-- La tarifa global anterior queda como dato histórico y deja de aceptar cambios desde la aplicación.
revoke update on public.coffee_export_pricing from authenticated;

create or replace function public.start_coffee_export(target_lot uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare lot public.coffee_lots;existing public.export_requests;last_rejected public.export_requests;result_id uuid;
begin
  select * into lot from public.coffee_lots where id=target_lot for update;
  if not found or not public.can_manage_coffee_owner(lot.owner_id) or lot.cultivation_id is null or lot.lot_code is null then raise exception 'Selecciona un lote propio con cultivo y código registrados.' using errcode='42501';end if;
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

drop function public.quote_coffee_export(uuid); -- Retira la cotización global que no validaba una ruta.
create function public.quote_coffee_export(target_request uuid,target_rate uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare request_row public.export_requests;lot public.coffee_lots;tariff public.freight_rates;calculated numeric;
begin
  select * into request_row from public.export_requests where id=target_request;
  if not found or not public.can_manage_coffee_owner(request_row.owner_id) then raise exception 'No tienes acceso a esta solicitud.' using errcode='42501';end if;
  select * into tariff from public.freight_rates where id=target_rate and is_active and allows_coffee_export and lower(trim(unit))='kg';
  if not found then raise exception 'La ruta o tarifa seleccionada ya no está habilitada para exportar café. Actualiza las rutas disponibles.' using errcode='P0001';end if;
  select * into lot from public.coffee_lots where id=request_row.lot_id;
  calculated=round(lot.weight_kg*tariff.amount,2);
  if calculated<=0 or calculated>=10000000000000000 then raise exception 'El peso y la tarifa no producen un importe válido. Solicita revisión al administrador.' using errcode='22023';end if;
  return jsonb_build_object('freight_rate_id',tariff.id,'title',tariff.title,'origin',tariff.origin,'destination',tariff.destination,'description',tariff.description,
    'weight_kg',lot.weight_kg,'rate_per_kg',tariff.amount,'currency',tariff.currency,'total_cost',calculated,'is_reference',tariff.is_reference);
end;
$$;

drop function public.submit_coffee_export(uuid,text,text,text,text,numeric,text,numeric,boolean,boolean); -- Impide enviar solicitudes mediante el RPC anterior sin ruta.
create function public.submit_coffee_export(target_request uuid,target_rate uuid,pickup_location text,delivery_destination text,recipient text,contact_phone text,
  expected_total numeric,expected_currency text,expected_rate numeric,expected_origin text,expected_destination text,accept_charge boolean,accept_data_processing boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare request_row public.export_requests;lot public.coffee_lots;cultivation public.coffee_cultivations;tariff public.freight_rates;calculated numeric;
begin
  select * into request_row from public.export_requests where id=target_request;
  if not found then raise exception 'La solicitud no está disponible.' using errcode='22023';end if;
  select * into lot from public.coffee_lots where id=request_row.lot_id for update;
  select * into request_row from public.export_requests where id=target_request for update;
  if not public.can_manage_coffee_owner(request_row.owner_id) or request_row.owner_id<>auth.uid() then raise exception 'Solo el titular del lote puede autorizar el cargo y enviar su exportación.' using errcode='42501';end if;
  if request_row.status<>'draft' then raise exception 'La solicitud ya fue enviada.' using errcode='P0001';end if;
  if accept_charge is distinct from true or accept_data_processing is distinct from true then raise exception 'Debes autorizar el cargo y el tratamiento de datos.' using errcode='22023';end if;
  if pickup_location is null or length(trim(pickup_location)) not between 5 and 250 or delivery_destination is null or length(trim(delivery_destination)) not between 5 and 250
    or recipient is null or length(trim(recipient)) not between 3 and 150 or contact_phone is null or contact_phone!~'^[+0-9 ()-]{7,25}$'
    or length(regexp_replace(contact_phone,'[^0-9]','','g')) not between 7 and 15 then raise exception 'Completa las direcciones de recogida y entrega, destinatario y teléfono válido.' using errcode='22023';end if;
  if(select count(*) from public.export_documents where request_id=target_request)<>3 or exists(select 1 from public.export_documents d where d.request_id=target_request and not exists(select 1 from storage.objects o where o.bucket_id='export-documents' and o.name=d.storage_path)) then raise exception 'Adjunta los tres documentos de exportación válidos.' using errcode='22023';end if;
  select * into tariff from public.freight_rates where id=target_rate and is_active and allows_coffee_export and lower(trim(unit))='kg' for share;
  if not found then raise exception 'La ruta o tarifa seleccionada ya no está habilitada para exportar café. Actualiza las rutas disponibles.' using errcode='P0001';end if;
  calculated=round(lot.weight_kg*tariff.amount,2);
  if calculated<=0 or calculated>=10000000000000000 then raise exception 'El importe calculado supera los límites permitidos. Solicita revisión al administrador.' using errcode='22023';end if;
  if expected_total is distinct from calculated or expected_currency is distinct from tariff.currency or expected_rate is distinct from tariff.amount
    or expected_origin is distinct from tariff.origin or expected_destination is distinct from tariff.destination then raise exception 'La tarifa o su ruta cambió. Actualiza las rutas y autoriza nuevamente la cotización.' using errcode='P0001';end if;
  select * into cultivation from public.coffee_cultivations where id=lot.cultivation_id;
  update public.export_requests set freight_rate_id=tariff.id,
    tariff_snapshot=jsonb_build_object('id',tariff.id,'title',tariff.title,'origin',tariff.origin,'destination',tariff.destination,'description',tariff.description,'unit','kg','rate_per_kg',tariff.amount,'currency',tariff.currency,'is_reference',tariff.is_reference),
    pickup_address=trim(pickup_location),delivery_address=trim(delivery_destination),
    origin=tariff.origin||' · '||trim(pickup_location),destination=tariff.destination||' · '||trim(delivery_destination),
    recipient_name=trim(recipient),recipient_phone=trim(contact_phone),
    lot_snapshot=jsonb_build_object('lot_code',lot.lot_code,'lot_name',lot.name,'weight_kg',lot.weight_kg,'harvest_date',lot.harvest_date,'cultivation_name',cultivation.name,'farm_name',cultivation.farm_name,'location',cultivation.location,'variety',cultivation.variety),
    weight_kg=lot.weight_kg,rate_per_kg=tariff.amount,currency=tariff.currency,total_cost=calculated,pricing_reference=tariff.is_reference,
    charge_authorized_at=now(),charge_authorized_by=auth.uid(),data_consent_at=now(),consent_version='coffee-export-2026-11-08-v1',submitted_at=now(),status='pending' where id=target_request;
  perform public.emit_export_message(target_request,'Solicitud de exportación de café enviada. Lote '||lot.lot_code||'. Ruta: '||tariff.origin||' → '||tariff.destination||'. Los documentos y la autorización del cargo están en el expediente privado. Pendiente de revisión del personal.');
  return public.open_export_conversation(target_request);
end;
$$;

revoke all on function public.quote_coffee_export(uuid,uuid),public.submit_coffee_export(uuid,uuid,text,text,text,text,numeric,text,numeric,text,text,boolean,boolean) from public,anon,authenticated;
grant execute on function public.quote_coffee_export(uuid,uuid),public.submit_coffee_export(uuid,uuid,text,text,text,text,numeric,text,numeric,text,text,boolean,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
