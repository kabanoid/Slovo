package Slovo::Model::Stranici;
use Mojo::Base 'Slovo::Model', -signatures;
use feature qw(lexical_subs unicode_strings);
## no critic qw(TestingAndDebugging::ProhibitNoWarnings)
no warnings "experimental::lexical_subs";
use Slovo::Model::Celini;

my $table        = 'stranici';
my $celini_table = Slovo::Model::Celini->table;

has not_found_id    => 4;
has table           => $table;
has title_data_type => 'заглавѥ';
has celini          => sub { $_[0]->c->celini };

# Returns a list of page alises and titles in the current languade for
# displaying as breadcrumb. No permission filters are applied because if the
# user gets to this page, he should have passed throu all filters from the
# parrent page to this page. This SQL is supported now even in MySQL 8.
# https://stackoverflow.com/questions/324935/mysql-with-clause#325243
# https://sqlite.org/lang_with.html
sub breadcrumb ($m, $pid, $l) {
  state $sqla = $m->dbx->abstract;
  my $lang_like = {'c.language' => $m->celini->language_like($l)};
  state $LSQL = ($sqla->where($lang_like) =~ s/WHERE//r);
  my @lang_like = map { $_->{'-like'} } $sqla->values($lang_like);
  state $SQL = <<"SQL";
WITH RECURSIVE pids(p)
  AS(VALUES(?) UNION SELECT pid FROM $table s, pids WHERE s.id = p)
  SELECT s.alias, c.title, c.language FROM $table s, $celini_table c
  WHERE s.id IN pids
    AND c.page_id = s.id
    AND $LSQL
    AND c.data_type = 'заглавѥ'
    AND s.page_type !='коренъ';
SQL
  my $rows = $m->dbx->db->query($SQL, $pid, @lang_like)->hashes;

  return $rows;
}

# Returns a structure for a 'where' clause to be shared among select methods
# for pages to be displayed in the site.
sub _where_with_permissions ($m, $user, $domain, $preview) {

  my $now = time;

  # Match by domain or one of the domain aliases or IPs - in that order. This
  # is to give chance to all domains and their aliases to match in case the
  # request URL does not start with an IP. In case the request URL starts with
  # an IP (e.g. http://127.0.0.1/some/route) the first domain record with that
  # IP will take the request.
  state $domain_sql = <<"SQL";
= (SELECT id FROM domove
    WHERE (? LIKE '%' || domain OR aliases LIKE ? OR ips LIKE ?) AND published = ? LIMIT 1)
SQL

  return {
    # must not be deleted
    $preview ? () : ("$table.deleted" => 0),

    # must be available within a given range of time values
    $preview ? () : ("$table.start" => [{'=' => 0}, {'<' => $now}]),
    $preview ? () : ("$table.stop"  => [{'=' => 0}, {'>' => $now}]),

    # the page must belong to the current domain
    "$table.dom_id" =>
      \[$domain_sql, => ($domain, "%$domain%", "%$domain%", 2)],

    # TODO: May be drop this column as 'hidden' can be
    # implemented by putting '.' as first character for the alias.
    $preview ? () : ("$table.hidden" => 0),

    -or => [

      # published and everybody can read and execute
      # This page can be stored on disk and served as static page
      # after displayed for the first time
      {"$table.published" => 2, "$table.permissions" => {-like => '%r_x'}},

      # preview of a page, owned by this user
      {
       "$table.user_id"     => $user->{id},
       "$table.permissions" => {-like => '_r_x%'}
      },

      # preview of a page, which can be read and executed
      # by one of the groups to which this user belongs.
      {
       "$table.permissions" => {-like => '____r_x%'},
       "$table.published"   => $preview ? 1 : 2,

    # TODO: Implement 'adding users to multiple groups in /Ꙋправленѥ/users/:id':
       "$table.group_id" => \[
           "IN (SELECT group_id from user_group WHERE user_id=?)" => $user->{id}
       ],
      },
    ]
  };
}

# Find a page by $alias which can be seen by the current user
sub find_for_display ($m, $alias, $user, $domain, $preview) {

  #local $m->dbx->db->dbh->{TraceLevel} = "3|SQL";
  return
    $m->dbx->db->select(
                        $table, undef,
                        {
                         alias => $alias,
                         %{
                           $m->_where_with_permissions(
                                                       $user, $domain, $preview
                                                      )
                          }
                        }
                       )->hash;
}


sub add ($m, $row) {
  $row->{tstamp} = time - 1;
  $row->{start} //= $row->{tstamp};
  my $title = {};
  @$title{qw(title language body data_format)}
    = delete @$row{qw(title language body data_format)};
  @$title{
    qw(sorting data_type created_at user_id
      group_id changed_by alias permissions published)
    }
    = (
    0,
    $m->title_data_type,
    @$row{
      qw(tstamp user_id
        group_id changed_by alias permissions published)
    }
    );
  my $db = $m->dbx->db;
  eval {
    my $tx = $db->begin;
    $title->{page_id} = $db->insert($table, $row)->last_insert_id;
    $db->insert($celini_table, $title);
    $tx->commit;
  } || Carp::croak("Error creating stranici record: $@");
  return $title->{page_id};
}


sub find_for_edit ($m, $id, $l) {
  my $db = $m->dbx->db;
  my $p = $db->select($table, undef, {id => $id})->hash;
  my $title = $db->select(
                          $celini_table,
                          'title,body,language,id as title_id',
                          {
                           page_id   => $id,
                           language  => $m->celini->language_like($l),
                           data_type => $m->title_data_type,
                           sorting   => 0,
                           box       => 'main'
                          },
                          {-asc => ['sorting', 'id']}
                         )->hash // {};
  return {%$p, %$title};
}

sub save ($m, $id, $row) {
  my $title = {};

  # Get the values for celini
  @$title{
    qw(page_id title body language id data_format
      alias changed_by permissions published)
    }
    = (
       $id,
       delete @$row{qw(title body language title_id data_format)},
       @$row{qw(alias changed_by permissions published)}
      );
  my $db = $m->dbx->db;
  eval {
    my $tx = $db->begin;
    $db->update($table,        $row,   {id => $id});
    $db->update($celini_table, $title, {id => $title->{id}});
    $tx->commit;
  } || Carp::croak("Error updating stranici record: $@");

  return $id;
}

sub remove ($self, $id) {
  return $self->dbx->db->update($table, {deleted => 1}, {id => $id});
}

# Transforms a column accordingly as passed from $opts->{columns} and returns
# the transfromed column.
## no critic (Modules::RequireEndWithOne)
my sub _transform_columns($col) {
  if ($col eq 'title' or $col eq 'language') {
    return "$/$celini_table.$col AS $col";
  }
  elsif ($col eq 'is_dir') {
    return "$/EXISTS (SELECT 1 WHERE $table.permissions LIKE 'd%') AS is_dir";
  }

  # local $db->dbh->{TraceLevel} = "3|SQL";
  return "$/$table.$col AS $col";
}

# Returns all pages for listing in a sidebar or via Swagger API. Beware not to
# mention one column twice as a key in the WHERE clause, because only the
# second mention will remain for generating the SQL.
sub all_for_list ($self, $user, $domain, $preview, $l, $opts = {}) {
  $opts->{table} = [$table, $celini_table];
  my @columns = map { _transform_columns($_) } @{$opts->{columns}};
  $opts->{columns} = join ",", @columns;
  my $pid = delete $opts->{pid} // 0;
  $opts->{where} = {
    "$table.pid" => $pid,

    # avoid any potential recursion
    # must not be the not_found_id
    "$table.id" =>
      {-not_in => [$self->not_found_id, $pid ? () : {-ident => "$table.pid"}]},
    "$celini_table.page_id"   => {-ident => "$table.id"},
    "$celini_table.data_type" => $self->title_data_type,
    "$celini_table.language"  => $self->celini->language_like($l),
    "$celini_table.box" => [{-in => ['main', 'главна', '']}, {'=' => undef}],
    %{$self->_where_with_permissions($user, $domain, $preview)},
    %{$self->celini->where_with_permissions($user, $preview)},
    %{$opts->{where} // {}}
                   };

  # local $db->dbh->{TraceLevel} = "3|SQL";
  return $self->all($opts);
}


# Get all pages under current (home) page which have заглавѥ which is directory
# (i.e.  contains articles) and get 6 articles for each. $opts contains only
# two keys (stranici_opts, and celini_opts). They will be passed respectively to
# all_for_list() and all_for_display_in_stranica().
sub all_for_home ($m, $user, $domain, $preview, $l, $opts = {}) {
  state $ct = $celini_table;
  state $t  = $table;
  my $stranici_opts = {

    #columns => $list_columns,
    #pid     => $page->{pid},
    where => {"$ct.permissions" => {-like => 'd%'}},
    %{delete $opts->{stranici_opts}}
  };
  my $celini_opts = {
          columns => 'title, id, alias, substr(body,1,255) as teaser, language',
          limit   => 6,
          where   => {"$ct.data_type" => {'!=' => 'заглавѥ'}},
          %{delete $opts->{celini_opts}}
  };

  return $m->all_for_list($user, $domain, $preview, $l, $stranici_opts)->each(
    sub ($p, $i) {
      state $SQL = <<"SQL";
=(SELECT id FROM $ct
  WHERE pid=? AND page_id=? AND data_type=? limit 1)
SQL
      my $opts = {%$celini_opts};    #copy
      $opts->{where}{"$ct.pid"} = \[$SQL, 0, $p->{id}, 'заглавѥ'];
      $p->{articles}
        = $m->celini->all_for_display_in_stranica($p, $user, $l, $preview,
                                                  $opts);
    }
  );
}

# Returns list of languages for this page in which we have readable by the
# current user content.
# Arguments: Current page alias, user, preview mode or not.
sub languages ($m, $alias, $u, $prv) {
  my $db = $m->dbx->db;

  my $where = {
    page_id   => \["=(SELECT id FROM $table WHERE alias=?)", $alias],
    data_type => 'заглавѥ',
    box       => ['main', 'главна'],

    # and those titles are readable by the current user
    %{$m->celini->where_with_permissions($u, $prv)},
              };

  #local $db->dbh->{TraceLevel} = "3|SQL";
  return
    $db->select(
                $celini_table, 'DISTINCT title,language',
                $where, {-asc => [qw(sorting id)]}
               )->hashes;
}


1;
