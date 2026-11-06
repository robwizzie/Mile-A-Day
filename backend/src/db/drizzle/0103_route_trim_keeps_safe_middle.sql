-- Show friends the part of a route that is safe to show, however short, rather
-- than nothing. Hide start & end still applies in full: both cuts, along the
-- path and in a straight line. Mirrored in Utils/RoutePrivacyTrim.swift.
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

	-- Serve whatever is safe. The cuts above are the privacy rule; this only
	-- drops a line too short to draw. Was greatest(300, 2/3 of the cuts), which
	-- hid the whole route on ordinary walks with a perfectly safe middle.
	thr := 30.0;
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

-- `privacy_bounds` is a cache, and only rows with a hidden setting can change.
-- Clearing it is safe: a NULL is computed at read, and removing the marker
-- lets the boot backfill refill these rows in batches.
UPDATE workout_routes SET privacy_bounds = NULL
 WHERE privacy_bounds IS NOT NULL AND privacy_bounds::text LIKE '%null%';
--> statement-breakpoint
DELETE FROM maintenance_runs WHERE name = 'route_privacy_bounds_v1';
