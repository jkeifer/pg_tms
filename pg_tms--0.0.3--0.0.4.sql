\echo Use "CREATE EXTENSION pg_tms" to load this file. \quit

DROP FUNCTION tms_copy_to_tile(raster, raster);
CREATE FUNCTION tms_copy_to_tile(
  input raster,
  tile raster,
  algorithm text DEFAULT 'NearestNeighbor'
)
RETURNS raster
LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE
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
    process := ST_MapAlgebra(
        ST_Resample(ST_Clip(input, ST_Envelope(tile)), tile, algorithm),
        band, tile, band, '[rast1]', NULL, 'SECOND', NULL, '[rast1]', NULL);
    --RAISE WARNING 'Process - band % - % - %', band, st_summary(process), st_summarystats(process);
    output := ST_AddBand(output, process);
    --RAISE WARNING 'Output - band % - % - %', band, st_summary(output), st_summarystats(output, band);
    --RAISE WARNING 'after';
  END LOOP;
  RETURN output;
END;
$$;
