# $Header$
#
# 00basic.t - test harness for Batch::Temp - basic tests
#
# History:
# $Log$
use Log::Log4perl qw/ :easy /; Log::Log4perl->easy_init($ERROR);

use Data::Dumper;
use File::Glob;

use Test::More tests => 31;

BEGIN { use_ok('Batch::Temp') };


# -------- global variables --------
my $log = get_logger(__FILE__);
my $c_this = "Batch::Temp";
my $cycle = 1;
my @parms = qw/ echo fatal prefix retry /;
my $dummy = "foobar";


# -------- new / initilaisation --------
my $obj1 = Batch::Temp->new;
my $obj2 = Batch::Temp->new( map{ $_ => $dummy } @parms);

$log->info("creating new $c_this objects...");

isa_ok( $obj1, $c_this,	'new no args');
isa_ok( $obj2, $c_this,	'new with args');


# -------- simple attributes: numbers --------
for my $parm (@parms) {

	isnt($obj1->$parm, -1,			"default $parm cycle_$cycle");

	my $default = $obj1->$parm;
	my $assign = !$default;

	is($obj1->$parm($assign), $assign,	"assign $parm cycle_$cycle");
	isnt($obj1->$parm, $default,		"check $parm cycle_$cycle");

	$log->debug(sprintf "parm [$parm]=%d", $obj1->$parm);

	ok($obj1->$parm >= 0,			"integer $parm cycle_$cycle");
	is($obj1->$parm($default), $default,	"reset $parm cycle_$cycle");

	ok($obj2->$parm eq $dummy,		"dummy $parm cycle_$cycle");
	ok($obj1->$parm ne $obj2->$parm,	"override $parm cycle_$cycle");

        $cycle++;
}


# -------- finalise --------
$log->info("processing complete.");

__END__

=head1 DESCRIPTION

00basic.t - test harness for Batch::Temp - basic tests

=head1 VERSION

$Revision: 1.7 $

=head1 AUTHOR

Copyright (C) 2017  B<Tom McMeekin> tmcmeeki@cpan.org

=head1 LICENSE

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published
by the Free Software Foundation; either version 2 of the License,
or any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

=head1 SEE ALSO

L<perl>.

=cut

