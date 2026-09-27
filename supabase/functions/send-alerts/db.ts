// Just enough PostgREST to call two functions, so the edge function has no
// dependencies to download.
export function postgrest(url: string, serviceKey: string, fetchFn: typeof fetch = fetch) {
  const headers: Record<string, string> = { apikey: serviceKey, "content-type": "application/json" };
  // Legacy service_role keys are JWTs and go in Authorization too; new
  // sb_secret_ keys only go in apikey.
  if (serviceKey.startsWith("eyJ")) headers.authorization = `Bearer ${serviceKey}`;

  return {
    async rpc<T = void>(fn: string, args: Record<string, unknown>): Promise<T> {
      const res = await fetchFn(`${url}/rest/v1/rpc/${fn}`, {
        method: "POST",
        headers,
        body: JSON.stringify(args),
      });
      if (!res.ok) throw new Error(`${fn} ${res.status}: ${await res.text()}`);
      const text = await res.text();
      return (text ? JSON.parse(text) : undefined) as T;
    },
  };
}
