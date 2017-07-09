package Batch::Exec;
# $Header: /home/tomby/src/perl/RCS/zzz_template_class.pm,v 1.11 2015/09/25 21:10:51 tomby Exp $
#
# Batch::Exec - Batch executive framework: common routines and error handling
#
# History:
# $Log$

=head1 NAME

Batch::Exec - Batch executive framework: common routines and error handling

=head1 AUTHOR

Copyright (C) 2017  B<Tom McMeekin> E<lt>tmcmeeki@cpan.orgE<gt>

=head1 SYNOPSIS

  use Batch::Exec;
  blah blah blah

=head1 DESCRIPTION

The batch executive is a series of modules which provide a framework for
batch processing.  The fundamental principles of the executive are as follows:

=over 4

=item a.  Log it.

Provide as much detail as possible about what step you are up to and what
you're trying to do.

=item b.  Check it.

Don't keep processing if the last command fails.  Always check that the
last step succeeded.

=item c.  Tidy up.

If you're creating a bunch of temporary files to assist with processing, then
eventually you'll need to clean up after yourself.

=back

This framework applies wrapper routines to existing perl modules and functions,
and attempts to provides for a more consistent experience
for batch scripting, execution and debugging.  Whilst the bulk of handling is
geared at convenience (e.g. avoiding repetitive error checking and logging),
there are some very specific functions that form part of good batch 
frameworks, such as semaphore-controlled counting.

The batch executive comprises the following modules:

B<Batch::Exec>	(common routines and error handling)

B<Batch::Log>	(logging and debugging message handling)

B<Batch::Counter>	(semaphore-controlled access to counter files)

B<Batch::Temp>	(temporary file and directory creation and purge).

The Batch::Exec module provides a very simple series of functions, and the 
basis for the other modules in this series.  Specifically, it covers
shell execution and status checking, along with file/directory creation 
and deletion.  It comprises the following attributes and methods:

=cut

#use 5.010000;
use strict;
use warnings;

# --- includes ---
use Carp qw(cluck confess);     # only use stack backtrace within class
use Data::Dumper;
use Cwd;
use File::Basename;
use File::Path;
use Scalar::Util;	# check filehandle

#use Batch::Log qw/ :all /;
use Logfer qw/ :all /;

use vars qw/ @EXPORT $VERSION /;


# --- package constants ---
use constant PREFIX_TMP => basename($0);


# --- package globals ---
$VERSION = sprintf "%d.%03d", q$Revision: 1.11 $ =~ /(\d+)/g;
our $AUTOLOAD;


# --- package locals ---
my $_n_objects = 0;     # counter of objects created.

=over 4

=item 1a.  OBJ->echo(EXPR)

Echo the stdout from the B<execute()> method to the log.
Takes a boolean (0 or 1) argument.
Default is 0 (disabled).

=item 1b.  OBJ->fatal(EXPR)

Controls whether failed status checks "die".
Default is 1 (enabled).

=item 1c.  OBJ->prefix(EXPR)

File prefix, defaults to the basename of the program (i.e. argv[0]).

=item 1d.  OBJ->retry(EXPR)

Retry count for the execute method.
Default is 1 (attempt only once).

=cut

my %attribute = (
	_n_objects => \$_n_objects,
	_id => undef,
	_log => get_logger("Batch::Exec"),
	_dn_start => cwd,       # default this value, may need it later!
	echo => 0,
	fatal => 1,
	prefix => PREFIX_TMP,
	retry => 1,
);


#INIT { };


sub AUTOLOAD {
	my $self = shift;
	my $type = ref($self) or confess "$self is not an object";

	my $name = $AUTOLOAD;
	$name =~ s/.*://;   # strip fully−qualified portion

	unless (exists $self->{_permitted}->{$name} ) {
		confess "no attribute [$name] in class [$type]";
	}

	if (@_) {
		return $self->{$name} = shift;
	} else {
		return $self->{$name};
	}
}


sub new {
	my ($class) = shift;
	#my $self = $class->SUPER::new(@_);
	my $self = { _permitted => \%attribute, %attribute };

	$self->{_id} = ++ ${ $self->{_n_objects} };

	bless ($self, $class);

	my %args = @_;	# start processing any parameters passed
	my ($method,$value);
	while (($method, $value) = each %args) {

		confess "SYNTAX new(method => value, ...) value not specified"
			unless (defined $value);

		$self->_log->debug("method [self->$method($value)]");

		$self->$method($value);
	}

	return $self;
}


DESTROY {
	my $self = shift;

	-- ${ $self->{_n_objects} };
}


=item 2a.  OBJ->cough(EXPR)

Issue warning or fatal message (EXPR) based on fatal attribute.

=cut

sub cough {
	my $self = shift;
	my $msg = shift;

	$self->_log->logdie("FATAL $msg")
		if ($self->fatal);

	$self->_log->logwarn("WARNING $msg");

	return 1;
}


=item 2b.  OBJ->delete(EXPR)

Remove the file or directory specified from the filesystem, i.e. unlink or
this module's rmdir() function.

=cut

sub delete {	# delete a file or directory
	my $self = shift;
	my $pn = shift;
	confess "SYNTAX: delete(EXPR)" unless defined ($pn);

	if (-d $pn) {

		return $self->rmdir($pn);

	} elsif (-f $pn) {

		$self->_log->info("removing file [$pn]")
			if (${^GLOBAL_PHASE} ne 'DESTRUCT');

		unlink($pn) || $self->cough("unlink($pn) failed");
	}

	return ($self->cough("could not remove file [$pn]"))
		if (-f $pn);

	return 0;
}


=item 2c.  OBJ->execute([EXPR1], [ARRAY_REF], EXPR2, ...)

Attempt to run the command (arguments starting with EXPR2) via readpipe().
EXPR1 is the retry count (which defaults to 1).  Output can be stored in
the ARRAY_REF, if needed for subsequent processing.  The echo attribute
allows output to be logged.

=cut

sub execute {
	my $self = shift;
	my $c_retry = shift;
	my $ra_stdout = shift;	# optional; will hold command stdout
	my $command = join(" ", @_);
	my $c_exec;
	my ($retval, $stdout);

	$self->_log->info("about to execute [$command]");

	$self->{'retry'} = 1 if (not defined $self->{'retry'});

	$self->_log->debug(sprintf "retry [%s] command [$command]",
		$self->{'retry'});

	for ($c_exec = 0; $c_exec < $self->{'retry'}; $c_exec++) {

		$self->_log->debug("c_exec [$c_exec]");

		$stdout = readpipe($command);
		$retval = $?;

		last unless ($retval);
	}

	$self->_log->info("command output:");

	for (split(/\n+/, $stdout)) {

		if ($self->{'echo'}) {
			$self->_log->info("stdout: $_");
		}

		push @$ra_stdout, $_
			if (defined $ra_stdout);
	}

	return( $self->cough(sprintf "command [%s] failed after %d retries",
		$command, $self->{'retry'}))
		if ($retval ne 0);

	return 0;
}


=item 2d.  OBJ->header(FILEHANDLE)

Writes a nice header (generated-by program & timestamp) to the filehandle
specified by FILEHANDLE.
Will check if FILEHANDLE is both a filehandle and points to an open file.

=cut

sub header {
	my $self = shift;
	my $fh = openhandle(shift);
	confess "SYNTAX: header(FILEHANDLE)" unless defined ($fh);

	printf $fh "# ---- automatically generated by %s ----\n", $self->{'prefix'};

	printf $fh "# ---- timestamp %s ---- \n", scalar(localtime(time));
}

1;

__END__

=back

=cut

=head1 VERSION

$Revision: 1.11 $

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

L<perl>, L<Cwd>, L<File::Path>, L<Batch::Log>.

=cut

