package Slovo::Model::Domove;
use Mojo::Base -base, -signatures;

has 'dbx';

sub add ($self, $row) {
  return $self->dbx->db->insert('domove', $row)->last_insert_id;
}

sub all ($self, $opts = {}) {
  $opts->{limit} //= 100;
  $opts->{limit} = 100 unless $opts->{limit} =~ /^\d+$/;
  $opts->{offset} //= 0;
  $opts->{offset} = 0 unless $opts->{offset} =~ /^\d+$/;
  state $abstr = $self->dbx->abstract;
  my ($sql, @bind) = $abstr->select('domove', '*', $opts->{where} // ());
  $sql .= " LIMIT $opts->{limit}"
    . ($opts->{offset} ? " OFFSET $opts->{offset}" : '');
  return $self->dbx->db->query($sql, @bind)->hashes->to_array;
}

sub find ($self, $id) {
  return $self->dbx->db->select('domove', undef, {id => $id})->hash;
}

sub remove ($self, $id) {
  return $self->dbx->db->delete('domove', {id => $id});
}

sub save ($self, $id, $row) {
  return $self->dbx->db->update('domove', $row, {id => $id});
}

1;
