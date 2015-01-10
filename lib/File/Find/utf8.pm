package File::Find::utf8;
use strict;
use warnings;
use 5.010; # state

# ABSTRACT: Fully UTF-8 aware File::Find
# VERSION

=for test_synopsis
my @directories_to_search;

=head1 SYNOPSIS

    # Use the utf-8 versions of find and finddepth
    use File::Find::utf8;
    find(\&wanted, @directories_to_search);

    # Revert back to non-utf-8 versions
    no File::Find::utf8;
    finddepth(\&wanted, @directories_to_search);

    # Export only the find function
    use File::Find::utf8 qw(find);
    find(\&wanted, @directories_to_search);

    # Export no functions
    use File::Find::utf8 qw(:none); # NOT "use File::Find::utf8 qw();"!
    File::Find::find(\&wanted, @directories_to_search);

=head1 DESCRIPTION

While the original L<File::Find> functions are capable of handling
UTF-8 quite well, they expect and return all data as bytes, not as
characters.

This module replaces the L<File::Find> functions with fully UTF-8
aware versions, both expecting and returning characters.

B<Note:> Replacement of functions is not done on DOS, Windows, and OS/2
as these systems do not have full UTF-8 file system support.

=head2 Behaviour

The module behaves as a pragma so you can use both C<use
File::Find::utf8> and C<no File::Find::utf8> to turn utf-8 support on
or off.

By default, both find() and finddepth() are exported (as with the original
L<File::Find>), if you want to prevent this, use C<use File::Find::utf8
qw(:none)>. (As all the magic happens in the module's import function,
you can not simply use C<use File::Find::utf8 qw()>)

L<File::Find> warning levels are properly propagated. Note though that
for propagation of fatal L<File::Find> warnings, Perl 5.12 or higher
is required (or the appropriate version of L<warnings>).

=head1 COMPATIBILITY

The filesystems of Dos, Windows, and OS/2 do not (fully) support
UTF-8. The L<File::Find> function will therefore not be replaced on these
systems.

=head1 SEE ALSO

=for :list
* L<File::Find> -- The original module.
* L<Cwd::utf8> -- Fully utf-8 aware version of the L<Cwd> functions.
* L<utf8::all> -- Turn on utf-8, all of it.
  This was also the module I first added the utf-8 aware versions of
  L<Cwd> and L<File::Find> to before moving them to their own package.

=cut

use File::Find qw();
use Encode;

# Holds the pointers to the original version of redefined functions
state %_orig_functions;

# Current (i.e., this) package
my $current_package = __PACKAGE__;

# Original package (i.e., the one for which this module is replacing the functions)
my $original_package = $current_package;
$original_package =~ s/::utf8$//;

require Carp;
$Carp::Internal{$current_package}++; # To get warnings reported at correct caller level

sub import {
    # Target package (i.e., the one loading this module)
    my $target_package = caller;

    # If run on the dos/os2/windows platform, ignore overriding functions silently.
    # These platforms do not have (proper) utf-8 file system suppport...
    unless ($^O =~ /MSWin32|cygwin|dos|os2/) {
        no strict qw(refs); ## no critic (TestingAndDebugging::ProhibitNoStrict)
        no warnings qw(redefine);

        # Redefine each of the functions to their UTF-8 equivalent
        for my $f (@{$original_package . '::EXPORT'}, @{$original_package . '::EXPORT_OK'}) {
            # If we already have the _orig_function, we have redefined the function
            # in an earlier load of this module, so we need not do it again
            unless ($_orig_functions{$f}) {
                $_orig_functions{$f} = \&{$original_package . '::' . $f};
                *{$original_package . '::' . $f} = \&{"_utf8_$f"};
            }
        }
        $^H{$current_package} = 1; # Set compiler hint that we should use the utf-8 version
    }

    # Determine symbols to export
    shift; # First argument contains the package (that's us)
    @_ = (':DEFAULT') if !@_; # If nothing provided, use default
    @_ = map { $_ eq ':none' ? () : $_ } @_; # Replace :none tag with empty list

    # Use exporter to export
    require Exporter;
    Exporter::export_to_level($original_package, 1, $target_package, @_) if (@_);

    return;
}

sub unimport { ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    $^H{$current_package} = 0; # Set compiler hint that we should not use the utf-8 version
    return;
}

sub _utf8_find {
    my $ref = shift; # This can be the wanted function or a find options hash
    #  Make argument always into the find's options hash
    my %find_options_hash = ref($ref) eq "HASH" ? %$ref : (wanted => $ref);

    # Save original processors
    my %org_proc;
    for my $proc ("wanted", "preprocess", "postprocess") { $org_proc{$proc} = $find_options_hash{$proc}; }

    my @args = @_;

    # Get the hint from the caller (one level deeper if called from finddepth)
    my $hints = ((caller 1)[3]//'') ne 'File::Find::utf8::_utf8_finddepth' ? (caller 0)[10] : (caller 1)[10];
    if ($hints->{$current_package}) {
        # Wrap processors to become utf8-aware
        for my $proc ("wanted", "preprocess", "postprocess") {
            if (defined $org_proc{$proc} && ref $org_proc{$proc}) {
                $find_options_hash{$proc} = sub {
                    # Decode the file variables so they become characters
                    local $_                    = decode('UTF-8', $_);
                    local $File::Find::name     = decode('UTF-8', $File::Find::name);
                    local $File::Find::dir      = decode('UTF-8', $File::Find::dir);
                    local $File::Find::fullname = decode('UTF-8', $File::Find::fullname);
                    local $File::Find::topdir   = decode('UTF-8', $File::Find::topdir);
                    local $File::Find::topdev   = decode('UTF-8', $File::Find::topdev);
                    local $File::Find::topino   = decode('UTF-8', $File::Find::topino);
                    local $File::Find::topmode  = decode('UTF-8', $File::Find::topmode);
                    local $File::Find::topnlink = decode('UTF-8', $File::Find::topnlink);
                    $org_proc{$proc}->(@_);
                };
            }
        }
        # Encode arguments as utf-8 so that the original File::Find receives bytes
        @args = map { encode('UTF-8', $_) } @_;
    }

    # Make sure warning level propagates to File::Find
    # Note: on perl prior to v5.12 warnings_fatal_enabled does not exist
    #       so we can not use it.
    if (!warnings::enabled('File::Find')) {
        no warnings 'File::Find';
        return $_orig_functions{find}->(\%find_options_hash, @args);
    } elsif (!exists &warnings::fatal_enabled or !warnings::fatal_enabled('File::Find')) {
        use warnings 'File::Find';
        return $_orig_functions{find}->(\%find_options_hash, @args);
    } else {
        use warnings FATAL => qw(File::Find);
        return $_orig_functions{find}->(\%find_options_hash, @args);
    }
}

sub _utf8_finddepth {
    my $ref = shift; # This can be the wanted function or a find options hash
    return _utf8_find( { bydepth => 1, ref($ref) eq "HASH" ? %$ref : (wanted => $ref) }, @_);
}

1;
