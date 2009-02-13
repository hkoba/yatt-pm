package YATT::DBSchema;
use strict;
use warnings FATAL => qw(all);
use Carp;

use File::Basename;

use base qw(YATT::Class::Configurable);
use YATT::Fields (qw(schemas tables cf_DBH
		     cf_user
		     cf_auth
		     ^cf_connection_spec
		   )
		  , ['^cf_NULL' => '']
		  , ['^cf_name' => 'DBSchema']
		  , qw(
			cf_no_header
			cf_auto_create
		     )
		 );

use YATT::Types [Item => [qw(cf_name)]];

use YATT::Types -base => Item
  , [Table => [qw(raw_create chk_unique chk_index chk_check)]
     , [Column => [qw(cf_type
		      cf_inserted
		      cf_unique
		      cf_indexed
		      cf_decode_depth
		      cf_encoded_by
		      cf_updated
		      cf_primary_key
		    )]]];
use YATT::Util::Symbol;
use YATT::Util qw(coalesce);
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

  $schema->export_to($callpack);

  $schema->rebless_with($callpack);
}

sub export_to {
  (my MY $schema, my ($callpack)) = @_;
  # Install to caller
  *{globref($callpack, $schema->name)} = sub () { $schema };
  # special new for singleton.
  *{globref($callpack, 'new')} = sub {
    shift;
    $schema->configure(@_) if @_;
    $schema;
  };
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
  for (; @$list; shift @$list) {
    last if ref $list->[0];
    if ($list->[0] =~ /^-(\w+)/) {
      $opts->{$1} = 1;
    } else {
      croak "Option value is missing for $list->[0]"
	unless @$list >= 2;
      $opts->{$list->[0]} = $list->[1];
      shift @$list;
    }
  }
}

#========================================

sub dbh {
  (my MY $schema) = @_;
  unless ($schema->{cf_DBH}) {
    my $spec = $schema->connection_spec;
    unless (defined $spec) {
      croak "connection_spec is empty";
    }
    if (ref $spec eq 'ARRAY') {
      my ($type, @args) = @$spec;
      my $sub = $schema->can("connect_via_$type")
	or croak "No such connection spec type: $type";
      $sub->($schema, @args);
    } elsif (ref $spec eq 'CODE') {
      $schema->{cf_DBH} = $spec->($schema);
    } else {
      croak "Unknown connection spec obj: $spec";
    }
  };

  $schema->{cf_DBH}
}

sub connect_via_sqlite {
  (my MY $schema, my ($dbname, $rwflag)) = @_;
  my $ro = !defined $rwflag || $rwflag !~ /w/i;
  my $dbi_dsn = "dbi:SQLite:dbname=$dbname";
  $schema->{cf_auto_create} = 1;
  $schema->connect_via_dbi
    ($dbi_dsn, undef, undef
     , {RaiseError => 1, PrintError => 0, AutoCommit => $ro});
}

sub connect_via_dbi {
  (my MY $schema, my ($dbi_dsn, $user, $auth, $param)) = @_;
  my %param = %$param if $param;
  $param{RaiseError} = 1 unless defined $param{RaiseError};
  $param{PrintError} = 0 unless defined $param{PrintError};
  require DBI;
  my $dbh = $schema->{cf_DBH} = DBI->connect($dbi_dsn, $user, $auth, \%param);
  $schema->install_tables($dbh) if $schema->{cf_auto_create};
  $dbh;
}

sub install_tables {
  (my MY $schema, my $dbh) = @_;
  foreach my Table $table (@{$schema->{schemas}}) {
    next if $schema->has_table($table->{cf_name}, $dbh);
    foreach my $create ($schema->sql_create_table($table)) {
      $dbh->do($create);
    }
  }
}

sub has_table {
  (my MY $schema, my ($table, $dbh)) = @_;
  $dbh ||= $schema->dbh;
  $dbh->tables("", "", $table, 'TABLE');
}

sub tables {
  my MY $schema = shift;
  keys %{$schema->{tables}};
}

sub has_column {
  (my MY $schema, my ($table, $column, $dbh)) = @_;
  my $hash = $schema->columns_hash($table, $dbh || $schema->dbh);
  exists $hash->{$column};
}

sub columns_hash {
  (my MY $schema, my ($table, $dbh)) = @_;
  $dbh ||= $schema->dbh;
  my $sth = $dbh->prepare("select * from $table limit 0");
  $sth->execute;
  my %hash = %{$sth->{NAME_hash}};
  \%hash;
}

#========================================

sub add_table {
  (my MY $self, my ($name, $opts, @columns)) = @_;
  $self->{tables}{$name} ||= do {
    push @{$self->{schemas}}
      , my Table $tab = $self->Table->new;

    local our %colNameCache;

    $tab->{cf_name} = $name;
    if (@columns) {
      # XXX: 拡張の余地あり
      $tab->{raw_create} = $opts;
      my $fields = $tab->fields_hash;
      foreach my $desc (@columns) {
	if (ref (my $kw = $desc->[0])) {
	  unless ($fields->{my $fname = "chk_$$kw"}) {
	    croak "Invalid column constraint $kw for table $name";
	  } else {
	    push @{$tab->{$fname}}, [@{$desc}[1 .. $#$desc]];
	  }
	} else {
	  my ($col, $type, @desc) = @$desc;
	  $self->add_table_column($tab, $col, $type, map {
	    if (/^-(\w+)/) {
	      $1 => 1
	    } else {
	      $_
	    }
	  } @desc);
	}
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

sub is_fresh_colname {
  (my MY $self, my Table $tab, my ($colName, $cache, $assign)) = @_;
  if ($tab->{Column} and not %$cache) {
    my $i;
    foreach my Column $col (@{$tab->{Column}}) {
      $cache->{$col->{cf_name}} = ++$i;
    }
  }
  exists $cache->{$colName} ? 0 :
    $assign ? ($cache->{$colName} = keys(%$cache) + 1) : 1;
}

sub add_table_column {
  (my MY $self, my Table $tab, my ($colName, $type, @opts)) = @_;
  unless ($self->is_fresh_colname($tab, $colName, \ our %colNameCache, 1)) {
    croak "Conflicting column name $colName for table $tab->{cf_name}";
  }
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
  foreach my $constraint (map {$_ ? @$_ : ()} $tab->{chk_unique}) {
    push @cols, sprintf q{unique(%s)}, join(", ", @$constraint);
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

  # insert が有っても、構わない。
  push @create, map {$_ ? @$_ : ()} $tab->{raw_create};

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
  my $dbh = delete $params->{dbh} || $schema->dbh;
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
  $dbh ||= $schema->dbh;
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

sub sql {
  (my MY $self, my ($mode, $table)) = splice @_, 0, 3;
  $self->parse_params(\@_, \ my %param);
  $self->can("sql_${mode}")->($self, $table, \%param, @_);
}

# XXX: explain を。 cf_explain で？
sub cmd_select {
  my MY $self = shift;
  $self->parse_opts(\@_, \ my %opts);
  my $table = shift;
  $self->parse_opts(\@_, \ %opts);
  $self->configure(%opts) if %opts;
  $self->parse_params(\@_, \ my %param);
  my $sth = do {
    if (my $sub = $self->can("select_$table")) {
      $sub->($self, \%param, @_);
    } elsif ($sub = $self->can("sql_select_$table")) {
      my $s = $self->dbh->prepare($sub->($self, \%param));
      $s->execute(@_);
      $s;
    } else {
      $self->to_select($table, \%param, \@_);
    }
  };
  my $null = $self->NULL;
  my $format = $self->can('tsv_with_null');
  print $format->($null, @{$sth->{NAME}}) unless $self->{cf_no_header};
  while (my (@res) = $sth->fetchrow_array) {
    print $format->($null, @res);
  }
}

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
  my $dbh = (delete $params->{dbh}) || $schema->dbh;
  my $sth = $dbh->prepare($schema->sql_select($tabName, $params, \ my $bind));
  if (my $ary = $values || $bind) {
    my $rv = $sth->execute(@$ary);
    $$rvref = $rv if $rvref;
  }
  $sth;
}

sub sql_decode {
  (my MY $schema, my Table $tab
   , my ($selJoins, $depth, $alias, $until)) = @_;
  $depth = 0 unless defined $depth;
  $alias ||= $tab->{cf_name};
  my @selCols;
  foreach my Column $col (@{$tab->{Column}}) {
    my Table $enc = $col->{cf_encoded_by};
    if ($depth || $enc) {
      # primary key は既に積まれている。
      push @selCols, "$alias.$col->{cf_name}"
	unless $col->{cf_primary_key};
    } else {
      push @selCols, $col->{cf_name};
    }

    if ($enc && $depth < coalesce($until, 1)) {
      # alias と rowid と…
      push @$selJoins, "\nLEFT JOIN $enc->{cf_name} $col->{cf_name}"
	. " on $alias.$col->{cf_name}"
	  . " = $col->{cf_name}._rowid_";

      push @selCols, $schema->sql_decode
	($enc, $selJoins, $depth + 1, $col->{cf_name}
	 , $col->{cf_decode_depth});
    }
  }
  @selCols;
}

sub sql_join {
  (my MY $schema, my ($tabName, $params)) = @_;

  if (my $sub = $schema->can("sql_select_$tabName")) {
    return $sub->($schema, $params);
  }

  my Table $tab = $schema->{tables}{$tabName}
    or croak "No such table: $tabName";

  my @selJoins = $tab->{cf_name};
  my @selCols  = $schema->sql_decode($tab, \@selJoins);

  my (@appendix, @bind);
  if (my $where = delete $params->{where}) {
    push @appendix, do {
      if (ref $where) {
	require SQL::Abstract;
	(my $stmt, @bind) = SQL::Abstract->new->where($where);
	$stmt;
      } else {
	$where;
      }
    };
  }

  {
    if ($params->{offset} and not $params->{limit}) {
      die "offset needs limit!";
    }

    foreach my $kw (qw(group_by order_by limit offset)) {
      if (my $val = delete $params->{$kw}) {
	push @appendix, join(" ", map(do {s/_/ /; $_}, uc($kw)), $val);
      }
    }

    die "Unknown param(s) for select $tabName: "
      , join(", ", map {"$_=" . $params->{$_}} keys %$params) if %$params;
  }

  (\@selCols, \@selJoins, \@appendix, @bind ? \@bind : ());
}

sub sql_select {
  (my MY $schema, my ($tabName, $params, $bindref)) = @_;

  my $raw = delete $params->{raw};
  my $colExpr = do {
    if (my $val = delete $params->{columns}) {
      ref $val ? join(", ", @$val) : $val;
    } elsif ($raw) {
      '*';
    }
  };

  my ($selCols, $selJoins, $where, $bind)
    = $schema->sql_join($tabName, $params);

  $$bindref = $bind if $bind and $bindref;

  join("\n", sprintf(q{SELECT %s FROM %s}, $colExpr || join(", ", @$selCols)
		     , $raw ? $tabName : join("", @$selJoins))
       , @$where);
}

#----------------------------------------

sub indexed {
  (my MY $schema, my ($tabName, $colName, $value, $params)) = @_;
  my $dbh = delete $params->{dbh} || $schema->dbh;
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
  my $sth = $schema->dbh->prepare
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

########################################

sub tsv_with_null {
  my $null = shift;
  join("\t", map {defined $_ ? $_ : $null} @_). "\n";
}


########################################

sub run {
  my $pack = shift;
  $pack->cmd_help unless @_;
  $pack->parse_opts(\@_, \ my %opts);
  my MY $obj = $pack->new(%opts);
  my $cmd = shift || "help";
  $pack->parse_opts(\@_, \ %opts);
  $obj->configure(%opts);
  my $method = "cmd_$cmd";
  if (my $sub = $obj->can("cmd_$cmd")) {
    $sub->($obj, @_);
  } elsif ($sub = $obj->can($cmd)) {
    my @res = $sub->($obj, @_);
    exit 1 unless @res;
    unless (@res == 1 and defined $res[0] and $res[0] eq "1") {
      if (grep {defined $_ && ref $_} @res) {
	require Data::Dumper;
	print Data::Dumper->new([$_])->Indent(0)->Terse(1)->Dump
	  , "\n" for @res;
      } else {
	print join("\n", @res), "\n";
      }
    }
    exit 0
  } else {
    die "No such method $cmd for $pack\n";
  }
}

sub cmd_help {
  my ($self) = @_;
  my $pack = ref($self) || $self;
  my $stash = do {
    my $pkg = $pack . '::';
    no strict 'refs';
    \%{$pkg};
  };
  my @methods = sort grep s/^cmd_//, keys %$stash;
  die "Usage: @{[basename($0)]} method args..\n  "
    . join("\n  ", @methods) . "\n";
}

1;
# -for_dbic
# -for_sqlengine
# -for_sqlt
