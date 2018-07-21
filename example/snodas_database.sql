CREATE EXTENSION pg_tms CASCADE;


CREATE TABLE "snodas" (
  "snodas_id" serial PRIMARY KEY,
  "swe" raster NOT NULL,
  "depth" raster NOT NULL,
  "melt" raster NOT NULL,
  "sublimation" raster NOT NULL,
  "sublimation_blowing" raster NOT NULL,
  "precip_solid" raster NOT NULL,
  "precip_liquid" raster NOT NULL,
  "average_temp" raster NOT NULL,
  "date" date NOT NULL,
  -- swe constraints
  CONSTRAINT enforce_height_swe CHECK (st_height(swe) = 3351),
  CONSTRAINT enforce_nodata_values_swe CHECK (_raster_constraint_nodata_values(swe)::numeric(16,10)[] = '{-9999}'::numeric(16,10)[]),
  CONSTRAINT enforce_num_bands_swe CHECK (st_numbands(swe) = 1),
  CONSTRAINT enforce_out_db_swe CHECK (_raster_constraint_out_db(swe) = '{f}'::boolean[]),
  CONSTRAINT enforce_pixel_types_swe CHECK (_raster_constraint_pixel_types(swe) = '{16BSI}'::text[]),
  CONSTRAINT enforce_scalex_swe CHECK (st_scalex(swe)::numeric(25,10) = 0.00833333333333328::numeric(25,10)),
  CONSTRAINT enforce_scaley_swe CHECK (st_scaley(swe)::numeric(25,10) = (-0.00833333333333333)::numeric(25,10))
  -- depth constraints
  CONSTRAINT enforce_height_depth CHECK (st_height(depth) = 3351),
  CONSTRAINT enforce_nodata_values_depth CHECK (_raster_constraint_nodata_values(depth)::numeric(16,10)[] = '{-9999}'::numeric(16,10)[]),
  CONSTRAINT enforce_num_bands_depth CHECK (st_numbands(depth) = 1),
  CONSTRAINT enforce_out_db_depth CHECK (_raster_constraint_out_db(depth) = '{f}'::boolean[]),
  CONSTRAINT enforce_pixel_types_depth CHECK (_raster_constraint_pixel_types(depth) = '{16BSI}'::text[]),
  CONSTRAINT enforce_scalex_depth CHECK (st_scalex(depth)::numeric(25,10) = 0.00833333333333328::numeric(25,10)),
  CONSTRAINT enforce_scaley_depth CHECK (st_scaley(depth)::numeric(25,10) = (-0.00833333333333333)::numeric(25,10))
  -- melt constraints
  CONSTRAINT enforce_height_melt CHECK (st_height(melt) = 3351),
  CONSTRAINT enforce_nodata_values_melt CHECK (_raster_constraint_nodata_values(melt)::numeric(16,10)[] = '{-9999}'::numeric(16,10)[]),
  CONSTRAINT enforce_num_bands_melt CHECK (st_numbands(melt) = 1),
  CONSTRAINT enforce_out_db_melt CHECK (_raster_constraint_out_db(melt) = '{f}'::boolean[]),
  CONSTRAINT enforce_pixel_types_melt CHECK (_raster_constraint_pixel_types(melt) = '{16BSI}'::text[]),
  CONSTRAINT enforce_scalex_melt CHECK (st_scalex(melt)::numeric(25,10) = 0.00833333333333328::numeric(25,10)),
  CONSTRAINT enforce_scaley_melt CHECK (st_scaley(melt)::numeric(25,10) = (-0.00833333333333333)::numeric(25,10))
  -- sublimation constraints
  CONSTRAINT enforce_height_sublimation CHECK (st_height(sublimation) = 3351),
  CONSTRAINT enforce_nodata_values_sublimation CHECK (_raster_constraint_nodata_values(sublimation)::numeric(16,10)[] = '{-9999}'::numeric(16,10)[]),
  CONSTRAINT enforce_num_bands_sublimation CHECK (st_numbands(sublimation) = 1),
  CONSTRAINT enforce_out_db_sublimation CHECK (_raster_constraint_out_db(sublimation) = '{f}'::boolean[]),
  CONSTRAINT enforce_pixel_types_sublimation CHECK (_raster_constraint_pixel_types(sublimation) = '{16BSI}'::text[]),
  CONSTRAINT enforce_scalex_sublimation CHECK (st_scalex(sublimation)::numeric(25,10) = 0.00833333333333328::numeric(25,10)),
  CONSTRAINT enforce_scaley_sublimation CHECK (st_scaley(sublimation)::numeric(25,10) = (-0.00833333333333333)::numeric(25,10))
  -- sublimation_blowing constraints
  CONSTRAINT enforce_height_sublimation_blowing CHECK (st_height(sublimation_blowing) = 3351),
  CONSTRAINT enforce_nodata_values_sublimation_blowing CHECK (_raster_constraint_nodata_values(sublimation_blowing)::numeric(16,10)[] = '{-9999}'::numeric(16,10)[]),
  CONSTRAINT enforce_num_bands_sublimation_blowing CHECK (st_numbands(sublimation_blowing) = 1),
  CONSTRAINT enforce_out_db_sublimation_blowing CHECK (_raster_constraint_out_db(sublimation_blowing) = '{f}'::boolean[]),
  CONSTRAINT enforce_pixel_types_sublimation_blowing CHECK (_raster_constraint_pixel_types(sublimation_blowing) = '{16BSI}'::text[]),
  CONSTRAINT enforce_scalex_sublimation_blowing CHECK (st_scalex(sublimation_blowing)::numeric(25,10) = 0.00833333333333328::numeric(25,10)),
  CONSTRAINT enforce_scaley_sublimation_blowing CHECK (st_scaley(sublimation_blowing)::numeric(25,10) = (-0.00833333333333333)::numeric(25,10))
  -- precip_solid constraints
  CONSTRAINT enforce_height_precip_solid CHECK (st_height(precip_solid) = 3351),
  CONSTRAINT enforce_nodata_values_precip_solid CHECK (_raster_constraint_nodata_values(precip_solid)::numeric(16,10)[] = '{-9999}'::numeric(16,10)[]),
  CONSTRAINT enforce_num_bands_precip_solid CHECK (st_numbands(precip_solid) = 1),
  CONSTRAINT enforce_out_db_precip_solid CHECK (_raster_constraint_out_db(precip_solid) = '{f}'::boolean[]),
  CONSTRAINT enforce_pixel_types_precip_solid CHECK (_raster_constraint_pixel_types(precip_solid) = '{16BSI}'::text[]),
  CONSTRAINT enforce_scalex_precip_solid CHECK (st_scalex(precip_solid)::numeric(25,10) = 0.00833333333333328::numeric(25,10)),
  CONSTRAINT enforce_scaley_precip_solid CHECK (st_scaley(precip_solid)::numeric(25,10) = (-0.00833333333333333)::numeric(25,10))
  -- precip_liquid constraints
  CONSTRAINT enforce_height_precip_liquid CHECK (st_height(precip_liquid) = 3351),
  CONSTRAINT enforce_nodata_values_precip_liquid CHECK (_raster_constraint_nodata_values(precip_liquid)::numeric(16,10)[] = '{-9999}'::numeric(16,10)[]),
  CONSTRAINT enforce_num_bands_precip_liquid CHECK (st_numbands(precip_liquid) = 1),
  CONSTRAINT enforce_out_db_precip_liquid CHECK (_raster_constraint_out_db(precip_liquid) = '{f}'::boolean[]),
  CONSTRAINT enforce_pixel_types_precip_liquid CHECK (_raster_constraint_pixel_types(precip_liquid) = '{16BSI}'::text[]),
  CONSTRAINT enforce_scalex_precip_liquid CHECK (st_scalex(precip_liquid)::numeric(25,10) = 0.00833333333333328::numeric(25,10)),
  CONSTRAINT enforce_scaley_precip_liquid CHECK (st_scaley(precip_liquid)::numeric(25,10) = (-0.00833333333333333)::numeric(25,10))
  -- average_temp constraints
  CONSTRAINT enforce_height_average_temp CHECK (st_height(average_temp) = 3351),
  CONSTRAINT enforce_nodata_values_average_temp CHECK (_raster_constraint_nodata_values(average_temp)::numeric(16,10)[] = '{-9999}'::numeric(16,10)[]),
  CONSTRAINT enforce_num_bands_average_temp CHECK (st_numbands(average_temp) = 1),
  CONSTRAINT enforce_out_db_average_temp CHECK (_raster_constraint_out_db(average_temp) = '{f}'::boolean[]),
  CONSTRAINT enforce_pixel_types_average_temp CHECK (_raster_constraint_pixel_types(average_temp) = '{16BSI}'::text[]),
  CONSTRAINT enforce_scalex_average_temp CHECK (st_scalex(average_temp)::numeric(25,10) = 0.00833333333333328::numeric(25,10)),
  CONSTRAINT enforce_scaley_average_temp CHECK (st_scaley(average_temp)::numeric(25,10) = (-0.00833333333333333)::numeric(25,10))
);


CREATE TABLE "snodas_swe_tiles" (
  "tile_id" serial PRIMARY KEY,
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
  DELETE FROM snodas_swe_tiles WHERE parent = NEW.rid;
  
  -- do a 2.5 std dev stretch on the imagery
  stats := ST_SummaryStats(NEW.swe);
  lower := GREATEST(0, stats.mean - 2.5 * stats.stddev);
  upper := LEAST(32767, stats.mean + 2.5 * stats.stddev);
  warped := ST_Reclass(
    NEW.swe,
    1,
    '-32768-0):0, [0-' || lower || '):0, [' || lower || '-' || upper || ']:0-255, (' || upper || '-32767:255'::text,
    '8BUI'::text,
    0::double precision
  );
  
  -- reproject the raster to the output crs
  warped := ST_Transform(warped, 3857);
      
  -- generate the tiles inserting each into the tile table
  -- we override the defaults and generate zoom levels 0 through 7
  INSERT INTO snodas_swe_tiles
    (parent, rast, x, y, zoom)
  SELECT
    NEW.snodas_id, t.rast, t.x, t.y, t.z
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
  SELECT snodas_id FROM snodas WHERE date = _q_rdate INTO _q_parent_id;

  -- we try to get the tile rid and
  -- raster data for the request tile
  SELECT tile_id, rast
  FROM snodas_swe_tiles
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
    FROM snodas_swe_tiles
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
    INSERT INTO snodas_swe_tiles (
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
