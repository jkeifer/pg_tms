#/bin/sh

# get directory of this script
a="/${0}"; a=${a%/*}; a=${a#/}; a=${a:-.}; BASEDIR=$(cd "${a}"; pwd)

for f in "${a}"/{pg_tms*.sql,pg_tms.control}; do
    if ! [ -e "${f}" ]; then
        echo "ERROR: pg_tms files could not be found."
        echo "${0} must be in the pg_tms directory when run."
	exit 3
    fi
    break
done 

psqlpath="$(which psql 2> /dev/null)"

if [ -z "${1}" ] && [ "${psqlpath}" == "." ]; then
    echo "ERROR: did not find psql on the path and no PG extension dir provided."
    exit 1
fi

pg_share=${1:-"$(dirname "$(dirname "${psqlpath}")")/share/extension/"}

if ! [ -d "${pg_share}" ]; then
    echo "ERROR: PG extension path is not a directory: ${pg_share}"
    exit 2
fi

echo "Install pg_tms to '${pg_share}' (y/N)?"
read -r -p "${confirm}" response
case $response in
    [yY][eE][sS]|[yY])
        cp -v "${a}"/{pg_tms*.sql,pg_tms.control} "${pg_share}"
        ;;
    *) ;;
esac
