-- Required v2.0 website patch: return SHIELD deadline in safe state.
-- Only room members can call get_game_state; existing RLS remains in force.
CREATE OR REPLACE FUNCTION public.get_game_state(p_room_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE r public.rooms%ROWTYPE; m public.game_matches%ROWTYPE; ps jsonb; h text[]; loser uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT * INTO r FROM public.rooms WHERE room_code=p_room_code;
 IF r.id IS NULL OR NOT EXISTS (SELECT 1 FROM public.room_players WHERE room_id=r.id AND user_id=auth.uid()) THEN RAISE EXCEPTION 'Access denied'; END IF;
 SELECT * INTO m FROM public.game_matches WHERE room_id=r.id ORDER BY match_number DESC LIMIT 1;
 IF m.id IS NULL THEN RAISE EXCEPTION 'Match not initialized'; END IF;
 SELECT hand INTO h FROM public.game_players WHERE match_id=m.id AND user_id=auth.uid();
 SELECT coalesce(jsonb_agg(jsonb_build_object('user_id',gp.user_id,'name',rp.player_name,'seat',gp.seat,'debt',gp.debt,'escaped',gp.escaped,'hand_count',coalesce(array_length(gp.hand,1),0),'drawn_this_turn',gp.drawn_this_turn,'replaced_this_turn',gp.replaced_this_turn,'bounty_owner',gp.bounty_owner,'rematch_ready',gp.rematch_ready) ORDER BY gp.seat),'[]'::jsonb) INTO ps FROM public.game_players gp JOIN public.room_players rp ON rp.room_id=r.id AND rp.user_id=gp.user_id WHERE gp.match_id=m.id;
 IF m.status='finished' THEN SELECT user_id INTO loser FROM public.game_players WHERE match_id=m.id AND NOT escaped LIMIT 1; END IF;
 RETURN jsonb_build_object('match_id',m.id,'match_number',m.match_number,'status',m.status,'turn_user_id',m.turn_user_id,'round',m.round_number,'draw_count',coalesce(array_length(m.draw_pile,1),0),'discard_count',coalesce(array_length(m.discard_pile,1),0),'escape_order',to_jsonb(m.escape_order),'loser_user_id',loser,'pending_action',m.pending_action,'pending_deadline',m.pending_deadline,'last_action',m.last_action,'players',ps,'my_hand',to_jsonb(coalesce(h,ARRAY[]::text[])));
END; $$;
REVOKE ALL ON FUNCTION public.get_game_state(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_game_state(text) TO authenticated;
