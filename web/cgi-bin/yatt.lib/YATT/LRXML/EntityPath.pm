package YATT::LRXML::EntityPath;
# -*- coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use Exporter qw(import);
our @EXPORT_OK = qw(parse_entpath);
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

sub parse_entpath {
  my ($pack, $orig) = @_;
  return undef unless defined $orig;
  local $_ = $orig;
  &_parse_pipeline;
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
	push @pipe, _parse_group(['aref'], ']', sub {
				   s{^($re_word)}{}
				     or die "Can't match: $_";
				   $1;
				 });
      } else {
	die "?? $_";
      }
    } while s/^$re_var | ^(\[)//x;
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
  # :foo()     [call => foo]
  # :foo(,)    [call => foo => [text => '']]
  # :foo(bar)  [call => foo => [text => 'bar']]
  # :foo(,,)   [call => foo => [text => ''], [text => '']]
  # :foo(bar,) [call => foo => [text => 'bar'], [text => '']]
  # :foo(bar,,)[call => foo => [text => 'bar'], [text => '']]
  if (s{^,}{}x) {
    return [text => ''];
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
    [$is_expr ? 'expr' : 'text' => $result];
  }
}

sub _parse_group {
  my ($group, $close, $sub) = @_;
  for (my ($len, $cnt) = length($_); $_ ne ''; $len = length($_), $cnt++) {
    if (s/^ ([\)\]\}])//x) {
      die "Paren mismatch: expect $close got $1 " if $1 ne $close;
      s/^,//;
      last;
    }
    my @pipe = $sub->();
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
