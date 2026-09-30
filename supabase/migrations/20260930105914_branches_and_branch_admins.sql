-- Branches, branch PINs and branch-scoped coaches, sessions and approvals.
-- Already applied to the live project (version 20260930105914).

-- ===== Safety copy of the data before reorganising it by branch =====
create schema if not exists backup_20260930;
revoke all on schema backup_20260930 from public, anon, authenticated;
create table backup_20260930.coaches as table public.coaches;
create table backup_20260930.coach_sessions as table public.coach_sessions;
create table backup_20260930.coach_approvals as table public.coach_approvals;

-- ===== Branches =====
create table public.branches (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 60),
  pin_hash text,
  sort int not null default 0,
  created_at timestamptz not null default now()
);
create unique index branches_name_key on public.branches (lower(name));
insert into public.branches (name, sort) values
  ('Furn El Chebbek', 1), ('Hazmieh', 2), ('Sin El Fil', 3), ('Mansourieh', 4), ('Beit Meri', 5), ('Hadath', 6);

-- Which coaches belong to which branch. active = false means removed from that branch's list (history kept).
create table public.coach_branches (
  coach_id uuid not null references public.coaches(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  active boolean not null default true,
  added_at timestamptz not null default now(),
  primary key (coach_id, branch_id)
);

-- Sessions and approvals now belong to a branch. Existing rows stay unassigned (null) until the
-- coach is given a branch, then they move to that first branch.
alter table public.coach_sessions add column branch_id uuid references public.branches(id);
alter table public.coach_sessions drop constraint coach_sessions_pkey;
create unique index coach_sessions_key on public.coach_sessions (coach_id, day, role, branch_id) nulls not distinct;
create index coach_sessions_branch_day_idx on public.coach_sessions (branch_id, day);

alter table public.coach_approvals add column branch_id uuid references public.branches(id);
alter table public.coach_approvals drop constraint coach_approvals_pkey;
create unique index coach_approvals_key on public.coach_approvals (coach_id, month, branch_id) nulls not distinct;

alter table public.branches enable row level security;
alter table public.coach_branches enable row level security;
revoke all on public.branches, public.coach_branches from anon, authenticated;

-- ===== Who is calling =====
-- The main admin PIN (app_settings) sees every branch; a branch PIN sees only its branch.
create function private.auth(p text, out is_admin boolean, out branch uuid)
language plpgsql security definer set search_path = '' as $$
declare h text; b record;
begin
  if p is null or p = '' then raise exception 'Incorrect PIN' using errcode = '28P01'; end if;
  select pin_hash into h from public.app_settings where id = 1;
  if h is not null and extensions.crypt(p, h) = h then is_admin := true; branch := null; return; end if;
  for b in select id, pin_hash from public.branches where pin_hash is not null loop
    if extensions.crypt(p, b.pin_hash) = b.pin_hash then is_admin := false; branch := b.id; return; end if;
  end loop;
  raise exception 'Incorrect PIN' using errcode = '28P01';
end $$;

-- The branch a call acts on: the admin may pass any branch or null (= all branches);
-- a branch admin always acts on their own branch and may not name another one.
create function private.scope(p text, in_branch uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare a record;
begin
  select * into a from private.auth(p);
  if a.is_admin then return in_branch; end if;
  if in_branch is not null and in_branch <> a.branch then
    raise exception 'This PIN only has access to its own branch' using errcode = '42501';
  end if;
  return a.branch;
end $$;

create function private.require_branch(p text, in_branch uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare s uuid := private.scope(p, in_branch);
begin
  if s is null then raise exception 'Choose a branch first' using errcode = 'BFA02'; end if;
  return s;
end $$;

create function private.require_admin(p text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not (select is_admin from private.auth(p)) then
    raise exception 'Only the main admin can do this' using errcode = '42501';
  end if;
end $$;

create function private.pin_in_use(new_pin text, except_branch uuid) returns boolean
language sql security definer set search_path = '' as $$
  select exists (select 1 from public.app_settings s where except_branch is not null and extensions.crypt(new_pin, s.pin_hash) = s.pin_hash)
      or exists (select 1 from public.branches b where b.pin_hash is not null
                   and b.id is distinct from except_branch and extensions.crypt(new_pin, b.pin_hash) = b.pin_hash);
$$;

-- Give a coach a branch; their unassigned history moves to it.
create function private.join_branch(coach uuid, br uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.coach_branches (coach_id, branch_id, active) values (coach, br, true)
  on conflict (coach_id, branch_id) do update set active = true;
  update public.coaches set archived = false where id = coach and archived;
  update public.coach_sessions set branch_id = br where coach_id = coach and branch_id is null;
  update public.coach_approvals set branch_id = br where coach_id = coach and branch_id is null;
end $$;

revoke all on all functions in schema private from public;

-- ===== Replace the old single-team functions =====
drop function if exists public.set_sessions(text, uuid, date, int, text);
drop function if exists public.set_role_sessions(text, uuid, date, text, int);
drop function if exists public.sessions_between(text, date, date);
drop function if exists public.list_coaches(text);
drop function if exists public.add_coach(text, text);
drop function if exists public.rename_coach(text, uuid, text);
drop function if exists public.set_coach_archived(text, uuid, boolean);
drop function if exists public.approve_month(text, uuid, date);
drop function if exists public.reopen_month(text, uuid, date);
drop function if exists public.approvals_for(text, date);

create or replace function public.check_pin(p text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin perform private.auth(p); return true; end $$;

create function public.whoami(p text)
returns table (is_admin boolean, branch_id uuid, branch_name text)
language plpgsql security definer set search_path = '' as $$
declare a record;
begin
  select * into a from private.auth(p);
  return query select a.is_admin, a.branch, (select b.name from public.branches b where b.id = a.branch);
end $$;

create function public.list_branches(p text)
returns table (id uuid, name text, sort int, has_pin boolean)
language plpgsql security definer set search_path = '' as $$
declare a record;
begin
  select * into a from private.auth(p);
  return query select b.id, b.name, b.sort, b.pin_hash is not null from public.branches b
    where a.is_admin or b.id = a.branch order by b.sort, lower(b.name);
end $$;

create function public.add_branch(p text, branch_name text)
returns table (id uuid, name text)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_admin(p);
  return query insert into public.branches (name, sort)
    values (regexp_replace(trim(branch_name), '\s+', ' ', 'g'), coalesce((select max(b.sort) from public.branches b), 0) + 1)
    returning branches.id, branches.name;
end $$;

create function public.rename_branch(p text, branch uuid, new_name text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_admin(p);
  update public.branches set name = regexp_replace(trim(new_name), '\s+', ' ', 'g') where id = branch;
end $$;

create function public.set_branch_pin(p text, branch uuid, new_pin text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_admin(p);
  if new_pin !~ '^\d{4,8}$' then raise exception 'PIN must be 4 to 8 digits'; end if;
  if private.pin_in_use(new_pin, branch) then raise exception 'That PIN is already used by another branch or the main admin'; end if;
  update public.branches set pin_hash = extensions.crypt(new_pin, extensions.gen_salt('bf')) where id = branch;
end $$;

create or replace function public.change_pin(p text, new_pin text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_admin(p);
  if new_pin !~ '^\d{4,8}$' then raise exception 'PIN must be 4 to 8 digits'; end if;
  if exists (select 1 from public.branches b where b.pin_hash is not null and extensions.crypt(new_pin, b.pin_hash) = b.pin_hash) then
    raise exception 'That PIN is already used by a branch';
  end if;
  update public.app_settings set pin_hash = extensions.crypt(new_pin, extensions.gen_salt('bf')) where id = 1;
end $$;

-- Coaches for one branch (members, including removed ones), or for the admin with no branch, everyone.
create function public.list_coaches(p text, in_branch uuid)
returns table (id uuid, name text, archived boolean, member_of uuid[], removed_from uuid[])
language plpgsql security definer set search_path = '' as $$
declare s uuid := private.scope(p, in_branch);
begin
  return query
  select c.id, c.name, c.archived,
         coalesce(array_agg(cb.branch_id) filter (where cb.active and (s is null or cb.branch_id = s)), '{}'),
         coalesce(array_agg(cb.branch_id) filter (where not cb.active and (s is null or cb.branch_id = s)), '{}')
  from public.coaches c
  left join public.coach_branches cb on cb.coach_id = c.id
  group by c.id
  having s is null or bool_or(cb.branch_id = s)
  order by lower(c.name);
end $$;

-- Add a coach to a branch by name. The same name anywhere in the academy is the same person.
create function public.add_coach(p text, in_branch uuid, coach_name text)
returns table (id uuid, name text)
language plpgsql security definer set search_path = '' as $$
declare s uuid := private.require_branch(p, in_branch); c public.coaches;
        n text := regexp_replace(trim(coach_name), '\s+', ' ', 'g');
begin
  select * into c from public.coaches x where lower(x.name) = lower(n);
  if not found then insert into public.coaches (name) values (n) returning * into c; end if;
  perform private.join_branch(c.id, s);
  return query select c.id, c.name;
end $$;

create function public.set_coach_branch(p text, coach uuid, in_branch uuid, is_member boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare s uuid := private.require_branch(p, in_branch);
begin
  if is_member then perform private.join_branch(coach, s);
  else update public.coach_branches set active = false where coach_id = coach and branch_id = s;
  end if;
end $$;

-- Admin only: hide or show a coach who has no branch (old removed coaches).
create function public.set_coach_archived(p text, coach uuid, is_archived boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_admin(p);
  update public.coaches set archived = is_archived where id = coach;
end $$;

create function public.rename_coach(p text, coach uuid, new_name text) returns void
language plpgsql security definer set search_path = '' as $$
declare a record;
begin
  select * into a from private.auth(p);
  if not a.is_admin and not exists (select 1 from public.coach_branches where coach_id = coach and branch_id = a.branch) then
    raise exception 'This coach is not in your branch' using errcode = '42501';
  end if;
  update public.coaches set name = regexp_replace(trim(new_name), '\s+', ' ', 'g') where id = coach;
end $$;

create function private.check_open(coach uuid, br uuid, on_day date) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.coach_branches where coach_id = coach and branch_id = br) then
    raise exception 'This coach is not in this branch' using errcode = '42501';
  end if;
  if exists (select 1 from public.coach_approvals a where a.coach_id = coach and a.branch_id = br
             and a.month = date_trunc('month', on_day)::date) then
    raise exception 'This coach''s sessions for this month are approved and locked' using errcode = 'BFA01';
  end if;
end $$;
revoke all on function private.check_open(uuid, uuid, date) from public;

create function public.set_role_sessions(p text, in_branch uuid, coach uuid, on_day date, in_role text, n int) returns void
language plpgsql security definer set search_path = '' as $$
declare s uuid := private.require_branch(p, in_branch);
begin
  if in_role not in ('coach', 'assistant') then raise exception 'Role must be coach or assistant'; end if;
  perform private.check_open(coach, s, on_day);
  if n <= 0 then
    delete from public.coach_sessions where coach_id = coach and day = on_day and role = in_role and branch_id = s;
  else
    insert into public.coach_sessions (coach_id, day, role, sessions, branch_id) values (coach, on_day, in_role, least(n, 20), s)
    on conflict (coach_id, day, role, branch_id) do update set sessions = excluded.sessions, updated_at = now();
  end if;
end $$;

create function public.clear_person_day(p text, in_branch uuid, coach uuid, on_day date) returns void
language plpgsql security definer set search_path = '' as $$
declare s uuid := private.require_branch(p, in_branch);
begin
  perform private.check_open(coach, s, on_day);
  delete from public.coach_sessions where coach_id = coach and day = on_day and branch_id = s;
end $$;

create function public.sessions_between(p text, in_branch uuid, from_day date, to_day date)
returns table (coach_id uuid, day date, sessions int, role text, branch_id uuid)
language plpgsql security definer set search_path = '' as $$
declare s uuid := private.scope(p, in_branch);
begin
  return query select x.coach_id, x.day, x.sessions, x.role, x.branch_id from public.coach_sessions x
    where x.day between from_day and to_day and (s is null or x.branch_id = s) order by x.day;
end $$;

create function public.approvals_for(p text, in_branch uuid, in_month date)
returns setof public.coach_approvals
language plpgsql security definer set search_path = '' as $$
declare s uuid := private.scope(p, in_branch);
begin
  return query select * from public.coach_approvals a
    where a.month = date_trunc('month', in_month)::date and (s is null or a.branch_id = s);
end $$;

-- Approve a coach (or everyone, coach = null) for a month in one branch; the admin may pass
-- branch = null to approve across all branches. Only coach-branch pairs with sessions are approved.
create function public.approve_month(p text, in_branch uuid, coach uuid, in_month date)
returns setof public.coach_approvals
language plpgsql security definer set search_path = '' as $$
declare s uuid := private.scope(p, in_branch); m date := date_trunc('month', in_month)::date;
begin
  return query
  insert into public.coach_approvals (coach_id, month, branch_id, sessions, days, coach_sessions, assistant_sessions)
  select x.coach_id, m, x.branch_id,
         sum(x.sessions)::int,
         count(distinct x.day)::int,
         coalesce(sum(x.sessions) filter (where x.role = 'coach'), 0)::int,
         coalesce(sum(x.sessions) filter (where x.role = 'assistant'), 0)::int
  from public.coach_sessions x
  where x.day >= m and x.day < (m + interval '1 month')::date
    and x.branch_id is not null and (s is null or x.branch_id = s)
    and (coach is null or x.coach_id = coach)
  group by x.coach_id, x.branch_id
  on conflict (coach_id, month, branch_id) do nothing
  returning *;
end $$;

create function public.reopen_month(p text, in_branch uuid, coach uuid, in_month date) returns void
language plpgsql security definer set search_path = '' as $$
declare s uuid := private.require_branch(p, in_branch);
begin
  delete from public.coach_approvals
  where coach_id = coach and branch_id = s and month = date_trunc('month', in_month)::date;
end $$;

revoke execute on all functions in schema public from public;
grant execute on function
  public.pin_is_set(), public.setup_pin(text), public.check_pin(text), public.whoami(text), public.change_pin(text, text),
  public.list_branches(text), public.add_branch(text, text), public.rename_branch(text, uuid, text), public.set_branch_pin(text, uuid, text),
  public.list_coaches(text, uuid), public.add_coach(text, uuid, text), public.set_coach_branch(text, uuid, uuid, boolean),
  public.set_coach_archived(text, uuid, boolean), public.rename_coach(text, uuid, text),
  public.set_role_sessions(text, uuid, uuid, date, text, int), public.clear_person_day(text, uuid, uuid, date),
  public.sessions_between(text, uuid, date, date), public.approvals_for(text, uuid, date),
  public.approve_month(text, uuid, uuid, date), public.reopen_month(text, uuid, uuid, date)
  to anon, authenticated;
