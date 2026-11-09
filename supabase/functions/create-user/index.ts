import { createClient } from "npm:@supabase/supabase-js@2.108.2"; // Utiliza un cliente de servidor con versión fija.

const corsHeaders = { // Permite invocar la función desde Flutter web sin almacenar cookies.
  "Access-Control-Allow-Origin": "*", // Admite los dominios donde se publique la aplicación.
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type", // Admite las cabeceras de Supabase.
  "Access-Control-Allow-Methods": "POST, OPTIONS", // Limita los métodos anunciados al navegador.
};

// Genera respuestas homogéneas sin devolver claves, contraseñas ni errores internos.
function respond(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status, // Conserva el código HTTP que corresponde a la operación.
    headers: { ...corsHeaders, "Content-Type": "application/json" }, // Informa el formato de la respuesta.
  });
}

// Procesa cada solicitud mediante autenticación y autorización explícitas.
export async function handleRequest(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders }); // Atiende la verificación del navegador.
  }
  if (request.method !== "POST") {
    return respond(405, { error: "Método no permitido." }); // Rechaza operaciones no previstas.
  }
  const authorization = request.headers.get("Authorization"); // Obtiene la sesión del administrador.
  if (!authorization?.startsWith("Bearer ")) {
    return respond(401, { error: "Debes iniciar sesión." }); // Exige un token de acceso.
  }
  const url = Deno.env.get("SUPABASE_URL"); // Lee la dirección del proyecto desde el servidor.
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY"); // Lee la clave pública para las consultas con permisos del usuario.
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"); // Mantiene la clave administrativa únicamente en el servidor.
  if (!url || !anonKey || !serviceKey) {
    return respond(500, {
      error: "El servicio de usuarios no está configurado.",
    });
  }

  try {
    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } }, // Conserva la identidad del solicitante para las funciones SQL.
      auth: { persistSession: false, autoRefreshToken: false }, // No comparte sesiones entre solicitudes.
    });
    const { data: identity, error: authError } = await userClient.auth.getUser(
      authorization.slice(7),
    ); // Valida el token con Supabase Auth.
    if (authError || !identity.user) {
      return respond(401, {
        error: "Tu sesión no es válida. Inicia sesión nuevamente.",
      });
    }
    const { data: isAdmin, error: permissionError } = await userClient.rpc(
      "has_role",
      { requested_role: "admin" },
    ); // Consulta permisos actuales.
    if (permissionError || isAdmin !== true) {
      return respond(403, {
        error: "Necesitas el rol de administrador para crear usuarios.",
      });
    }

    let body: Record<string, unknown>; // Conserva únicamente un objeto de datos validado.
    try {
      body = await request.json(); // Interpreta el contenido JSON de la solicitud.
      if (!body || typeof body !== "object" || Array.isArray(body)) {
        throw new Error("Invalid body"); // Rechaza valores que no sean objetos.
      }
    } catch {
      return respond(400, {
        error: "Los datos de la solicitud no son válidos.",
      }); // Informa el problema sin mostrar detalles internos.
    }
    const fullName = typeof body.fullName === "string"
      ? body.fullName.trim()
      : ""; // Normaliza el nombre completo.
    const email = typeof body.email === "string"
      ? body.email.trim().toLowerCase()
      : ""; // Normaliza el correo de acceso.
    const password = typeof body.password === "string" ? body.password : ""; // Conserva la contraseña sin modificarla.
    const roles = body.roles; // Obtiene la selección de permisos solicitada.
    const allowedRoles = ["admin", "client", "associate", "worker"]; // Comparte los identificadores admitidos en la base de datos.
    if (
      fullName.length < 3 || fullName.length > 100 ||
      !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) ||
      password.length < 8 || password.length > 72 || !Array.isArray(roles) ||
      roles.length === 0 ||
      roles.some((role) =>
        typeof role !== "string" || !allowedRoles.includes(role)
      )
    ) {
      return respond(400, {
        error:
          "Verifica el nombre, el correo, la contraseña y los roles seleccionados.",
      });
    }

    const adminClient = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false }, // No almacena una sesión administrativa persistente.
    });
    const { data: created, error: createError } = await adminClient.auth.admin
      .createUser({
        email, // Establece el correo de acceso de la cuenta administrada.
        password, // Delega el almacenamiento seguro de la contraseña a Supabase Auth.
        email_confirm: true, // Habilita la cuenta provisionada explícitamente por el administrador.
        user_metadata: { full_name: fullName }, // Excluye los roles de los metadatos editables.
      });
    if (createError || !created.user) {
      if (
        createError?.code === "email_exists" ||
        createError?.code === "user_already_exists"
      ) {
        return respond(409, {
          error: "Ya existe una cuenta con este correo electrónico.",
        });
      }
      if (createError?.code === "weak_password") {
        return respond(400, {
          error:
            "La contraseña no cumple los requisitos de seguridad del servidor.",
        });
      }
      return respond(400, {
        error:
          "No fue posible crear la cuenta. Revisa los datos e intenta nuevamente.",
      });
    }

    let rolesFailed = false; // Controla los fallos de permisos y de conexión durante la asignación.
    try {
      const { error } = await userClient.rpc("set_user_roles", {
        target_user_id: created.user.id, // Asigna permisos solamente a la cuenta recién creada.
        new_roles: [...new Set(roles)], // Elimina los roles duplicados antes de guardar.
      }); // Vuelve a verificar los permisos actuales del administrador.
      rolesFailed = error !== null; // Detecta una asignación rechazada por la base de datos.
    } catch {
      rolesFailed = true; // Solicita también la reversión cuando falla la conexión.
    }
    if (rolesFailed) {
      const { error: cleanupError } = await adminClient.auth.admin.deleteUser(
        created.user.id,
      ); // Revierte la creación si fallan los roles.
      if (cleanupError) {
        console.error(
          "No fue posible revertir la creación de la cuenta:",
          created.user.id,
        ); // Registra solo el identificador para revisión operativa.
        return respond(500, {
          error:
            "La cuenta se creó, pero no se pudieron confirmar sus roles ni cancelar la creación. Revisa la lista de usuarios.",
        });
      }
      return respond(403, {
        error:
          "No fue posible asignar los roles. La creación fue cancelada; actualiza tus permisos.",
      });
    }
    return respond(201, { id: created.user.id }); // Confirma la creación sin devolver datos sensibles.
  } catch {
    return respond(500, {
      error: "El servicio de usuarios no está disponible. Intenta nuevamente.",
    }); // Controla fallos de red o del servidor.
  }
}

// Inicia el servicio solo al ejecutar el archivo, sin abrir un puerto durante las pruebas.
if (import.meta.main) Deno.serve(handleRequest);
