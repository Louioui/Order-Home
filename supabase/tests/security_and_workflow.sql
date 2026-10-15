-- Run only against a disposable local database after the migration.
-- This script creates synthetic auth users within a transaction, then rolls back.
-- psql -v ON_ERROR_STOP=1 -f supabase/tests/security_and_workflow.sql
begin;
insert into auth.users(id) values
  ('00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-000000000003');
insert into public.recipes_cache(id,title,provider,is_fully_hydrated,ingredients_json,steps_json) values
  ('test-pasta','Pasta','test',true,'[{"name":"Pasta","baseAmount":400,"unit":"g"}]','[{"instruction":"Cook the pasta"},{"instruction":"Serve"}]'),
  ('test-soup','Soup','test',true,'[]','[{"instruction":"Simmer"}]');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select set_config('test.household_id',public.create_kitchen('Test kitchen','family','Alex')::text,true);
reset role;
insert into public.household_members(household_id,user_id,display_name)
  values(current_setting('test.household_id')::uuid,'00000000-0000-0000-0000-000000000002','Sam');
set local role authenticated;
select set_config('test.session_id',public.open_dinner(current_setting('test.household_id')::uuid,now() + interval '1 hour')::text,true);
select set_config('test.first_pitch',public.add_pitch(current_setting('test.session_id')::uuid,'test-pasta')::text,true);
select set_config('test.second_pitch',public.add_pitch(current_setting('test.session_id')::uuid,'test-soup')::text,true);
select public.start_voting(current_setting('test.session_id')::uuid);
select public.submit_order(current_setting('test.session_id')::uuid,
  jsonb_build_array(jsonb_build_object('pitch_id',current_setting('test.first_pitch'),'weight',2),jsonb_build_object('pitch_id',current_setting('test.second_pitch'),'weight',1)));

do $$
begin
  if (select count(*) from public.diner_orders where session_id = current_setting('test.session_id')::uuid) <> 2 then raise exception 'Attendance must count people, not votes'; end if;
  if (select status from public.dinner_sessions where id = current_setting('test.session_id')::uuid) <> 'voting' then raise exception 'Incomplete poll locked early'; end if;
  begin
    insert into public.dish_votes(household_id,session_id,pitch_id,member_id,vote_weight)
      values (current_setting('test.household_id')::uuid,current_setting('test.session_id')::uuid,current_setting('test.first_pitch')::uuid,gen_random_uuid(),2);
    raise exception 'Direct write incorrectly allowed';
  exception when insufficient_privilege then null;
  end;
end;
$$;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select public.submit_order(current_setting('test.session_id')::uuid,
  jsonb_build_array(jsonb_build_object('pitch_id',current_setting('test.first_pitch'),'weight',0),jsonb_build_object('pitch_id',current_setting('test.second_pitch'),'weight',1)),true,array['Mild spice'],'Home at six');

do $$
begin
  if (select status from public.dinner_sessions where id = current_setting('test.session_id')::uuid) <> 'ticket_locked' then raise exception 'Completed poll did not lock'; end if;
  if (select winning_pitch_id from public.dinner_sessions where id = current_setting('test.session_id')::uuid) <> current_setting('test.second_pitch')::uuid then raise exception 'Equal-score tie must prefer fewer passes'; end if;
  begin
    perform public.advance_kitchen(current_setting('test.session_id')::uuid,'cooking');
    raise exception 'Non-chef incorrectly changed cooking status';
  exception when raise_exception then
    if sqlerrm <> 'Only the chef can update cooking' then raise; end if;
  end;
end;
$$;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
do $$
begin
  if exists(select 1 from public.households) or exists(select 1 from public.household_members) or exists(select 1 from public.dinner_sessions) or exists(select 1 from public.dish_pitches) or exists(select 1 from public.dish_votes) or exists(select 1 from public.diner_orders) then raise exception 'RLS leaked another household'; end if;
  begin
    perform public.submit_order(current_setting('test.session_id')::uuid,'[]');
    raise exception 'Outsider submitted an order';
  exception when raise_exception then
    if sqlerrm <> 'Household membership required' then raise; end if;
  end;
  begin
    perform public._resolve_ticket(current_setting('test.session_id')::uuid,true);
    raise exception 'Internal resolver incorrectly exposed';
  exception when insufficient_privilege then null;
  end;
end;
$$;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select public.advance_kitchen(current_setting('test.session_id')::uuid,'cooking');
select public.advance_kitchen(current_setting('test.session_id')::uuid,'served');
do $$
begin
  if (select status from public.dinner_sessions where id = current_setting('test.session_id')::uuid) <> 'served' then raise exception 'Dinner lifecycle failed'; end if;
end;
$$;

-- A second independent household validates couple matching without a majority.
select set_config('test.couple_id',public.create_kitchen('Two seats','couple','Alex')::text,true);
reset role;
insert into public.household_members(household_id,user_id,display_name)
  values(current_setting('test.couple_id')::uuid,'00000000-0000-0000-0000-000000000002','Sam');
set local role authenticated;
select set_config('test.couple_session',public.open_dinner(current_setting('test.couple_id')::uuid,now() + interval '1 hour')::text,true);
select set_config('test.couple_first',public.add_pitch(current_setting('test.couple_session')::uuid,'test-pasta')::text,true);
select set_config('test.couple_second',public.add_pitch(current_setting('test.couple_session')::uuid,'test-soup')::text,true);
select public.start_voting(current_setting('test.couple_session')::uuid);
select public.submit_order(current_setting('test.couple_session')::uuid,
  jsonb_build_array(jsonb_build_object('pitch_id',current_setting('test.couple_first'),'weight',2),jsonb_build_object('pitch_id',current_setting('test.couple_second'),'weight',0)));
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select public.submit_order(current_setting('test.couple_session')::uuid,
  jsonb_build_array(jsonb_build_object('pitch_id',current_setting('test.couple_first'),'weight',0),jsonb_build_object('pitch_id',current_setting('test.couple_second'),'weight',2)));
do $$
begin
  if (select status from public.dinner_sessions where id = current_setting('test.couple_session')::uuid) <> 'voting' then raise exception 'Incompatible couple votes must stay open'; end if;
end;
$$;
select public.submit_order(current_setting('test.couple_session')::uuid,
  jsonb_build_array(jsonb_build_object('pitch_id',current_setting('test.couple_first'),'weight',2),jsonb_build_object('pitch_id',current_setting('test.couple_second'),'weight',2)));
do $$
begin
  if (select winning_pitch_id from public.dinner_sessions where id = current_setting('test.couple_session')::uuid) <> current_setting('test.couple_first')::uuid then raise exception 'Mutual couple love did not lock a winner'; end if;
end;
$$;
reset role;
rollback;
