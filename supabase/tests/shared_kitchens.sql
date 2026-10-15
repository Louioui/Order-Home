-- Disposable database only. Synthetic auth identities; real JWT/Apple transport
-- is deliberately outside this relational/security regression test.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values
  ('10000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002'),
  ('10000000-0000-0000-0000-000000000003'),
  ('10000000-0000-0000-0000-000000000004');

create function public.test_expect_error(p_query text, p_message text)
returns void language plpgsql security invoker as $$
begin
  begin
    execute p_query;
  exception when others then
    if position(p_message in sqlerrm) > 0 then return; end if;
    raise exception 'Unexpected error: % (wanted %)',sqlerrm,p_message;
  end;
  raise exception 'Expected failure: %',p_message;
end;
$$;
create function public.test_assert(p_condition boolean, p_message text)
returns void language plpgsql security invoker as $$
begin
  if p_condition is distinct from true then raise exception '%',p_message; end if;
end;
$$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true) as ignored \gset
set local role authenticated;
select public.test_assert((select count(*) = 0 from public.my_kitchens()),'Fresh identity leaked kitchens');
select set_config('test.kitchen',public.create_kitchen('Shared family','family','Alex')::text,true) as ignored \gset
select public.test_assert(public.kitchen_snapshot(current_setting('test.kitchen')::uuid)->'session' = 'null'::jsonb,'New kitchen has a phantom session');
select public.test_assert(public.kitchen_snapshot(current_setting('test.kitchen')::uuid)->'pitches' = '[]'::jsonb,'New kitchen pitches should be an empty array');
select public.test_assert((select count(*) = 1 from public.my_kitchens()),'Owner cannot find newly created kitchen');
select set_config('test.invite',public.create_kitchen_invite(current_setting('test.kitchen')::uuid)->>'token',true) as ignored \gset
select set_config('test.expired',public.create_kitchen_invite(current_setting('test.kitchen')::uuid)->>'token',true) as ignored \gset
select set_config('test.revoked',public.create_kitchen_invite(current_setting('test.kitchen')::uuid)->>'token',true) as ignored \gset
select set_config('test.late_join',public.create_kitchen_invite(current_setting('test.kitchen')::uuid)->>'token',true) as ignored \gset
select public.test_assert(current_setting('test.invite') ~ '^[0-9a-f]{64}$','Invite token format incorrect');
select public.revoke_kitchen_invite(current_setting('test.kitchen')::uuid,current_setting('test.revoked'));
select public.test_expect_error('select * from order_home_private.kitchen_invites','permission denied');
reset role;
select public.test_assert(exists(select 1 from order_home_private.kitchen_invites where token_hash = sha256(convert_to(current_setting('test.invite'),'UTF8'))),'Database must store token SHA-256');
update order_home_private.kitchen_invites set expires_at = now()-interval '1 second' where token_hash = sha256(convert_to(current_setting('test.expired'),'UTF8'));

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true) as ignored \gset
select public.test_expect_error(format('select public.kitchen_snapshot(%L)',current_setting('test.kitchen')),'Household membership required');
select public.test_expect_error(format('select public.create_kitchen_invite(%L)',current_setting('test.kitchen')),'Only the kitchen owner');
select public.test_expect_error(format('select public.join_kitchen(%L,%L)',current_setting('test.expired'),'Sam'),'Invitation is unavailable or expired');
select public.test_expect_error(format('select public.join_kitchen(%L,%L)',current_setting('test.revoked'),'Sam'),'Invitation is unavailable or expired');
select public.test_expect_error('select public.join_kitchen(''invalid-token'',''Sam'')','Invitation is unavailable or expired');
select public.test_assert(public.join_kitchen(current_setting('test.invite'),'Sam') = current_setting('test.kitchen')::uuid,'Invite joined the wrong kitchen');
select public.test_assert(public.join_kitchen(current_setting('test.invite'),'Sam') = current_setting('test.kitchen')::uuid,'Retry after a lost response must be idempotent');
select public.test_assert((select count(*) = 2 from public.household_members),'Retry created duplicate membership');
select public.update_own_profile(current_setting('test.kitchen')::uuid,'Sammy','🧑‍🍳',array['Vegetarian']);
select public.test_assert((select display_name = 'Sammy' and default_role = 'diner' from public.household_members where user_id = auth.uid()),'Self profile update changed authority');
select public.test_expect_error(format('select public.update_own_profile(%L,%L,%L,%L)',current_setting('test.kitchen'),'','😀','{}'),'Invalid profile');
select public.test_expect_error(format('select public.set_kitchen_mode(%L,%L)',current_setting('test.kitchen'),'couple'),'Only the kitchen owner');
select public.test_expect_error(format('select public.revoke_kitchen_invite(%L,%L)',current_setting('test.kitchen'),current_setting('test.late_join')),'Only the kitchen owner');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true) as ignored \gset
select public.test_expect_error(format('select public.join_kitchen(%L,%L)',current_setting('test.invite'),'Third'),'Invitation is unavailable or expired');
select public.test_assert((select count(*) = 0 from public.my_kitchens()),'Consumed invitation leaked a membership');
select public.test_expect_error(format('select public.update_own_profile(%L,%L,%L,%L)',current_setting('test.kitchen'),'Hacker','😀','{}'),'Household membership required');
select public.test_assert((select count(*) = 0 from public.household_members),'Outsider could read members');
select public.test_expect_error('select public.close_due_dinners()','permission denied');
reset role;
set local role anon;
select public.test_expect_error('select public.my_kitchens()','permission denied');
select public.test_expect_error(format('select public.join_kitchen(%L,%L)',current_setting('test.late_join'),'Anon'),'permission denied');
reset role;
set local role authenticated;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true) as ignored \gset
select set_config('test.session',public.open_dinner(current_setting('test.kitchen')::uuid,now()+interval '1 hour')::text,true) as ignored \gset
select set_config('test.first',public.add_pitch(current_setting('test.session')::uuid,'pasta')::text,true) as ignored \gset
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true) as ignored \gset
select public.test_expect_error(format('select public.remove_pitch(%L,%L)',current_setting('test.session'),'pasta'),'Only the nominator or chef');
select public.add_pitch(current_setting('test.session')::uuid,'soup');
select public.remove_pitch(current_setting('test.session')::uuid,'soup');
select set_config('test.second',public.add_pitch(current_setting('test.session')::uuid,'soup')::text,true) as ignored \gset
select public.save_diner_preferences(current_setting('test.session')::uuid,true,array['Mild spice'],'Home at six');
select public.test_expect_error(format('select public.cancel_dinner(%L)',current_setting('test.session')),'Only the chef');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true) as ignored \gset
select public.start_voting(current_setting('test.session')::uuid);
select public.test_assert((select count(*) = 2 from public.diner_orders),'Voting did not snapshot both members');
select public.test_assert(exists(select 1 from public.diner_orders where diner_note = 'Home at six' and submitted_at is null),'Opening voting lost saved order preferences');
select public.test_expect_error(format('select public.set_kitchen_mode(%L,%L)',current_setting('test.kitchen'),'couple'),'before voting starts');
select public.test_expect_error(format('select public.remove_pitch(%L,%L)',current_setting('test.session'),'pasta'),'Nominations are closed');
select public.test_expect_error(format('select public.submit_order(%L,%L)',current_setting('test.session'),'[]'),'reaction for every dish');
select public.submit_order(current_setting('test.session')::uuid,jsonb_build_array(jsonb_build_object('pitch_id',current_setting('test.first'),'weight',2),jsonb_build_object('pitch_id',current_setting('test.second'),'weight',0)));
select public.test_assert(public.expire_voting(current_setting('test.session')::uuid) is null,'A future deadline was expired');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true) as ignored \gset
select public.test_expect_error(format('select public.join_kitchen(%L,%L)',current_setting('test.late_join'),'Third'),'Join after the current dinner');
select public.test_expect_error(format('select public.expire_voting(%L)',current_setting('test.session')),'Household membership required');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true) as ignored \gset
select public.submit_order(current_setting('test.session')::uuid,jsonb_build_array(jsonb_build_object('pitch_id',current_setting('test.first'),'weight',1),jsonb_build_object('pitch_id',current_setting('test.second'),'weight',2)));
select public.test_assert((public.kitchen_snapshot(current_setting('test.kitchen')::uuid)->'session'->>'winning_pitch_id')::uuid = current_setting('test.first')::uuid,'Complete family vote did not choose pasta');
select set_config('test.snapshot',public.kitchen_snapshot(current_setting('test.kitchen')::uuid)::text,true) as ignored \gset
select public.test_expect_error(format('select public.submit_order(%L,%L)',current_setting('test.session'),'[]'),'Voting has closed');
select public.test_expect_error(format('select public.advance_kitchen(%L,%L)',current_setting('test.session'),'cooking'),'Only the chef');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true) as ignored \gset
select public.test_assert(public.kitchen_snapshot(current_setting('test.kitchen')::uuid) = current_setting('test.snapshot')::jsonb,'Two member identities received different authoritative tickets');
select public.test_expect_error(format('select public.cancel_dinner(%L)',current_setting('test.session')),'confirmed dinner');
select public.test_expect_error(format('select public.advance_kitchen(%L,%L,999)',current_setting('test.session'),'cooking'),'Invalid cooking step');
select public.advance_kitchen(current_setting('test.session')::uuid,'cooking');
select public.advance_kitchen(current_setting('test.session')::uuid,'served');
select public.test_assert(public.kitchen_snapshot(current_setting('test.kitchen')::uuid)->'session'->>'status' = 'served','Reconnect snapshot lost last served dinner');

-- An overdue partial family poll closes from a member RPC (same resolver as Cron).
select set_config('test.deadline_session',public.open_dinner(current_setting('test.kitchen')::uuid,now()+interval '1 hour')::text,true) as ignored \gset
select set_config('test.deadline_first',public.add_pitch(current_setting('test.deadline_session')::uuid,'pasta')::text,true) as ignored \gset
select set_config('test.deadline_second',public.add_pitch(current_setting('test.deadline_session')::uuid,'soup')::text,true) as ignored \gset
select public.start_voting(current_setting('test.deadline_session')::uuid);
select public.submit_order(current_setting('test.deadline_session')::uuid,jsonb_build_array(jsonb_build_object('pitch_id',current_setting('test.deadline_first'),'weight',0),jsonb_build_object('pitch_id',current_setting('test.deadline_second'),'weight',2)));
reset role;
update public.dinner_sessions set voting_deadline = now()-interval '1 second' where id = current_setting('test.deadline_session')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true) as ignored \gset
select public.test_expect_error(format('select public.submit_order(%L,%L)',current_setting('test.deadline_session'),'[]'),'Voting deadline has passed');
select public.test_assert(public.expire_voting(current_setting('test.deadline_session')::uuid) = current_setting('test.deadline_second')::uuid,'Deadline failed to lock submitted family winner');
select public.test_assert(public.expire_voting(current_setting('test.deadline_session')::uuid) = current_setting('test.deadline_second')::uuid,'Deadline retry changed the winner');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true) as ignored \gset
select public.advance_kitchen(current_setting('test.deadline_session')::uuid,'cooking');
select public.advance_kitchen(current_setting('test.deadline_session')::uuid,'served');

-- Trusted worker closes a due family poll while phones are closed. No-ballot
-- polls remain unresolved and can be extended/cancelled by their chef.
select set_config('test.worker',public.open_dinner(current_setting('test.kitchen')::uuid,now()+interval '1 hour')::text,true) as ignored \gset
select set_config('test.worker_first',public.add_pitch(current_setting('test.worker')::uuid,'pasta')::text,true) as ignored \gset
select set_config('test.worker_second',public.add_pitch(current_setting('test.worker')::uuid,'soup')::text,true) as ignored \gset
select public.start_voting(current_setting('test.worker')::uuid);
reset role;
update public.dinner_sessions set voting_deadline = now()-interval '1 second' where id = current_setting('test.worker')::uuid;
select public.test_assert(public.close_due_dinners() = 0,'Empty family poll invented a winner');
set local role authenticated;
select public.extend_voting(current_setting('test.worker')::uuid,now()+interval '2 hours');
select public.submit_order(current_setting('test.worker')::uuid,jsonb_build_array(jsonb_build_object('pitch_id',current_setting('test.worker_first'),'weight',2),jsonb_build_object('pitch_id',current_setting('test.worker_second'),'weight',0)));
reset role;
update public.dinner_sessions set voting_deadline = now()-interval '1 second' where id = current_setting('test.worker')::uuid;
select public.test_assert(public.close_due_dinners() = 1,'Worker did not close a due partial family poll');
select public.test_assert(public.close_due_dinners() = 0,'Worker repeated an already committed winner');
select public.test_assert(not has_function_privilege('authenticated','public.close_due_dinners()','EXECUTE'),'Untrusted worker permission');
select public.test_assert(not has_schema_privilege('authenticated','order_home_private','USAGE'),'Private invitation schema exposed');
select public.test_assert(not has_table_privilege('authenticated','order_home_private.kitchen_invites','SELECT'),'Invitation hash table exposed');
do $$
begin
  if exists(select 1 from pg_roles where rolname='service_role') and not has_function_privilege('service_role','public.close_due_dinners()','EXECUTE') then raise exception 'Service worker has no execute grant'; end if;
end;
$$;
set local role authenticated;
select public.advance_kitchen(current_setting('test.worker')::uuid,'cooking');
select public.advance_kitchen(current_setting('test.worker')::uuid,'served');

-- Couple capacity, no fallback match, extension, draft invalidation and cancel.
select set_config('test.couple',public.create_kitchen('Two seats','couple','Alex')::text,true) as ignored \gset
select set_config('test.couple_invite',public.create_kitchen_invite(current_setting('test.couple')::uuid)->>'token',true) as ignored \gset
select set_config('test.couple_extra',public.create_kitchen_invite(current_setting('test.couple')::uuid)->>'token',true) as ignored \gset
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true) as ignored \gset
select public.join_kitchen(current_setting('test.couple_invite'),'Sam');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true) as ignored \gset
select public.test_expect_error(format('select public.join_kitchen(%L,%L)',current_setting('test.couple_extra'),'Third'),'already has two people');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true) as ignored \gset
select set_config('test.couple_session',public.open_dinner(current_setting('test.couple')::uuid,now()+interval '1 hour')::text,true) as ignored \gset
select set_config('test.couple_first',public.add_pitch(current_setting('test.couple_session')::uuid,'pasta')::text,true) as ignored \gset
select set_config('test.couple_second',public.add_pitch(current_setting('test.couple_session')::uuid,'soup')::text,true) as ignored \gset
select public.start_voting(current_setting('test.couple_session')::uuid);
select public.submit_order(current_setting('test.couple_session')::uuid,jsonb_build_array(jsonb_build_object('pitch_id',current_setting('test.couple_first'),'weight',2),jsonb_build_object('pitch_id',current_setting('test.couple_second'),'weight',0)));
select public.save_diner_preferences(current_setting('test.couple_session')::uuid,true,'{}','Updated draft');
select public.test_assert(not exists(select 1 from public.dish_votes where session_id = current_setting('test.couple_session')::uuid),'Changed draft retained stale votes');
select public.submit_order(current_setting('test.couple_session')::uuid,jsonb_build_array(jsonb_build_object('pitch_id',current_setting('test.couple_first'),'weight',2),jsonb_build_object('pitch_id',current_setting('test.couple_second'),'weight',0)));
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true) as ignored \gset
select public.submit_order(current_setting('test.couple_session')::uuid,jsonb_build_array(jsonb_build_object('pitch_id',current_setting('test.couple_first'),'weight',0),jsonb_build_object('pitch_id',current_setting('test.couple_second'),'weight',2)));
reset role;
update public.dinner_sessions set voting_deadline = now()-interval '1 second' where id = current_setting('test.couple_session')::uuid;
select public.test_assert(public.close_due_dinners() = 0,'Cron created a fallback couple winner');
set local role authenticated;
select public.test_assert(public.expire_voting(current_setting('test.couple_session')::uuid) is null,'Couple deadline invented a match');
select public.test_expect_error(format('select public.extend_voting(%L,now()+interval ''1 hour'')',current_setting('test.couple_session')),'Only the chef');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true) as ignored \gset
select public.extend_voting(current_setting('test.couple_session')::uuid,now()+interval '2 hours');
select public.test_expect_error(format('select public.extend_voting(%L,now()+interval ''1 hour'')',current_setting('test.couple_session')),'later deadline');
select public.cancel_dinner(current_setting('test.couple_session')::uuid);
select public.test_assert(public.kitchen_snapshot(current_setting('test.couple')::uuid)->'session' = 'null'::jsonb,'Cancelled unconfirmed poll remained active');

-- Owner cannot shrink a family with three members into a two-seat table.
select public.set_kitchen_mode(current_setting('test.couple')::uuid,'family');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true) as ignored \gset
select public.join_kitchen(current_setting('test.couple_extra'),'Third');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true) as ignored \gset
select public.test_expect_error(format('select public.set_kitchen_mode(%L,%L)',current_setting('test.couple'),'couple'),'at most two people');

reset role;
rollback;
\echo 'Shared kitchen, invitation, isolation, snapshot, voting and deadline checks passed.'
