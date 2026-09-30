-- Database for BFA Coach Attendance (Supabase project "bfa-coach-attendance").
-- Already applied to the live project; kept here so the setup can be recreated.
--
-- The tables are closed to the public API. The app talks only to the functions
-- below, and every function except pin_is_set/setup_pin checks the team PIN.

create extension if not exists pgcrypto with schema extensions;

create table public.app_settings (
  id int primary key default 1 check (id = 1),
  pin_hash text not null
);

create table public.coaches (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 80),
  archived boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index coaches_name_key on public.coaches (lower(name));

create table public.coach_sessions (
  coach_id uuid not null references public.coaches(id) on delete cascade,
  day date not null,
  sessions int not null check (sessions between 1 and 20),
  updated_at timestamptz not null default now(),
  primary key (coach_id, day)
);
create index coach_sessions_day_idx on public.coach_sessions (day);

-- No direct table access: everything goes through PIN-checked functions below.
alter table public.app_settings enable row level security;
alter table public.coaches enable row level security;
alter table public.coach_sessions enable row level security;
revoke all on public.app_settings, public.coaches, public.coach_sessions from anon, authenticated;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create function private.require_pin(p text) returns void
language plpgsql security definer set search_path = '' as $$
declare h text;
begin
  select pin_hash into h from public.app_settings where id = 1;
  if h is null or p is null or extensions.crypt(p, h) <> h then
    raise exception 'Incorrect PIN' using errcode = '28P01';
  end if;
end $$;

create function public.pin_is_set() returns boolean
language sql security definer set search_path = '' as $$
  select exists (select 1 from public.app_settings where id = 1);
$$;

create function public.setup_pin(new_pin text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if new_pin !~ '^\d{4,8}$' then raise exception 'PIN must be 4 to 8 digits'; end if;
  insert into public.app_settings (id, pin_hash)
  values (1, extensions.crypt(new_pin, extensions.gen_salt('bf')))
  on conflict (id) do nothing;
  if not found then raise exception 'A PIN has already been set'; end if;
end $$;

create function public.change_pin(p text, new_pin text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_pin(p);
  if new_pin !~ '^\d{4,8}$' then raise exception 'PIN must be 4 to 8 digits'; end if;
  update public.app_settings set pin_hash = extensions.crypt(new_pin, extensions.gen_salt('bf')) where id = 1;
end $$;

create function public.check_pin(p text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_pin(p);
  return true;
end $$;

create function public.list_coaches(p text)
returns setof public.coaches
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_pin(p);
  return query select * from public.coaches order by lower(name);
end $$;

create function public.add_coach(p text, coach_name text)
returns public.coaches
language plpgsql security definer set search_path = '' as $$
declare c public.coaches; n text := regexp_replace(trim(coach_name), '\s+', ' ', 'g');
begin
  perform private.require_pin(p);
  select * into c from public.coaches where lower(name) = lower(n);
  if found then
    if c.archived then
      update public.coaches set archived = false where id = c.id returning * into c;
    end if;
    return c;
  end if;
  insert into public.coaches (name) values (n) returning * into c;
  return c;
end $$;

create function public.rename_coach(p text, coach uuid, new_name text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_pin(p);
  update public.coaches set name = regexp_replace(trim(new_name), '\s+', ' ', 'g') where id = coach;
end $$;

create function public.set_coach_archived(p text, coach uuid, is_archived boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_pin(p);
  update public.coaches set archived = is_archived where id = coach;
end $$;

create function public.set_sessions(p text, coach uuid, on_day date, n int) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_pin(p);
  if n <= 0 then
    delete from public.coach_sessions where coach_id = coach and day = on_day;
  else
    insert into public.coach_sessions (coach_id, day, sessions) values (coach, on_day, least(n, 20))
    on conflict (coach_id, day) do update set sessions = excluded.sessions, updated_at = now();
  end if;
end $$;

create function public.sessions_between(p text, from_day date, to_day date)
returns table (coach_id uuid, day date, sessions int)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_pin(p);
  return query select s.coach_id, s.day, s.sessions from public.coach_sessions s
    where s.day between from_day and to_day order by s.day;
end $$;

revoke execute on all functions in schema public from public;
revoke execute on function private.require_pin(text) from public;
grant execute on function public.pin_is_set(), public.setup_pin(text), public.change_pin(text, text),
  public.check_pin(text), public.list_coaches(text), public.add_coach(text, text),
  public.rename_coach(text, uuid, text), public.set_coach_archived(text, uuid, boolean),
  public.set_sessions(text, uuid, date, int), public.sessions_between(text, date, date)
  to anon, authenticated;
