-- Each day's attendance is recorded as 'coach' or 'assistant'. Approvals also store the split.
-- Already applied to the live project.

alter table public.coach_sessions
  add column role text not null default 'coach' check (role in ('coach', 'assistant'));

alter table public.coach_approvals
  add column coach_sessions int not null default 0,
  add column assistant_sessions int not null default 0;
update public.coach_approvals set coach_sessions = sessions;

-- set_sessions gains an optional role. Left null, a new entry is 'coach' and an existing entry keeps its role.
drop function public.set_sessions(text, uuid, date, int);
create function public.set_sessions(p text, coach uuid, on_day date, n int, in_role text default null) returns void
language plpgsql security definer set search_path = '' as $$
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
  else
    insert into public.coach_sessions (coach_id, day, sessions, role)
    values (coach, on_day, least(n, 20), coalesce(in_role, 'coach'))
    on conflict (coach_id, day) do update
      set sessions = excluded.sessions,
          role = coalesce(in_role, public.coach_sessions.role),
          updated_at = now();
  end if;
end $$;

drop function public.sessions_between(text, date, date);
create function public.sessions_between(p text, from_day date, to_day date)
returns table (coach_id uuid, day date, sessions int, role text)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_pin(p);
  return query select s.coach_id, s.day, s.sessions, s.role from public.coach_sessions s
    where s.day between from_day and to_day order by s.day;
end $$;

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
         count(s.day)::int,
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

revoke execute on function public.set_sessions(text, uuid, date, int, text), public.sessions_between(text, date, date) from public;
grant execute on function public.set_sessions(text, uuid, date, int, text), public.sessions_between(text, date, date),
  public.approve_month(text, uuid, date) to anon, authenticated;
