-- One row per person, day and role, so a person can be coach and assistant on the same day.
-- Already applied to the live project.
alter table public.coach_sessions drop constraint coach_sessions_pkey;
alter table public.coach_sessions add primary key (coach_id, day, role);

-- Set the number of sessions for exactly one role on one day (0 removes that role for the day).
create function public.set_role_sessions(p text, coach uuid, on_day date, in_role text, n int) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_pin(p);
  if in_role not in ('coach', 'assistant') then raise exception 'Role must be coach or assistant'; end if;
  if exists (select 1 from public.coach_approvals a
             where a.coach_id = coach and a.month = date_trunc('month', on_day)::date) then
    raise exception 'This coach''s sessions for this month are approved and locked' using errcode = 'BFA01';
  end if;
  if n <= 0 then
    delete from public.coach_sessions where coach_id = coach and day = on_day and role = in_role;
  else
    insert into public.coach_sessions (coach_id, day, role, sessions) values (coach, on_day, in_role, least(n, 20))
    on conflict (coach_id, day, role) do update set sessions = excluded.sessions, updated_at = now();
  end if;
end $$;

-- set_sessions keeps its meaning of "this person's single entry for the day" for older app versions.
-- n = 0 clears the whole day for the person (both roles); the app uses it for unticking.
create or replace function public.set_sessions(p text, coach uuid, on_day date, n int, in_role text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare r text;
begin
  perform private.require_pin(p);
  if in_role is not null and in_role not in ('coach', 'assistant') then
    raise exception 'Role must be coach or assistant';
  end if;
  if exists (select 1 from public.coach_approvals a
             where a.coach_id = coach and a.month = date_trunc('month', on_day)::date) then
    raise exception 'This coach''s sessions for this month are approved and locked' using errcode = 'BFA01';
  end if;
  if n <= 0 then
    delete from public.coach_sessions where coach_id = coach and day = on_day;
    return;
  end if;
  select coalesce(in_role, (select s.role from public.coach_sessions s
                            where s.coach_id = coach and s.day = on_day order by s.role desc limit 1), 'coach')
    into r;
  delete from public.coach_sessions where coach_id = coach and day = on_day and role <> r;
  insert into public.coach_sessions (coach_id, day, role, sessions) values (coach, on_day, r, least(n, 20))
  on conflict (coach_id, day, role) do update set sessions = excluded.sessions, updated_at = now();
end $$;

-- Days are counted as distinct days, not rows.
create or replace function public.approve_month(p text, coach uuid, in_month date)
returns setof public.coach_approvals
language plpgsql security definer set search_path = '' as $$
declare m date := date_trunc('month', in_month)::date;
begin
  perform private.require_pin(p);
  return query
  insert into public.coach_approvals (coach_id, month, sessions, days, coach_sessions, assistant_sessions)
  select c.id, m,
         coalesce(sum(s.sessions), 0)::int,
         count(distinct s.day)::int,
         coalesce(sum(s.sessions) filter (where s.role = 'coach'), 0)::int,
         coalesce(sum(s.sessions) filter (where s.role = 'assistant'), 0)::int
  from public.coaches c
  left join public.coach_sessions s
    on s.coach_id = c.id and s.day >= m and s.day < (m + interval '1 month')::date
  where (coach is null or c.id = coach)
  group by c.id
  having coach is not null or count(s.day) > 0
  on conflict (coach_id, month) do nothing
  returning *;
end $$;

revoke execute on function public.set_role_sessions(text, uuid, date, text, int) from public;
grant execute on function public.set_role_sessions(text, uuid, date, text, int) to anon, authenticated;
