import { handleRequest, transporterEmails } from "./index.ts"; // Ejecuta la implementación que se desplegará en Supabase.
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
async function scenario(
  options: {
    admin?: boolean;
    token?: boolean;
    existing?: boolean;
    assignFail?: boolean;
    transporterAlreadyExists?: boolean;
  } = {},
) {
  const savedFetch = globalThis.fetch;
  const names = [
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
  ];
  const previous = names.map((name) => Deno.env.get(name));
  Deno.env.set(names[0], "https://test.supabase.co");
  Deno.env.set(names[1], "test-anon");
  Deno.env.set(names[2], "test-service");
  const calls: {
    path: string;
    method: string;
    body: Record<string, unknown>;
  }[] = [];
  let createdIndex = 0;
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    const path = new URL(request.url).pathname;
    const body = request.body ? await request.json() : {};
    calls.push({ path, method: request.method, body });
    const json = (value: unknown, status = 200) =>
      new Response(JSON.stringify(value), {
        status,
        headers: { "Content-Type": "application/json" },
      });
    if (path === "/auth/v1/user") {
      return json({
        id: "00000000-0000-0000-0000-000000000001",
        email: "admin@example.com",
      });
    }
    if (path.endsWith("/has_role")) return json(options.admin !== false);
    if (path === "/auth/v1/admin/users" && request.method === "GET") {
      return json({
        users: options.existing
          ? [{
            id: "00000000-0000-0000-0000-000000000010",
            email: transporterEmails[0],
          }]
          : [],
        aud: "authenticated",
      });
    }
    if (path === "/rest/v1/profiles") return json([{ is_active: true }]);
    if (path === "/rest/v1/user_roles") {
      return json([{
        role: options.transporterAlreadyExists ? "transporter" : "client",
      }]); // Comprueba tanto la idempotencia como la protección de cuentas ajenas.
    }
    if (path === "/auth/v1/admin/users" && request.method === "POST") {
      createdIndex++;
      return json({
        id: `00000000-0000-0000-0000-${
          String(createdIndex + 10).padStart(12, "0")
        }`,
        email: body.email,
      });
    }
    if (path.endsWith("/set_user_roles")) {
      return options.assignFail
        ? json({ code: "42501", message: "Denied" }, 403)
        : json(null);
    }
    if (
      path.startsWith("/auth/v1/admin/users/") && request.method === "DELETE"
    ) return json({});
    throw new Error(`Solicitud inesperada: ${path}`);
  };
  try {
    const response = await handleRequest(
      new Request("https://test.supabase.co/functions/v1/seed-transporters", {
        method: "POST",
        headers: options.token === false
          ? {}
          : { Authorization: "Bearer test-token" },
      }),
    );
    return { status: response.status, body: await response.json(), calls };
  } finally {
    globalThis.fetch = savedFetch;
    names.forEach((name, index) => {
      if (previous[index] === undefined) Deno.env.delete(name);
      else Deno.env.set(name, previous[index]!);
    });
  }
}
Deno.test("Solo se generan cinco direcciones de transporte sin repetir la cuenta base", () => {
  assert(transporterEmails.length === 5, "Deben ser cinco cuentas");
  assert(
    transporterEmails[0] === "transportador@gmail.com" &&
      transporterEmails[4] === "transportador4@gmail.com",
    "Debe respetar la secuencia acordada",
  );
});
Deno.test("El administrador crea las cinco cuentas y les asigna únicamente transporte", async () => {
  const result = await scenario();
  assert(
    result.status === 200 && result.body.created === 5,
    "Debe crear cinco cuentas",
  );
  const creates = result.calls.filter((call) =>
    call.path === "/auth/v1/admin/users" && call.method === "POST"
  );
  assert(
    creates.every((call) => call.body.password === "12345678"),
    "Debe utilizar la contraseña de prueba autorizada",
  );
  assert(
    result.calls.filter((call) => call.path.endsWith("/set_user_roles")).every(
      (call) => JSON.stringify(call.body.new_roles) === '["transporter"]',
    ),
    "No debe conceder permisos de empleado",
  );
  assert(
    !("password" in result.body),
    "No debe devolver credenciales en la respuesta",
  );
});
Deno.test("Un empleado o una solicitud sin sesión no puede crear las cuentas", async () => {
  const denied = await scenario({ admin: false });
  assert(
    denied.status === 403 &&
      !denied.calls.some((call) => call.path.includes("/admin/users")),
    "Debe rechazar antes de acceder a Auth Admin",
  );
  const anonymous = await scenario({ token: false });
  assert(
    anonymous.status === 401 && anonymous.calls.length === 0,
    "Debe exigir sesión",
  );
});
Deno.test("Una cuenta existente con otro rol no cambia de contraseña ni se convierte automáticamente en transportador", async () => {
  const result = await scenario({ existing: true });
  assert(
    result.body.created === 4 && result.body.errors.length === 1,
    "Debe conservar la cuenta existente y preparar las restantes",
  );
  assert(
    !result.calls.some((call) => call.method === "PUT"),
    "No debe restablecer contraseñas existentes",
  );
});
Deno.test("El fallo al asignar transporte cancela las cuentas recién creadas", async () => {
  const result = await scenario({ assignFail: true });
  assert(
    result.body.created === 0 &&
      result.calls.filter((call) => call.method === "DELETE").length === 5,
    "Debe compensar las creaciones que no recibieron el rol",
  );
});

Deno.test("Repetir la preparación conserva al transportador existente sin restablecer su contraseña", async () => {
  const result = await scenario({
    existing: true,
    transporterAlreadyExists: true,
  });
  assert(
    result.body.created === 4 && result.body.skipped === 1 &&
      result.body.errors.length === 0,
    "Debe completar las cuentas faltantes y conservar la existente",
  );
  assert(
    !result.calls.some((call) => call.method === "PUT"),
    "No debe cambiar contraseñas ni datos de cuentas existentes",
  );
});
