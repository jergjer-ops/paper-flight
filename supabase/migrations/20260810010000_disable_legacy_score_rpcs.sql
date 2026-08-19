-- Phase 2: run only after the web client has switched to the v2 session API.
-- Keep the function definitions for emergency rollback, but remove all client access.

revoke all on function public.submit_score(text, integer)
  from public, anon, authenticated;

revoke all on function public.sync_player(text, integer, integer)
  from public, anon, authenticated;
