-- The owner check runs with definer rights, so it lives in a schema the
-- API does not expose (it was callable as /rest/v1/rpc/is_owner).

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.is_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.owners o
    where o.email = (auth.jwt() ->> 'email')
  );
$$;
revoke all on function private.is_owner() from public, anon;
grant execute on function private.is_owner() to authenticated;

alter policy books_owner on public.books
  using (user_id = (select auth.uid()) and (select private.is_owner()))
  with check (user_id = (select auth.uid()) and (select private.is_owner()));
alter policy progress_owner on public.progress
  using (user_id = (select auth.uid()) and (select private.is_owner()))
  with check (user_id = (select auth.uid()) and (select private.is_owner()));
alter policy translations_owner on public.translations
  using (user_id = (select auth.uid()) and (select private.is_owner()))
  with check (user_id = (select auth.uid()) and (select private.is_owner()));
alter policy books_files_owner on storage.objects
  using (
    bucket_id = 'books'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select private.is_owner())
  )
  with check (
    bucket_id = 'books'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select private.is_owner())
  );

drop function public.is_owner();
