-- 가족모아 DB 스키마 + 보안 정책 (Supabase SQL Editor에 전체 붙여넣고 Run)
-- 재실행해도 안전하도록 기존 객체를 먼저 정리합니다.

drop policy if exists "photos_storage_delete" on storage.objects;
drop policy if exists "photos_storage_select" on storage.objects;
drop policy if exists "photos_storage_insert" on storage.objects;

drop function if exists public.unlock_event(uuid, text);
drop function if exists public.list_events(uuid);
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user();
drop function if exists public.current_family_id();

drop table if exists public.notifications cascade;
drop table if exists public.photos cascade;
drop table if exists public.albums cascade;
drop table if exists public.events cascade;
drop table if exists public.profiles cascade;
drop table if exists public.families cascade;

create extension if not exists pgcrypto;

-- ---------- tables ----------
create table public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text not null unique,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text not null,
  family_id uuid references public.families(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  title text not null,
  date date not null,
  "time" text not null,
  location text,
  participants text[] not null default '{}',
  prep text,
  password text,
  author_id uuid not null references auth.users(id),
  author_name text not null,
  created_at timestamptz not null default now()
);

create table public.albums (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table public.photos (
  id uuid primary key default gen_random_uuid(),
  album_id uuid not null references public.albums(id) on delete cascade,
  family_id uuid not null references public.families(id) on delete cascade,
  storage_path text not null,
  caption text,
  uploader_id uuid not null references auth.users(id),
  uploader_name text not null,
  date date not null,
  created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  type text not null,
  message text not null,
  created_at timestamptz not null default now()
);

-- ---------- helper: current user's family ----------
create or replace function public.current_family_id()
returns uuid
language sql stable security definer set search_path = public
as $$
  select family_id from public.profiles where id = auth.uid()
$$;

-- ---------- auto-create profile on signup ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)), new.email);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- row level security ----------
alter table public.profiles enable row level security;
alter table public.families enable row level security;
alter table public.events enable row level security;
alter table public.albums enable row level security;
alter table public.photos enable row level security;
alter table public.notifications enable row level security;

create policy "profiles_select" on public.profiles
  for select using (id = auth.uid() or family_id = public.current_family_id());
create policy "profiles_update_self" on public.profiles
  for update using (id = auth.uid());

create policy "families_select" on public.families
  for select using (auth.role() = 'authenticated');
create policy "families_insert" on public.families
  for insert with check (auth.uid() = created_by);
create policy "families_update_members" on public.families
  for update using (id = public.current_family_id());

-- events: insert allowed to any family member; select/update/delete restricted to the
-- author's own rows only. Non-owners never read events directly (no general select
-- policy) — they must go through list_events()/unlock_event(), which are the only
-- paths that decide whether to reveal password-protected fields.
create policy "events_insert_family" on public.events
  for insert with check (family_id = public.current_family_id());
create policy "events_select_own" on public.events
  for select using (author_id = auth.uid());
create policy "events_update_own" on public.events
  for update using (author_id = auth.uid() and family_id = public.current_family_id())
  with check (author_id = auth.uid() and family_id = public.current_family_id());
create policy "events_delete_own" on public.events
  for delete using (author_id = auth.uid() and family_id = public.current_family_id());

create policy "albums_family_all" on public.albums
  for all using (family_id = public.current_family_id())
  with check (family_id = public.current_family_id());

create policy "photos_family_all" on public.photos
  for all using (family_id = public.current_family_id())
  with check (family_id = public.current_family_id());

create policy "notifications_family_all" on public.notifications
  for all using (family_id = public.current_family_id())
  with check (family_id = public.current_family_id());

-- ---------- password-protected event access (server-side check, password never sent to client) ----------
create or replace function public.list_events(_family_id uuid)
returns table(
  id uuid, family_id uuid, date date, "time" text, is_locked boolean,
  title text, location text, participants text[], prep text,
  author_id uuid, author_name text, created_at timestamptz
)
language sql stable security definer set search_path = public
as $$
  select e.id, e.family_id, e.date, e."time", (e.password is not null and e.password <> ''),
    case when e.password is not null and e.password <> '' and e.author_id <> auth.uid() then null else e.title end,
    case when e.password is not null and e.password <> '' and e.author_id <> auth.uid() then null else e.location end,
    case when e.password is not null and e.password <> '' and e.author_id <> auth.uid() then null else e.participants end,
    case when e.password is not null and e.password <> '' and e.author_id <> auth.uid() then null else e.prep end,
    e.author_id, e.author_name, e.created_at
  from public.events e
  where e.family_id = _family_id and e.family_id = public.current_family_id()
$$;

create or replace function public.unlock_event(_event_id uuid, _password text)
returns table(
  id uuid, title text, location text, participants text[], prep text
)
language sql stable security definer set search_path = public
as $$
  select e.id, e.title, e.location, e.participants, e.prep
  from public.events e
  where e.id = _event_id
    and e.family_id = public.current_family_id()
    and e.password = _password
$$;

-- ---------- storage: family photo bucket ----------
insert into storage.buckets (id, name, public)
values ('photos', 'photos', false)
on conflict (id) do nothing;

create policy "photos_storage_insert" on storage.objects
  for insert with check (
    bucket_id = 'photos' and (storage.foldername(name))[1] = public.current_family_id()::text
  );
create policy "photos_storage_select" on storage.objects
  for select using (
    bucket_id = 'photos' and (storage.foldername(name))[1] = public.current_family_id()::text
  );
create policy "photos_storage_delete" on storage.objects
  for delete using (
    bucket_id = 'photos' and (storage.foldername(name))[1] = public.current_family_id()::text
  );
