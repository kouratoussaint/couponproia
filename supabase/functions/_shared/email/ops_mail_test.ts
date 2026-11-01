import { assert, assertEquals } from "jsr:@std/assert@1";
import { alertEmail } from "./ops_mail.ts";

Deno.test("e-mail d'alerte : une alerte, puis plusieurs", () => {
  const one = alertEmail([{ id: 1, severity: "critical", title: "IA indisponible", body: "3 erreurs" }]);
  assertEquals(one.subject, "Alerte : IA indisponible");
  assert(one.text.includes("[CRITIQUE] IA indisponible"));
  const two = alertEmail([
    { id: 1, severity: "critical", title: "A", body: "a" },
    { id: 2, severity: "warning", title: "B", body: "b" },
  ]);
  assertEquals(two.subject, "2 alertes d'exploitation dont 1 critique(s)");
});
