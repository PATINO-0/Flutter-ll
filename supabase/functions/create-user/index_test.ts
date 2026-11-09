import { handleRequest } from "./index.ts"; // Prueba la misma función que se despliega en Supabase.

const createdId = "00000000-0000-0000-0000-000000000002"; // Reproduce el identificador válido que devuelve Supabase Auth.

// Comprueba condiciones sin incorporar dependencias adicionales a las pruebas.
function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message); // Identifica el comportamiento que falló.
}

// Simula Supabase Auth y REST; ninguna prueba crea usuarios ni envía datos a la red.
async function runScenario(options: {
  admin?: boolean; // Permite probar usuarios sin permisos administrativos.
  invalidSession?: boolean; // Permite probar tokens rechazados por Auth.
  rolesFail?: boolean; // Simula un fallo al guardar roles después de crear la cuenta.
  rolesThrow?: boolean; // Simula una interrupción de red al guardar roles.
  cleanupFail?: boolean; // Simula un fallo al revertir la cuenta recién creada.
  body?: unknown; // Permite probar datos malformados o roles no permitidos.
  authorization?: boolean; // Permite probar solicitudes sin token.
} = {}) {
  const originalFetch = globalThis.fetch; // Conserva la implementación original de red.
  const calls: {
    path: string;
    method: string;
    body: Record<string, unknown>;
  }[] = []; // Registra operaciones sin exponer contraseñas en la salida.
  const names = [
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
  ]; // Enumera las variables aisladas del escenario.
  const previous = names.map((name) => Deno.env.get(name)); // Conserva la configuración del proceso.
  Deno.env.set(names[0], "https://test.supabase.co"); // Evita utilizar un proyecto real.
  Deno.env.set(names[1], "test-anon-key"); // Proporciona una clave ficticia de cliente.
  Deno.env.set(names[2], "test-service-key"); // Proporciona una clave ficticia de servidor.
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init); // Normaliza las solicitudes del cliente oficial.
    const path = new URL(request.url).pathname; // Identifica la API llamada por el controlador.
    const body = request.body ? await request.json() : {}; // Permite revisar los datos enviados a Supabase.
    calls.push({ path, method: request.method, body }); // Conserva el orden de las operaciones.
    const json = (value: unknown, status = 200) =>
      new Response(JSON.stringify(value), {
        status,
        headers: { "Content-Type": "application/json" },
      });
    if (path === "/auth/v1/user") {
      return options.invalidSession
        ? json({ message: "Invalid token" }, 401)
        : json({ id: "administrator", email: "admin@example.com" });
    }
    if (path.endsWith("/has_role")) return json(options.admin !== false); // Simula la autorización actual del solicitante.
    if (path === "/auth/v1/admin/users" && request.method === "POST") {
      return json({ id: createdId, email: "worker@example.com" });
    }
    if (path.endsWith("/set_user_roles")) {
      if (options.rolesThrow) throw new Error("Simulated network failure"); // Comprueba la compensación ante excepciones de red.
      return options.rolesFail
        ? json({ message: "Denied", code: "42501" }, 403)
        : json(null);
    }
    if (
      path === `/auth/v1/admin/users/${createdId}` &&
      request.method === "DELETE"
    ) {
      return options.cleanupFail
        ? json({ message: "Unavailable" }, 503)
        : json({}); // Controla el resultado de la reversión.
    }
    throw new Error(`Solicitud inesperada: ${path}`); // Prohíbe cualquier llamada de red no prevista por la prueba.
  };
  try {
    const response = await handleRequest(
      new Request("https://test.supabase.co/functions/v1/create-user", {
        method: "POST", // Reproduce el método utilizado por la aplicación.
        headers: {
          "Content-Type": "application/json",
          ...(options.authorization === false
            ? {}
            : { Authorization: "Bearer test-token" }),
        },
        body: JSON.stringify(
          options.body ??
            {
              fullName: "Persona de prueba",
              email: "worker@example.com",
              password: "password123",
              roles: ["worker", "admin"],
            },
        ),
      }),
    );
    return { response, payload: await response.json(), calls }; // Devuelve solo los resultados necesarios para las comprobaciones.
  } finally {
    globalThis.fetch = originalFetch; // Restaura la red después del escenario.
    names.forEach((name, index) => {
      if (previous[index] === undefined) Deno.env.delete(name); // Retira variables creadas por la prueba.
      else Deno.env.set(name, previous[index]!); // Recupera variables que ya existían en el proceso.
    });
  }
}

Deno.test("La creación administrativa valida identidad y permisos antes de crear y asignar roles", async () => {
  const { response, payload, calls } = await runScenario(); // Ejecuta una solicitud autorizada completa.
  assert(
    response.status === 201 && payload.id === createdId,
    "Debe confirmar la cuenta creada",
  );
  assert(
    calls.map((call) => call.path).join(",") ===
      "/auth/v1/user,/rest/v1/rpc/has_role,/auth/v1/admin/users,/rest/v1/rpc/set_user_roles",
    "Debe comprobar permisos antes de crear y asignar roles",
  );
  const created =
    calls.find((call) => call.path === "/auth/v1/admin/users")!.body; // Examina los datos destinados a Auth.
  assert(
    JSON.stringify(created.user_metadata) ===
      JSON.stringify({ full_name: "Persona de prueba" }),
    "Los metadatos no deben contener permisos",
  );
  assert(
    !("password" in payload),
    "La respuesta nunca debe devolver la contraseña",
  );
});

Deno.test("La falta de token impide toda operación remota", async () => {
  const result = await runScenario({ authorization: false }); // Omite la cabecera de autenticación.
  assert(
    result.response.status === 401 && result.calls.length === 0,
    "Debe rechazar la solicitud sin token",
  );
});

Deno.test("Un token rechazado por Auth no permite crear cuentas", async () => {
  const result = await runScenario({ invalidSession: true }); // Reproduce una sesión inválida o vencida.
  assert(
    result.response.status === 401 && result.calls.length === 1,
    "Debe validar el token antes de consultar permisos",
  );
});

Deno.test("Una cuenta sin administración no puede utilizar la clave privilegiada", async () => {
  const result = await runScenario({ admin: false }); // Reproduce una cuenta con sesión y sin rol administrativo.
  assert(
    result.response.status === 403 && result.calls.length === 2,
    "Debe denegar la creación antes de utilizar la API administrativa",
  );
});

Deno.test("Los roles desconocidos se rechazan antes de crear una cuenta", async () => {
  const result = await runScenario({
    body: {
      fullName: "Persona",
      email: "person@example.com",
      password: "password123",
      roles: ["owner"],
    },
  });
  assert(
    result.response.status === 400 && result.calls.length === 2,
    "Debe validar los permisos solicitados antes de crear",
  );
});

Deno.test("Un fallo de asignación revierte la cuenta recién creada", async () => {
  const result = await runScenario({ rolesFail: true }); // Reproduce una revocación del administrador durante la creación.
  assert(
    result.response.status === 403,
    "No debe confirmar una creación con roles incompletos",
  );
  assert(
    result.calls.at(-1)?.method === "DELETE",
    "Debe eliminar la cuenta creada cuando falla la asignación",
  );
});

Deno.test("Una excepción de red durante la asignación también revierte la cuenta", async () => {
  const result = await runScenario({ rolesThrow: true }); // Interrumpe la asignación después de crear la cuenta.
  assert(
    result.response.status === 403 && result.calls.at(-1)?.method === "DELETE",
    "Debe revertir también cuando falla la conexión",
  );
});

Deno.test("Si la reversión falla, informa que la cuenta requiere revisión sin confirmar su creación", async () => {
  const result = await runScenario({ rolesFail: true, cleanupFail: true }); // Reproduce un fallo de asignación seguido de un fallo al cancelar la cuenta.
  assert(
    result.response.status === 500,
    "No debe confirmar una operación incompleta",
  );
  assert(
    result.payload.error.includes("Revisa la lista de usuarios"),
    "Debe indicar cómo revisar la cuenta que no se pudo cancelar",
  );
});
