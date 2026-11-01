import { assert, assertEquals } from "jsr:@std/assert@1";
import { downloadUrl, intentUrl, isAndroid, parseShare } from "./links.ts";

Deno.test("liens : cibles reconnues, le reste refusé", () => {
  assertEquals(parseShare("/share/c/0D3A5B1C-1111-4222-8333-944455556666"), {
    kind: "coupon",
    id: "0d3a5b1c-1111-4222-8333-944455556666",
  });
  assertEquals(parseShare("/functions/v1/share/m/5988"), { kind: "match", id: "5988" });
  assertEquals(parseShare("/share/c/pas-un-uuid"), null);
  assertEquals(parseShare("/share/x/1"), null);
  assertEquals(parseShare("/share/m/1;evil"), null);
});

Deno.test("intent Android avec repli encodé", () => {
  const url = intentUrl({ kind: "match", id: "5988" }, "https://p.supabase.co/x.apk?a=1");
  assert(url.startsWith("intent://open/match/5988#Intent;scheme=couponproia;package=com.couponproia.app;"));
  assert(url.includes("S.browser_fallback_url=https%3A%2F%2Fp.supabase.co%2Fx.apk%3Fa%3D1;end"));
});

Deno.test("téléchargement : stockage public, jamais la release GitHub privée", () => {
  assertEquals(
    downloadUrl("https://p.supabase.co/", "https://github.com/x/y/releases/download/v1/a.apk"),
    "https://p.supabase.co/storage/v1/object/public/downloads/android/coupon-pro-ia-latest-arm64-v8a.apk",
  );
  const pub = "https://p.supabase.co/storage/v1/object/public/downloads/android/coupon-pro-ia-0.25.0-arm64-v8a.apk";
  assertEquals(downloadUrl("https://p.supabase.co", pub), pub);
  assert(isAndroid("Mozilla/5.0 (Linux; Android 14)"));
  assert(!isAndroid("Mozilla/5.0 (iPhone)"));
});
