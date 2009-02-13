package YATT::DBSchema;
use strict;
use warnings FATAL => qw(all);
use Carp;

use base qw(YATT::Class::Configurable);
use YATT::Fields qw(schemas tables);

use YATT::Types [Table => [qw(cf_name cf_additional)]
		 , [Column => [qw(cf_name cf_type
				  cf_primary_key
				  cf_updated
				  cf_unique
				  cf_indexed
				  cf_encoded_by
				)]]];

use YATT::Util::CmdLine;

sub import {
  my ($pack) = shift;
  return unless @_;
  my MY $schema = $pack->new(@_);
}

sub new {
  my MY $self = shift->SUPER::new;
  foreach my $item (@_) {
    if (ref $item) {
      $self->add_table(@$item);
    }
  }
  $self;
}

sub add_table {
  (my MY $self, my ($name, $opts, @columns)) = @_;
  $self->{tables}{$name} ||= do {
    push @{$self->{schemas}}
      , my Table $tab = $self->Table->new;
    $tab->{cf_name} = $name;
    if (@columns) {
      $tab->{cf_additional} = $opts;
      foreach my $desc (@columns) {
	my ($col, $type, @desc) = @$desc;
	$self->add_table_column($tab, $col, $type, map {
	  if (/^-(\w+)/) {
	    $1 => 1
	  } else {
	    $_ => 1
	  }
	} @desc);
      }
    } elsif (not ref $opts) {
      # $opts is used as column type.
      # XXX: SQLite specific.
      $self->add_table_column($tab, $name . 'no', 'integer'
			      , primary_key => 1);
      $self->add_table_column($tab, $name, $opts
			      , unique => 1);
    } else {
      die "Unknown table desc $name $opts";
    }
    $tab;
  };
}

sub add_table_column {
  (my MY $self, my Table $tab, my ($name, $type, @opts)) = @_;
  push @{$tab->{Column}}, my Column $col = $self->Column->new(@opts);
  $col->{cf_name} = $name;
  # if ref $type, else
  $col->{cf_type} = do {
    if (ref $type) {
      $col->{cf_encoded_by} = $self->add_table(@$type);
      # XXX: SQLite specific.
      'int'
    } else {
      $type
    }
  };
  # XXX: Validation: name/option conflicts and others.
  $col;
}

sub sql_create {
  (my MY $self) = @_;
  my @result;
  my $wantarray = wantarray;
  foreach my Table $tab (@{$self->{schemas}}) {
    push @result, map {
      $wantarray ? $_ . "\n" : $_
    } $self->sql_create_table($tab);
  }
  wantarray ? @result : join(";\n", @result);
}

sub sql_create_table {
  (my MY $schema, my Table $tab) = @_;
  my (@cols, @indices);
  foreach my Column $col (@{$tab->{Column}}) {
    push @cols, $schema->sql_create_column($tab, $col);
    push @indices, $col if $col->{cf_indexed};
  }
  # XXX: SQLite specific.
  push my @create
    , sprintf qq{CREATE TABLE %s\n(%s)}, $tab->{cf_name}
      , join "\n, ", @cols;

  foreach my Column $ix (@indices) {
    push @create
      , sprintf q{CREATE INDEX %1$s_%2$s on %1$s(%2$s)}
	, $tab->{cf_name}, $ix->{cf_name};
  }

  wantarray ? @create : join(";\n", @create);
}

sub sql_create_column {
  (my MY $schema, my Table $tab, my Column $col) = @_;
  join " ", $col->{cf_name}, do {
    if ($col->{cf_primary_key}) {
      # XXX: SQLite specific.
      'integer primary key'
    } else {
      $col->{cf_type} . ($col->{cf_unique} ? " unique" : "");
    }
  };
}

sub sql_select {
  (my MY $schema, my ($tabName, $params)) = @_;
  my Table $tab = $schema->{tables}{$tabName}
    or croak "No such table: $tabName";

  my $raw = delete $params->{raw};

  my (@selJoins, @selCols) = ($tab->{cf_name});
  foreach my Column $col (@{$tab->{Column}}) {
    if (my Table $enc = $col->{cf_encoded_by}) {
      push @selCols, "$tab->{cf_name}.$col->{cf_name}"
	, "$col->{cf_name}.$enc->{cf_name}";
      push @selJoins, "\nLEFT JOIN $enc->{cf_name} $col->{cf_name}"
	. " on $tab->{cf_name}.$col->{cf_name}"
	  . " = $col->{cf_name}.$enc->{cf_name}no";
    } else {
      push @selCols, $col->{cf_name};
    }
  }

  my $colExpr = join ", ", do {
    if (my $val = delete $params->{columns}) {
      ref $val ? @$val : $val;
    } elsif ($raw) {
      '*';
    } else {
      @selCols;
    }
  };

  my @appendix;
  {
    if ($params->{offset} and not $params->{limit}) {
      die "offset needs limit!";
    }

    foreach my $kw (qw(where group_by order_by limit offset)) {
      if (my $val = delete $params->{$kw}) {
	push @appendix, join(" ", map(do {s/_/ /; $_}, uc($kw)), $val);
      }
    }

    die "Unknown param(s) for select $tabName: "
      , join(", ", map {"$_=" . $params->{$_}} keys %$params) if %$params;
  }

  if (wantarray) {
    \ (@selCols, @selJoins, @appendix);
  } else {
    join("\n", sprintf(q{SELECT %s FROM %s}, $colExpr
		       , $raw ? $tabName : join("", @selJoins))
	 , @appendix);
  }
}

1;
# -for_dbic
# -for_sqlengine
# -for_sqlt

