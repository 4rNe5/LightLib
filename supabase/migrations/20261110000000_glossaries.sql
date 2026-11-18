-- Each book's glossary (names, genders, terms - BookGlossary's JSON), so
-- the phone and the web translate a book with the same names. The newest
-- one wins, by the clock of the device that saved it.

create table public.glossaries (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  md5 text not null check (md5 ~ '^[0-9a-f]{32}$'),
  data text not null,
  device text,
  updated_at timestamptz not null,
  primary key (user_id, md5)
);
alter table public.glossaries enable row level security;
create policy glossaries_owner on public.glossaries
  for all to authenticated
  using (user_id = (select auth.uid()) and (select private.is_owner()))
  with check (user_id = (select auth.uid()) and (select private.is_owner()));

-- Keeps a glossary only when it is newer than the one saved.
create or replace function public.put_glossary(
  p_md5 text,
  p_data text,
  p_device text,
  p_updated_at timestamptz
)
returns void
language sql
security invoker
set search_path = ''
as $$
  insert into public.glossaries (md5, data, device, updated_at)
  values (p_md5, p_data, p_device, p_updated_at)
  on conflict (user_id, md5) do update
    set data = excluded.data,
        device = excluded.device,
        updated_at = excluded.updated_at
    where public.glossaries.updated_at < excluded.updated_at;
$$;
revoke all on function public.put_glossary(text, text, text, timestamptz) from public, anon;
grant execute on function public.put_glossary(text, text, text, timestamptz) to authenticated;
