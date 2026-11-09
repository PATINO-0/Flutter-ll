import { createClient } from "npm:@supabase/supabase-js@2.108.2"; // Conserva la versión utilizada por las demás funciones de usuarios.
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
}; // Admite la aplicación web con autenticación explícita.
const respond = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers });
export const transporterEmails = Array.from(
  { length: 5 },
  (_, index) => `transportador${index === 0 ? "" : index}@gmail.com`,
); // Genera exactamente cinco cuentas, desde la dirección sin sufijo hasta transportador4.

/// Prepara cuentas de prueba sin sobrescribir contraseñas ni roles de usuarios existentes.
export async function handleRequest(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") return new Response(null, { headers });
  if (request.method !== "POST") {
    return respond(405, { error: "Método no permitido." });
  }
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return respond(401, { error: "Debes iniciar sesión." });
  }
  const url = Deno.env.get("SUPABASE_URL"),
    anonKey = Deno.env.get("SUPABASE_ANON_KEY"),
    serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) {
    return respond(500, {
      error: "El servicio de usuarios no está configurado.",
    });
  }
  try {
    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: identity, error: identityError } = await userClient.auth
      .getUser(authorization.slice(7)); // Verifica el token antes de utilizar la clave de servidor.
    if (identityError || !identity.user) {
      return respond(401, { error: "Tu sesión no es válida." });
    }
    const { data: admin, error: permissionError } = await userClient.rpc(
      "has_role",
      { requested_role: "admin" },
    );
    if (permissionError || admin !== true) {
      return respond(403, {
        error:
          "Solo el administrador puede preparar transportadores de prueba.",
      });
    }
    const server = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const existing = new Map<string, string>(); // Conserva solo las identidades que coinciden con los cinco correos solicitados.
    for (let page = 1; page <= 100; page++) {
      const { data, error } = await server.auth.admin.listUsers({
        page,
        perPage: 200,
      });
      if (error) {
        return respond(500, {
          error: "No fue posible verificar las cuentas existentes.",
        });
      }
      for (const account of data.users) {
        const email = account.email?.toLowerCase();
        if (email && transporterEmails.includes(email)) {
          existing.set(email, account.id);
        }
      }
      if (data.users.length < 200 || existing.size === 5) break;
      if (page === 100) {
        return respond(500, {
          error:
            "No fue posible completar la verificación de cuentas. Solicita una revisión administrativa.",
        });
      }
    }
    let created = 0, skipped = 0;
    const errors: string[] = [];
    for (const [index, email] of transporterEmails.entries()) {
      const previousId = existing.get(email);
      if (previousId) {
        const { data: profile, error: profileError } = await server.from(
          "profiles",
        ).select("is_active").eq("id", previousId).maybeSingle();
        const { data: roles, error: rolesError } = await server.from(
          "user_roles",
        ).select("role").eq("user_id", previousId);
        if (
          !profileError && !rolesError && profile?.is_active === true &&
          roles?.some((row) => row.role === "transporter") &&
          roles.every((row) => ["transporter", "client"].includes(row.role))
        ) {
          skipped++;
          continue;
        }
        errors.push(
          `${email}: la cuenta ya existe con otro acceso; revísala desde Administración.`,
        );
        continue; // No toma control de una cuenta existente ni restablece su contraseña.
      }
      const { data: account, error: createError } = await server.auth.admin
        .createUser({
          email,
          password: "12345678",
          email_confirm: true,
          user_metadata: { full_name: `Transportador de prueba ${index + 1}` },
        }); // Utiliza exclusivamente la contraseña de prueba solicitada por el propietario.
      if (createError || !account.user) {
        errors.push(`${email}: no fue posible crear la cuenta.`);
        continue;
      }
      let failed = false;
      try {
        const { error } = await userClient.rpc("set_user_roles", {
          target_user_id: account.user.id,
          new_roles: ["transporter"],
        });
        failed = error !== null;
      } catch {
        failed = true;
      } // Vuelve a verificar los permisos administrativos en la asignación.
      if (failed) {
        const { error } = await server.auth.admin.deleteUser(account.user.id);
        errors.push(
          error
            ? `${email}: cuenta creada sin completar el rol; revisa Administración.`
            : `${email}: creación cancelada porque no se pudo asignar el rol.`,
        );
        continue;
      }
      created++;
    }
    return respond(200, { created, skipped, errors }); // No devuelve claves, contraseñas ni tokens en la respuesta.
  } catch {
    return respond(500, {
      error:
        "No fue posible preparar las cuentas de prueba. Intenta nuevamente.",
    });
  }
}
if (import.meta.main) Deno.serve(handleRequest); // Permite importar el controlador sin abrir un servicio durante las pruebas.
