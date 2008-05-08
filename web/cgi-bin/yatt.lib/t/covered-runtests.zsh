#!/bin/zsh

# set -e

function die { echo 1>&2 $*; exit 1 }

function usage {
    die Usage: $0:t "[-db cover_db]" foo.t bar.t ...
}

function runtests {
    time perl -MTest::Harness -e 'runtests(@ARGV)' $*
}

#----------------------------------------
integer nocover=0
typeset -A opts
opts[-charset]=utf-8

zparseopts -K -D -A opts h help x xtrace charset: browser: nocover

(($+opts[-x] || $+opts[-xtrace])) && set -x

if ((ARGC)); then
    files=($*)
else
	cd $0:h
    files=(*.t(N))
fi

(($#files)) || usage

export HARNESS_PERL_SWITCHES
if ((!$+opts[-nocover])) {
    cover_opt=(-ignore /dev/null)
    while ((ARGC >= 2)) && [[ $1 = [+-]* ]]; do
	opts[$1]=$2
	cover_opt+=($1 $2)
	shift; shift;
    done

    # If no db is specified and single file mode,
    # create specific db with same rootname.
    if ((!$+opts[-db])) && ((ARGC == 1)); then
	opts[-db]=$argv[1]:r.db
	cover_opt+=(-db $opts[-db])
    fi

    HARNESS_PERL_SWITCHES=-MDevel::Cover=${(j/,/)cover_opt}
}

if [[ -z $opts[-db] ]]; then
    cover_db_path=$PWD/cover_db
elif [[ $opts[-db] = /* ]]; then
    cover_db_path=$opts[-db]
else
    cover_db_path=$PWD/$opts[-db]
fi

#----------------------------------------
if (($+opts[-h])) || (($+opts[-help])); then
    usage
fi

(($+db[-add])) || cover -delete $opts[-db]

runtests $files

# To avoid &#8249; and other annoying of CGI::escapeHTML.
perl -e 'use CGI; CGI::self_or_default()->charset("utf-8"); do shift;' \
    =cover $opts[-db]

chmod a+rx $cover_db_path{,/**/*}(/N)

if (($+opts[-charset])); then
    cat <<EOF > $cover_db_path/.htaccess
allow from localhost
AddHandler default-handler .html
AddType "text/html; charset=$opts[-charset]" .html
EOF
fi

if (($+opts[-browser])); then
    $opts[-browser] file://$cover_db_path/coverage.html
fi
