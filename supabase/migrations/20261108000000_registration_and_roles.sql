-- Ejecuta el cambio completo en una transacción para no dejar permisos parciales.
begin;

-- Evita que un registro concurrente altere la elección de la cuenta preexistente durante la migración.
lock table auth.users in share row exclusive mode;

-- Mantiene compatibilidad con los campos que ya consulta la aplicación.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade, -- Vincula el perfil con autenticación.
  full_name text not null default 'Usuario', -- Almacena el nombre visible del usuario.
  email text not null default '', -- Conserva el correo utilizado en la lista administrativa.
  created_at timestamptz not null default now(), -- Registra la creación del perfil.
  updated_at timestamptz not null default now() -- Registra su última actualización.
);

-- Separa los permisos de los metadatos editables por el propio usuario.
create table public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade, -- Identifica al titular del permiso.
  role text not null check (role in ('admin', 'client', 'associate', 'worker')), -- Limita los roles válidos.
  primary key (user_id, role) -- Impide asignar dos veces el mismo rol.
);

-- Agiliza la comprobación de administradores y la protección del último administrador.
create index user_roles_role_idx on public.user_roles(role);

-- Completa los perfiles de las cuentas existentes sin sobrescribir sus datos.
insert into public.profiles (id, full_name, email)
select id, coalesce(nullif(trim(raw_user_meta_data->>'full_name'), ''), 'Usuario'), coalesce(email, '')
from auth.users
on conflict (id) do nothing;

-- Conserva el acceso básico de todas las cuentas que existían antes de la migración.
insert into public.user_roles (user_id, role)
select id, 'client' from public.profiles;

-- Promueve únicamente la cuenta preexistente cuando es la única cuenta del proyecto.
-- Si hay cero o varias cuentas, un operador debe elegir el administrador mediante SQL.
insert into public.user_roles (user_id, role)
select id, 'admin' from auth.users
where (select count(*) from auth.users) = 1
on conflict do nothing;

-- Crea el perfil y su rol de cliente dentro de la misma transacción del registro.
-- Los valores role y roles enviados en metadatos se ignoran deliberadamente.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (
    new.id, -- Utiliza la identidad verificada por Supabase Auth.
    left(coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), 'Usuario'), 100), -- Limita el nombre público.
    coalesce(new.email, '') -- Conserva el correo de autenticación.
  ) on conflict (id) do nothing; -- Permite coexistir con un disparador anterior que use esta misma función.
  insert into public.user_roles (user_id, role)
  values (new.id, 'client') -- Todas las altas públicas reciben exclusivamente el rol de cliente.
  on conflict do nothing; -- Evita duplicados si ya existía un disparador de perfiles.
  return new; -- Permite completar el registro de autenticación.
end;
$$;

-- Sustituye el disparador habitual y mantiene una única definición de este nombre.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Comprueba únicamente los permisos de la sesión actual sin consultar metadatos del cliente.
create function public.has_role(requested_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role = requested_role -- Obtiene la identidad desde el JWT verificado.
  );
$$;

-- Obliga a que toda lectura desde la aplicación pase por políticas de acceso.
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;

-- Retira políticas anteriores de perfiles que podrían permitir leer otras cuentas o escribir permisos.
do $$
declare
  existing_policy record; -- Recorre solamente políticas de la tabla de perfiles.
begin
  for existing_policy in select policyname from pg_policies where schemaname = 'public' and tablename = 'profiles'
  loop
    execute format('drop policy %I on public.profiles', existing_policy.policyname); -- Escapa el nombre de cada política.
  end loop;
end;
$$;

-- El usuario consulta sus datos; el administrador puede consultar todos los perfiles.
create policy profiles_read on public.profiles for select to authenticated
using (id = (select auth.uid()) or (select public.has_role('admin')));

-- El usuario consulta sus roles; el administrador puede consultar los de otras cuentas.
create policy user_roles_read on public.user_roles for select to authenticated
using (user_id = (select auth.uid()) or (select public.has_role('admin')));

-- Prohíbe insertar, actualizar o borrar perfiles y roles directamente desde el cliente.
revoke all on public.profiles, public.user_roles from public, anon, authenticated;
grant select on public.profiles, public.user_roles to authenticated;
grant all on public.profiles, public.user_roles to service_role; -- Reserva las tareas internas al servidor.

-- Devuelve una página acotada de perfiles solo después de validar al administrador.
create function public.list_users(page_offset integer default 0, page_size integer default 20)
returns table (id uuid, full_name text, email text, created_at timestamptz, updated_at timestamptz, roles text[])
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_role('admin') then
    raise exception 'Solo un administrador puede consultar usuarios.' using errcode = '42501';
  end if;
  if page_offset < 0 or page_size < 1 or page_size > 100 or page_offset is null or page_size is null then
    raise exception 'La paginación no es válida.' using errcode = '22023';
  end if;
  return query
  select p.id, p.full_name, p.email, p.created_at, p.updated_at,
    coalesce(array_agg(r.role order by r.role) filter (where r.role is not null), '{}'::text[])
  from public.profiles p
  left join public.user_roles r on r.user_id = p.id -- Incluye también las cuentas sin roles.
  group by p.id, p.full_name, p.email, p.created_at, p.updated_at
  order by p.created_at desc, p.id -- Mantiene estable la paginación cuando coinciden las fechas.
  limit page_size offset page_offset;
end;
$$;

-- Reemplaza los roles de una cuenta en una sola transacción controlada.
create function public.set_user_roles(target_user_id uuid, new_roles text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(748192031); -- Serializa los cambios para proteger al último administrador.
  if auth.uid() is null or not public.has_role('admin') then
    raise exception 'Solo un administrador puede modificar roles.' using errcode = '42501';
  end if;
  if new_roles is null or array_position(new_roles, null) is not null
    or not (new_roles <@ array['admin', 'client', 'associate', 'worker']::text[]) then
    raise exception 'La selección contiene roles no válidos.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = target_user_id) then
    raise exception 'El usuario no existe.' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.user_roles where user_id = target_user_id and role = 'admin')
    and not ('admin' = any(new_roles))
    and (select count(*) from public.user_roles where role = 'admin') <= 1 then
    raise exception 'Debe permanecer al menos un administrador.' using errcode = '23514';
  end if;
  delete from public.user_roles where user_id = target_user_id; -- Retira la selección anterior dentro de la transacción.
  insert into public.user_roles (user_id, role)
  select target_user_id, selected_role from (select distinct unnest(new_roles) as selected_role) selected;
  update public.profiles set updated_at = now() where id = target_user_id; -- Registra la modificación del perfil.
end;
$$;

-- Impide ejecutar funciones privilegiadas mediante la clave pública sin sesión.
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.has_role(text) from public, anon, authenticated;
revoke all on function public.list_users(integer, integer) from public, anon, authenticated;
revoke all on function public.set_user_roles(uuid, text[]) from public, anon, authenticated;
grant execute on function public.has_role(text) to authenticated;
grant execute on function public.list_users(integer, integer) to authenticated;
grant execute on function public.set_user_roles(uuid, text[]) to authenticated;

-- Confirma conjuntamente las tablas, los disparadores y las restricciones de acceso.
commit;
