-- Morning Wave: initial schema.
-- Rule for every table: a signed-in member sees only rows of their own family.
-- Writes that need to cross that line (creating or joining a family) go through
-- the security definer functions at the bottom. The service role (pg_cron job,
-- Edge Functions) bypasses RLS.

create schema if not exists private;

-- Invite codes ----------------------------------------------------------------
-- Read aloud over the phone: 8 characters from an alphabet without look-alikes
-- (no 0/O, 1/I). 32 symbols, so byte % 32 is unbiased.
-- ponytail: no retry on a collision (32^8 codes); the unique index turns one
-- into an error the caller can retry.

create function private.new_invite_code()
returns text
language sql volatile set search_path = ''
as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', get_byte(b, i) % 32 + 1, 1), '')
  from extensions.gen_random_bytes(8) b, generate_series(0, 7) i
$$;

revoke all on function private.new_invite_code() from public;

-- Families ------------------------------------------------------------------
-- A family is named for its parent, as the children call them ("Mom").
-- Two codes, and the code decides the role:
--   parent_code  lets one parent in, then is cleared. A child issues a new one
--                with reinvite_parent() after a reinstall or new phone.
--   child_code   lets siblings in, any number of times.

create table public.families (
  id          uuid primary key default gen_random_uuid(),
  parent_name text not null check (char_length(parent_name) between 1 and 60),
  parent_code text unique default private.new_invite_code(),
  child_code  text not null unique default private.new_invite_code(),
  created_at  timestamptz not null default now()
);

-- Members -------------------------------------------------------------------
-- Escalation order among children is join order (created_at): the first child
-- is the primary contact, the next one the 2nd contact.

create table public.members (
  id           uuid primary key default gen_random_uuid(),
  family_id    uuid not null references public.families on delete cascade,
  user_id      uuid not null references auth.users on delete cascade,
  role         text not null check (role in ('parent', 'child')),
  display_name text not null,
  email        text,
  fcm_token    text,
  created_at   timestamptz not null default now(),
  unique (family_id, user_id),
  unique (family_id, id)  -- target of the composite FKs below
);

-- A child may be in several families (Mom and Dad in separate homes), so
-- user_id alone is not unique. A family has at most one parent.
create index members_user_id_idx on public.members (user_id);
create unique index members_one_parent_idx on public.members (family_id) where role = 'parent';

-- Schedules (one per family) ------------------------------------------------

create table public.schedules (
  family_id    uuid primary key references public.families on delete cascade,
  window_start time not null default '07:00',
  window_end   time not null default '10:00',
  time_zone    text not null default 'UTC'
               check ((now() at time zone time_zone) is not null), -- rejects unknown zones
  paused_until timestamptz,  -- "I'm away" mode
  check (window_start < window_end)
);

-- Check-ins -----------------------------------------------------------------

create table public.checkins (
  id         uuid primary key default gen_random_uuid(),
  family_id  uuid not null,
  member_id  uuid not null,
  source     text not null check (source in ('tap', 'steps')),
  mood       text,
  media_path text,  -- Storage object path (voice note or photo)
  created_at timestamptz not null default now(),
  foreign key (family_id, member_id) references public.members (family_id, id) on delete cascade
);

create index checkins_family_created_idx on public.checkins (family_id, created_at desc);

-- Alerts --------------------------------------------------------------------
-- Inserted by the every-minute job, sent by an Edge Function which fills sent_at.
-- Steps: 1 nudge parent, 2 urgent push to child, 3 push to 2nd contact, 4 email.
-- The unique constraint guarantees each step fires at most once per family per day.

create table public.alerts (
  id              uuid primary key default gen_random_uuid(),
  family_id       uuid not null references public.families on delete cascade,
  day             date not null,  -- the day in the family's time zone
  step            smallint not null check (step between 1 and 4),
  channel         text not null check (channel in ('push', 'urgent_push', 'email')),
  recipient_id    uuid,           -- null for the step 4 email to all children
  created_at      timestamptz not null default now(),
  sent_at         timestamptz,
  acknowledged_at timestamptz,
  unique (family_id, day, step),
  foreign key (family_id, recipient_id) references public.members (family_id, id) on delete set null (recipient_id)
);

-- Heartbeat -----------------------------------------------------------------
-- The every-minute job upserts its row; the uptime endpoint fails if
-- last_run_at is older than 5 minutes. No client access: RLS on, no policies.

create table public.heartbeats (
  job         text primary key,
  last_run_at timestamptz not null default now()
);

-- Wrong invite codes, for the attempt limit in join_family. Not exposed.
create table private.join_attempts (
  user_id      uuid not null,
  attempted_at timestamptz not null default now()
);

create index join_attempts_user_idx on private.join_attempts (user_id, attempted_at);

-- Row Level Security --------------------------------------------------------

-- Security definer so policies on members can use it without recursing into
-- members' own policy. Lives in a non-exposed schema so it isn't an RPC.
create function private.my_family_ids()
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select family_id from public.members where user_id = auth.uid()
$$;

revoke all on function private.my_family_ids() from public;
grant usage on schema private to authenticated;
grant execute on function private.my_family_ids() to authenticated;

alter table public.families   enable row level security;
alter table public.members    enable row level security;
alter table public.schedules  enable row level security;
alter table public.checkins   enable row level security;
alter table public.alerts     enable row level security;
alter table public.heartbeats enable row level security;

create policy "members read their family"
  on public.families for select to authenticated
  using (id in (select private.my_family_ids()));

create policy "members read their family's members"
  on public.members for select to authenticated
  using (family_id in (select private.my_family_ids()));

-- Only these columns are client-editable, and only on your own row.
revoke update on public.members from anon, authenticated;
grant update (display_name, fcm_token) on public.members to authenticated;

create policy "members update themselves"
  on public.members for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "members read their schedule"
  on public.schedules for select to authenticated
  using (family_id in (select private.my_family_ids()));

create policy "members create their schedule"
  on public.schedules for insert to authenticated
  with check (family_id in (select private.my_family_ids()));

create policy "members change their schedule"
  on public.schedules for update to authenticated
  using (family_id in (select private.my_family_ids()))
  with check (family_id in (select private.my_family_ids()));

create policy "members read their check-ins"
  on public.checkins for select to authenticated
  using (family_id in (select private.my_family_ids()));

-- The composite FK ties member_id to family_id, so owning the member row is enough.
create policy "members check in as themselves"
  on public.checkins for insert to authenticated
  with check (member_id in (select id from public.members where user_id = (select auth.uid())));

create policy "members read their alerts"
  on public.alerts for select to authenticated
  using (family_id in (select private.my_family_ids()));

revoke update on public.alerts from anon, authenticated;
grant update (acknowledged_at) on public.alerts to authenticated;

create policy "members acknowledge their alerts"
  on public.alerts for update to authenticated
  using (family_id in (select private.my_family_ids()))
  with check (family_id in (select private.my_family_ids()));

-- Family creation and invite codes ------------------------------------------

-- An adult child starts a family for their parent and becomes its first member.
create function public.create_family(parent_name text, my_name text)
returns public.families
language plpgsql security definer set search_path = ''
as $$
declare
  fam public.families;
begin
  insert into public.families (parent_name) values (trim(parent_name)) returning * into fam;
  insert into public.members (family_id, user_id, role, display_name, email)
  values (fam.id, auth.uid(), 'child', my_name, auth.jwt() ->> 'email');
  return fam;
end
$$;

-- Joins with either code; the code decides the role. Spaces, dashes and case
-- are ignored. A wrong code returns null (not an error, so the attempt is
-- kept); after 10 wrong codes in an hour it raises PT429.
-- The parent's member row takes the family's parent_name. If the family
-- already has a parent (re-invite), that row moves to the caller, so the
-- check-in history stays and the old phone loses access.
create function public.join_family(code text, my_name text)
returns public.families
language plpgsql security definer set search_path = ''
as $$
declare
  me  uuid := auth.uid();
  fam public.families;
  typed text := upper(regexp_replace(code, '[\s-]', '', 'g'));
begin
  if me is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if (select count(*) from private.join_attempts
      where user_id = me and attempted_at > now() - interval '1 hour') >= 10 then
    raise exception 'too many attempts, try again later' using errcode = 'PT429';
  end if;

  select * into fam from public.families where parent_code = typed for update;
  if found then
    update public.members set user_id = me, display_name = fam.parent_name,
                              email = auth.jwt() ->> 'email', fcm_token = null
      where family_id = fam.id and role = 'parent';
    if not found then
      insert into public.members (family_id, user_id, role, display_name, email)
      values (fam.id, me, 'parent', fam.parent_name, auth.jwt() ->> 'email');
    end if;
    update public.families set parent_code = null where id = fam.id returning * into fam;
    return fam;
  end if;

  select * into fam from public.families where child_code = typed;
  if found then
    insert into public.members (family_id, user_id, role, display_name, email)
    values (fam.id, me, 'child', my_name, auth.jwt() ->> 'email');
    return fam;
  end if;

  insert into private.join_attempts (user_id) values (me);
  return null;
end
$$;

-- A child issues a fresh parent code, for a new phone or a reinstall.
create function public.reinvite_parent(family_id uuid)
returns public.families
language plpgsql security definer set search_path = ''
as $$
declare
  fam public.families;
begin
  if not exists (select 1 from public.members m
                 where m.family_id = reinvite_parent.family_id
                   and m.user_id = auth.uid() and m.role = 'child') then
    raise exception 'only a child of this family can re-invite the parent' using errcode = '42501';
  end if;
  update public.families f set parent_code = private.new_invite_code()
    where f.id = reinvite_parent.family_id returning * into fam;
  return fam;
end
$$;

revoke all on function public.create_family(text, text) from public, anon;
revoke all on function public.join_family(text, text) from public, anon;
revoke all on function public.reinvite_parent(uuid) from public, anon;
grant execute on function public.create_family(text, text) to authenticated;
grant execute on function public.join_family(text, text) to authenticated;
grant execute on function public.reinvite_parent(uuid) to authenticated;
