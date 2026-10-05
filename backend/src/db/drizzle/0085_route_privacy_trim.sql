-- Custom SQL migration file, put your code below! --
-- Hide start & end (route privacy). Every read that serves a stored route to
-- someone other than its OWNER is bounded by mad_route_view_bounds, which trims
-- a jittered stretch off each end (the owner's notification_settings
-- .route_privacy_meters, NULL = 201 m) and re-bases the replay clock in
-- lockstep. Trim at READ, nothing stored or deleted: changing the setting
-- applies to every route already posted. Metadata-only (function DDL), so it
-- is instant at boot. The Swift mirror is Utils/RoutePrivacyTrim.swift — the
-- hash, the jitter and the distance formula must stay identical.

-- FNV-1a (32-bit) over the workout id's UTF-8 bytes. Deterministic per
-- workout, so repeated views of one route always trim the same way and can't
-- be averaged back to the true endpoints.
CREATE OR REPLACE FUNCTION mad_route_jitter_hash(p_workout_id text)
RETURNS bigint
LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE AS $fn$
DECLARE
	h bigint := 2166136261;
	b bytea := convert_to(p_workout_id, 'UTF8');
	i integer;
BEGIN
	FOR i IN 0 .. length(b) - 1 LOOP
		h := ((h # get_byte(b, i)) * 16777619) % 4294967296;
	END LOOP;
	RETURN h;
END
$fn$;
--> statement-breakpoint

-- The actual cut at each end: the setting scaled by 0.9–1.3 (start from the
-- hash's low 16 bits, end from the next 16), so a 1/8 mile setting cuts
-- ~181–261 m and the two ends differ.
CREATE OR REPLACE FUNCTION mad_route_privacy_cuts(
	p_workout_id text,
	p_setting_m integer,
	OUT cut_start double precision,
	OUT cut_end double precision
)
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $fn$
DECLARE
	h bigint := mad_route_jitter_hash(COALESCE(p_workout_id, ''));
BEGIN
	cut_start := p_setting_m * (0.9 + 0.4 * ((h & 65535)::double precision / 65535.0));
	cut_end := p_setting_m * (0.9 + 0.4 * (((h >> 16) & 65535)::double precision / 65535.0));
END
$fn$;
--> statement-breakpoint

-- 1-based [i_s, i_e] of the points a non-owner may see, or NULLs when what
-- would be left is a sliver (under 300 m, or under 40% of the whole route) —
-- then nothing is served at all, exactly like maps-off.
--
-- A boundary point must be at least the cut away from its true endpoint BOTH
-- along the path AND in a straight line, so a walk that loops around the
-- block before leaving can't leave its first kept point beside the front
-- door. Equirectangular distance (exact enough at these lengths, and the
-- cheapest formula to mirror bit-for-bit on the phone). A plain loop with
-- early exits, not window functions: ~10x cheaper, and this runs per served
-- route on the feed's page.
CREATE OR REPLACE FUNCTION mad_route_trim_bounds(
	p_route jsonb,
	p_cut_start double precision,
	p_cut_end double precision,
	OUT i_s integer,
	OUT i_e integer
)
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $fn$
DECLARE
	lat double precision[];
	lng double precision[];
	n integer;
	i integer;
	c double precision;
	k double precision;
	cs double precision;
	ce double precision;
	mid double precision;
	thr double precision;
BEGIN
	SELECT array_agg((t.e ->> 0)::double precision ORDER BY t.o),
	       array_agg((t.e ->> 1)::double precision ORDER BY t.o)
	  INTO lat, lng
	  FROM jsonb_array_elements(p_route) WITH ORDINALITY AS t(e, o);
	n := COALESCE(array_length(lat, 1), 0);
	IF n < 3 THEN
		RETURN;
	END IF;

	c := 0;
	FOR i IN 2 .. n LOOP
		k := cos((lat[i - 1] + lat[i]) * 0.5 * 0.017453292519943295);
		c := c + 6371008.8 * sqrt(
			((lat[i] - lat[i - 1]) * 0.017453292519943295) ^ 2
			+ ((lng[i] - lng[i - 1]) * 0.017453292519943295 * k) ^ 2);
		IF c >= p_cut_start THEN
			k := cos((lat[1] + lat[i]) * 0.5 * 0.017453292519943295);
			IF 6371008.8 * sqrt(
				((lat[i] - lat[1]) * 0.017453292519943295) ^ 2
				+ ((lng[i] - lng[1]) * 0.017453292519943295 * k) ^ 2) >= p_cut_start THEN
				i_s := i;
				cs := c;
				EXIT;
			END IF;
		END IF;
	END LOOP;
	IF i_s IS NULL THEN
		RETURN;
	END IF;

	c := 0;
	FOR i IN REVERSE n - 1 .. 1 LOOP
		k := cos((lat[i + 1] + lat[i]) * 0.5 * 0.017453292519943295);
		c := c + 6371008.8 * sqrt(
			((lat[i] - lat[i + 1]) * 0.017453292519943295) ^ 2
			+ ((lng[i] - lng[i + 1]) * 0.017453292519943295 * k) ^ 2);
		IF c >= p_cut_end THEN
			k := cos((lat[n] + lat[i]) * 0.5 * 0.017453292519943295);
			IF 6371008.8 * sqrt(
				((lat[i] - lat[n]) * 0.017453292519943295) ^ 2
				+ ((lng[i] - lng[n]) * 0.017453292519943295 * k) ^ 2) >= p_cut_end THEN
				i_e := i;
				ce := c;
				EXIT;
			END IF;
		END IF;
	END LOOP;
	IF i_e IS NULL OR i_e <= i_s THEN
		i_s := NULL;
		i_e := NULL;
		RETURN;
	END IF;

	-- kept >= 0.4 * (cs + kept + ce)  <=>  kept >= (2/3) * (cs + ce)
	thr := greatest(300.0, (cs + ce) * 2.0 / 3.0);
	mid := 0;
	FOR i IN i_s + 1 .. i_e LOOP
		k := cos((lat[i - 1] + lat[i]) * 0.5 * 0.017453292519943295);
		mid := mid + 6371008.8 * sqrt(
			((lat[i] - lat[i - 1]) * 0.017453292519943295) ^ 2
			+ ((lng[i] - lng[i - 1]) * 0.017453292519943295 * k) ^ 2);
		EXIT WHEN mid >= thr;
	END LOOP;
	IF mid < thr THEN
		i_s := NULL;
		i_e := NULL;
	END IF;
END
$fn$;
--> statement-breakpoint

-- Every offered setting's bounds for one route, as the jsonb cached in
-- workout_routes.privacy_bounds: {"201":[i_s,i_e] | null, "402":…, "805":…,
-- "1609":…}. Must list exactly ROUTE_PRIVACY_OPTIONS (routePrivacy.ts) minus
-- 0; a setting missing here is simply computed at read.
CREATE OR REPLACE FUNCTION mad_route_privacy_bounds(p_route jsonb, p_workout_id text)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $fn$
DECLARE
	v_out jsonb := '{}'::jsonb;
	v_setting integer;
	v_cut_s double precision;
	v_cut_e double precision;
	v_is integer;
	v_ie integer;
BEGIN
	IF p_route IS NULL OR jsonb_typeof(p_route) <> 'array' THEN
		RETURN NULL;
	END IF;
	FOREACH v_setting IN ARRAY ARRAY[201, 402, 805, 1609] LOOP
		SELECT c.cut_start, c.cut_end INTO v_cut_s, v_cut_e
		  FROM mad_route_privacy_cuts(p_workout_id, v_setting) c;
		SELECT b.i_s, b.i_e INTO v_is, v_ie
		  FROM mad_route_trim_bounds(p_route, v_cut_s, v_cut_e) b;
		v_out := v_out || jsonb_build_object(
			v_setting::text,
			CASE WHEN v_is IS NULL THEN NULL ELSE jsonb_build_array(v_is, v_ie) END);
	END LOOP;
	RETURN v_out;
END
$fn$;
--> statement-breakpoint

-- What THIS viewer may see of a route, as 1-based point bounds:
--   full_route  → the stored row untouched (the owner; an owner whose
--                 setting is 0)
--   i_s NULL    → nothing at all (a sliver) — the caller drops the row, so a
--                 friend can't tell it from maps-off
--   otherwise   → points i_s..i_e, the clock sliced and re-based with them.
-- The owner's setting is looked up HERE (no row / NULL = 201 m) so no caller
-- can pass the wrong one. `p_bounds` is the row's cached privacy_bounds; a
-- NULL cache or a setting it doesn't list is computed on the spot. The cached
-- path never reads the polyline itself (it is TOASTed; detoasting it per
-- served column was most of the cost).
CREATE OR REPLACE FUNCTION mad_route_view_bounds(
	p_route jsonb,
	p_point_count integer,
	p_bounds jsonb,
	p_workout_id text,
	p_owner_id text,
	p_is_owner boolean,
	OUT i_s integer,
	OUT i_e integer,
	OUT full_route boolean
)
LANGUAGE plpgsql STABLE PARALLEL SAFE AS $fn$
DECLARE
	v_setting integer;
	v_key text;
	v_cut_s double precision;
	v_cut_e double precision;
BEGIN
	full_route := false;
	IF p_route IS NULL THEN
		RETURN;
	END IF;
	IF COALESCE(p_is_owner, false) THEN
		full_route := true;
	ELSE
		SELECT ns.route_privacy_meters INTO v_setting
		  FROM notification_settings ns
		 WHERE ns.user_id = p_owner_id;
		v_setting := COALESCE(v_setting, 201);
		full_route := v_setting <= 0;
	END IF;
	IF full_route THEN
		i_s := 1;
		i_e := p_point_count;
		RETURN;
	END IF;
	v_key := v_setting::text;
	IF p_bounds IS NOT NULL AND jsonb_typeof(p_bounds) = 'object' AND p_bounds ? v_key THEN
		IF jsonb_typeof(p_bounds -> v_key) = 'array' THEN
			i_s := (p_bounds -> v_key ->> 0)::integer;
			i_e := (p_bounds -> v_key ->> 1)::integer;
		END IF;
		RETURN;
	END IF;
	IF jsonb_typeof(p_route) <> 'array' THEN
		RETURN;
	END IF;
	SELECT c.cut_start, c.cut_end INTO v_cut_s, v_cut_e
	  FROM mad_route_privacy_cuts(p_workout_id, v_setting) c;
	SELECT b.i_s, b.i_e INTO i_s, i_e
	  FROM mad_route_trim_bounds(p_route, v_cut_s, v_cut_e) b;
END
$fn$;
--> statement-breakpoint

-- Points i_s..i_e of a route (every element of each point kept — an
-- optional third, altitude, survives). jsonpath slicing: C-level, ~3x
-- cheaper than unnesting and re-aggregating the polyline.
CREATE OR REPLACE FUNCTION mad_route_slice(p_route jsonb, p_is integer, p_ie integer)
RETURNS jsonb
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
	SELECT jsonb_path_query_array(
		p_route, '$[$a to $b]', jsonb_build_object('a', p_is - 1, 'b', p_ie - 1))
$fn$;
--> statement-breakpoint

-- The replay clock for points i_s..i_e, re-based so the first kept point is
-- 0. A clock that doesn't line up 1:1 with the route (`p_point_count`) is
-- served as NO clock, never paired with a trimmed line.
CREATE OR REPLACE FUNCTION mad_route_slice_times(p_times jsonb, p_point_count integer, p_is integer, p_ie integer)
RETURNS jsonb
-- plpgsql, not sql: a SQL-language body with a sub-SELECT can't be inlined,
-- and the non-inlined SQL-function path cost ~0.4 ms a call here against
-- ~0.05 ms for a plpgsql body whose plan is cached for the session.
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $fn$
DECLARE
	v_t0 numeric;
	v_out jsonb;
BEGIN
	IF p_times IS NULL OR jsonb_typeof(p_times) <> 'array'
	   OR jsonb_array_length(p_times) <> p_point_count THEN
		RETURN NULL;
	END IF;
	v_t0 := (p_times ->> (p_is - 1))::numeric;
	SELECT jsonb_agg(t.e::numeric - v_t0 ORDER BY t.o) INTO v_out
	  FROM jsonb_array_elements(jsonb_path_query_array(
		p_times, '$[$a to $b]', jsonb_build_object('a', p_is - 1, 'b', p_ie - 1)))
	  WITH ORDINALITY AS t(e, o);
	RETURN v_out;
END
$fn$;
--> statement-breakpoint

-- The first KEPT fix's instant: started_at moved by the seconds cut. NULL
-- without an aligned clock (the instant would describe a point not served).
CREATE OR REPLACE FUNCTION mad_route_shift_start(p_started_at timestamptz, p_times jsonb, p_point_count integer, p_is integer)
RETURNS timestamptz
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
	SELECT CASE
		WHEN p_times IS NULL OR jsonb_typeof(p_times) <> 'array'
		  OR jsonb_array_length(p_times) <> p_point_count THEN NULL
		ELSE p_started_at + make_interval(secs => (p_times ->> (p_is - 1))::double precision)
	END
$fn$;
