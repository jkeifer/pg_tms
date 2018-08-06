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

CREATE FUNCTION tms_fliprastergeotransform(input raster)
RETURNS raster
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
 RETURN (SELECT ST_SetGeoReference(
    input,
    ST_UpperLeftX(input),
    ST_UpperLeftY(input) + ST_Scaley(input) * ST_Height(input),
    ST_Scalex(input),
    -ST_Scaley(input),
    ST_Skewx(input),
    ST_Skewy(input)
  ));
END;
$$;

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
  RETURN (SELECT tms_fliprastergeotransform(ST_MakeEmptyRaster(
    256,
    256,
    ext.minx,
    ext.miny,
    res,
    res,
    0,
    0,
    3857
  )));
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
  RETURN (SELECT ST_MakeEnvelope(
    ext.maxx,
    ext.maxy,
    ext.minx,
    ext.miny,
    3857
  ));
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
  -- beyond that is just crazy tiles and we'll leave
  -- it to someone with those needs to change the code
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

CREATE FUNCTION tms_raster2tilecoord_ext(
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
  INTO tminx, tmaxy;
  SELECT
    t.x, t.y
  FROM
    tms_meters2tile(
      ST_UpperLeftX(input) + ST_Scalex(input) * ST_Width(input),
      ST_UpperLeftY(input) - ABS(ST_Scaley(input) * ST_Height(input)),
      zoom
    ) AS t
  INTO tmaxx, tminy;

  -- we have to crop the top and bottom of the map
  -- if it falls outside the valid area
  --tmaxx := (SELECT LEAST(2^zoom-1, tmaxx));
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
  process raster;
  bands int;
BEGIN
  SELECT ST_MakeEmptyRaster(tile) INTO output;
  SELECT ST_NumBands(input) into bands;
  FOR band in 1..bands LOOP
    --RAISE WARNING 'Input - band % - % - %', band, st_summary(input), st_summarystats(input);
    tile := ST_AddBand(
      tile,
      band,
      ST_BandPixelType(input, band),
      ST_BandNoDataValue(input, band),
      ST_BandNoDataValue(input, band)
    );
    --RAISE WARNING 'Input - band % - % - %', band, st_summary(input), st_summarystats(input);
    --RAISE WARNING 'before';
    process := ST_MapAlgebra(input, band, tile, band, '[rast1]', NULL, 'SECOND', NULL, '[rast1]', NULL);
    --RAISE WARNING 'Process - band % - % - %', band, st_summary(process), st_summarystats(process);
    output := ST_AddBand(output, process);
    --RAISE WARNING 'Output - band % - % - %', band, st_summary(output), st_summarystats(output, band);
    --RAISE WARNING 'after';
  END LOOP;
  RETURN output;
END;
$$;


CREATE FUNCTION tms_has_data(
  input raster
)
RETURNS bool
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  RETURN (SELECT EXISTS (
    SELECT *
    FROM generate_series(1, ST_NumBands(input)) as band
    WHERE ST_Count(input, band) > 0
  ));
END
$$;


CREATE FUNCTION tms_tilecoordz_from_raster(
  input raster,
  zoom int
)
RETURNS SETOF tms_tilecoordz
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
  tminx int;
  tminy int;
  tmaxx int;
  tmaxy int;
BEGIN
  -- find the extent of the input raster in tile coords
  SELECT
    t.minx, t.miny, t.maxx, t.maxy
  FROM
    tms_raster2tilecoord_ext(input, zoom) AS t
  INTO
    tminx, tminy, tmaxx, tmaxy;

  RETURN QUERY (
    SELECT
      -- We have to handle data crossing 180E, which could have
      -- invalid tile coords. So we mod x by the number of x tiles.
      x % (2 ^ zoom)::int, y, zoom
    FROM
      generate_series(tminx, tmaxx) AS x,
      generate_series(tminy, tmaxy) AS y
  );
END;
$$;


CREATE FUNCTION tms_tile_raster_to_zoom(
  input raster,
  zoom int DEFAULT -1,
  drop_blanks bool DEFAULT true,
  algorithm text DEFAULT 'NearestNeighbor'
)
RETURNS SETOF tms_tile
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
  -- if zoom not specified, find the native zoom level
  IF zoom = -1 THEN
    SELECT tms_zoomforpixelsize(ST_Scalex(input)) INTO zoom;
  END IF;

  -- generate the tiles for this zoom level
  RETURN QUERY (
    SELECT
      CASE
        WHEN NOT drop_blanks OR tms_has_data(tile) THEN
          tile
        ELSE
          NULL
        END,
      t.x,
      t.y,
      zoom
    FROM
      tms_tilecoordz_from_raster(input, zoom) as t,
    LATERAL
      tms_copy_to_tile(
        ST_Resample(input, t::raster, algorithm),
        t::raster
    ) as tile
  );
END
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

