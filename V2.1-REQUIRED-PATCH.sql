-- LAST DEBT v2.1: turn choices + first rematch draw
-- Run once in Supabase SQL Editor BEFORE using v2.1 website.
BEGIN;

-- Shared server-side turn validation; each action locks the match.
CREATE OR REPLACE FUNCTION public.skip_turn_pushups(p_room_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_match public.game_matches%ROWTYPE; v_room uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
 SELECT id INTO v_room FROM public.rooms WHERE room_code=p_room_code AND status='playing';
 IF v_room IS NULL OR NOT EXISTS (SELECT 1 FROM public.room_players WHERE room_id=v_room AND user_id=auth.uid()) THEN RAISE EXCEPTION 'Room unavailable'; END IF;
 SELECT * INTO v_match FROM public.game_matches WHERE room_id=v_room AND status='playing' ORDER BY match_number DESC LIMIT 1 FOR UPDATE;
 IF v_match.id IS NULL OR v_match.turn_user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Not your turn'; END IF;
 IF v_match.pending_action IS NOT NULL THEN RAISE EXCEPTION 'Resolve reaction first'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.game_players WHERE match_id=v_match.id AND user_id=auth.uid() AND NOT escaped) THEN RAISE EXCEPTION 'Player not active'; END IF;
 UPDATE public.game_matches SET last_action='💪 Player skipped their turn: 5 push-ups!' WHERE id=v_match.id;
 PERFORM public.advance_game_turn(v_match.id);
 RETURN public.get_game_state(p_room_code);
END; $$;

CREATE OR REPLACE FUNCTION public.reroll_card_pushups(p_room_code text, p_card text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_match public.game_matches%ROWTYPE; v_player public.game_players%ROWTYPE;
 v_room uuid; v_deck text[]; v_discard text[]; v_hand text[]; v_index int; v_pick int; v_new text;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
 SELECT id INTO v_room FROM public.rooms WHERE room_code=p_room_code AND status='playing';
 IF v_room IS NULL OR NOT EXISTS (SELECT 1 FROM public.room_players WHERE room_id=v_room AND user_id=auth.uid()) THEN RAISE EXCEPTION 'Room unavailable'; END IF;
 SELECT * INTO v_match FROM public.game_matches WHERE room_id=v_room AND status='playing' ORDER BY match_number DESC LIMIT 1 FOR UPDATE;
 IF v_match.id IS NULL OR v_match.turn_user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Not your turn'; END IF;
 IF v_match.pending_action IS NOT NULL THEN RAISE EXCEPTION 'Resolve reaction first'; END IF;
 SELECT * INTO v_player FROM public.game_players WHERE match_id=v_match.id AND user_id=auth.uid() FOR UPDATE;
 IF v_player.user_id IS NULL OR v_player.escaped THEN RAISE EXCEPTION 'Player not active'; END IF;
 IF v_player.replaced_this_turn THEN RAISE EXCEPTION 'Already swapped a card this turn'; END IF;
 v_index:=array_position(v_player.hand,p_card);
 IF v_index IS NULL THEN RAISE EXCEPTION 'Select a card from your hand'; END IF;
 v_deck:=coalesce(v_match.draw_pile,ARRAY[]::text[]);
 v_discard:=coalesce(v_match.discard_pile,ARRAY[]::text[]);
 -- Draw only from deck or PREVIOUS discard. Never redraw the card just submitted.
 IF coalesce(array_length(v_deck,1),0)=0 AND coalesce(array_length(v_discard,1),0)>0 THEN
   SELECT coalesce(array_agg(x ORDER BY random()),ARRAY[]::text[]) INTO v_deck FROM unnest(v_discard) AS x;
   v_discard:=ARRAY[]::text[];
 END IF;
 IF coalesce(array_length(v_deck,1),0)=0 THEN RAISE EXCEPTION 'No cards available to swap'; END IF;
 v_pick:=1+floor(random()*array_length(v_deck,1))::int;
 v_new:=v_deck[v_pick];
 v_deck:=coalesce(v_deck[1:v_pick-1],ARRAY[]::text[]) || coalesce(v_deck[v_pick+1:array_length(v_deck,1)],ARRAY[]::text[]);
 v_hand:=v_player.hand;
 v_hand[v_index]:=v_new;
 v_discard:=array_append(v_discard,p_card);
 UPDATE public.game_players SET hand=v_hand,replaced_this_turn=true WHERE match_id=v_match.id AND user_id=auth.uid();
 UPDATE public.game_matches SET draw_pile=v_deck,discard_pile=v_discard,last_action='💪 Player swapped a random card: 10 push-ups!' WHERE id=v_match.id;
 RETURN public.get_game_state(p_room_code);
END; $$;

-- Rematch: once all three new game_players are dealt, draw a third card
-- for the starting player. Initial starts already have three and are unaffected.
CREATE OR REPLACE FUNCTION public.fix_rematch_first_draw()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_match public.game_matches%ROWTYPE; v_first uuid; v_hand text[]; v_card text[];
BEGIN
 SELECT * INTO v_match FROM public.game_matches WHERE id=NEW.match_id FOR UPDATE;
 IF (SELECT count(*) FROM public.game_players WHERE match_id=NEW.match_id) <> 3 THEN RETURN NEW; END IF;
 v_first:=v_match.turn_user_id;
 SELECT hand INTO v_hand FROM public.game_players WHERE match_id=NEW.match_id AND user_id=v_first;
 IF coalesce(array_length(v_hand,1),0)<>2 OR coalesce(array_length(v_match.draw_pile,1),0)=0 THEN RETURN NEW; END IF;
 v_card:=v_match.draw_pile;
 UPDATE public.game_players SET hand=array_append(hand,v_card[1]),drawn_this_turn=true WHERE match_id=NEW.match_id AND user_id=v_first;
 UPDATE public.game_matches SET draw_pile=coalesce(v_card[2:array_length(v_card,1)],ARRAY[]::text[]) WHERE id=NEW.match_id;
 RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS lastdebt_rematch_first_draw ON public.game_players;
CREATE TRIGGER lastdebt_rematch_first_draw AFTER INSERT ON public.game_players FOR EACH ROW EXECUTE FUNCTION public.fix_rematch_first_draw();

REVOKE ALL ON FUNCTION public.skip_turn_pushups(text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.reroll_card_pushups(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.skip_turn_pushups(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reroll_card_pushups(text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.fix_rematch_first_draw() FROM PUBLIC,anon,authenticated;
COMMIT;
