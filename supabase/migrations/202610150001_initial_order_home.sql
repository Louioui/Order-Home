-- Order Home: deployment baseline for a future connected client.
-- This migration is NOT used by the local-first iOS build.
-- Run with the Supabase migration owner. API clients may read household rows
-- under RLS; every supported write is a narrow, authenticated RPC below.
begin;

create table public.households (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id),
  name text not null check (length(btrim(name)) between 1 and 80),
  mode text not null default 'family' check (mode in ('family', 'couple')),
  created_at timestamptz not null default now()
);

create table public.household_members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  display_name text not null check (length(btrim(display_name)) between 1 and 40),
  avatar_emoji text not null default '🍽️',
  default_role text not null default 'diner' check (default_role in ('head_chef', 'sous_chef', 'diner')),
  dietary_tags text[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (household_id, user_id),
  unique (household_id, id)
);

-- Cache only licensed, public provider recipes here. Private household notes and
-- social URLs must remain household scoped. Service-role workers populate this.
create table public.recipes_cache (
  id text primary key,
  title text not null check (length(btrim(title)) between 1 and 200),
  cuisine_tag text,
  image_url text,
  source_url text,
  provider text not null,
  prep_time_minutes integer not null default 30 check (prep_time_minutes > 0),
  base_servings integer not null default 4 check (base_servings > 0),
  youtube_video_id text,
  ingredients_json jsonb not null default '[]' check (jsonb_typeof(ingredients_json) = 'array'),
  steps_json jsonb not null default '[]' check (jsonb_typeof(steps_json) = 'array'),
  is_fully_hydrated boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.dinner_sessions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  head_chef_id uuid not null,
  sous_chef_id uuid,
  status text not null default 'pitching' check (status in ('pitching', 'voting', 'ticket_locked', 'cooking', 'served')),
  poll_mode text not null default 'open_cravings' check (poll_mode in ('open_cravings', 'chefs_menu')),
  voting_deadline timestamptz not null,
  winning_pitch_id uuid,
  missing_groceries text[] not null default '{}',
  cooking_step_index integer not null default 0 check (cooking_step_index >= 0),
  created_at timestamptz not null default now(),
  unique (household_id, id),
  foreign key (household_id, head_chef_id) references public.household_members(household_id, id),
  foreign key (household_id, sous_chef_id) references public.household_members(household_id, id)
);
create unique index one_active_dinner_per_household on public.dinner_sessions(household_id) where status <> 'served';

create table public.dish_pitches (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  session_id uuid not null,
  pitched_by_member_id uuid not null,
  recipe_id text not null references public.recipes_cache(id),
  custom_note text check (length(custom_note) <= 400),
  created_at timestamptz not null default clock_timestamp(),
  unique (session_id, recipe_id),
  unique (household_id, session_id, id),
  foreign key (household_id, session_id) references public.dinner_sessions(household_id, id) on delete cascade,
  foreign key (household_id, pitched_by_member_id) references public.household_members(household_id, id)
);
alter table public.dinner_sessions add constraint winning_pitch_belongs_to_session
  foreign key (household_id, id, winning_pitch_id) references public.dish_pitches(household_id, session_id, id) deferrable initially deferred;

-- Attendance and notes belong to an order, once per diner per session. Keeping
-- them separate from dish_votes prevents one diner being counted once per dish.
create table public.diner_orders (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  session_id uuid not null,
  member_id uuid not null,
  is_eating_home boolean not null default true,
  modifier_tags text[] not null default '{}',
  diner_note text not null default '' check (length(diner_note) <= 400),
  submitted_at timestamptz,
  unique (session_id, member_id),
  unique (household_id, session_id, member_id),
  foreign key (household_id, session_id) references public.dinner_sessions(household_id, id) on delete cascade,
  foreign key (household_id, member_id) references public.household_members(household_id, id)
);

create table public.dish_votes (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  session_id uuid not null,
  pitch_id uuid not null,
  member_id uuid not null,
  vote_weight integer not null check (vote_weight in (0, 1, 2)),
  unique (pitch_id, member_id),
  foreign key (household_id, session_id, pitch_id) references public.dish_pitches(household_id, session_id, id) on delete cascade,
  foreign key (household_id, session_id, member_id) references public.diner_orders(household_id, session_id, member_id) on delete cascade
);
create index household_members_user on public.household_members(user_id, household_id);
create index dish_pitches_session on public.dish_pitches(session_id);
create index diner_orders_session on public.diner_orders(session_id);
create index dish_votes_session on public.dish_votes(session_id);

-- The fixed, empty search_path and qualified names avoid search-path injection.
-- SECURITY DEFINER avoids recursive household_members RLS; this function exposes
-- only whether the authenticated caller is already a household member.
create function public.is_household_member(p_household_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.household_members m where m.household_id = p_household_id and m.user_id = auth.uid());
$$;
revoke all on function public.is_household_member(uuid) from public, anon;
grant execute on function public.is_household_member(uuid) to authenticated;

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.recipes_cache enable row level security;
alter table public.dinner_sessions enable row level security;
alter table public.dish_pitches enable row level security;
alter table public.diner_orders enable row level security;
alter table public.dish_votes enable row level security;

create policy household_read on public.households for select to authenticated using (public.is_household_member(id));
create policy member_read on public.household_members for select to authenticated using (public.is_household_member(household_id));
create policy public_recipe_read on public.recipes_cache for select to authenticated using (true);
create policy session_read on public.dinner_sessions for select to authenticated using (public.is_household_member(household_id));
create policy pitch_read on public.dish_pitches for select to authenticated using (public.is_household_member(household_id));
create policy order_read on public.diner_orders for select to authenticated using (public.is_household_member(household_id));
create policy vote_read on public.dish_votes for select to authenticated using (public.is_household_member(household_id));

revoke all on public.households, public.household_members, public.recipes_cache, public.dinner_sessions, public.dish_pitches, public.diner_orders, public.dish_votes from anon, authenticated;
grant select on public.households, public.household_members, public.recipes_cache, public.dinner_sessions, public.dish_pitches, public.diner_orders, public.dish_votes to authenticated;

create function public.create_kitchen(p_name text, p_mode text, p_display_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if p_mode not in ('family', 'couple') then raise exception 'Invalid household mode'; end if;
  insert into public.households(owner_user_id, name, mode) values (auth.uid(), btrim(p_name), p_mode) returning id into new_id;
  insert into public.household_members(household_id, user_id, display_name, default_role)
    values (new_id, auth.uid(), btrim(p_display_name), 'head_chef');
  return new_id;
end;
$$;

create function public.open_dinner(p_household_id uuid, p_deadline timestamptz, p_poll_mode text default 'open_cravings')
returns uuid language plpgsql security definer set search_path = '' as $$
declare member_id uuid; new_id uuid;
begin
  select m.id into member_id from public.household_members m where m.household_id = p_household_id and m.user_id = auth.uid();
  if member_id is null then raise exception 'Household membership required'; end if;
  if p_deadline is null or p_deadline <= now() then raise exception 'Choose a future voting deadline'; end if;
  insert into public.dinner_sessions(household_id, head_chef_id, voting_deadline, poll_mode)
    values (p_household_id, member_id, p_deadline, p_poll_mode) returning id into new_id;
  return new_id;
end;
$$;

create function public.add_pitch(p_session_id uuid, p_recipe_id text, p_note text default '')
returns uuid language plpgsql security definer set search_path = '' as $$
declare s public.dinner_sessions; member_id uuid; new_id uuid;
begin
  select * into s from public.dinner_sessions where id = p_session_id for update;
  if not found then raise exception 'Dinner unavailable'; end if;
  select m.id into member_id from public.household_members m where m.household_id = s.household_id and m.user_id = auth.uid();
  if member_id is null then raise exception 'Household membership required'; end if;
  if s.status <> 'pitching' then raise exception 'Nominations are closed'; end if;
  if s.poll_mode = 'chefs_menu' and s.head_chef_id <> member_id then raise exception 'The chef is choosing tonight''s menu'; end if;
  if (select count(*) from public.dish_pitches where session_id = s.id) >= 5 then raise exception 'The menu already has five dishes'; end if;
  insert into public.dish_pitches(household_id, session_id, pitched_by_member_id, recipe_id, custom_note)
    values (s.household_id, s.id, member_id, p_recipe_id, p_note) returning id into new_id;
  return new_id;
end;
$$;

create function public.start_voting(p_session_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare s public.dinner_sessions; household_mode text;
begin
  select * into s from public.dinner_sessions where id = p_session_id for update;
  if not found then raise exception 'Dinner unavailable'; end if;
  if not exists (select 1 from public.household_members where id = s.head_chef_id and user_id = auth.uid()) then raise exception 'Only the chef can open voting'; end if;
  if s.status <> 'pitching' then raise exception 'Dinner is not accepting nominations'; end if;
  if s.voting_deadline <= now() then raise exception 'Voting deadline has passed'; end if;
  if (select count(*) from public.dish_pitches where session_id = s.id) not between 2 and 5 then raise exception 'Nominate two to five dishes'; end if;
  select mode into household_mode from public.households where id = s.household_id;
  if household_mode = 'couple' and (select count(*) from public.household_members where household_id = s.household_id) <> 2 then raise exception 'Table for Two requires exactly two members'; end if;
  insert into public.diner_orders(household_id, session_id, member_id)
    select s.household_id, s.id, m.id from public.household_members m where m.household_id = s.household_id;
  update public.dinner_sessions set status = 'voting' where id = s.id;
end;
$$;

-- Internal-only resolver. Caller holds a session row lock; locking again is safe.
-- PostgreSQL serializes simultaneous submissions/chef closes on this row, so
-- only one winning ticket can be committed. No client-supplied winner is trusted.
create function public._resolve_ticket(p_session_id uuid, p_allow_family boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare s public.dinner_sessions; household_mode text; winner uuid; diners integer;
begin
  select * into s from public.dinner_sessions where id = p_session_id for update;
  if s.status <> 'voting' then return s.winning_pitch_id; end if;
  select mode into household_mode from public.households where id = s.household_id;
  select count(*) into diners from public.diner_orders where session_id = s.id and is_eating_home;
  if diners = 0 then return null; end if;
  if household_mode = 'couple' then
    if diners <> 2 then return null; end if;
    select p.id into winner from public.dish_pitches p
      join public.dish_votes v on v.pitch_id = p.id
      join public.diner_orders o on o.session_id = v.session_id and o.member_id = v.member_id
      where p.session_id = s.id and o.is_eating_home and o.submitted_at is not null and v.vote_weight = 2
      group by p.id having count(distinct v.member_id) = 2
      order by p.created_at, p.id limit 1;
  elsif p_allow_family then
    select p.id into winner from public.dish_pitches p
      join public.dish_votes v on v.pitch_id = p.id
      join public.diner_orders o on o.session_id = v.session_id and o.member_id = v.member_id
      where p.session_id = s.id and o.is_eating_home and o.submitted_at is not null
      group by p.id order by sum(v.vote_weight) desc,
        count(*) filter (where v.vote_weight = 0), p.created_at, p.id limit 1;
  end if;
  if winner is not null then
    update public.dinner_sessions set status = 'ticket_locked', winning_pitch_id = winner where id = s.id;
  end if;
  return winner;
end;
$$;

-- Reactions example: [{"pitch_id":"UUID", "weight":2}, ...]. Every attending
-- diner submits exactly one reaction for every current pitch, atomically.
create function public.submit_order(p_session_id uuid, p_reactions jsonb, p_eating_home boolean default true, p_tags text[] default '{}', p_note text default '')
returns uuid language plpgsql security definer set search_path = '' as $$
declare s public.dinner_sessions; v_member_id uuid; household_mode text; pitch_count integer; winner uuid;
begin
  select * into s from public.dinner_sessions where id = p_session_id for update;
  if not found then raise exception 'Dinner unavailable'; end if;
  select m.id into v_member_id from public.household_members m where m.household_id = s.household_id and m.user_id = auth.uid();
  if v_member_id is null then raise exception 'Household membership required'; end if;
  if s.status <> 'voting' then raise exception 'Voting has closed'; end if;
  if s.voting_deadline <= now() then raise exception 'Voting deadline has passed'; end if;
  if p_eating_home is null or p_note is null or p_tags is null or length(p_note) > 400 or cardinality(p_tags) > 12 then raise exception 'Invalid order'; end if;
  if exists (select 1 from unnest(p_tags) tag where tag is null or length(tag) > 60) then raise exception 'Invalid order tag'; end if;
  select mode into household_mode from public.households where id = s.household_id;
  if not exists(select 1 from public.diner_orders where session_id = s.id and diner_orders.member_id = v_member_id) then raise exception 'You were not part of this poll when voting opened'; end if;
  if p_eating_home then
    if p_reactions is null or jsonb_typeof(p_reactions) <> 'array' then raise exception 'Provide a reaction for every dish'; end if;
    select count(*) into pitch_count from public.dish_pitches where session_id = s.id;
    if jsonb_array_length(p_reactions) <> pitch_count then raise exception 'Provide a reaction for every dish'; end if;
    if (select count(distinct (r->>'pitch_id')::uuid) from jsonb_array_elements(p_reactions) r) <> pitch_count then raise exception 'Duplicate reactions'; end if;
    if exists (
      select 1 from jsonb_array_elements(p_reactions) r
      where r->>'pitch_id' is null or r->>'weight' is null
        or not exists(select 1 from public.dish_pitches p where p.id = (r->>'pitch_id')::uuid and p.session_id = s.id)
        or (r->>'weight')::integer not in (0,1,2)
        or (household_mode = 'couple' and (r->>'weight')::integer = 1)
    ) then raise exception 'Invalid reaction'; end if;
  end if;
  update public.diner_orders set is_eating_home = p_eating_home, modifier_tags = p_tags, diner_note = p_note, submitted_at = now()
    where session_id = s.id and diner_orders.member_id = v_member_id;
  delete from public.dish_votes where session_id = s.id and dish_votes.member_id = v_member_id;
  if p_eating_home then
    insert into public.dish_votes(household_id, session_id, pitch_id, member_id, vote_weight)
      select s.household_id, s.id, (r->>'pitch_id')::uuid, v_member_id, (r->>'weight')::integer from jsonb_array_elements(p_reactions) r;
  end if;
  winner := public._resolve_ticket(s.id, not exists(select 1 from public.diner_orders where session_id = s.id and submitted_at is null));
  return winner;
end;
$$;

create function public.close_voting(p_session_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare s public.dinner_sessions; winner uuid;
begin
  select * into s from public.dinner_sessions where id = p_session_id for update;
  if not found then raise exception 'Dinner unavailable'; end if;
  if not exists(select 1 from public.household_members where id = s.head_chef_id and user_id = auth.uid()) then raise exception 'Only the chef can close voting'; end if;
  if s.status <> 'voting' then raise exception 'Dinner is not voting'; end if;
  winner := public._resolve_ticket(s.id, true);
  if winner is null then raise exception 'No eligible dinner yet: check attendance, submitted votes, or mutual couple likes'; end if;
  return winner;
end;
$$;

create function public.advance_kitchen(p_session_id uuid, p_status text, p_step_index integer default 0, p_missing_groceries text[] default '{}')
returns void language plpgsql security definer set search_path = '' as $$
declare s public.dinner_sessions; step_count integer;
begin
  select * into s from public.dinner_sessions where id = p_session_id for update;
  if not found then raise exception 'Dinner unavailable'; end if;
  if not exists(select 1 from public.household_members where id = s.head_chef_id and user_id = auth.uid()) then raise exception 'Only the chef can update cooking'; end if;
  if p_missing_groceries is null or cardinality(p_missing_groceries) > 100 then raise exception 'Invalid grocery list'; end if;
  if exists(select 1 from unnest(p_missing_groceries) item where item is null or length(item) > 200) then raise exception 'Invalid grocery item'; end if;
  if not ((s.status = 'ticket_locked' and p_status in ('ticket_locked','cooking')) or (s.status = 'cooking' and p_status in ('cooking','served'))) then raise exception 'Invalid dinner transition'; end if;
  select jsonb_array_length(r.steps_json) into step_count from public.dish_pitches p join public.recipes_cache r on r.id = p.recipe_id where p.id = s.winning_pitch_id and r.is_fully_hydrated;
  if p_status in ('cooking', 'served') and (step_count is null or step_count = 0) then raise exception 'Hydrate the winning recipe before cooking'; end if;
  if p_step_index is null or p_step_index < 0 or (step_count is not null and p_step_index >= step_count) then raise exception 'Invalid cooking step'; end if;
  update public.dinner_sessions set status = p_status, cooking_step_index = p_step_index, missing_groceries = p_missing_groceries where id = s.id;
end;
$$;

-- Postgres grants EXECUTE to PUBLIC by default; remove it explicitly for every
-- definer function. The internal resolver has no client execute permission.
revoke all on function public.create_kitchen(text,text,text) from public, anon;
revoke all on function public.open_dinner(uuid,timestamptz,text) from public, anon;
revoke all on function public.add_pitch(uuid,text,text) from public, anon;
revoke all on function public.start_voting(uuid) from public, anon;
revoke all on function public._resolve_ticket(uuid,boolean) from public, anon, authenticated;
revoke all on function public.submit_order(uuid,jsonb,boolean,text[],text) from public, anon;
revoke all on function public.close_voting(uuid) from public, anon;
revoke all on function public.advance_kitchen(uuid,text,integer,text[]) from public, anon;
grant execute on function public.create_kitchen(text,text,text), public.open_dinner(uuid,timestamptz,text), public.add_pitch(uuid,text,text), public.start_voting(uuid), public.submit_order(uuid,jsonb,boolean,text[],text), public.close_voting(uuid), public.advance_kitchen(uuid,text,integer,text[]) to authenticated;

-- Publish only household scoped collaboration rows, and keep RLS enabled.
-- Already-published tables are skipped to allow an existing Supabase project.
do $$
declare table_name text;
begin
  if exists(select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach table_name in array array['dinner_sessions','dish_pitches','diner_orders','dish_votes'] loop
      if not exists(select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = table_name) then
        execute format('alter publication supabase_realtime add table public.%I', table_name);
      end if;
    end loop;
  end if;
end;
$$;

commit;
