-- Asigna administración a la cuenta de prueba indicada explícitamente por el propietario del proyecto.
begin;

-- Verifica conjuntamente el UUID y el correo para no promover clientes por antigüedad o por metadatos.
insert into public.user_roles (user_id, role)
select profiles.id, 'admin'
from public.profiles profiles
join auth.users account on account.id = profiles.id -- Confirma que el perfil pertenece a una cuenta real.
where account.id = '1bb00d6c-9b14-43d0-b096-88969fcd8376'::uuid -- Identifica al usuario de prueba autorizado.
  and lower(account.email) = 'usuarioprueba@gmail.com' -- Verifica además el correo confirmado por el propietario.
on conflict (user_id, role) do nothing; -- Conserva los roles existentes y permite repetir esta asignación sin duplicados.

-- Actualiza el esquema publicado después de crear las tablas y funciones de la migración anterior.
notify pgrst, 'reload schema';

-- Confirma la asignación únicamente después de completar todas las verificaciones.
commit;
