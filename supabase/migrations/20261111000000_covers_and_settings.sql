-- The web lists the library without downloading a single book: each
-- book's card (cover thumbnail, publisher, description) is kept beside
-- its row, and the file comes only when the book is opened there.
--
-- The cover is books/<user id>/<md5>.cover.jpg (a small JPEG the device
-- that has the book makes); cover_at says when it was put, null = none.

alter table public.books
  add column if not exists publisher text,
  add column if not exists description text,
  add column if not exists cover_at timestamptz;

update storage.buckets
   set allowed_mime_types =
       array['application/epub+zip', 'application/octet-stream', 'image/jpeg']
 where id = 'books';

-- ---------------------------------------------------------------------------
-- Settings the owner's devices share (the Gemini API key first): one row
-- per name, the newest one wins by the clock of the device that saved it.
-- An empty value is a removal the other devices follow.
-- ---------------------------------------------------------------------------

create table public.settings (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (name ~ '^[a-z0-9_]{1,64}$'),
  value text not null check (length(value) <= 4096),
  device text,
  updated_at timestamptz not null,
  primary key (user_id, name)
);
alter table public.settings enable row level security;
create policy settings_owner on public.settings
  for all to authenticated
  using (user_id = (select auth.uid()) and (select private.is_owner()))
  with check (user_id = (select auth.uid()) and (select private.is_owner()));

-- Keeps a setting only when it is newer than the one saved.
create or replace function public.put_setting(
  p_name text,
  p_value text,
  p_device text,
  p_updated_at timestamptz
)
returns void
language sql
security invoker
set search_path = ''
as $$
  insert into public.settings (name, value, device, updated_at)
  values (p_name, p_value, p_device, p_updated_at)
  on conflict (user_id, name) do update
    set value = excluded.value,
        device = excluded.device,
        updated_at = excluded.updated_at
    where public.settings.updated_at < excluded.updated_at;
$$;
revoke all on function public.put_setting(text, text, text, timestamptz) from public, anon;
grant execute on function public.put_setting(text, text, text, timestamptz) to authenticated;

-- ---------------------------------------------------------------------------
-- How far a book was read (0..1), next to its position, so a library
-- that does not have the file can still show it. Versions of the app that
-- do not send it clear it (their position is newer than the number).
-- ---------------------------------------------------------------------------

alter table public.progress
  add column if not exists fraction real check (fraction >= 0 and fraction <= 1);

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
        updated_at = excluded.updated_at,
        fraction = null
    where public.progress.updated_at < excluded.updated_at;
$$;

create or replace function public.put_reading(
  p_md5 text,
  p_position text,
  p_completed boolean,
  p_fraction real,
  p_device text,
  p_updated_at timestamptz
)
returns void
language sql
security invoker
set search_path = ''
as $$
  insert into public.progress (md5, position, completed, fraction, device, updated_at)
  values (p_md5, p_position, p_completed, p_fraction, p_device, p_updated_at)
  on conflict (user_id, md5) do update
    set position = excluded.position,
        completed = excluded.completed,
        fraction = excluded.fraction,
        device = excluded.device,
        updated_at = excluded.updated_at
    where public.progress.updated_at < excluded.updated_at;
$$;
revoke all on function public.put_reading(text, text, boolean, real, text, timestamptz) from public, anon;
grant execute on function public.put_reading(text, text, boolean, real, text, timestamptz) to authenticated;
