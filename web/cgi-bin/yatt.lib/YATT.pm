#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
package YATT;
require 5.007_001; # For sprintf reordering.

use strict;
use warnings FATAL => qw(all);
use version; our $VERSION = qv('0.0.2');
use File::Basename;

BEGIN {
  unless (caller(2)) {
    unshift @INC, dirname(__PACKAGE__);
  }
}

use YATT::Util qw(escape decode_args attr named_attr);
use YATT::Util::Finalizer qw(capture);

# for user
sub breakpoint {}

# for YATT itself.
sub break_rc {}
sub break_after_rc {}
sub break_handler {}
sub break_dispatch {}
sub break_run {}

sub break_translator {}
sub break_parser {}
sub break_cursor {}

sub break_eval {}

unless (caller) {
  
}

1;
__END__

=head1 NAME

YATT - Yet Another Template Toolkit

=head1 VERSION

Version 0.0.1

=head1 SYNOPSIS

    require YATT::LRXML;

=head1 DESCRIPTION

YATT is Yet Another Template Toolkit. Like PHP (and unlike HTML::Template),
YATT translates each template into (executable) Perl package(class)
so that you can define subs to build up your own abstraction architecture.

This is pre-alpha release to avoid CPAN namespace purge. So, you might not
find any usefull feature in this.

=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
C<bug-yatt at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=YATT>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc YATT

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/YATT>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/YATT>

=item * Bug tracker (svntrac)

L<http://buribullet.net/svntrac/buribullet/rptview?rn=12>

=item * Search CPAN

L<http://search.cpan.org/dist/YATT>

=back

=head1 AUTHOR

"KOBAYASI, Hiroaki", C<< <hkoba at cpan.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, "KOBAYASI, Hiroaki" C<< <hkoba@cpan.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
