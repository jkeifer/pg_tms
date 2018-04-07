CREATE TABLE "snodas" (
  "rid" serial PRIMARY KEY,
  "rast" raster NOT NULL,
  "filename" text,
  "date" date NOT NULL,
  CONSTRAINT enforce_height_rast CHECK (st_height(rast) = 3351),
  CONSTRAINT enforce_nodata_values_rast CHECK (_raster_constraint_nodata_values(rast)::numeric(16,10)[] = '{-9999}'::numeric(16,10)[]),
  CONSTRAINT enforce_num_bands_rast CHECK (st_numbands(rast) = 1),
  CONSTRAINT enforce_out_db_rast CHECK (_raster_constraint_out_db(rast) = '{f}'::boolean[]),
  CONSTRAINT enforce_pixel_types_rast CHECK (_raster_constraint_pixel_types(rast) = '{16BSI}'::text[]),
  CONSTRAINT enforce_scalex_rast CHECK (st_scalex(rast)::numeric(25,10) = 0.00833333333333328::numeric(25,10)),
  CONSTRAINT enforce_scaley_rast CHECK (st_scaley(rast)::numeric(25,10) = (-0.00833333333333333)::numeric(25,10))
);


CREATE TABLE "snodas_tiles" (
  "rid" serial PRIMARY KEY,
  "parent" integer NOT NULL REFERENCES "snodas" ON DELETE CASCADE,
  "rast" raster,
  "x" integer NOT NULL CHECK (x >= 0),
  "y" integer NOT NULL CHECK (y >= 0),
  "zoom" smallint NOT NULL CHECK (zoom between 0 and 20)
  CONSTRAINT enforce_height_rast CHECK (st_height(rast) = 256),
  CONSTRAINT enforce_num_bands_rast CHECK (st_numbands(rast) = 1),
  CONSTRAINT enforce_out_db_rast CHECK (_raster_constraint_out_db(rast) = '{f}'::boolean[]),
  CONSTRAINT enforce_srid_rast CHECK (st_srid(rast) = 3857),
  CONSTRAINT enforce_width_rast CHECK (st_width(rast) = 256)
);


CREATE OR REPLACE FUNCTION tile_snodas()
RETURNS TRIGGER
LANGUAGE plpgsql VOLATILE
AS $$
DECLARE
  warped raster;
  stats summarystats;
  lower double precision;
  upper double precision;
BEGIN
  -- clean out old tiles so we can rebuild
  DELETE FROM snodas_tiles WHERE parent = NEW.rid;
  
  -- do a 2.5 std dev stretch on the imagery
  stats := ST_SummaryStats(NEW.rast);
  lower := GREATEST(0, stats.mean - 2.5 * stats.stddev);
  upper := LEAST(32767, stats.mean + 2.5 * stats.stddev);
  warped := ST_Reclass(
    NEW.rast,
    1,
    '-32768-0):0, [0-' || lower || '):0, [' || lower || '-' || upper || ']:0-255, (' || upper || '-32767:255'::text,
    '8BUI'::text,
    0::double precision
  );
  
  -- reproject the raster to the output crs
  warped := ST_Transform(warped, 3857);
      
  -- generate the tiles inserting each into the tile table
  -- we override the defaults and generate zoom levels 0 through 7
  INSERT INTO snodas_tiles
    (parent, rast, x, y, zoom)
  SELECT
    NEW.rid, t.rast, t.x, t.y, t.z
  FROM tms_build_tiles(warped, 0, 7) AS t;
  RETURN NULL;
END;
$$;

CREATE TRIGGER snodas_tile_trigger
AFTER INSERT OR UPDATE ON snodas
FOR EACH ROW EXECUTE PROCEDURE tile_snodas();


-- this function will dynamically create a
-- missing tile if we try to load one from
-- a higher zoom level and it is missing
-- we use this function for returning TMS
-- tiles throught the API
CREATE OR REPLACE FUNCTION snodas2png(
  _q_coord tms_tilecoordz,
  _q_rdate date,
  _q_resample bool DEFAULT true
)
RETURNS bytea
LANGUAGE plpgsql VOLATILE
AS $$
DECLARE
  _q_tile raster;
  _q_rid integer;
  _q_parent_id integer;
  _q_outrast raster;
BEGIN
  -- find the parent raster so we can query just its tiles
  SELECT rid FROM snodas WHERE date = _q_rdate INTO _q_parent_id;

  -- we try to get the tile rid and
  -- raster data for the request tile
  SELECT rid, rast
  FROM snodas_tiles
  WHERE
      x = _q_coord.x AND
      y = _q_coord.y AND
      zoom = _q_coord.z AND
      parent = _q_parent_id
  INTO _q_rid, _q_tile;

  -- if the tile rid is null then we don't have that tile
  -- so we can resample to create a new one, if requested
  IF _q_rid IS NULL AND _q_resample THEN
    _q_outrast := _q_coord::raster;
    SELECT tms_copy_to_tile(ST_Resample(rast, _q_outrast), _q_outrast)
    FROM snodas_tiles
    WHERE
      parent = _q_parent_id AND
      ST_Intersects(rast, _q_outrast)
    ORDER BY zoom DESC
    LIMIT 1
    INTO _q_tile;
    
    -- if the generated tile has no data then we just set it
    -- to null, reducing the size of the saved row
    IF _q_tile IS NOT NULL AND NOT tms_has_data(_q_tile) THEN
      _q_tile := NULL;
    END IF;
    
    -- we save the generated tile for next time
    INSERT INTO snodas_tiles (
      rast,
      parent,
      x,
      y,
      zoom
    ) VALUES (
      _q_tile,
      _q_parent_id,
      _q_coord.x,
      _q_coord.y,
      _q_coord.z
    );
  END IF;

  -- if the tile is null, either from the inital
  -- query or the resample, then we don't need to
  -- provide a png, as it would just be empty
  IF _q_tile IS NULL THEN
    RETURN NULL;
  END IF;

  -- otherwise we return the raster tile as a png
  RETURN (SELECT ST_AsPNG(_q_tile));
END;
$$;

