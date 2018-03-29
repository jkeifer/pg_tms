\echo Use "CREATE EXTENSION pg_tms" to load this file. \quit

---------------
-- pg_tms types
---------------

CREATE TYPE tms_latlon AS (lat double precision, lon double precision);
CREATE TYPE tms_latlon_ext AS (
  minlat double precision,
  minlon double precision,
  maxlat double precision,
  maxlon double precision
);

CREATE TYPE tms_meters AS (x double precision, y double precision);
CREATE TYPE tms_meters_ext AS (
  minx double precision,
  miny double precision,
  maxx double precision,
  maxy double precision
);

CREATE TYPE tms_pixels AS (x int, y int);

CREATE TYPE tms_tilecoord AS (x int, y int);
CREATE TYPE tms_tilecoordz AS (x int, y int, z int);
CREATE TYPE tms_tilecoord_ext AS (minx int, miny int, maxx int, maxy int);

CREATE TYPE tms_tile AS (rast raster, x int, y int, z int);


--------------------
-- pg_tms type casts
--------------------

CREATE FUNCTION tms_tilecoordz2raster(coords tms_tilecoordz)
RETURNS raster
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  ext tms_meters_ext;
  res double precision;
BEGIN
  ext := coords::tms_meters_ext;
  SELECT
    tms_resolution(coords.z)
  INTO res;
  RETURN (SELECT ST_MakeEmptyRaster(
    256,
    256,
    ext.minx,
    ext.miny,
    res,
    res,
    0,
    0,
    3857
  ));
END;
$$;

CREATE CAST (tms_tilecoordz AS raster)
  WITH FUNCTION tms_tilecoordz2raster(tms_tilecoordz)
  AS ASSIGNMENT;

CREATE FUNCTION tms_tilecoordz2polygon(coords tms_tilecoordz)
RETURNS geometry
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  ext tms_meters_ext;
BEGIN
  ext := coords::tms_meters_ext;
  RETURN (SELECT ST_MakeEnvelop(
    ext.minx,
    ext.miny,
    ext.maxx,
    ext.maxy
  ), 3857);
END;
$$;

CREATE CAST (tms_tilecoordz AS geometry)
  WITH FUNCTION tms_tilecoordz2polygon(tms_tilecoordz)
  AS ASSIGNMENT;


------------------------
-- pg_tms base functions
------------------------

CREATE FUNCTION tms_initialresolution()
RETURNS double precision
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  -- 6378137 is the radius of the earth in m
  -- 256 is the tile size
  RETURN(SELECT 2 * pi() * 6378137 / 256);
END;
$$;

CREATE FUNCTION tms_originshift()
RETURNS double precision
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  -- 6378137 is the radius of the earth in m
  RETURN(SELECT 2 * pi() * 6378137 / 2.0);
END;
$$;

CREATE FUNCTION tms_resolution(zoom int)
RETURNS double precision
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN(SELECT tms_initialresolution() / 2 ^ zoom);
END;
$$;

CREATE FUNCTION tms_zoomforpixelsize(pixelSize double precision)
RETURNS int
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  -- gdal2tile uses max zoom level of 32
  -- seems a little arbitray, but we'll go with it
  -- beyond that is too many tiles
  FOR i in 0..32 LOOP
    IF pixelSize > tms_resolution(i) THEN
      IF i != 0 THEN
        RETURN i - 1;
      ELSE
        RETURN 0;
      END IF;
    END IF;
  END LOOP;
END;
$$;


--------------------------
-- pg_tms tiling functions
--------------------------

CREATE FUNCTION tms_calc_zoom(
  input raster,
  zoom int
)
RETURNS tms_tilecoord_ext 
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  tminx int;
  tminy int;
  tmaxx int;
  tmaxy int;
  tox double precision;
  toy double precision;
BEGIN
  -- find the extent of the input raster in tile coords
  SELECT
    t.x, t.y
  FROM
    tms_meters2tile(ST_UpperLeftX(input), ST_UpperLeftY(input), zoom) AS t
  INTO tminx, tminy;
  SELECT
    t.x, t.y
  FROM
    tms_meters2tile(
      ST_UpperLeftX(input) + ST_Scalex(input) * ST_Width(input),
      ST_UpperLeftY(input) - ST_Scaley(input) * ST_Height(input),
      zoom
    ) AS t
  INTO tmaxx, tmaxy;

  -- we have to crop the top and bottom of the map
  -- if it falls outside the valid area
  tmaxx := (SELECT LEAST(2^zoom-1, tmaxx));
  tmaxy := (SELECT LEAST(2^zoom-1, tmaxy));

  RETURN (tminx, tminy, tmaxx, tmaxy)::tms_tilecoord_ext;
END;
$$;

CREATE FUNCTION tms_copy_to_tile(
  input raster,
  tile raster
)
RETURNS raster
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  output raster;
  bands int;
BEGIN
  SELECT ST_MakeEmptyRaster(tile) INTO output;
  SELECT ST_NumBands(input) into bands;
  FOR band in 1..bands LOOP
    tile := ST_AddBand(
      tile,
      band,
      ST_BandPixelType(input, band),
      ST_BandNoDataValue(input, band),
      ST_BandNoDataValue(input, band)
    );
    output := ST_AddBand(output, ST_MapAlgebra(input, band, tile, 1, '[rast1]', NULL, 'SECOND'));
  END LOOP;
  RETURN output;
END;
$$;

CREATE FUNCTION tms_tile_zoom(
  input raster,
  zoom int,
  algorithm text DEFAULT 'NearestNeighbor'
)
RETURNS SETOF tms_tile
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  resampled raster DEFAULT NULL;
  tile raster;
  tminx int;
  tminy int;
  tmaxx int;
  tmaxy int;
BEGIN
  -- find the extent of the input raster in tile coords
  SELECT
    t.minx, t.miny, t.maxx, t.maxy
  FROM
    tms_calc_zoom(input, zoom) AS t
  INTO
    tminx, tminy, tmaxx, tmaxy;

  -- generate the tiles for this zoom level
  FOR tx IN tminx..tmaxx LOOP
    FOR ty IN tminy..tmaxy LOOP
      -- We have to handle data crossing 180E, which could have
      -- invalid tile coords. So we mod by the number of x tiles.
      tx := tx % (2 ^ zoom)::int;

      RAISE DEBUG 'PROCESS TILE XYZ (%,%, %)', tx, ty, zoom;

      -- generate a blank raster for the tile
      SELECT (tx, ty, zoom)::tms_tilecoordz::raster INTO tile;
     
      -- if we haven't created the resampled raster, do so now
      IF resampled IS NULL THEN
        SELECT ST_Resample(input, tile, algorithm) INTO resampled;
      END IF;
      
      RETURN NEXT (tms_copy_to_tile(resampled, tile), tx, ty, zoom)::tms_tile;
    END LOOP;
  END LOOP;
  RETURN;
END
$$;

CREATE FUNCTION tms_build_tiles(
  input raster,
  min_zoom int DEFAULT -1,
  max_zoom int DEFAULT -1,
  algorithm text DEFAULT 'NearestNeighbor'
)
RETURNS SETOF tms_tile
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  _min_zoom int;
  _max_zoom int;
  tminx int;
  tminy int;
  tmaxx int;
  tmaxy int;
BEGIN
  IF ST_SRID(input) != 3857 THEN
    RAISE EXCEPTION 'Raster SRID is not 3857 or equivalent, rather is %', ST_SRID(input)
      USING HINT = 'Use ST_Transform to warp the input raster to 3857 before tiling';
  END IF;

  IF min_zoom = -1 THEN
    -- assumes raster is in 3857 thus pixels are square
    SELECT tms_zoomforpixelsize(
        (ST_Scalex(input) * GREATEST(ST_Height(input), ST_Width(input)) / 256)
    ) INTO _min_zoom;
  ELSE
    _min_zoom := min_zoom;
  END IF;
  RAISE INFO 'MIN ZOOM LEVEL %', _min_zoom;

  IF max_zoom = -1 THEN
    -- assumes raster is in 3857 thus pixels are square
    SELECT tms_zoomforpixelsize(ST_Scalex(input)) INTO _max_zoom;
  ELSE
    _max_zoom := max_zoom;
  END IF;
  RAISE INFO 'MAX ZOOM LEVEL %', _max_zoom;
  
  -- generate the tiles for this zoom level
  FOR zoom IN _min_zoom.._max_zoom LOOP
    RETURN QUERY SELECT t.rast, t.x, t.y, t.z FROM tms_tile_zoom(input, zoom, algorithm) as t;
  END LOOP;
RETURN;
END;
$$;


-------------------------
-- pg_tms query functions
-------------------------

/*
CREATE FUNCTION tms_gen_missing_tile(
  coord tms_tilecoordz,
  _tbl_type anyelement
)
RETURNS raster
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  tile raster;
  tbound tms_tilebounds_meters;
  poly geometry;
BEGIN
  SELECT tms_tilebounds_meters(coord.x, coord.y, coord.x) INTO tbound;
  SELECT coord::geometry INTO poly;
  RETURN EXECUTE format('
    SELECT ST_Resample(rast, $1)
    FROM %s
    WHERE
      ST_Intersects(rast, $2)
    ORDER BY zoom DESC
    LIMIT 1
  ', pg_typeof(_tbl_type))
  USING coord::raster, poly;
END;
$$;

-- pass this a table already filtered for a specific
-- parent raster via a subselect for _tbl_type
CREATE FUNCTION tms_get_tile(
  coord tms_tilecoordz,
  _tbl_type anyelement
)
RETURNS raster
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN QUERY EXECUTE format('
    SELECT rast
    FROM %s
    WHERE
      x = $1,
      y = $2,
      z = $3
  ', pg_typeof(_tbl_type))
  USING coord.x, coord.y, coord.z;
END
$$;
*/

-- pass this a table already filtered for a specific
-- parent raster via a subselect for _tbl_type
CREATE FUNCTION tms_tile2png(
  coord tms_tilecoordz,
  _tbl_type anyelement,
  resample bool DEFAULT true
)
RETURNS bytea
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  tile raster;
BEGIN
  EXECUTE format('
    SELECT rast
    FROM %s
    WHERE
      x = $1,
      y = $2,
      z = $3
  ', pg_typeof(_tbl_type))
  USING coord.x, coord.y, coord.z
  INTO tile;

  IF tile IS NULL AND resample THEN
    EXECUTE format('
      SELECT ST_Resample(rast, $1)
      FROM %s
      WHERE
        ST_Intersects(rast, $2)
      ORDER BY zoom DESC
      LIMIT 1
    ', pg_typeof(_tbl_type))
    USING coord::raster, poly
    INTO tile;
  END IF;

  IF tile IS NULL THEN
    RETURN NULL;
  END IF;
  
  RETURN (SELECT ST_AsPNG(tile));
END;
$$;


-------------------------------------------
-- pg_tms conversions and tile calculations
-------------------------------------------

CREATE FUNCTION tms_latlon2meters(lat double precision, lon double precision)
RETURNS tms_meters
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (select tms_latlon2meters((lat, lon)::tms_latlon));
END;
$$;

CREATE FUNCTION tms_latlon2meters(coords tms_latlon)
RETURNS tms_meters
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  ret tms_meters;
BEGIN
  SELECT
    coords.lon * tms_originshift() / 180.0,
    (ln(tan((90 + coords.lat) * pi() / 360)) / (pi() / 180)) * tms_originshift() / 180
  INTO ret;
  RETURN ret;
END;
$$;


CREATE FUNCTION tms_meters2latlon(mx double precision, my double precision)
RETURNS tms_latlon
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (select tms_meters2latlon((mx, my)::tms_meters));
END;
$$;

CREATE FUNCTION tms_meters2latlon(coords tms_meters)
RETURNS tms_latlon
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  ret tms_latlon;
BEGIN
  SELECT
    180 / pi() * (2 * atan(exp((coords.y / tms_originshift() * 180) * pi() / 180)) - pi() / 2),
    coords.x / tms_originshift() * 180
  INTO ret;
  RETURN ret;
END;
$$;


CREATE FUNCTION tms_pixels2meters(px int, py int, zoom int)
RETURNS tms_meters
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (SELECT tms_pixels2meters((px, py)::tms_pixels, zoom));
END;
$$;

CREATE FUNCTION tms_pixels2meters(coords tms_pixels, zoom int)
RETURNS tms_meters
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  ret tms_meters;
BEGIN
  SELECT
    coords.x * tms_resolution(zoom) - tms_originshift(),
    coords.y * tms_resolution(zoom) - tms_originshift()
  INTO ret;
  RETURN ret;
END;
$$;


CREATE FUNCTION tms_meters2pixels(mx double precision, my double precision, zoom int)
RETURNS tms_pixels
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (SELECT tms_meters2pixels((mx, my)::tms_meters, zoom));
END;
$$;

CREATE FUNCTION tms_meters2pixels(coords tms_meters, zoom int)
RETURNS tms_pixels 
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  ret tms_pixels;
BEGIN
  SELECT
    ((coords.x + tms_originshift()) / tms_resolution(zoom))::int,
    ((coords.y + tms_originshift()) / tms_resolution(zoom))::int
  INTO ret;
  RETURN ret;
END;
$$;


CREATE FUNCTION tms_pixels2tile(px int, py int)
RETURNS tms_tilecoord
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (SELECT tms_pixels2tile((px, py)::tms_pixels));
END;
$$;

CREATE FUNCTION tms_pixels2tile(coords tms_pixels)
RETURNS tms_tilecoord 
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  ret tms_tilecoord;
BEGIN
  SELECT
    (ceil(coords.x / 256::double precision) - 1),
    (ceil(coords.y / 256::double precision) - 1)
  INTO ret;
  RETURN ret;
END;
$$;


CREATE FUNCTION tms_pixels2raster(px int, py int, zoom int)
RETURNS tms_pixels
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (SELECT tms_pixels2raster((px, py)::tms_pixels, zoom));
END;
$$;

CREATE FUNCTION tms_pixels2raster(coords tms_pixels, zoom int)
RETURNS tms_pixels
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  ret tms_pixels;
BEGIN
  SELECT
    px,
    (256 << zoom) - py
  INTO ret;
  RETURN ret;
END;
$$;


CREATE FUNCTION tms_meters2tile(mx double precision, my double precision, zoom int)
RETURNS tms_tilecoord
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (SELECT tms_meters2tile((mx, my)::tms_meters, zoom));
END;
$$;

CREATE FUNCTION tms_meters2tile(coords tms_meters, zoom int)
RETURNS tms_tilecoord
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (SELECT tms_pixels2tile(tms_meters2pixels(coords.x, coords.y, zoom)));
END;
$$;


CREATE FUNCTION tms_tileorigin_meters(tx int, ty int, zoom int)
RETURNS tms_meters
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (SELECT tms_tileorigin_meters((tx, ty, zoom)::tms_tilecoordz));
END;
$$;

CREATE FUNCTION tms_tileorigin_meters(coords tms_tilecoord, zoom int)
RETURNS tms_meters
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (SELECT tms_tileorigin_meters((coords.x, coords.y, zoom)::tms_tilecoordz));
END;
$$;

CREATE FUNCTION tms_tileorigin_meters(coords tms_tilecoordz)
RETURNS tms_meters
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (SELECT tms_pixels2meters(coords.x * 256, coords.y * 256, coords.z));
END;
$$;


CREATE FUNCTION tms_tilebounds_meters(tx int, ty int, zoom int)
RETURNS tms_meters_ext
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (SELECT tms_tilebounds_meters((tx, ty, zoom)::tms_tilecoordz));
END;
$$;

CREATE FUNCTION tms_tilebounds_meters(coords tms_tilecoord, zoom int)
RETURNS tms_meters_ext
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (SELECT tms_tilebounds_meters((coords.x, coords.y, zoom)::tms_tilecoordz));
END;
$$;

CREATE FUNCTION tms_tilebounds_meters(coords tms_tilecoordz)
RETURNS tms_meters_ext
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  ret tms_meters_ext;
BEGIN
  SELECT
    t1.x AS minx,
    t1.y AS miny,
    t2.x AS maxx,
    t2.y AS maxy
  FROM
    tms_pixels2meters(coords.x * 256, coords.y * 256, coords.z) as t1,
    tms_pixels2meters((coords.x + 1) * 256, (coords.y + 1) * 256, coords.z) as t2
  INTO ret;
  RETURN ret;
END;
$$;

CREATE CAST (tms_tilecoordz AS tms_meters_ext)
  WITH FUNCTION tms_tilebounds_meters(tms_tilecoordz)
  AS ASSIGNMENT;


CREATE FUNCTION tms_tilebounds_latlon(tx int, ty int, zoom int)
RETURNS tms_latlon_ext
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (SELECT tms_tilebounds_latlon((tx, ty, zoom)::tms_tilecoordz));
END;
$$;

CREATE FUNCTION tms_tilebounds_latlon(coords tms_tilecoord, zoom int)
RETURNS tms_latlon_ext
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (SELECT tms_tilebounds_latlon((coords.x, coords.y, zoom)::tms_tilecoordz));
END;
$$;

CREATE FUNCTION tms_tilebounds_latlon(coords tms_tilecoordz)
RETURNS tms_latlon_ext
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  ret tms_latlon_ext;
BEGIN
  SELECT
    t1.lat AS minlat,
    t1.lon AS minlon,
    t2.lat AS maxlat,
    t2.lon AS maxlon
  FROM
    (SELECT lat, lon from tms_meters2latlon((
       SELECT (minx, miny)::tms_meters FROM tms_tilebounds_meters(coords)))) AS t1,
    (SELECT lat, lon from tms_meters2latlon((
       SELECT (maxx, maxy)::tms_meters FROM tms_tilebounds_meters(coords)))) AS t2
  INTO ret;
  RETURN ret;
END;
$$;

CREATE CAST (tms_tilecoordz AS tms_latlon_ext)
  WITH FUNCTION tms_tilebounds_latlon(tms_tilecoordz)
  AS ASSIGNMENT;
