drop policy if exists profiles_read_workspace_members on public.profiles;
create policy profiles_read_workspace_members on public.profiles for select to authenticated using (
 exists(select 1 from public.memberships own join public.memberships peer on peer.organization_id=own.organization_id where own.user_id=(select auth.uid()) and own.role in ('owner','admin','manager','dispatcher') and peer.user_id=profiles.id)
);
