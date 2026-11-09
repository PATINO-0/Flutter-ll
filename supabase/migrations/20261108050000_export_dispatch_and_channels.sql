-- Revisión de exportaciones, chats separados y asignación exclusiva de transportadores.
begin;
alter table public.export_requests add column charge_authorized_by uuid references public.profiles(id); -- Identifica al titular que autorizó el cargo.
alter table public.shipments drop constraint shipments_status_check;
alter table public.shipments add constraint shipments_status_check check(status in('pending','accepted','received','in_transit','customs','delivered','cancelled'));
alter table public.shipments add column export_request_id uuid unique references public.export_requests(id);
alter table public.shipments add column lot_id uuid references public.coffee_lots(id);
alter table public.shipments add column transporter_id uuid references public.profiles(id);
alter table public.shipments add column current_location text;
alter table public.shipments add column delivered_at timestamptz;
alter table public.shipment_events add column location text;
alter table public.shipment_events add column delivery_confirmed boolean not null default false;
create index shipments_transporter_active on public.shipments(transporter_id,status);

alter table public.conversations drop constraint conversations_client_id_key;
alter table public.conversations add column channel text not null default 'support' check(channel in('support','exports','transport'));
alter table public.conversations add column export_request_id uuid references public.export_requests(id);
create unique index conversation_general_channel on public.conversations(client_id,channel) where export_request_id is null;
create unique index conversation_export_request on public.conversations(export_request_id);
alter table public.chat_messages add column export_request_id uuid references public.export_requests(id);

-- El transportador accede exclusivamente a sus chats operativos y a los expedientes de envío que tomó.
create or replace function public.can_access_conversation(target_conversation uuid) returns boolean language sql stable security definer set search_path='' as $$
  select public.is_active_user() and exists(select 1 from public.conversations c where c.id=target_conversation and
    (public.is_staff() or(c.client_id=auth.uid() and((c.channel='support' and public.effective_role() in('client','associate')) or(c.channel='exports' and public.effective_role()='associate')
      or(c.channel='transport' and public.effective_role()='transporter')))
    or(c.channel='exports' and public.effective_role()='transporter' and exists(select 1 from public.shipments s where s.export_request_id=c.export_request_id and s.transporter_id=auth.uid()))));
$$;
drop policy conversations_read on public.conversations;
create policy conversations_read on public.conversations for select to authenticated using(public.can_access_conversation(id));
create or replace function public.open_support_conversation(target_owner uuid default auth.uid()) returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid;
begin
  if not public.can_access_owner(target_owner) or(not public.is_staff() and public.effective_role()='transporter') then raise exception 'No tienes acceso a esta conversación.' using errcode='42501';end if;
  insert into public.conversations(client_id,channel) values(target_owner,'support') on conflict(client_id,channel) where export_request_id is null do update set client_id=excluded.client_id returning id into result_id;
  return result_id;
end;
$$;
create function public.open_transport_conversation(target_driver uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid;
begin
  if not public.is_active_user() or not(public.is_staff() or(auth.uid()=target_driver and public.effective_role()='transporter'))
    or not exists(select 1 from public.profiles p join public.user_roles r on r.user_id=p.id where p.id=target_driver and p.is_active and r.role='transporter') then raise exception 'No tienes acceso al chat del transportador.' using errcode='42501';end if;
  insert into public.conversations(client_id,channel) values(target_driver,'transport') on conflict(client_id,channel) where export_request_id is null do update set client_id=excluded.client_id returning id into result_id;
  return result_id;
end;
$$;
create function public.open_export_conversation(target_request uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare owner uuid;result_id uuid;
begin
  select owner_id into owner from public.export_requests where id=target_request;
  if not found or not(public.can_manage_coffee_owner(owner) or exists(select 1 from public.conversations where export_request_id=target_request and public.can_access_conversation(id))) then raise exception 'No tienes acceso al chat de esta exportación.' using errcode='42501';end if;
  insert into public.conversations(client_id,channel,export_request_id) values(owner,'exports',target_request) on conflict(export_request_id) do update set client_id=excluded.client_id returning id into result_id;
  return result_id;
end;
$$;
create function public.emit_export_message(target_request uuid,message_body text) returns void language plpgsql security definer set search_path='' as $$
declare conversation uuid;
begin
  conversation=public.open_export_conversation(target_request);
  insert into public.chat_messages(conversation_id,sender_id,export_request_id,kind,body) values(conversation,auth.uid(),target_request,'system',message_body);
  update public.conversations set last_message_at=now() where id=conversation;
end;
$$; -- Su ejecución se reserva a las funciones del servidor para no permitir avisos de sistema falsificados.

create function public.submit_coffee_export(target_request uuid,pickup_location text,delivery_destination text,recipient text,contact_phone text,
  expected_total numeric,expected_currency text,expected_rate numeric,accept_charge boolean,accept_data_processing boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare request_row public.export_requests;lot public.coffee_lots;cultivation public.coffee_cultivations;pricing public.coffee_export_pricing;calculated numeric;
begin
  select * into request_row from public.export_requests where id=target_request;
  if not found then raise exception 'La solicitud no está disponible.' using errcode='22023';end if;
  select * into lot from public.coffee_lots where id=request_row.lot_id for update;
  select * into request_row from public.export_requests where id=target_request for update;
  if not public.can_manage_coffee_owner(request_row.owner_id) then raise exception 'No tienes acceso a esta solicitud.' using errcode='42501';end if;
  if request_row.owner_id<>auth.uid() then raise exception 'Solo el titular del lote puede autorizar el cargo y enviar su exportación.' using errcode='42501';end if;
  if request_row.status<>'draft' then raise exception 'La solicitud ya fue enviada.' using errcode='P0001';end if;
  if accept_charge is distinct from true or accept_data_processing is distinct from true then raise exception 'Debes autorizar el cargo y el tratamiento de datos.' using errcode='22023';end if;
  if pickup_location is null or length(trim(pickup_location)) not between 5 and 250 or delivery_destination is null or length(trim(delivery_destination)) not between 5 and 250
    or recipient is null or length(trim(recipient)) not between 3 and 150 or contact_phone is null or contact_phone!~'^[+0-9 ()-]{7,25}$'
    or length(regexp_replace(contact_phone,'[^0-9]','','g')) not between 7 and 15 then raise exception 'Completa recogida, destino, destinatario y teléfono válido.' using errcode='22023';end if;
  if(select count(*) from public.export_documents where request_id=target_request)<>3 or exists(select 1 from public.export_documents d where d.request_id=target_request and not exists(select 1 from storage.objects o where o.bucket_id='export-documents' and o.name=d.storage_path)) then raise exception 'Adjunta los tres documentos de exportación válidos.' using errcode='22023';end if;
  select * into pricing from public.coffee_export_pricing where id=true for share;
  calculated=round(lot.weight_kg*pricing.rate_per_kg,2);
  if calculated<=0 or calculated>=10000000000000000 then raise exception 'El importe calculado supera los límites permitidos. Solicita revisión al administrador.' using errcode='22023';end if;
  if expected_total is distinct from calculated or expected_currency is distinct from pricing.currency or expected_rate is distinct from pricing.rate_per_kg then raise exception 'La tarifa cambió. Actualiza la cotización y autoriza nuevamente el cargo.' using errcode='P0001';end if;
  select * into cultivation from public.coffee_cultivations where id=lot.cultivation_id;
  update public.export_requests set origin=trim(pickup_location),destination=trim(delivery_destination),recipient_name=trim(recipient),recipient_phone=trim(contact_phone),
    lot_snapshot=jsonb_build_object('lot_code',lot.lot_code,'lot_name',lot.name,'weight_kg',lot.weight_kg,'harvest_date',lot.harvest_date,'cultivation_name',cultivation.name,'farm_name',cultivation.farm_name,'location',cultivation.location,'variety',cultivation.variety),
    weight_kg=lot.weight_kg,rate_per_kg=pricing.rate_per_kg,currency=pricing.currency,total_cost=calculated,pricing_reference=pricing.is_reference,
    charge_authorized_at=now(),charge_authorized_by=auth.uid(),data_consent_at=now(),consent_version='coffee-export-2026-11-08-v1',submitted_at=now(),status='pending' where id=target_request;
  perform public.emit_export_message(target_request,'Solicitud de exportación de café enviada. Lote '||lot.lot_code||'. Los documentos y la autorización del cargo están en el expediente privado. Pendiente de revisión del personal.');
  return public.open_export_conversation(target_request);
end;
$$;
create function public.review_coffee_export(target_request uuid,approve boolean,reason text default '') returns void language plpgsql security definer set search_path='' as $$
declare request_row public.export_requests;shipment_id uuid;
begin
  select * into request_row from public.export_requests where id=target_request;
  if not found then raise exception 'La solicitud no está disponible.' using errcode='22023';end if;
  perform 1 from public.coffee_lots where id=request_row.lot_id for update;
  select * into request_row from public.export_requests where id=target_request for update;
  if not public.is_staff() then raise exception 'Solo el personal puede revisar exportaciones.' using errcode='42501';end if;
  if request_row.status<>'pending' then raise exception 'La solicitud ya no está pendiente.' using errcode='P0001';end if;
  if approve is null or(not approve and(reason is null or length(trim(reason)) not between 5 and 2000)) then raise exception 'Explica el motivo del rechazo y las correcciones requeridas.' using errcode='22023';end if;
  if not exists(select 1 from public.profiles where id=request_row.owner_id and is_active) then raise exception 'El titular ya no tiene acceso activo.' using errcode='42501';end if;
  update public.export_requests set status=case when approve then 'approved' else 'rejected' end,reviewed_at=now(),reviewed_by=auth.uid(),rejection_reason=case when approve then null else trim(reason) end where id=target_request;
  if approve then
    insert into public.shipments(owner_id,operation_type,description,origin,destination,status,created_by,export_request_id,lot_id)
      values(request_row.owner_id,'export','Exportación de café · '||(request_row.lot_snapshot->>'lot_code'),request_row.origin,request_row.destination,'accepted',auth.uid(),target_request,request_row.lot_id) returning id into shipment_id;
    insert into public.shipment_events(shipment_id,status,notes,created_by) values(shipment_id,'accepted','Exportación aceptada por el personal. Pendiente de transportador.',auth.uid());
    insert into public.export_charges(request_id,owner_id,amount,currency,authorized_at) values(target_request,request_row.owner_id,request_row.total_cost,request_row.currency,request_row.charge_authorized_at);
    perform public.emit_export_message(target_request,'Exportación aceptada. Los documentos y la autorización del cargo quedaron archivados. El envío está disponible para un transportador.');
  else perform public.emit_export_message(target_request,'Exportación rechazada: '||trim(reason)||'. Puedes corregir la solicitud del mismo lote. No se registró un cargo por esta solicitud.');end if;
end;
$$;

-- Compara ubicaciones completas normalizando únicamente espacios y mayúsculas.
create function public.normalized_shipping_location(location_text text) returns text language sql immutable set search_path='' as $$select lower(regexp_replace(trim(location_text),'\s+',' ','g'));$$;
create function public.can_take_coffee_shipment(target_shipment uuid) returns boolean language sql stable security definer set search_path='' as $$
  select coalesce(public.is_active_user() and public.effective_role() in('transporter','admin') and exists(select 1 from public.shipments target where target.id=target_shipment
    and target.export_request_id is not null and target.status='accepted' and target.transporter_id is null and not exists(select 1 from public.shipments active
      where active.transporter_id=auth.uid() and active.status in('accepted','received','in_transit') and
      (active.status='in_transit' or public.normalized_shipping_location(active.origin)<>public.normalized_shipping_location(target.origin)
       or public.normalized_shipping_location(active.destination)<>public.normalized_shipping_location(target.destination)))),false);
$$;
create function public.take_coffee_shipment(target_shipment uuid) returns void language plpgsql security definer set search_path='' as $$
declare shipment public.shipments;driver_name text;
begin
  perform pg_advisory_xact_lock(hashtextextended('driver:'||coalesce(auth.uid()::text,''),0)); -- Serializa las asignaciones simultáneas de un mismo transportador.
  select * into shipment from public.shipments where id=target_shipment for update;
  if not found or not public.can_take_coffee_shipment(target_shipment) then raise exception 'El envío ya fue tomado o no es compatible con tu carga actual. Solo puedes agrupar lotes con igual recogida y destino antes de salir.' using errcode='P0001';end if;
  update public.shipments set transporter_id=auth.uid(),updated_at=now() where id=target_shipment;
  select full_name into driver_name from public.profiles where id=auth.uid();
  insert into public.shipment_events(shipment_id,status,notes,created_by) values(target_shipment,'accepted','El transportador tomó el envío.',auth.uid());
  perform public.emit_export_message(shipment.export_request_id,'El transportador '||driver_name||' tomó el envío '||shipment.tracking_code||'.');
end;
$$;
create function public.update_coffee_delivery(target_shipment uuid,new_status text,update_notes text,new_location text,confirm_delivery boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare shipment public.shipments;location_text text;assigned_driver uuid;
begin
  select transporter_id into assigned_driver from public.shipments where id=target_shipment;
  perform pg_advisory_xact_lock(hashtextextended('driver:'||coalesce(assigned_driver::text,auth.uid()::text,''),0)); -- Serializa la salida de una ruta con la toma de nuevas cargas del mismo transportador.
  select * into shipment from public.shipments where id=target_shipment for update;
  if not found or not public.is_active_user() or not coalesce((public.has_role('admin') or(public.effective_role()='transporter' and shipment.transporter_id=auth.uid())),false)
    or shipment.export_request_id is null then raise exception 'Solo el transportador asignado puede actualizar este envío.' using errcode='42501';end if;
  if update_notes is null or length(trim(update_notes)) not between 3 and 2000 or new_status is null then raise exception 'Escribe una anotación de seguimiento válida.' using errcode='22023';end if;
  if not((shipment.status='accepted' and new_status='received') or(shipment.status='received' and new_status='in_transit')
    or(shipment.status='in_transit' and new_status in('in_transit','delivered'))) then raise exception 'El seguimiento debe pasar por recibido, en camino y terminado.' using errcode='22023';end if;
  if new_status='delivered' and confirm_delivery is distinct from true then raise exception 'Confirma que el lote fue entregado en destino.' using errcode='22023';end if;
  if new_status='in_transit' and(new_location is null or length(trim(new_location)) not between 3 and 250) then raise exception 'Indica dónde se encuentra actualmente el envío.' using errcode='22023';end if;
  location_text=case when new_status='delivered' then shipment.destination else nullif(trim(new_location),'') end;
  update public.shipments set status=new_status,current_location=location_text,updated_at=now(),delivered_at=case when new_status='delivered' then now() else null end where id=target_shipment;
  insert into public.shipment_events(shipment_id,status,notes,created_by,location,delivery_confirmed) values(target_shipment,new_status,trim(update_notes),auth.uid(),location_text,new_status='delivered');
  perform public.emit_export_message(shipment.export_request_id,case new_status when 'delivered' then 'Pedido entregado y confirmado por el transportador. '
    when 'received' then 'El transportador recibió el lote. ' else 'En camino. Ubicación: '||location_text||'. ' end||trim(update_notes));
end;
$$;
create function public.request_transport_pickup(target_driver uuid,target_shipment uuid,message_body text) returns uuid language plpgsql security definer set search_path='' as $$
declare shipment public.shipments;conversation uuid;
begin
  if not public.is_staff() then raise exception 'Solo el personal puede solicitar una recogida.' using errcode='42501';end if;
  select * into shipment from public.shipments where id=target_shipment and export_request_id is not null and status='accepted' and transporter_id is null;
  if not found then raise exception 'El envío ya no está disponible para recoger.' using errcode='P0001';end if;
  if message_body is null or length(trim(message_body)) not between 3 and 2000 then raise exception 'Escribe la indicación para el transportador.' using errcode='22023';end if;
  conversation=public.open_transport_conversation(target_driver);
  insert into public.chat_messages(conversation_id,sender_id,export_request_id,body) values(conversation,auth.uid(),shipment.export_request_id,'Solicitud de recogida '||shipment.tracking_code||': '||trim(message_body)||'. Origen: '||shipment.origin||'. Destino: '||shipment.destination||'.');
  update public.conversations set last_message_at=now() where id=conversation;
  return conversation;
end;
$$;

create function public.list_transport_shipments() returns setof jsonb language plpgsql security definer set search_path='' as $$
begin
  if not public.is_active_user() or coalesce(public.effective_role(),'') not in('transporter','admin') then raise exception 'Necesitas el rol de transportador.' using errcode='42501';end if;
  return query select jsonb_build_object('id',s.id,'tracking_code',s.tracking_code,'origin',s.origin,'destination',s.destination,'status',s.status,'transporter_id',s.transporter_id,
    'lot_code',r.lot_snapshot->>'lot_code','lot_name',r.lot_snapshot->>'lot_name','weight_kg',r.weight_kg,'current_location',s.current_location,'delivered_at',s.delivered_at,
    'recipient_name',case when s.transporter_id=auth.uid() then r.recipient_name else '' end,'recipient_phone',case when s.transporter_id=auth.uid() then r.recipient_phone else '' end,
    'conversation_id',c.id,'export_request_id',r.id,'can_take',public.can_take_coffee_shipment(s.id))
    from public.shipments s join public.export_requests r on r.id=s.export_request_id left join public.conversations c on c.export_request_id=r.id
    where s.transporter_id=auth.uid() or(s.transporter_id is null and s.status='accepted') order by s.created_at desc,s.id;
end;
$$;
create function public.list_transporters() returns table(id uuid,full_name text,email text,active_shipments bigint) language plpgsql security definer set search_path='' as $$
begin
  if not public.is_staff() then raise exception 'Solo el personal puede consultar transportadores.' using errcode='42501';end if;
  return query select p.id,p.full_name::text,p.email::text,(select count(*) from public.shipments s where s.transporter_id=p.id and s.status in('accepted','received','in_transit'))
    from public.profiles p where p.is_active and exists(select 1 from public.user_roles r where r.user_id=p.id and r.role='transporter') order by p.full_name,p.id;
end;
$$;

-- La bandeja devuelve canales identificables sin ampliar los permisos de lectura de sus mensajes.
drop function public.list_conversations();
create function public.list_conversations() returns table(id uuid,client_id uuid,client_name text,last_message_at timestamptz,unread_count bigint,channel text,export_request_id uuid)
language sql stable security definer set search_path='' as $$
  select c.id,c.client_id,p.full_name::text||case when c.channel='exports' then ' · EXP-'||e.request_number::text else '' end,c.last_message_at,
    (select count(*) from public.chat_messages m where m.conversation_id=c.id and m.sender_id<>auth.uid() and m.created_at>coalesce(r.read_at,'epoch'::timestamptz)),c.channel,c.export_request_id
  from public.conversations c join public.profiles p on p.id=c.client_id left join public.export_requests e on e.id=c.export_request_id
  left join public.conversation_reads r on r.conversation_id=c.id and r.user_id=auth.uid() where public.can_access_conversation(c.id) order by c.last_message_at desc,c.id;
$$;
create or replace function public.list_customers() returns table(id uuid,full_name text,email text,created_at timestamptz,updated_at timestamptz,roles text[]) language plpgsql security definer set search_path='' as $$
begin
  if not public.is_staff() then raise exception 'Solo el personal puede consultar clientes.' using errcode='42501';end if;
  return query select p.id,p.full_name::text,p.email::text,p.created_at,p.updated_at,array_agg(r.role order by r.role) from public.profiles p join public.user_roles r on r.user_id=p.id where p.is_active
    and not exists(select 1 from public.user_roles elevated where elevated.user_id=p.id and elevated.role in('admin','worker','transporter')) group by p.id,p.full_name,p.email,p.created_at,p.updated_at order by p.full_name,p.id;
end;
$$;
create or replace function public.can_access_shipment(target_shipment uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.shipments s where s.id=target_shipment and public.is_active_user() and(public.is_staff()
    or(s.owner_id=auth.uid() and public.effective_role()='associate') or(s.transporter_id=auth.uid() and public.effective_role()='transporter')));
$$;
drop policy shipments_read on public.shipments;
create policy shipments_read on public.shipments for select to authenticated using(public.can_access_shipment(id));
-- El antiguo RPC no puede servir para saltarse la confirmación de entrega ni la asignación al transportador.
revoke execute on function public.update_shipment_status(uuid,text,text) from public,anon,authenticated;
do $$declare item record;begin
  for item in select oid::regprocedure signature from pg_proc where pronamespace='public'::regnamespace and proname in
    ('open_transport_conversation','open_export_conversation','submit_coffee_export','review_coffee_export','normalized_shipping_location','can_take_coffee_shipment','take_coffee_shipment','update_coffee_delivery','request_transport_pickup','list_transport_shipments','list_transporters','list_conversations')
  loop execute format('revoke all on function %s from public,anon,authenticated',item.signature);execute format('grant execute on function %s to authenticated',item.signature);end loop;
end $$;
revoke all on function public.emit_export_message(uuid,text) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
