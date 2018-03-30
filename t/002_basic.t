use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use FindBin;
use lib "$FindBin::Bin/lib";
my $t = Test::Mojo->with_roles('+Slovo')->install()->new('Slovo');
$t->get_ok('/')->status_is(200)->content_like(qr/Mojolicious/i);

done_testing();