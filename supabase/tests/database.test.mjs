import assert from 'node:assert/strict'; // Comprueba resultados y códigos de PostgreSQL.
import { readFile } from 'node:fs/promises'; // Lee la misma migración que se desplegará.
import test from 'node:test'; // Ejecuta las pruebas sin un servicio externo.
import { PGlite } from '@electric-sql/pglite'; // Ejecuta PostgreSQL aislado en memoria.

const migration = await readFile(new URL('../migrations/20261108000000_registration_and_roles.sql', import.meta.url), 'utf8'); // Evita duplicar el SQL productivo.
const administratorMigration = await readFile(new URL('../migrations/20261108010000_assign_test_administrator.sql', import.meta.url), 'utf8'); // Comprueba la asignación específica autorizada por el propietario.
const adminId = '00000000-0000-0000-0000-000000000001'; // Identifica la cuenta preexistente de prueba.
const clientId = '00000000-0000-0000-0000-000000000002'; // Identifica la cuenta pública de prueba.
const testAdministratorId = '1bb00d6c-9b14-43d0-b096-88969fcd8376'; // Identifica exclusivamente la cuenta autorizada para administración.

// Recrea únicamente las interfaces de Supabase Auth que necesita la migración.
async function createDatabase(existingUsers = 1) {
  const database = new PGlite(); // Aísla cada escenario de las otras pruebas.
  await database.exec(`
    create role anon;
    create role authenticated;
    create role service_role bypassrls;
    create schema auth;
    create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb default '{}');
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema public, auth to anon, authenticated, service_role;
    grant execute on function auth.uid() to anon, authenticated, service_role;
  `); // Simula identidades verificadas sin contactar el proyecto real.
  for (let index = 1; index <= existingUsers; index++) {
    await database.query('insert into auth.users (id, email) values ($1, $2)', [
      `00000000-0000-0000-0000-${String(index).padStart(12, '0')}`, // Genera identidades reproducibles.
      `user${index}@example.com`, // Evita utilizar direcciones reales.
    ]);
  }
  await database.exec(migration); // Ejecuta la migración completa, incluidos disparadores y políticas.
  return database; // Entrega la base aislada al escenario de prueba.
}

// Establece la identidad que PostgreSQL recibe normalmente desde un JWT de Supabase.
async function authenticate(database, userId) {
  await database.query("select set_config('request.jwt.claim.sub', $1, false)", [userId]);
  await database.exec('set role authenticated'); // Aplica privilegios y políticas reales al ejecutar las consultas.
}

test('La cuenta de prueba indicada recibe administración aunque ya existan clientes nuevos', async () => {
  const database = await createDatabase(0); // No promueve ninguna cuenta por el número de usuarios.
  try {
    await database.query('insert into auth.users (id, email) values ($1, $2), ($3, $4)', [testAdministratorId, 'usuarioprueba@gmail.com', clientId, 'client@example.com']);
    await database.exec(administratorMigration); // Asigna el rol mediante el UUID y el correo autorizados.
    await database.exec(administratorMigration); // Comprueba que repetir la asignación no crea duplicados.
    const { rows } = await database.query("select user_id from public.user_roles where role = 'admin'");
    assert.deepEqual(rows, [{ user_id: testAdministratorId }]); // Ningún cliente nuevo recibe administración.
    const clientRoles = await database.query('select role from public.user_roles where user_id = $1', [clientId]);
    assert.deepEqual(clientRoles.rows, [{ role: 'client' }]); // Las altas públicas conservan el rol de cliente.
  } finally {
    await database.close(); // Libera los recursos del escenario.
  }
});

test('La asignación administrativa requiere que coincidan tanto el UUID como el correo', async () => {
  const database = await createDatabase(0); // Prepara un proyecto sin administradores iniciales.
  try {
    await database.query('insert into auth.users (id, email) values ($1, $2), ($3, $4)', [testAdministratorId, 'different@example.com', clientId, 'usuarioprueba@gmail.com']);
    await database.exec(administratorMigration); // Rechaza promover una identidad que solo coincida parcialmente.
    const { rows } = await database.query("select count(*)::integer as total from public.user_roles where role = 'admin'");
    assert.equal(rows[0].total, 0); // Un correo o UUID aislado no concede permisos administrativos.
  } finally {
    await database.close(); // Libera los datos aislados de la prueba.
  }
});

test('La cuenta única existente recibe administración y los registros ignoran roles enviados por el cliente', async () => {
  const database = await createDatabase(); // Carga una cuenta antes de ejecutar la migración.
  try {
    await database.query('insert into auth.users (id, email, raw_user_meta_data) values ($1, $2, $3)', [
      clientId, 'client@example.com', { full_name: 'Cliente Público', role: 'admin', roles: ['admin'] },
    ]); // Intenta conceder administración mediante metadatos manipulados.
    const { rows } = await database.query('select user_id, role from public.user_roles order by user_id, role');
    assert.deepEqual(rows, [
      { user_id: adminId, role: 'admin' }, // Solo la cuenta previa conserva administración.
      { user_id: adminId, role: 'client' }, // La cuenta previa también conserva acceso de cliente.
      { user_id: clientId, role: 'client' }, // La cuenta pública nunca obtiene el rol enviado en metadatos.
    ]);
  } finally {
    await database.close(); // Libera PostgreSQL al terminar el escenario.
  }
});

test('No promueve automáticamente cuentas cuando el proyecto empieza vacío o tiene varias cuentas', async () => {
  for (const count of [0, 2]) {
    const database = await createDatabase(count); // Comprueba ambas situaciones ambiguas de inicialización.
    try {
      await database.query('insert into auth.users (id, email) values ($1, $2)', [
        '00000000-0000-0000-0000-000000000003', 'new@example.com',
      ]); // La primera alta después del despliegue tampoco debe obtener administración.
      const { rows } = await database.query("select count(*)::integer as total from public.user_roles where role = 'admin'");
      assert.equal(rows[0].total, 0); // Exige una asignación explícita del operador en estos escenarios.
    } finally {
      await database.close(); // Libera la base utilizada por cada caso.
    }
  }
});

test('Un cliente solo lee su perfil y no puede listar usuarios ni escribir roles directamente', async () => {
  const database = await createDatabase(); // Prepara el administrador inicial.
  try {
    await database.query('insert into auth.users (id, email) values ($1, $2)', [clientId, 'client@example.com']);
    await authenticate(database, clientId); // Ejecuta las consultas con privilegios de cliente.
    const profiles = await database.query('select id from public.profiles');
    assert.deepEqual(profiles.rows, [{ id: clientId }]); // La política oculta el perfil del administrador.
    const roles = await database.query('select user_id, role from public.user_roles');
    assert.deepEqual(roles.rows, [{ user_id: clientId, role: 'client' }]); // Oculta también los permisos de otros usuarios.
    await assert.rejects(database.query('select * from public.list_users()'), { code: '42501' });
    await assert.rejects(database.query('select public.set_user_roles($1, $2)', [clientId, ['admin']]), { code: '42501' });
    await assert.rejects(database.query("insert into public.user_roles values ($1, 'admin')", [clientId]), { code: '42501' });
    await assert.rejects(database.query("update public.profiles set full_name = 'Otro'"), { code: '42501' });
  } finally {
    await database.close(); // Elimina los datos aislados de esta prueba.
  }
});

test('El administrador asigna varios roles, los retira y no puede eliminar el último administrador', async () => {
  const database = await createDatabase(); // Prepara la cuenta administrativa inicial.
  try {
    await database.query('insert into auth.users (id, email) values ($1, $2)', [clientId, 'client@example.com']);
    await authenticate(database, adminId); // Ejecuta la gestión con la identidad autorizada.
    await database.query('select public.set_user_roles($1, $2)', [clientId, ['associate', 'worker', 'worker']]);
    const roles = await database.query('select role from public.user_roles where user_id = $1 order by role', [clientId]);
    assert.deepEqual(roles.rows, [{ role: 'associate' }, { role: 'worker' }]); // Comprueba la selección múltiple sin duplicados.
    await database.query('select public.set_user_roles($1, $2)', [clientId, []]); // Permite retirar todos los roles no administrativos.
    const page = await database.query('select * from public.list_users(0, 20)');
    assert.equal(page.rows.length, 2); // La consulta administrativa incluye todas las cuentas.
    assert.deepEqual(page.rows.find((row) => row.id === clientId).roles, []); // La lista incluye perfiles sin roles.
    await assert.rejects(database.query('select public.set_user_roles($1, $2)', [adminId, ['client']]), { code: '23514' });
    await assert.rejects(database.query('select public.set_user_roles($1, $2)', [clientId, ['owner']]), { code: '22023' });
    await assert.rejects(database.query('select public.set_user_roles($1, $2)', [clientId, [null]]), { code: '22023' });
    await assert.rejects(database.query('select * from public.list_users(-1, 20)'), { code: '22023' });
    const preserved = await database.query("select public.has_role('admin') as allowed");
    assert.equal(preserved.rows[0].allowed, true); // Un rechazo no modifica los permisos previos.
    await database.query('select public.set_user_roles($1, $2)', [clientId, ['admin']]); // Habilita un segundo administrador.
    await database.query('select public.set_user_roles($1, $2)', [adminId, ['client']]); // Permite retirar administración cuando queda otra cuenta responsable.
    await assert.rejects(database.query('select * from public.list_users()'), { code: '42501' }); // La revocación se aplica sin renovar el JWT.
  } finally {
    await database.close(); // Libera la instancia de PostgreSQL.
  }
});

test('Una solicitud anónima no puede leer perfiles ni ejecutar funciones administrativas', async () => {
  const database = await createDatabase(); // Prepara perfiles que deben permanecer privados.
  try {
    await database.exec('set role anon'); // Simula una solicitud con la clave pública y sin usuario.
    await assert.rejects(database.query('select * from public.profiles'), { code: '42501' });
    await assert.rejects(database.query('select * from public.user_roles'), { code: '42501' });
    await assert.rejects(database.query('select * from public.list_users()'), { code: '42501' });
    await assert.rejects(database.query('select public.set_user_roles($1, $2)', [adminId, ['admin']]), { code: '42501' });
  } finally {
    await database.close(); // Libera los recursos de la prueba.
  }
});
