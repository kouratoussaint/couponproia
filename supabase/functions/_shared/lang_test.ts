import { assertEquals } from "jsr:@std/assert@1";
import { asLang, browserLang, pick } from "./lang.ts";

Deno.test("langue : français par défaut, anglais si demandé", () => {
  assertEquals(asLang("en"), "en");
  assertEquals(asLang("de"), "fr");
  assertEquals(asLang(undefined), "fr");
  assertEquals(browserLang("en-GB,en;q=0.9,fr;q=0.8"), "en");
  assertEquals(browserLang("fr-FR,fr;q=0.9,en;q=0.5"), "fr");
  assertEquals(browserLang(null), "fr");
  assertEquals(browserLang("fr-FR", "en"), "en");
  assertEquals(pick("en", "Bonjour", "Hello"), "Hello");
});
