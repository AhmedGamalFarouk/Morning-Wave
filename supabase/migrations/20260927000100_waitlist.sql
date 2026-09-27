-- Waitlist signups from the public site (web/waitlist).
-- Visitors can add a row with the anon/publishable key, but nobody can read,
-- change or delete rows through the API. Read signups in the Supabase dashboard.

create table public.waitlist (
  id           bigint generated always as identity primary key,
  email        text not null
               check (char_length(email) <= 254 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  own_phone    text not null check (own_phone in ('android', 'iphone', 'other')),
  parent_phone text not null check (parent_phone in ('android', 'iphone', 'no_smartphone', 'not_sure')),
  source       text check (char_length(source) <= 64),
  created_at   timestamptz not null default now()
);

-- One signup per address, whatever the capitalisation.
create unique index waitlist_email_key on public.waitlist (lower(email));

alter table public.waitlist enable row level security;

-- Supabase grants every privilege on new public tables to anon and authenticated.
-- Take them back, then allow only an insert of the form's columns.
revoke all on public.waitlist from anon, authenticated;
grant insert (email, own_phone, parent_phone, source) on public.waitlist to anon;

create policy "Anyone can join the waitlist"
  on public.waitlist for insert
  to anon
  with check (true);
