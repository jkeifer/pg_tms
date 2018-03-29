pg_tms: A postgres Tile Map Service tiler
=========================================

pg_tms is a postgres extension that provides functions
to tile rasters as tiles compatible with a
[Tile Map Service (TMS)](https://wiki.osgeo.org/wiki/Tile_Map_Service_Specification).
Included in the extension are some functions useful
for querying for the correct tile.

It is inspired by [gdal2tiles.py](https://github.com/OSGeo/gdal/blob/master/gdal/swig/python/scripts/gdal2tiles.py)
but please note that only the Global Mercator option has been
implemented.

Note that this extension does not serve the tiled
rasters, just makes the tiles. You will need an additional
layer in front of the database taking HTTP requests for
tiles, querying the database, and returning the result.

This extension is under development and the documentation
has not yet been completed. Please refer to the sql source
for usage information as it is fairly straightforward.
