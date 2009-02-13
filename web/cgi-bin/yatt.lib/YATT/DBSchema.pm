package YATT::DBSchema;
use strict;
use warnings FATAL => qw(all);

use base qw(YATT::Class::Configurable);
use YATT::Fields qw(schemas tables);

use YATT::Types [Table => [qw(cf_name cf_additional)]
		 , [Column => [qw(cf_name cf_type
				  cf_primary_key
				  cf_updated
				  cf_unique
				  cf_indexed
				  cf_encoder
				)]]];

use YATT::Util::CmdLine;

sub import {
  my ($pack) = shift;
  return unless @_;
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
      $col->{cf_encoder} = $self->add_table(@$type);
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
    } $tab->sql_create($self);
  }
  wantarray ? @result : join(";\n", @result);
}

Table->define
  (sql_create => sub {
     (my Table $tab, my MY $schema) = @_;
     my (@cols, @indices);
     foreach my Column $col (@{$tab->{Column}}) {
       push @cols, $col->sql_create;
       if ($col->{cf_indexed}) {
	 push @indices, $col;
       }
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
   });

Column->define
  (sql_create => sub {
     (my Column $col, my MY $schema) = @_;
     join " ", $col->{cf_name}, do {
       if ($col->{cf_primary_key}) {
	 # XXX: SQLite specific.
	 'integer primary key'
       } else {
	 $col->{cf_type} . ($col->{cf_unique} ? " unique" : "");
       }
     };
   });

1;
# -for_dbic
# -for_sqlengine
# -for_sqlt

