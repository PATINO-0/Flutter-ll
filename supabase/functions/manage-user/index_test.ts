import { handleRequest } from "./index.ts"; // Ejecuta la misma implementación que se desplegará.
const target = "00000000-0000-0000-0000-000000000002"; // Utiliza una cuenta ficticia con UUID válido.
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
} // Identifica el comportamiento que falló.

async function scenario(
  action: string,
  options: {
    admin?: boolean;
    token?: boolean;
    databaseError?: string;
    userId?: string;
  } = {},
) {
  const originalFetch = globalThis.fetch; // Impide cualquier petición real durante la prueba.
  const variables = [
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
  ];
  const previous = variables.map((name) => Deno.env.get(name)); // Restaura las variables al finalizar cada caso.
  Deno.env.set(variables[0], "https://test.supabase.co");
  Deno.env.set(variables[1], "test-anon");
  Deno.env.set(variables[2], "test-service");
  const calls: {
    path: string;
    method: string;
    body: Record<string, unknown>;
  }[] = [];
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    const path = new URL(request.url).pathname;
    const body = request.body ? await request.json() : {};
    calls.push({ path, method: request.method, body }); // Registra solamente datos ficticios para comprobar el orden de autorización.
    const response = (value: unknown, status = 200) =>
      new Response(JSON.stringify(value), {
        status,
        headers: { "Content-Type": "application/json" },
      });
    if (path === "/auth/v1/user") {
      return response({
        id: "00000000-0000-0000-0000-000000000001",
        email: "admin@example.com",
      });
    }
    if (path.endsWith("/has_role")) return response(options.admin !== false);
    if (path.startsWith("/rest/v1/rpc/")) {
      return options.databaseError
        ? response({ code: options.databaseError, message: "Denied" }, 403)
        : response(null);
    }
    if (path === `/auth/v1/admin/users/${target}`) {
      return response({
        id: target,
        email: "old@example.com",
        user_metadata: { full_name: "Nombre anterior" },
      });
    }
    throw new Error(`Petición no prevista: ${path}`); // Rechaza cualquier acceso externo que no sea parte de la prueba.
  };
  try {
    const response = await handleRequest(
      new Request("https://test.supabase.co/functions/v1/manage-user", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(options.token === false
            ? {}
            : { Authorization: "Bearer test-token" }),
        },
        body: JSON.stringify({
          action,
          userId: options.userId ?? target,
          fullName: "Nombre nuevo",
          email: "new@example.com",
          roles: ["client"],
        }),
      }),
    );
    return { status: response.status, body: await response.json(), calls };
  } finally {
    globalThis.fetch = originalFetch;
    variables.forEach((name, index) => {
      if (previous[index] === undefined) Deno.env.delete(name);
      else Deno.env.set(name, previous[index]!);
    });
  }
}

Deno.test("Una solicitud sin sesión no puede actualizar ni eliminar acceso", async () => {
  const result = await scenario("update", { token: false });
  assert(
    result.status === 401 && result.calls.length === 0,
    "Debe rechazar antes de contactar al servicio administrativo",
  );
});
Deno.test("Un trabajador no puede utilizar la función exclusiva del administrador", async () => {
  const result = await scenario("deactivate", { admin: false });
  assert(
    result.status === 403 && result.calls.length === 2,
    "Debe comprobar el rol antes de utilizar privilegios internos",
  );
});
Deno.test("La edición sincroniza Auth y el perfil con la identidad del administrador", async () => {
  const result = await scenario("update");
  assert(result.status === 200, "Debe confirmar la actualización autorizada");
  const update = result.calls.find((call) =>
    call.path.endsWith(target) && call.method === "PUT"
  );
  assert(
    update?.body.email === "new@example.com",
    "Debe actualizar el correo de acceso",
  );
  assert(
    result.calls.at(-1)?.path.endsWith("/admin_update_user"),
    "Debe comprobar los permisos también al guardar el perfil y sus roles",
  );
});
Deno.test("La protección del último administrador revierte los cambios previos de Auth", async () => {
  const result = await scenario("update", { databaseError: "23514" });
  assert(
    result.status === 409,
    "Debe rechazar la retirada del último administrador",
  );
  assert(
    result.calls.at(-1)?.body.email === "old@example.com",
    "Debe restablecer el correo anterior si el servidor rechaza el cambio",
  );
});
Deno.test("La eliminación de acceso revoca primero los datos y después bloquea Auth", async () => {
  const result = await scenario("deactivate");
  assert(
    result.status === 200 && result.body.accessRemoved === true,
    "Debe confirmar la revocación",
  );
  const databaseIndex = result.calls.findIndex((call) =>
    call.path.endsWith("/admin_deactivate_user")
  );
  const banIndex = result.calls.findIndex((call) =>
    call.body.ban_duration === "876000h"
  );
  assert(
    databaseIndex >= 0 && banIndex > databaseIndex,
    "La revocación de datos debe preceder al bloqueo de Auth",
  );
});
Deno.test("Un rechazo de revocación no debe bloquear la cuenta en Auth", async () => {
  const result = await scenario("deactivate", { databaseError: "23514" });
  assert(
    result.status === 409,
    "Debe informar que el último administrador no puede eliminarse",
  );
  assert(
    !result.calls.some((call) => call.path.includes("/admin/users/")),
    "No debe bloquear una cuenta cuya revocación fue rechazada",
  );
});
Deno.test("Un identificador inválido no permite acceder a la API administrativa", async () => {
  const result = await scenario("update", { userId: "invalid" });
  assert(
    result.status === 400 && result.calls.length === 2,
    "Debe validar la cuenta antes de utilizar la clave administrativa",
  );
});
