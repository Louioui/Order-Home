-- Connected kitchens: authenticated invitations, coherent snapshots and deadlines.
-- Apply after 202610150001_initial_order_home.sql. No service secret belongs in iOS.
begin;

create schema if not exists order_home_private;
revoke all on schema order_home_private from public, anon, authenticated;

create table order_home_private.kitchen_invites (
  token_hash bytea primary key check (octet_length(token_hash) = 32),
  household_id uuid not null references public.households(id) on delete cascade,
  created_by_user_id uuid not null references auth.users(id),
  expires_at timestamptz not null,
  redeemed_by_user_id uuid references auth.users(id),
  redeemed_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  check ((redeemed_at is null) = (redeemed_by_user_id is null))
);
create index kitchen_invites_household on order_home_private.kitchen_invites(household_id);
alter table order_home_private.kitchen_invites enable row level security;
revoke all on order_home_private.kitchen_invites from public, anon, authenticated;

create function public.my_kitchens()
returns table(id uuid, name text, mode text, owner_user_id uuid)
language sql stable security definer set search_path = '' as $$
  select h.id, h.name, h.mode, h.owner_user_id
  from public.households h
  where exists(select 1 from public.household_members m where m.household_id = h.id and m.user_id = auth.uid())
  order by h.created_at, h.id;
$$;

-- Every array is built by the SAME SQL statement/MVCC snapshot. A client never
-- combines a new winning session with old votes fetched by separate requests.
create function public.kitchen_snapshot(p_household_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  select jsonb_build_object(
    'household', jsonb_build_object('id',h.id,'name',h.name,'mode',h.mode,'owner_user_id',h.owner_user_id),
    'members', coalesce((select jsonb_agg(jsonb_build_object(
      'id',m.id,'user_id',m.user_id,'display_name',m.display_name,'avatar_emoji',m.avatar_emoji,
      'default_role',m.default_role,'dietary_tags',m.dietary_tags) order by m.created_at,m.id)
      from public.household_members m where m.household_id = h.id),'[]'::jsonb),
    'session', to_jsonb(s),
    'pitches', coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at,p.id) from public.dish_pitches p where p.session_id = s.id),'[]'::jsonb),
    'votes', coalesce((select jsonb_agg(to_jsonb(v) order by v.pitch_id,v.member_id) from public.dish_votes v where v.session_id = s.id),'[]'::jsonb),
    'orders', coalesce((select jsonb_agg(to_jsonb(o) order by o.member_id) from public.diner_orders o where o.session_id = s.id),'[]'::jsonb)
  ) into result
  from public.households h
  left join lateral (select ds.* from public.dinner_sessions ds where ds.household_id = h.id
    order by (ds.status <> 'served') desc, ds.created_at desc, ds.id desc limit 1) s on true
  where h.id = p_household_id and exists(select 1 from public.household_members m where m.household_id = h.id and m.user_id = auth.uid());
  if result is null then raise exception 'Household membership required'; end if;
  return result;
end;
$$;

create function public.create_kitchen_invite(p_household_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare h public.households; token text; deadline timestamptz := now() + interval '7 days';
begin
  select * into h from public.households where id = p_household_id for update;
  if not found or h.owner_user_id is distinct from auth.uid() then raise exception 'Only the kitchen owner can invite people'; end if;
  -- Core PostgreSQL UUIDs use a cryptographic generator. Two UUIDs contribute
  -- 244 random bits; SHA-256 encodes them as a fixed, unguessable 64-hex token.
  token := encode(sha256(convert_to(gen_random_uuid()::text || gen_random_uuid()::text,'UTF8')),'hex');
  insert into order_home_private.kitchen_invites(token_hash,household_id,created_by_user_id,expires_at)
    values(sha256(convert_to(token,'UTF8')),h.id,auth.uid(),deadline);
  return jsonb_build_object('token',token,'expires_at',deadline,'household_name',h.name);
end;
$$;

create function public.join_kitchen(p_token text, p_display_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare invite order_home_private.kitchen_invites; h public.households; token text := lower(btrim(p_token));
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if p_display_name is null or length(btrim(p_display_name)) not between 1 and 40 then raise exception 'Choose a name between 1 and 40 characters'; end if;
  if token is null or token !~ '^[0-9a-f]{64}$' then raise exception 'Invitation is unavailable or expired'; end if;
  select * into invite from order_home_private.kitchen_invites where token_hash = sha256(convert_to(token,'UTF8'));
  if not found then raise exception 'Invitation is unavailable or expired'; end if;
  -- All membership/capacity changes and opening voting lock household FIRST.
  -- This prevents two simultaneous joins taking the last seat in a couple.
  select * into h from public.households where id = invite.household_id for update;
  select * into invite from order_home_private.kitchen_invites where token_hash = sha256(convert_to(token,'UTF8')) for update;
  if invite.revoked_at is not null then raise exception 'Invitation is unavailable or expired'; end if;
  if invite.redeemed_by_user_id = auth.uid() and exists(select 1 from public.household_members where household_id = h.id and user_id = auth.uid()) then return h.id; end if;
  if invite.redeemed_at is not null or invite.expires_at <= now() then raise exception 'Invitation is unavailable or expired'; end if;
  if exists(select 1 from public.household_members where household_id = h.id and user_id = auth.uid()) then raise exception 'You already belong to this kitchen'; end if;
  if exists(select 1 from public.dinner_sessions where household_id = h.id and status in ('voting','ticket_locked','cooking')) then raise exception 'Join after the current dinner is served'; end if;
  if h.mode = 'couple' and (select count(*) from public.household_members where household_id = h.id) >= 2 then raise exception 'Table for Two already has two people'; end if;
  insert into public.household_members(household_id,user_id,display_name) values(h.id,auth.uid(),btrim(p_display_name));
  update order_home_private.kitchen_invites set redeemed_by_user_id = auth.uid(), redeemed_at = now() where token_hash = invite.token_hash;
  return h.id;
end;
$$;

create function public.revoke_kitchen_invite(p_household_id uuid, p_token text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists(select 1 from public.households where id = p_household_id and owner_user_id = auth.uid()) then raise exception 'Only the kitchen owner can revoke invitations'; end if;
  update order_home_private.kitchen_invites set revoked_at = now()
    where household_id = p_household_id and token_hash = sha256(convert_to(lower(btrim(p_token)),'UTF8'));
end;
$$;

create function public.update_own_profile(p_household_id uuid, p_display_name text, p_avatar_emoji text, p_dietary_tags text[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_display_name is null or length(btrim(p_display_name)) not between 1 and 40
    or p_avatar_emoji is null or length(btrim(p_avatar_emoji)) not between 1 and 16
    or p_dietary_tags is null or cardinality(p_dietary_tags) > 12
    or exists(select 1 from unnest(p_dietary_tags) t where t is null or length(t) > 60) then raise exception 'Invalid profile'; end if;
  update public.household_members set display_name = btrim(p_display_name), avatar_emoji = btrim(p_avatar_emoji), dietary_tags = p_dietary_tags
    where household_id = p_household_id and user_id = auth.uid();
  if not found then raise exception 'Household membership required'; end if;
end;
$$;

create function public.set_kitchen_mode(p_household_id uuid, p_mode text)
returns void language plpgsql security definer set search_path = '' as $$
declare h public.households;
begin
  select * into h from public.households where id = p_household_id for update;
  if not found or h.owner_user_id is distinct from auth.uid() then raise exception 'Only the kitchen owner can change its mode'; end if;
  if p_mode is null or p_mode not in ('family','couple') then raise exception 'Invalid household mode'; end if;
  if exists(select 1 from public.dinner_sessions where household_id = h.id and status in ('voting','ticket_locked','cooking')) then raise exception 'Change the table mode before voting starts'; end if;
  if p_mode = 'couple' and (select count(*) from public.household_members where household_id = h.id) > 2 then raise exception 'Table for Two supports at most two people'; end if;
  update public.households set mode = p_mode where id = h.id;
end;
$$;

-- Also serialize open/start with invitations and mode changes.
create or replace function public.open_dinner(p_household_id uuid, p_deadline timestamptz, p_poll_mode text default 'open_cravings')
returns uuid language plpgsql security definer set search_path = '' as $$
declare member_id uuid; new_id uuid;
begin
  perform 1 from public.households where id = p_household_id for update;
  select m.id into member_id from public.household_members m where m.household_id = p_household_id and m.user_id = auth.uid();
  if member_id is null then raise exception 'Household membership required'; end if;
  if p_deadline is null or p_deadline <= now() or p_deadline > now() + interval '7 days' then raise exception 'Choose a voting deadline within the next seven days'; end if;
  insert into public.dinner_sessions(household_id,head_chef_id,voting_deadline,poll_mode)
    values(p_household_id,member_id,p_deadline,p_poll_mode) returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.start_voting(p_session_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare s public.dinner_sessions; h public.households;
begin
  select h1.* into h from public.households h1 join public.dinner_sessions ds on ds.household_id = h1.id where ds.id = p_session_id for update of h1;
  select * into s from public.dinner_sessions where id = p_session_id for update;
  if not found then raise exception 'Dinner unavailable'; end if;
  if not exists(select 1 from public.household_members where id = s.head_chef_id and user_id = auth.uid()) then raise exception 'Only the chef can open voting'; end if;
  if s.status <> 'pitching' then raise exception 'Dinner is not accepting nominations'; end if;
  if s.voting_deadline <= now() then raise exception 'Voting deadline has passed'; end if;
  if (select count(*) from public.dish_pitches where session_id = s.id) not between 2 and 5 then raise exception 'Nominate two to five dishes'; end if;
  if h.mode = 'couple' and (select count(*) from public.household_members where household_id = h.id) <> 2 then raise exception 'Table for Two requires exactly two members'; end if;
  if exists(select 1 from public.dish_pitches p join public.recipes_cache r on r.id = p.recipe_id where p.session_id = s.id and (not r.is_fully_hydrated or jsonb_array_length(r.steps_json) = 0)) then raise exception 'Every nominated recipe needs cooking instructions'; end if;
  insert into public.diner_orders(household_id,session_id,member_id)
    select s.household_id,s.id,m.id from public.household_members m where m.household_id = s.household_id
    on conflict (session_id,member_id) do nothing;
  update public.dinner_sessions set status = 'voting' where id = s.id;
end;
$$;

create function public.remove_pitch(p_session_id uuid, p_recipe_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare s public.dinner_sessions; member_id uuid; pitch public.dish_pitches;
begin
  select * into s from public.dinner_sessions where id = p_session_id for update;
  if not found then raise exception 'Dinner unavailable'; end if;
  select m.id into member_id from public.household_members m where m.household_id = s.household_id and m.user_id = auth.uid();
  if member_id is null then raise exception 'Household membership required'; end if;
  if s.status <> 'pitching' then raise exception 'Nominations are closed'; end if;
  select * into pitch from public.dish_pitches where session_id = s.id and recipe_id = p_recipe_id;
  if not found then return; end if;
  if pitch.pitched_by_member_id <> member_id and s.head_chef_id <> member_id then raise exception 'Only the nominator or chef can remove a dish'; end if;
  delete from public.dish_pitches where id = pitch.id;
end;
$$;

create function public.save_diner_preferences(p_session_id uuid, p_eating_home boolean, p_tags text[], p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare s public.dinner_sessions; v_member_id uuid;
begin
  select * into s from public.dinner_sessions where id = p_session_id for update;
  if not found then raise exception 'Dinner unavailable'; end if;
  select m.id into v_member_id from public.household_members m where m.household_id = s.household_id and m.user_id = auth.uid();
  if v_member_id is null then raise exception 'Household membership required'; end if;
  if s.status not in ('pitching','voting') then raise exception 'Orders are closed'; end if;
  if s.status = 'voting' and s.voting_deadline <= now() then raise exception 'Voting deadline has passed'; end if;
  if p_eating_home is null or p_tags is null or p_note is null or length(p_note) > 400 or cardinality(p_tags) > 12
    or exists(select 1 from unnest(p_tags) t where t is null or length(t) > 60) then raise exception 'Invalid order'; end if;
  insert into public.diner_orders(household_id,session_id,member_id,is_eating_home,modifier_tags,diner_note)
    values(s.household_id,s.id,v_member_id,p_eating_home,p_tags,p_note)
    on conflict (session_id,member_id) do update set is_eating_home = excluded.is_eating_home,
      modifier_tags = excluded.modifier_tags,diner_note = excluded.diner_note,submitted_at = null;
  -- A changed order becomes a draft again until submit_order atomically sends
  -- the complete ballot. No old votes can silently count with new attendance.
  delete from public.dish_votes where session_id = s.id and dish_votes.member_id = v_member_id;
end;
$$;

create function public.cancel_dinner(p_session_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare s public.dinner_sessions;
begin
  select * into s from public.dinner_sessions where id = p_session_id for update;
  if not found then raise exception 'Dinner unavailable'; end if;
  if not exists(select 1 from public.household_members where id = s.head_chef_id and user_id = auth.uid()) then raise exception 'Only the chef can cancel dinner'; end if;
  if s.status not in ('pitching','voting') then raise exception 'A confirmed dinner cannot be cancelled'; end if;
  delete from public.dinner_sessions where id = s.id;
end;
$$;

create function public.expire_voting(p_session_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare s public.dinner_sessions;
begin
  select * into s from public.dinner_sessions where id = p_session_id for update;
  if not found then raise exception 'Dinner unavailable'; end if;
  if not public.is_household_member(s.household_id) then raise exception 'Household membership required'; end if;
  if s.status <> 'voting' then return s.winning_pitch_id; end if;
  if s.voting_deadline > now() then return null; end if;
  return public._resolve_ticket(s.id,true);
end;
$$;

create function public.extend_voting(p_session_id uuid, p_deadline timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
declare s public.dinner_sessions;
begin
  select * into s from public.dinner_sessions where id = p_session_id for update;
  if not found then raise exception 'Dinner unavailable'; end if;
  if not exists(select 1 from public.household_members where id = s.head_chef_id and user_id = auth.uid()) then raise exception 'Only the chef can extend voting'; end if;
  if s.status not in ('pitching','voting') then raise exception 'Dinner already has a ticket'; end if;
  if p_deadline is null or p_deadline <= now() or p_deadline > now() + interval '7 days' or p_deadline <= s.voting_deadline then raise exception 'Choose a later deadline within the next seven days'; end if;
  update public.dinner_sessions set voting_deadline = p_deadline where id = s.id;
end;
$$;

-- A trusted Cron/service worker runs this even when every phone is closed.
-- Couples without two mutual loves and empty family polls stay unresolved.
create function public.close_due_dinners()
returns integer language plpgsql security definer set search_path = '' as $$
declare s public.dinner_sessions; resolved integer := 0;
begin
  for s in select * from public.dinner_sessions where status = 'voting' and voting_deadline <= now() for update skip locked loop
    if public._resolve_ticket(s.id,true) is not null then resolved := resolved + 1; end if;
  end loop;
  return resolved;
end;
$$;
create index dinner_voting_deadline on public.dinner_sessions(voting_deadline) where status = 'voting';

revoke all on function public.my_kitchens(), public.kitchen_snapshot(uuid), public.create_kitchen_invite(uuid), public.join_kitchen(text,text), public.revoke_kitchen_invite(uuid,text), public.update_own_profile(uuid,text,text,text[]), public.set_kitchen_mode(uuid,text), public.remove_pitch(uuid,text), public.save_diner_preferences(uuid,boolean,text[],text), public.expire_voting(uuid), public.cancel_dinner(uuid), public.extend_voting(uuid,timestamptz), public.close_due_dinners() from public,anon,authenticated;
grant execute on function public.my_kitchens(), public.kitchen_snapshot(uuid), public.create_kitchen_invite(uuid), public.join_kitchen(text,text), public.revoke_kitchen_invite(uuid,text), public.update_own_profile(uuid,text,text,text[]), public.set_kitchen_mode(uuid,text), public.remove_pitch(uuid,text), public.save_diner_preferences(uuid,boolean,text[],text), public.expire_voting(uuid), public.cancel_dinner(uuid), public.extend_voting(uuid,timestamptz) to authenticated;
do $$
begin
  if exists(select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.close_due_dinners() to service_role;
  end if;
  -- Enabling the Cron extension is an account-level deployment step. Do not
  -- force-create it in projects without that extension or local PostgreSQL.
  if exists(select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('order-home-close-due-dinners','* * * * *','select public.close_due_dinners()');
  else
    raise notice 'Enable Supabase Cron, then schedule select public.close_due_dinners() every minute; deadline RPC is available to active member clients.';
  end if;
end;
$$;

-- Membership and mode are collaboration state too. Invitations remain private.
do $$
declare table_name text;
begin
  if exists(select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach table_name in array array['households','household_members'] loop
      if not exists(select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = table_name) then
        execute format('alter publication supabase_realtime add table public.%I',table_name);
      end if;
    end loop;
  end if;
end;
$$;

commit;
