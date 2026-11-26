import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const JSON_HEADERS = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed." }),
      {
        status: 405,
        headers: { ...JSON_HEADERS, Allow: "POST, OPTIONS" },
      },
    );
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return new Response(
      JSON.stringify({ error: "Missing authorization token." }),
      { status: 401, headers: JSON_HEADERS },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error("[delete-account] Missing required Supabase env variables.");
    return new Response(
      JSON.stringify({ error: "Service temporarily unavailable." }),
      { status: 500, headers: JSON_HEADERS },
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
      { status: 401, headers: JSON_HEADERS },
    );
  }

  if (user.is_anonymous) {
    return new Response(
      JSON.stringify({ error: "Anonymous sessions cannot invoke account deletion." }),
      { status: 403, headers: JSON_HEADERS },
    );
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const uid = user.id;

  // 1. Release any claimed team player spots while keeping match history intact.
  const { error: unlinkError } = await admin
    .from("players")
    .update({
      user_id: null,
      claimed_at: null,
      avatar_url: null,
      updated_at: Date.now(),
    })
    .eq("user_id", uid);

  if (unlinkError) {
    console.error("[delete-account] Failed to unlink player rows:", unlinkError.message);
    return new Response(
      JSON.stringify({ error: "Could not prepare account deletion. Please try again." }),
      { status: 500, headers: JSON_HEADERS },
    );
  }

  // 2. Clear logo URLs on teams owned by this user before deleting storage files
  //    so kept match scorecards don't point to dead image URLs.
  const { error: logoError } = await admin
    .from("teams")
    .update({ logo_url: null })
    .eq("owner_id", uid)
    .not("logo_url", "is", null);

  if (logoError) {
    console.error("[delete-account] Non-fatal team logo cleanup error:", logoError.message);
  }

  // 3. Remove any active handover codes created by this user.
  const { error: handoverError } = await admin
    .from("match_handover_codes")
    .delete()
    .eq("created_by", uid);

  if (handoverError) {
    console.error("[delete-account] Non-fatal handover cleanup error:", handoverError.message);
  }

  // 4. Remove all uploaded avatar/team images owned by this user (paginated).
  try {
    for (let page = 0; page < 20; page++) {
      const { data: files, error: listErr } = await admin.storage
        .from("avatars")
        .list(uid, { limit: 100 });
      if (listErr || !files || files.length === 0) break;
      const paths = files
        .filter((f) => f.name && f.name !== ".emptyFolderPlaceholder")
        .map((f) => `${uid}/${f.name}`);
      if (paths.length === 0) break;
      const { error: rmErr } = await admin.storage.from("avatars").remove(paths);
      if (rmErr) {
        console.error("[delete-account] Non-fatal storage remove error:", rmErr.message);
        break;
      }
      if (files.length < 100) break;
    }
  } catch (err) {
    console.error("[delete-account] Non-fatal storage cleanup exception:", err);
  }

  // 5. Delete the auth user (FKs use ON DELETE SET NULL for teams/matches).
  const { error: deleteError } = await admin.auth.admin.deleteUser(uid);
  if (deleteError) {
    console.error("[delete-account] auth.admin.deleteUser failed:", deleteError.message);
    return new Response(
      JSON.stringify({ error: "Account deletion failed. Please try again." }),
      { status: 500, headers: JSON_HEADERS },
    );
  }

  return new Response(
    JSON.stringify({ deleted: true }),
    { status: 200, headers: JSON_HEADERS },
  );
});
