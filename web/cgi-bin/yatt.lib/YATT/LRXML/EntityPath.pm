# -*- mode: perl; coding: utf-8 -*-
package YATT::LRXML::EntityPath;
use strict;
use warnings FATAL => qw(all);
use Exporter qw(import);
our @EXPORT_OK = qw(parse_entpath is_nested_entpath);
our @EXPORT = @EXPORT_OK;

=pod

  term     ::= ( text | expr | pipeline ) ','? ;

  pipeline ::= container?  trail+ ;

  trail    ::= var | '[' term ']' ;

  container::= '[' term* ']'
             |  '{' ( name (':' | '=') term )* '}' ;

  var      ::= (':'+ | '.'+) name ( '(' term* ')' )? ;
  name     ::= \w+ ;

  expr     ::= '=' text ;
  text     ::= word ( group word? )* ; -- group で始まるのは、container.

  group    ::= [\(\[\{] ( text | ',' )* [\}\]\)]

  word     ::= [\w\$\-\+\*/%<>]
               [\w\$\-\+\*/%<>:\.=]*
           ;

=cut

# is_nested_entpath($entpath, ?head?)

sub is_nested_entpath {
  return unless defined $_[0] and ref $_[0] eq 'ARRAY';
  my $item = shift;
  return unless defined $item->[0] and ref $item->[0] eq 'ARRAY';
  return 1 unless defined $_[0];
  defined $item->[0][0] and $item->[0][0] eq $_[0];
}

sub parse_entpath {
  my ($pack, $orig) = @_;
  return undef unless defined $orig;
  local $_ = $orig;
  my @result;
  if (wantarray) {
    @result = &_parse_pipeline;
  } else {
    $result[0] = &_parse_pipeline;
  }
  if ($_ ne '') {
    die "Unexpected token '$_' in entpath '$orig'";
  }
  wantarray ? @result : $result[0];
}

my %open_head = qw| ( call [ array { hash |;
my %open_rest = qw| ( call [ aref  |;
my %close_ch  = qw( ( ) [ ] { } );

my $re_var  = qr{[:\.]+ (\w+) (\()?}x;
my $re_word = qr{[\w\$\-\+\*/%<>]
		 [\w\$\-\+\*/%<>:\.=]*}x;

sub _parse_pipeline {
  my @pipe;
  if (s/^ \[ //x) {
    # container
    push @pipe, _parse_group(['array'], ']', \&_parse_term);
  } elsif (s/^ \{ //x) {
    push @pipe, &_parse_hash;
  }
  if (s/^$re_var//x) {
    do {
      if ($2) {
	# '('
	push @pipe, _parse_group([call => $1], ')', \&_parse_term);
      } elsif (defined $1) {
	# \w+
	push @pipe, [var => $1];
      } elsif (defined $3) {	# '['
	push @pipe, _parse_group(['aref'], ']', \&_parse_term, 'expr');
      } elsif (defined $4) {
	push @pipe, _parse_group(['var'], '}', \&_parse_term);
      } else {
	die "?? $_";
      }
    } while s/^$re_var | ^(\[) | ^(\{)//x;
  }
  wantarray ? @pipe : \@pipe;
}

my $re_grend = qr{ (?=[\)\]\}]) | $ }x;
my $re_text  = qr{($re_word)      # 1
		  (?: ([\(\[\{])  # 2
		  | $re_grend)?
		| $re_grend
	       }x;

sub _parse_term {
  my ($literal_type) = @_;
  $literal_type ||= 'text';
  # :foo()     [call => foo]
  # :foo(,)    [call => foo => [text => '']]
  # :foo(bar)  [call => foo => [text => 'bar']]
  # :foo(,,)   [call => foo => [text => ''], [text => '']]
  # :foo(bar,) [call => foo => [text => 'bar'], [text => '']]
  # :foo(bar,,)[call => foo => [text => 'bar'], [text => '']]
  if (s{^,}{}x) {
    return [$literal_type => ''];
  }
  my $is_expr = s{^=}{};
  unless (s{^$re_text}{}) {
    &_parse_pipeline;
  } else {
    my $result = '';
  TEXT: {
      do {
	$result .= $1 if defined $1;
	$result .= $4 if defined $4;
	if (my $opn = $2 || $3) {
	  # open group
	  $result .= $opn;
	  $result .= &_parse_group_string($close_ch{$opn});
	} elsif (not defined $1 and not defined $4) {
	  last TEXT;
	}
      } while s{^(?: $re_text | ([\(\[\{]) | ([:\.]) ) }{}x;
    }
    s/^,//;
    [$is_expr ? 'expr' : $literal_type => $result];
  }
}

sub _parse_group {
  my ($group, $close, $sub, @rest) = @_;
  for (my ($len, $cnt) = length($_); $_ ne ''; $len = length($_), $cnt++) {
    if (s/^ ([\)\]\}])//x) {
      die "Paren mismatch: expect $close got $1 " if $1 ne $close;
      s/^,//;
      last;
    }
    my @pipe = $sub->(@rest);
    die "Can't match: $_" if $cnt && $len == length($_);
    push @$group, @pipe <= 1 ? @pipe : \@pipe;
  }
  $group;
}

sub _parse_group_string {
  my ($close) = @_;
  my $result = '';
  for (my $len = length($_); $_ ne ''; $len = length($_)) {
    if (s/^ ([\)\]\}])//x) {
      die "Paren mismatch: expect $close got $1 " if $1 ne $close;
      $result .= $1;
      last;
    }
    if (s/^($re_word | , )//x) {
      $result .= $1;
    } elsif (s/^([\(\[\{])//) {
      $result .= &_parse_group_string($close_ch{$1});
    }
  }
  $result;
}

sub _parse_hash {
  my @hash = ('hash');
  for (my ($len, $cnt) = length($_); $_ ne ''; $len = length($_), $cnt++) {
    if (s/^ ([\)\]\}])//x) {
      die "Paren mismatch: expect \} got $1 " if $1 ne '}';
      s/^,//;
      last;
    }
    if ($cnt && $len == length($_)) {
      die "Can't parse: $_"
    }
    s/^,//;
    s/^(\w+) [:=] //x or die "Hash key is missing: $_";
    push @hash, [text => $1], &_parse_term;
  }
  \@hash;
}

1;
