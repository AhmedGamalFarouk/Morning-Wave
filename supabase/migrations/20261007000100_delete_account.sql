-- Account deletion, which Google Play requires in the app. The client first
-- removes the person's files through the Storage API (Supabase refuses
-- direct deletes from storage.objects), then deletes the account. Deleting
-- the auth user cascades to their members rows, and from there to their
-- check-ins, photos and voice notes rows. A family left with no child goes
-- too, with its parent row and schedule: nobody is left to hear from it.

-- Families this person is the last child of.
create function private.families_leaving_with_me()
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select m.family_id from public.members m
  where m.user_id = auth.uid() and m.role = 'child'
    and not exists (
      select 1 from public.members o
      where o.family_id = m.family_id and o.role = 'child'
        and o.user_id <> auth.uid())
$$;

revoke all on function private.families_leaving_with_me() from public;

-- Files to remove before delete_my_account: what this person sent, and
-- everything in the families that go with them.
create function public.my_account_files()
returns table (bucket text, path text)
language sql stable security definer set search_path = ''
as $$
  select 'family-photos', p.storage_path from public.family_photos p
  where p.member_id in (select id from public.members where user_id = auth.uid())
     or p.family_id in (select private.families_leaving_with_me())
  union all
  select 'family-voice-notes', v.storage_path from public.family_voice_notes v
  where v.member_id in (select id from public.members where user_id = auth.uid())
     or v.family_id in (select private.families_leaving_with_me())
$$;

create function public.delete_my_account()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  delete from public.families
    where id in (select private.families_leaving_with_me());
  delete from auth.users where id = auth.uid();
end
$$;

revoke all on function public.my_account_files() from public, anon;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.my_account_files() to authenticated;
grant execute on function public.delete_my_account() to authenticated;
