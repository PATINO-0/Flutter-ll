import { createClient } from "npm:@supabase/supabase-js@2.108.2"; // Mantiene la misma versión del servicio de creación de cuentas.
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
}; // Admite Flutter web con autenticación explícita.
const respond = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers }); // Evita devolver información técnica o credenciales.

/// Actualiza datos de Auth o revoca acceso únicamente después de validar al administrador.
export async function handleRequest(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") return new Response(null, { headers });
  if (request.method !== "POST") {
    return respond(405, { error: "Método no permitido." });
  }
  const authorization = request.headers.get("Authorization"); // Obtiene el token real de la sesión solicitante.
  if (!authorization?.startsWith("Bearer ")) {
    return respond(401, { error: "Debes iniciar sesión." });
  }
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"); // Mantiene la clave privilegiada en el servidor.
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
    const { data: identity, error: authError } = await userClient.auth.getUser(
      authorization.slice(7),
    ); // No confía únicamente en la presencia de un token.
    if (authError || !identity.user) {
      return respond(401, { error: "Tu sesión no es válida." });
    }
    const { data: isAdmin, error: permissionError } = await userClient.rpc(
      "has_role",
      { requested_role: "admin" },
    );
    if (permissionError || isAdmin !== true) {
      return respond(403, {
        error: "Necesitas administración para modificar usuarios.",
      });
    }
    let body: Record<string, unknown>;
    try {
      body = await request.json();
      if (!body || Array.isArray(body) || typeof body !== "object") {
        throw new Error("Invalid body");
      }
    } catch {
      return respond(400, { error: "La solicitud no contiene datos válidos." });
    }
    const id = typeof body.userId === "string" ? body.userId : "";
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        id,
      )
    ) return respond(400, { error: "El usuario seleccionado no es válido." });
    const server = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    }); // Utiliza privilegios internos solo tras comprobar el rol.
    if (body.action === "deactivate") {
      const { error } = await userClient.rpc("admin_deactivate_user", {
        target_user_id: id,
      }); // Bloquea inmediatamente los datos y conserva al último administrador.
      if (error) {
        return respond(error.code === "23514" ? 409 : 403, {
          error: error.code === "23514"
            ? "Debe permanecer al menos un administrador activo."
            : "No fue posible retirar el acceso. Actualiza tus permisos.",
        });
      }
      const { error: banError } = await server.auth.admin.updateUserById(id, {
        ban_duration: "876000h",
      }); // Impide nuevos inicios y renovaciones de sesión en Auth.
      if (banError) {
        console.error(
          "Acceso revocado; pendiente sincronizar el bloqueo de Auth:",
          id,
        ); // No registra correo, contraseña ni token.
      }
      return respond(200, { id, accessRemoved: true }); // La revocación de las políticas ya es efectiva aunque Auth requiera sincronización.
    }
    if (body.action !== "update") {
      return respond(400, { error: "La operación solicitada no es válida." });
    }
    const fullName = typeof body.fullName === "string"
      ? body.fullName.trim()
      : "";
    const email = typeof body.email === "string"
      ? body.email.trim().toLowerCase()
      : "";
    const roles = body.roles;
    if (
      fullName.length < 3 || fullName.length > 100 ||
      !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || !Array.isArray(roles) ||
      roles.some((role) =>
        !["admin", "worker", "associate", "client"].includes(role)
      )
    ) {
      return respond(400, {
        error: "Revisa el nombre, correo y roles del usuario.",
      });
    }
    const { data: previous, error: previousError } = await server.auth.admin
      .getUserById(id); // Conserva los datos anteriores para compensar un rechazo de la actualización del perfil.
    if (previousError || !previous.user) {
      return respond(404, { error: "El usuario ya no está disponible." });
    }
    const { error: authUpdateError } = await server.auth.admin.updateUserById(
      id,
      {
        email,
        email_confirm: true,
        user_metadata: { ...previous.user.user_metadata, full_name: fullName },
      },
    ); // Sincroniza el correo de acceso y el nombre visible.
    if (authUpdateError) {
      return respond(400, {
        error:
          "No fue posible actualizar el correo. Comprueba que no pertenezca a otra cuenta.",
      });
    }
    let databaseError: string | null = null;
    try {
      const result = await userClient.rpc("admin_update_user", {
        target_user_id: id,
        new_name: fullName,
        new_email: email,
        new_roles: roles,
      });
      databaseError = result.error?.code ?? null;
    } catch {
      databaseError = "network";
    } // Compensa también cuando no puede confirmarse el resultado de la base de datos.
    if (databaseError) {
      const { error: rollbackError } = await server.auth.admin.updateUserById(
        id,
        {
          email: previous.user.email,
          user_metadata: previous.user.user_metadata,
        },
      ); // Restablece los datos de acceso si el servidor rechaza el cambio de permisos.
      if (rollbackError) {
        console.error("Pendiente revisar sincronización del usuario:", id);
      }
      return respond(409, {
        error: databaseError === "23514"
          ? "Debe permanecer al menos un administrador activo."
          : "No fue posible confirmar la actualización. Actualiza la lista y revisa los datos del usuario.",
      });
    }
    return respond(200, { id });
  } catch {
    return respond(500, {
      error: "El servicio de usuarios no está disponible. Intenta nuevamente.",
    });
  }
}
if (import.meta.main) Deno.serve(handleRequest); // No abre un puerto al importar la implementación desde pruebas.
