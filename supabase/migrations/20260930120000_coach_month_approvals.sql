-- Monthly approval per coach. An approved coach-month is locked: set_sessions refuses changes
-- (SQLSTATE BFA01) until it is reopened. The totals at approval time are stored with it.
-- Already applied to the live project.

create table public.coach_approvals (
  coach_id uuid not null references public.coaches(id) on delete cascade,
  month date not null check (extract(day from month) = 1),
  sessions int not null,
  days int not null,
  approved_at timestamptz not null default now(),
  primary key (coach_id, month)
);
alter table public.coach_approvals enable row level security;
revoke all on public.coach_approvals from anon, authenticated;

create or replace function public.set_sessions(p text, coach uuid, on_day date, n int) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_pin(p);
  if exists (select 1 from public.coach_approvals a
             where a.coach_id = coach and a.month = date_trunc('month', on_day)::date) then
    raise exception 'This coach''s sessions for this month are approved and locked' using errcode = 'BFA01';
  end if;
  if n <= 0 then
    delete from public.coach_sessions where coach_id = coach and day = on_day;
  else
    insert into public.coach_sessions (coach_id, day, sessions) values (coach, on_day, least(n, 20))
    on conflict (coach_id, day) do update set sessions = excluded.sessions, updated_at = now();
  end if;
end $$;

-- Approve one coach for a month, or (coach = null) every coach with sessions that month.
create function public.approve_month(p text, coach uuid, in_month date)
returns setof public.coach_approvals
language plpgsql security definer set search_path = '' as $$
declare m date := date_trunc('month', in_month)::date;
begin
  perform private.require_pin(p);
  return query
  insert into public.coach_approvals (coach_id, month, sessions, days)
  select c.id, m, coalesce(sum(s.sessions), 0)::int, count(s.day)::int
  from public.coaches c
  left join public.coach_sessions s
    on s.coach_id = c.id and s.day >= m and s.day < (m + interval '1 month')::date
  where (coach is null or c.id = coach)
  group by c.id
  having coach is not null or count(s.day) > 0
  on conflict (coach_id, month) do nothing
  returning *;
end $$;

create function public.reopen_month(p text, coach uuid, in_month date) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_pin(p);
  delete from public.coach_approvals
  where coach_id = coach and month = date_trunc('month', in_month)::date;
end $$;

create function public.approvals_for(p text, in_month date)
returns setof public.coach_approvals
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_pin(p);
  return query select * from public.coach_approvals
  where month = date_trunc('month', in_month)::date;
end $$;

revoke execute on function public.approve_month(text, uuid, date), public.reopen_month(text, uuid, date),
  public.approvals_for(text, date) from public;
grant execute on function public.set_sessions(text, uuid, date, int), public.approve_month(text, uuid, date),
  public.reopen_month(text, uuid, date), public.approvals_for(text, date) to anon, authenticated;
