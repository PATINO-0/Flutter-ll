import { handleRequest as manageUser } from "../manage-user/index.ts"; // Comprueba el servicio de edición y revocación.
import { handleRequest as createUser } from "../create-user/index.ts"; // Comprueba el servicio de creación.
import { handleRequest as seedTransporters } from "../seed-transporters/index.ts"; // Conserva el mismo contrato para las cuentas de prueba.

for (
  const [name, handler] of [
    ["manage-user", manageUser],
    ["create-user", createUser],
    ["seed-transporters", seedTransporters],
  ] as const
) {
  Deno.test(`${name}: permite la petición previa del navegador sin consultar Auth`, async () => {
    const response = await handler(
      new Request(`https://test.supabase.co/functions/v1/${name}`, {
        method: "OPTIONS",
        headers: {
          Origin: "http://localhost:64942",
          "Access-Control-Request-Method": "POST",
          "Access-Control-Request-Headers":
            "authorization, apikey, x-client-info, content-type",
        },
      }),
    );
    if (
      !response.ok ||
      response.headers.get("access-control-allow-origin") !== "*"
    ) {
      throw new Error(
        "La petición previa debe responder correctamente antes de exigir autenticación.",
      );
    }
    const allowed =
      response.headers.get("access-control-allow-headers")?.toLowerCase().split(
        ",",
      ).map((header) => header.trim()) ?? [];
    for (
      const header of [
        "authorization",
        "apikey",
        "x-client-info",
        "content-type",
      ]
    ) {
      if (!allowed.includes(header)) {
        throw new Error(`Falta permitir la cabecera ${header}.`);
      }
    }
    if (
      !response.headers.get("access-control-allow-methods")?.includes("POST")
    ) {
      throw new Error(
        "La petición previa debe habilitar el método de edición.",
      );
    }
  });

  Deno.test(`${name}: responder a CORS no permite operar sin una sesión`, async () => {
    const response = await handler(
      new Request(`https://test.supabase.co/functions/v1/${name}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      }),
    );
    if (
      response.status !== 401 ||
      response.headers.get("access-control-allow-origin") !== "*"
    ) {
      throw new Error(
        "Debe conservar la autenticación y permitir leer el rechazo desde el navegador.",
      );
    }
    await response.body?.cancel(); // Consume la respuesta sin registrar datos de sesión.
  });
}
