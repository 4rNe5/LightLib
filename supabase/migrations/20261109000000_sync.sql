-- LightLib sync: the owner's books (EPUB files in Storage), reading
-- positions and saved translations, shared by the Android app and the web.
--
-- Only accounts listed in public.owners can read or write anything; the
-- list is filled from the SQL editor, never from the app:
--   insert into public.owners (email) values ('<owner email>');

-- ---------------------------------------------------------------------------
-- Owners
-- ---------------------------------------------------------------------------

create table public.owners (
  email text primary key
);
alter table public.owners enable row level security;
-- No policies: clients can neither read nor change the list.

create or replace function public.is_owner()
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
revoke all on function public.is_owner() from public, anon;
grant execute on function public.is_owner() to authenticated;

-- ---------------------------------------------------------------------------
-- Books: one row per file, keyed by the file's MD5 (the same on every
-- device). The file itself is books/<user id>/<md5>.<format> in Storage.
-- ---------------------------------------------------------------------------

create table public.books (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  md5 text not null check (md5 ~ '^[0-9a-f]{32}$'),
  book_id text not null,
  file_name text not null,
  title text not null default '',
  author text,
  format text not null default 'epub',
  size_bytes bigint,
  has_file boolean not null default false,
  added_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, md5)
);
alter table public.books enable row level security;
create policy books_owner on public.books
  for all to authenticated
  using (user_id = (select auth.uid()) and (select public.is_owner()))
  with check (user_id = (select auth.uid()) and (select public.is_owner()));

-- ---------------------------------------------------------------------------
-- Reading positions: the latest one wins (by the device's clock).
-- ---------------------------------------------------------------------------

create table public.progress (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  md5 text not null check (md5 ~ '^[0-9a-f]{32}$'),
  position text not null,
  completed boolean not null default false,
  device text,
  updated_at timestamptz not null,
  primary key (user_id, md5)
);
alter table public.progress enable row level security;
create policy progress_owner on public.progress
  for all to authenticated
  using (user_id = (select auth.uid()) and (select public.is_owner()))
  with check (user_id = (select auth.uid()) and (select public.is_owner()));

-- Keeps a position only when it is newer than the one saved.
create or replace function public.put_progress(
  p_md5 text,
  p_position text,
  p_completed boolean,
  p_device text,
  p_updated_at timestamptz
)
returns void
language sql
security invoker
set search_path = ''
as $$
  insert into public.progress (md5, position, completed, device, updated_at)
  values (p_md5, p_position, p_completed, p_device, p_updated_at)
  on conflict (user_id, md5) do update
    set position = excluded.position,
        completed = excluded.completed,
        device = excluded.device,
        updated_at = excluded.updated_at
    where public.progress.updated_at < excluded.updated_at;
$$;
revoke all on function public.put_progress(text, text, boolean, text, timestamptz) from public, anon;
grant execute on function public.put_progress(text, text, boolean, text, timestamptz) to authenticated;

-- ---------------------------------------------------------------------------
-- Translations: one map per book x language x style, source-text hash ->
-- translation (the app's TranslationCache). Merged by union, so two
-- devices translating the same book never lose each other's work.
-- ---------------------------------------------------------------------------

create table public.translations (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  md5 text not null check (md5 ~ '^[0-9a-f]{32}$'),
  lang text not null,
  style text not null check (style in ('shared', 'shared+plain')),
  entries jsonb not null default '{}'::jsonb,
  entry_count integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, md5, lang, style)
);
alter table public.translations enable row level security;
create policy translations_owner on public.translations
  for all to authenticated
  using (user_id = (select auth.uid()) and (select public.is_owner()))
  with check (user_id = (select auth.uid()) and (select public.is_owner()));

-- Adds p_delta to the saved map; returns the new size and time.
create or replace function public.merge_translations(
  p_md5 text,
  p_lang text,
  p_style text,
  p_delta jsonb
)
returns table (entry_count integer, updated_at timestamptz)
language sql
security invoker
set search_path = ''
as $$
  insert into public.translations as t (md5, lang, style, entries, entry_count)
  values (
    p_md5, p_lang, p_style, p_delta,
    (select count(*)::integer from jsonb_object_keys(p_delta))
  )
  on conflict (user_id, md5, lang, style) do update
    set entries = t.entries || excluded.entries,
        entry_count = (select count(*)::integer
                       from jsonb_object_keys(t.entries || excluded.entries)),
        updated_at = now()
  returning t.entry_count, t.updated_at;
$$;
revoke all on function public.merge_translations(text, text, text, jsonb) from public, anon;
grant execute on function public.merge_translations(text, text, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Storage: books/<user id>/<md5>.<format>, private.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('books', 'books', false, 52428800,
        array['application/epub+zip', 'application/octet-stream'])
on conflict (id) do nothing;

create policy books_files_owner on storage.objects
  for all to authenticated
  using (
    bucket_id = 'books'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.is_owner())
  )
  with check (
    bucket_id = 'books'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.is_owner())
  );
