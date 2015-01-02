#!perl
use strict;
use warnings;
use Test::More 0.96;
use Test::Warn;
use Encode qw(decode FB_CROAK);

# Enable utf-8 encoding so we do not get Wide character in print
# warnings when reporting test failures
use open qw{:encoding(UTF-8) :std};

# Test files
my $test_root     = "corpus.tmp";
my $unicode_file  = "\x{30c6}\x{30b9}\x{30c8}\x{30d5}\x{30a1}\x{30a4}\x{30eb}";
my $unicode_dir   = "\x{30c6}\x{30b9}\x{30c8}\x{30c6}\x{3099}\x{30a3}\x{30ec}\x{30af}\x{30c8}\x{30ea}";

if ($^O eq 'dos' or $^O eq 'os2') {
    plan skip_all => "Skipped: $^O does not have proper utf-8 file system support";
} else {
    # Create test files
    mkdir $test_root
        or die "Unable to create directory $test_root: $!"
        unless -d $test_root;
    mkdir "$test_root/$unicode_dir"
        or die "Unable to create directory $test_root/$unicode_dir: $!"
        unless -d "$test_root/$unicode_dir";
    for ("$unicode_dir/bar", $unicode_file) {
        open my $touch, '>', "$test_root/$_" or die "Couldn't open $test_root/$_ for writing: $!";
        close   $touch                       or die "Couldn't close $test_root/$_: $!";
    }
}

# Expected output of find commands
my @expected = sort ($test_root, "$test_root/$unicode_file", "$test_root/$unicode_dir", "$test_root/$unicode_dir/bar");

plan tests => 3;

# Runs find tests

for my $test (qw(find finddepth)) {
    subtest "utf8$test" => sub {
        plan tests => 8;

        # To keep results in
        my @files;
        my @utf8_files;

        # Use normal find to gather list of files in the test_root directory
        {
            use File::Find;
            (\&{$test})->({ no_chdir => 1, wanted => sub { push(@files, $_) if $_ !~ /^\.{1,2}$/ } }, $test_root);
        }

        # Use utf8 version of find to gather list of files in the test_root directory
        {
            use File::Find::utf8;
            (\&{$test})->({ no_chdir => 1, wanted => sub { push(@utf8_files, $_) if $_ !~ /^\.{1,2}$/ } }, $test_root);
        }

        # Compare results
        @files      = sort @files;
        @utf8_files = sort @utf8_files;
        is_deeply \@utf8_files, \@expected, "$test all utf8 files are present";
        is                   $files[0]            => $utf8_files[0], "$test normal directory";
        isnt                 $files[1]            => $utf8_files[1], "$test unicode file bytes != chars";
        is   decode('UTF-8', $files[1], FB_CROAK) => $utf8_files[1], "$test unicode file chars == chars";
        isnt                 $files[2]            => $utf8_files[2], "$test unicode dir bytes != chars";
        is   decode('UTF-8', $files[2], FB_CROAK) => $utf8_files[2], "$test unicode dir chars == chars";
        isnt                 $files[3]            => $utf8_files[3], "$test file in unicode dir bytes != chars";
        is   decode('UTF-8', $files[3], FB_CROAK) => $utf8_files[3], "$test file in unicode dir chars == chars";
    }
}

# Check if warnings levels progate well
subtest warninglevels => sub {
    plan tests => 3;

    use File::Find::utf8;

    # Test no warnings in File::Find
    warning_is
        {
            no warnings 'File::Find';
            find( { no_chdir => 1, wanted => sub { } }, "$test_root/does_not_exist");
        }
        undef, 'No warning for non-existing directory';

    # Test warnings in File::Find
    warning_like
        {
            #use warnings 'File::Find'; # This is actually the default
            find( { no_chdir => 1, wanted => sub { } }, "$test_root/does_not_exist");
        }
        qr/Can't stat $test_root\/does_not_exist/, 'Warning for non-existing directory' or diag $@;

    # Test fatal warnings in File::Find
    warning_like
        {
            eval {
                use warnings FATAL => 'File::Find';
                find( { no_chdir => 1, wanted => sub { } }, "$test_root/does_not_exist");
            };
            warn $@ if $@;
        }
        qr/Can't stat $test_root\/does_not_exist/, 'Fatal warning for non-existing directory' or diag $@;
}
