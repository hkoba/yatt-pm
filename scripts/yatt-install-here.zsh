#!/bin/zsh

function die { echo 1>&2 $*; exit 1 }

zmodload -i zsh/parameter

typeset -A repository
repository=(
    sf  https://yatt-pm.svn.sourceforge.net/svnroot
    bb  https://buribullet.net/svn
)

typeset -A repo_url
repo_url=(
    stable $repository[sf]/yatt-pm/trunk/yatt-pm/web
    devel  $repository[bb]/yatt-pm/web
)

function main {
    precheck || return 1
    
    local mode=devel url
    url=$repo_url[$mode]
    if [[ $PWD == */cgi-bin ]]; then
	echo Installing into existing cgi-bin ($PWD) ...
	svn -q co $url/cgi-bin/yatt.{cgi,lib} .
	echo Please make sure $PWD is allowed to run CGI.
	echo See \'Options +ExecCGI\' in Apache manual.
    else
	if [[ -d cgi-bin ]]; then
	    die Sorry, you already have cgi-bin. Please retry in $PWD/cgi-bin.
	fi
	echo Creating new cgi-bin...
	svn -q co $url/cgi-bin
	add_apache_htaccess
	add_sample
    fi
}

function precheck {
    setopt err_return
    (($+commands[svn]))
}

function add_apache_htaccess {
    local url_base
    if [[ $PWD == $HOME/public_html/* ]]; then
	url_base=/~$USER${PWD#$HOME/public_html}
	echo Making sure it does not violate suexec policy.
	chmod -R g-w cgi-bin
    else
	url_base=${PWD#/var/www/html}
    fi

    {
	echo Modifying .htaccess ...
	cat <<-EOF >> .htaccess
	Action x-yatt-handler $url_base/cgi-bin/yatt.cgi
	AddHandler x-yatt-handler .html
	EOF
    }
}

function add_sample {
    local fn
    fn=index.html
    if [[ -r $fn ]]; then
	echo "(skipping $fn)"
    else
	echo Adding sample index.html ...
	cat <<-EOF > index.html
	<yatt:hello>
	 world!
	</yatt:hello>
	
	<!yatt:widget hello body=[code]>
	<html>
	<head><title>Hello &yatt:body();</title></head>
	<body>
	<h2>Hello <yatt:body /></h2>
	</body></html>
	EOF
    fi
}

{ main "$@" } always {
    if (($TRY_BLOCK_ERROR)); then
	die "Install failed!"
    else
	echo OK!
    fi
}
