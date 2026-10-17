-- Walked straight roads are served as walked ground, not as a gap.
--
-- The app breaks a route's line at any step over 500 m that is more than a
-- quarter of the whole route (iOS `RouteGaps.dominantStep`) — meant for the
-- drive between two halves of a paused walk. But a stored route is
-- Douglas-Peucker simplified, so a straight road collapses to ONE step, and an
-- out-and-back down one is two steps of ~40% each: the app cut both and drew
-- only the turns at the ends.
--
-- What tells them apart is the recorded distance. A drive adds ground the
-- workout never counted, so the route comes out longer than `workouts.distance`
-- by about the gap; a walked straight adds nothing. Across prod at the time,
-- `route − recorded > step / 2` separated the two cleanly (118 walks wrongly
-- cut, 37 real gaps kept). A step that passes is served with evenly spaced
-- points along it (each piece under the app's 500 m bar), which draws the same
-- line and no longer trips the rule — so every installed app version is fixed
-- without a release. Gaps, steps over 3 km (the app's `maxOnFootStep`) and
-- steps faster than 12 m/s (`maxOnFootSpeed`) are served untouched.
--
-- Applied in `servedRouteFrom` AFTER the privacy slice, with the decision made
-- on the FULL stored route: a trimmed route is shorter than its recorded
-- distance, which would otherwise pass a real gap as walked.

-- Metres between two points, haversine (the app's own `RouteGaps` metric).
CREATE OR REPLACE FUNCTION mad_route_step_m(
	p_lat1 double precision, p_lng1 double precision,
	p_lat2 double precision, p_lng2 double precision)
RETURNS double precision
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $fn$
	SELECT 2 * 6371000 * asin(least(1, sqrt(
		power(sin(radians(p_lat2 - p_lat1) / 2), 2)
		+ cos(radians(p_lat1)) * cos(radians(p_lat2)) * power(sin(radians(p_lng2 - p_lng1) / 2), 2))))
$fn$;
--> statement-breakpoint

-- The served route (p_times_out false) or its clock (true) with walked long
-- steps filled in. `p_route`/`p_times` are what `servedRouteFrom` would serve
-- (sliced for a non-owner); `p_full_route` is the stored route the decision is
-- made on; `p_recorded_m` the workout's recorded distance in metres. Returns
-- the input unchanged when no step qualifies, which is nearly every route.
-- Route and clock make the same decision from the same inputs, so they stay
-- 1:1; a clock that wasn't 1:1 to begin with is returned as is.
--
-- plpgsql over float arrays unpacked once: walking the jsonb point by point
-- through a helper cost ~1.7 ms on a 300-point route, this ~0.1 ms — the
-- same as `mad_route_slice_times`, which every served route already pays.
CREATE OR REPLACE FUNCTION mad_route_fill_walked_steps(
	p_route jsonb,
	p_times jsonb,
	p_full_route jsonb,
	p_recorded_m double precision,
	p_times_out boolean
)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $fn$
DECLARE
	v_unchanged jsonb := CASE WHEN p_times_out THEN p_times ELSE p_route END;
	v_lat double precision[];
	v_lng double precision[];
	v_t double precision[];
	v_n integer;
	v_i integer;
	v_k integer;
	v_kx double precision;
	v_aligned boolean;
	v_full_m double precision := 0;
	v_excess double precision;
	v_m double precision;
	v_f double precision;
	v_pieces integer;
	v_a jsonb;
	v_b jsonb;
	v_pts jsonb[] := '{}';
	v_ts jsonb[] := '{}';
BEGIN
	IF p_route IS NULL OR jsonb_typeof(p_route) <> 'array'
	   OR p_recorded_m IS NULL OR p_recorded_m <= 0 THEN
		RETURN v_unchanged;
	END IF;
	SELECT array_agg((e ->> 0)::double precision ORDER BY o),
	       array_agg((e ->> 1)::double precision ORDER BY o)
	  INTO v_lat, v_lng
	  FROM jsonb_array_elements(p_route) WITH ORDINALITY AS x(e, o);
	v_n := coalesce(array_length(v_lat, 1), 0);
	IF v_n < 2 THEN
		RETURN v_unchanged;
	END IF;
	v_aligned := p_times IS NOT NULL AND jsonb_typeof(p_times) = 'array'
		AND jsonb_array_length(p_times) = v_n;
	IF p_times_out AND NOT v_aligned THEN
		RETURN p_times;
	END IF;

	-- Fast path: no step the app would cut as long — over 500 m AND over a
	-- quarter of the SERVED route (what the app measures). Flat-earth metres
	-- with margin on both bars; exact haversine only on the slow path.
	v_kx := cos(radians(v_lat[1]));
	FOR v_i IN 2 .. v_n LOOP
		v_m := sqrt(power((v_lat[v_i] - v_lat[v_i - 1]) * 111195, 2)
			+ power((v_lng[v_i] - v_lng[v_i - 1]) * 111195 * v_kx, 2));
		v_full_m := v_full_m + v_m;
		v_f := greatest(coalesce(v_f, 0), v_m);
	END LOOP;
	IF v_f <= 450 OR v_f < 0.2 * v_full_m THEN
		RETURN v_unchanged;
	END IF;
	v_full_m := 0;
	v_f := NULL;

	-- The decision is made on the FULL stored route's length.
	SELECT coalesce(sum(m), 0) INTO v_full_m FROM (
		SELECT mad_route_step_m(
			lag((e ->> 0)::double precision) OVER w, lag((e ->> 1)::double precision) OVER w,
			(e ->> 0)::double precision, (e ->> 1)::double precision) AS m
		  FROM jsonb_array_elements(coalesce(p_full_route, p_route)) WITH ORDINALITY AS x(e, o)
		WINDOW w AS (ORDER BY o)) s;
	v_excess := v_full_m - p_recorded_m;

	IF v_aligned THEN
		SELECT array_agg(e::double precision ORDER BY o) INTO v_t
		  FROM jsonb_array_elements_text(p_times) WITH ORDINALITY AS x(e, o);
	END IF;

	FOR v_i IN 1 .. v_n LOOP
		v_a := p_route -> (v_i - 1);
		v_pts := v_pts || v_a;
		IF v_aligned THEN
			v_ts := v_ts || (p_times -> (v_i - 1));
		END IF;
		CONTINUE WHEN v_i = v_n;
		v_m := mad_route_step_m(v_lat[v_i], v_lng[v_i], v_lat[v_i + 1], v_lng[v_i + 1]);
		-- Not one the app cuts as long; a gap (route longer than recorded by
		-- at least half this step); or past the app's on-foot step / speed.
		CONTINUE WHEN v_m <= 500 OR v_m > 3000 OR v_excess > v_m / 2;
		CONTINUE WHEN v_aligned AND v_t[v_i + 1] > v_t[v_i]
			AND v_m / (v_t[v_i + 1] - v_t[v_i]) > 12;
		v_b := p_route -> v_i;
		v_pieces := ceil(v_m / 400)::integer;
		FOR v_k IN 1 .. v_pieces - 1 LOOP
			v_f := v_k::double precision / v_pieces;
			v_pts := v_pts || (
				jsonb_build_array(
					round((v_lat[v_i] + (v_lat[v_i + 1] - v_lat[v_i]) * v_f)::numeric, 5),
					round((v_lng[v_i] + (v_lng[v_i + 1] - v_lng[v_i]) * v_f)::numeric, 5))
				|| CASE WHEN jsonb_typeof(v_a -> 2) = 'number' AND jsonb_typeof(v_b -> 2) = 'number'
					THEN jsonb_build_array(round(((v_a ->> 2)::numeric
						+ ((v_b ->> 2)::numeric - (v_a ->> 2)::numeric) * v_f::numeric), 1))
					ELSE '[]'::jsonb END);
			IF v_aligned THEN
				v_ts := v_ts || to_jsonb(round((v_t[v_i] + (v_t[v_i + 1] - v_t[v_i]) * v_f)::numeric, 1));
			END IF;
		END LOOP;
	END LOOP;

	IF p_times_out THEN
		RETURN to_jsonb(v_ts);
	END IF;
	RETURN to_jsonb(v_pts);
END
$fn$;
