package YATT::DBSchema;
use strict;
use warnings FATAL => qw(all);
use Carp;

use base qw(YATT::Class::Configurable);
use YATT::Fields (qw(schemas tables cf_DBH cf_auto_create
		     cf_no_header
		   )
		  , ['^cf_NULL' => '']
		  , ['^cf_name' => 'DBSchema']
		 );

use YATT::Types [Table => [qw(cf_name cf_additional)]
		 , [Column => [qw(cf_name cf_type
				  cf_inserted
				  cf_unique
				  cf_indexed
				  cf_encoded_by
				  cf_updated
				  cf_primary_key
				)]]];
use YATT::Util::Symbol;
require YATT::Inc;

#----------------------------------------

#========================================

sub import {
  my ($pack) = shift;
  return unless @_;
  my MY $schema = $pack->create(@_);

  $schema->export_and_rebless_with(caller);
}

sub export_and_rebless_with {
  (my MY $schema, my ($callpack)) = @_;

  # Allocate new class.
  my $classFullName = join("::", $callpack, $schema->name);
  YATT::Inc->add_inc($classFullName);
  eval sprintf q{use strict; package %s; use base qw(%s)}
    , $classFullName, ref $schema;
  # MY->add_isa($classFullName, $pack);
  eval qq{use strict; package $callpack; use base qw($classFullName)};
  # MY->add_isa($callpack, $classFullName);

  my $glob = globref($classFullName, "SCHEMA");
  *{$glob} = \ $schema;
  *{$glob} = sub () { $schema };

  # Install to caller
  *{globref($callpack, $schema->name)} = sub () { $schema };
  # special new for singleton.
  *{globref($callpack, 'new')} = sub {
    shift;
    $schema->configure(@_) if @_;
    $schema;
  };

  $schema->rebless_with($callpack);
}

sub create {
  my ($pack) = shift;
  $pack->parse_import(\@_, \ my %opts);
  my MY $self = $pack->new(%opts);
  foreach my $item (@_) {
    if (ref $item) {
      $self->add_table(@$item);
    } else {
      croak "Invalid schema item: $item";
    }
  }
  $self;
}

sub parse_import {
  my ($pack, $list, $opts) = @_;
  # -bool_flag
  # key => value
  for (my $i = 0; $i < @$list; $i++) {
    last if ref $list->[$i];
    if ($list->[$i] =~ /^-(\w+)/) {
      $opts->{$1} = 1;
    } else {
      croak "Option value is missing for $list->[$i]"
	unless $i+1 < @$list;
      $opts->{$list->[$i]} = $list->[$i+1];
      $i++;
    }
  }
}

#========================================

sub connect_sqlite {
  (my MY $schema, my ($dbname, $rwflag)) = @_;
  my $ro = !defined $rwflag || $rwflag !~ /w/i;
  my $dbi_dsn = "dbi:SQLite:dbname=$dbname";
  $schema->{cf_auto_create} = 1;
  $schema->connect($dbi_dsn, undef, undef
		   , {RaiseError => 1, PrintError => 0, AutoCommit => $ro})
}

sub connect {
  (my MY $schema, my ($dbi_dsn, $user, $auth, $param)) = @_;
  my %param = %$param if $param;
  $param{RaiseError} = 1 unless defined $param{RaiseError};
  $param{PrintError} = 0 unless defined $param{PrintError};
  require DBI;
  $schema->{cf_DBH} = DBI->connect($dbi_dsn, $user, $auth, \%param);
  $schema->install_tables if $schema->{cf_auto_create};
  $schema;
}

sub install_tables {
  (my MY $schema, my $dbh) = @_;
  $dbh ||= $schema->{cf_DBH};
  foreach my Table $table (@{$schema->{schemas}}) {
    next if $schema->has_table($table->{cf_name}, $dbh);
    foreach my $create ($schema->sql_create_table($table)) {
      $dbh->do($create);
    }
  }
}

sub has_table {
  (my MY $schema, my ($table, $dbh)) = @_;
  $dbh ||= $schema->{cf_DBH};
  $dbh->tables("", "", $table, 'TABLE');
}

#========================================

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
  (my MY $self, my Table $tab, my ($colName, $type, @opts)) = @_;
  push @{$tab->{Column}}, my Column $col = $self->Column->new(@opts);
  $col->{cf_inserted} = not ($colName =~ s/^-//);
  $col->{cf_name} = $colName;
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

#========================================

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

#========================================

sub sql_insert {
  (my MY $schema, my ($tabName, $insEncs)) = @_;
  my Table $tab = $schema->{tables}{$tabName}
    or croak "No such table: $tabName";
  my @insNames;
  foreach my Column $col (@{$tab->{Column}}) {
    push @insNames, $col->{cf_name} if $col->{cf_inserted};
    if (ref $insEncs eq 'ARRAY'
	and my Table $encTab = $col->{cf_encoded_by}) {
      push @$insEncs, [$#insNames => $encTab->{cf_name}];
    }
  }

  <<END;
insert into $tabName (@{[join ", ", @insNames]})
values(@{[join ", ", map {q|?|} @insNames]})
END
}

sub to_insert {
  (my MY $schema, my ($tabName, $params)) = @_;
  my $dbh = delete $params->{dbh} || $schema->{cf_DBH};
  my $sth = $dbh->prepare($schema->sql_insert($tabName, \ my @insEncs));
  # ここで encode 用の sql/sth も生成せよと?
  my @encoder;
  foreach my $item (@insEncs) {
    my ($i, $table) = @$item;
    push @encoder, [$schema->to_encode($table, $dbh), $i];
  }
  sub {
    my (@values) = @_;
    foreach my $enc (@encoder) {
      $enc->[0]->(\@values, $enc->[1]);
    }
    $sth->execute(@values);
  }
}

sub to_encode {
  (my MY $schema, my ($encDesc, $dbh)) = @_;
  $dbh ||= $schema->{cf_DBH};
  my ($table, $column) = ref $encDesc ? @$encDesc : ($encDesc, $encDesc);
  my $check_sql = <<END;
select rowid from $table where $column = ?
END
  my $ins_sql = <<END;
insert into $table($column) values(?)
END

  # XXX: sth にまでするべきか。prepare_cached 廃止案。
  sub {
    my ($list, $nth) = @_;
    my ($rowid) = do {
      my $check = $dbh->prepare_cached($check_sql);
      $dbh->selectrow_array($check, {}, $list->[$nth]);
    };
    unless (defined $rowid) {
      my $ins = $dbh->prepare_cached($ins_sql, undef, 1);
      $ins->execute($list->[$nth]);
      $rowid = $dbh->func('last_insert_rowid');
    }
    $list->[$nth] = $rowid;
  }
}

#========================================

sub select {
  (my MY $schema, my ($tabName, $params)) = splice @_, 0, 3;

  my $is_text = delete $params->{text};
  my $separator = delete $params->{separator} || "\t";
  ($is_text, $separator) = (1, "\t") if delete $params->{tsv};

  my (@fetch) = grep {delete $params->{$_}} qw(hashref arrayref array);
  die "Conflict! @fetch" if @fetch > 1;

  my $sth = $schema->to_select($tabName, $params, \@_);

  if ($is_text) {
    # Debugging aid.
    my $null = $schema->NULL;
    my $header = $schema->format_line($sth->{NAME}, $separator, $null)
      if $schema->{cf_no_header};
    my $res = $sth->fetchall_arrayref
      or return;
    join("", defined $header ? $header : ()
	 , map { $schema->format_line($_, $separator, $null) } @$res)
  } else {
    my $method = $fetch[0] || 'arrayref';
    $sth->can("fetchrow_$method")->($sth);
  }
}

sub to_select {
  (my MY $schema, my ($tabName, $params, $values, $rvref)) = @_;
  my $dbh = (delete $params->{dbh}) || $schema->{cf_DBH};
  my $sth = $dbh->prepare(scalar $schema->sql_select($tabName, $params));
  if ($values) {
    my $rv = $sth->execute(@$values);
    $$rvref = $rv if $rvref;
  }
  $sth;
}

sub sql_select {
  (my MY $schema, my ($tabName, $params)) = @_;

  if (my $sub = $schema->can("sql_select_$tabName")) {
    return $sub->($schema, $params);
  }

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

#----------------------------------------

sub indexed {
  (my MY $schema, my ($tabName, $colName, $value, $params)) = @_;
  my $dbh = delete $params->{dbh} || $schema->{cf_DBH};
  my $sql = $schema->sql_indexed($tabName, $colName);
  $dbh->selectrow_hashref($sql, undef, $value);
}

sub sql_indexed {
  (my MY $schema, my ($tabName, $colName)) = @_;
  <<"END";
select _rowid_, * from $tabName where $colName = ?
END
}

sub format_line {
  (my MY $schema, my ($rec, $separator, $null)) = @_;
  join($separator, map {
    unless (defined $_) {
      $null
    } elsif ((my $val = $_) =~ s/[\t\n]/ /g) {
      $val
    } else {
      $_
    }
  } @$rec). "\n";
}

#========================================

sub to_update {
  (my MY $schema, my ($tabName, $colName)) = @_;
  my $sth = $schema->{cf_DBH}->prepare
    ($schema->sql_update($tabName, $colName));
  sub {
    my ($colValue, $rowId) = @_;
    $sth->execute($colValue, $rowId);
  }
}

sub sql_update {
  (my MY $schema, my ($tabName, $colName)) = @_;
  "update $tabName set $colName = ? where _rowid_ = ?";
}

1;
# -for_dbic
# -for_sqlengine
# -for_sqlt

