import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return new Response(
      JSON.stringify({ error: "Missing authorization token." }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return new Response(
      JSON.stringify({ error: "Server configuration incomplete." }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser(token);

  if (userError || !user) {
    return new Response(
      JSON.stringify({ error: "Invalid or expired session." }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const uid = user.id;

  // 1. Release any claimed team player spots while keeping match history intact.
  await admin
    .from("players")
    .update({
      user_id: null,
      claimed_at: null,
      avatar_url: null,
      updated_at: Date.now(),
    })
    .eq("user_id", uid);

  // 2. Remove uploaded avatar/team images owned by this user.
  try {
    const { data: files } = await admin.storage.from("avatars").list(uid);
    if (files && files.length > 0) {
      const paths = files.map((f) => `${uid}/${f.name}`);
      await admin.storage.from("avatars").remove(paths);
    }
  } catch {
    // Non-fatal: proceed with auth deletion even if storage cleanup fails.
  }

  // 3. Delete the auth user (FKs use ON DELETE SET NULL for teams/matches).
  const { error: deleteError } = await admin.auth.admin.deleteUser(uid);
  if (deleteError) {
    return new Response(
      JSON.stringify({ error: deleteError.message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  return new Response(
    JSON.stringify({ deleted: true }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
