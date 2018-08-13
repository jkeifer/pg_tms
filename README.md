pg_tms: A postgres Tile Map Service tiler
=========================================

`pg_tms` is a postgres extension that provides functions
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

This extension is under development and full documentation
has not yet been completed. Please refer to the sql source
for usage information as it is fairly straightforward.


Installation
------------

`pg_tms` requires Postgres 9.3 or greater and PostGIS 2.1.
Be sure these dependencies are installed before installing `pg_tms` 

On a unix-like system, use the included MakeFile to build
and install the extension to postgres with pgxs. Just clone
and `cd` into this repo and run:

```
$ make install
```

Simple.

On Windows, building extensions is generally more complicated.
However, this project is all in SQL and does not require any
specific build steps, so in reality installation on Windows is
still easy. Clone this repo, then copy the sql and control files
your postgres installation's `share\extension` directory.
For example, on one of my installations,
that path is `C:\Program Files\PostgreSQL\9.6\share\extension`.

The `sh` script `win-install.sh` has been included in the repo
to auto-discover your extension directory and copy the files
there for you. It simply looks for `psql` on your path to find
your postgres bin directory, and finds the extension relative
to that path. It can be run from anything on Windows that will
execute `sh`, like cygwin or mingw64, and does not require make.

This means you should be able to install `pg_tms` on Windows with
a simple command:

```
$ ./win-install.sh
```

If `psql` is not on your path or you want to install `pg_tms` to a
different location, just provide the directory path desired as
the argument to `win-install.sh`.

In all cases the script will prompt before copying so you can
confirm the path is correct.


Adding `pg_tms` to your database
------------------------------

Once installed, `pg_tms` can be added to a database
with the following command:

```
CREATE EXTENSION pg_tms CASCADE;
```

The `CASCADE` will also add postgis to the database if
it is not present.
