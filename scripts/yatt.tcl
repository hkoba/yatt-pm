#!/usr/bin/wish
# -*- mode: tcl; tab-width: 8 -*-
# $Id$

package require Tkhtml 3

package require tclperl
set perl [perl::interp new]

$perl eval [subst -novariable {
    our $ROOTNAME = "[file rootname [info script]]";
}]

set html [$perl eval {
    our $ROOTNAME;
    use File::Basename;
    unshift @INC, "$ROOTNAME.lib";
    require YATT::Toplevel::CGI;
    our $YATT = new YATT::Toplevel::CGI([DIR => dirname($ROOTNAME)
					 , LIB => "$ROOTNAME.tmpl"]);

    $YATT->dispatch_captured("/index.html", $YATT->new_cgi);
}]

puts "html=($html)"

pack [html .html]

.html parse $html
