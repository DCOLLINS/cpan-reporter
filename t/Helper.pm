package t::Helper;
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

use vars qw/@EXPORT/;
@EXPORT = qw/
    test_grade_make test_grade_make_plan
    test_grade_PL test_grade_PL_plan
    test_grade_test test_grade_test_plan
    test_fake_config test_fake_config_plan
    test_report test_report_plan
    test_dispatch test_dispatch_plan
/;

use base 'Exporter';

use Config;
use File::Basename qw/basename/;
use File::Copy::Recursive qw/dircopy/;
use File::Path qw/mkpath/;
use File::pushd qw/tempd/;
use File::Spec ();
use File::Temp qw/tempdir/;
use IO::CaptureOutput qw/capture/;
use Probe::Perl ();
use Test::More;

use t::MockHomeDir;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $perl = Probe::Perl->find_perl_interpreter();
my $make = $Config{make};

my $temp_stdout = File::Temp->new() 
    or die "Couldn't make temporary file:$!\nIs your temp drive full?";

my $home_dir = t::MockHomeDir::home_dir();
my $config_dir = File::Spec->catdir( $home_dir, ".cpanreporter" );
my $config_file = File::Spec->catfile( $config_dir, "config.ini" );

my $bogus_email_from = 'johndoe@example.com';
my $bogus_email_to = 'no_one@example.com';
my $bogus_smtp = 'mail.mail.com';

my %tool_constants = (
    'eumm'  => {
        module  => 'ExtUtils::MakeMaker',
        have    => eval "require ExtUtils::MakeMaker" || 0,
        PL      => 'Makefile.PL',
    },
    'mb'    => {
        module  => 'Module::Build',
        have    => eval "require Module::Build" || 0,
        PL      => 'Build.PL'
    },
);

my $max_report_length = 50_000; # 50K

# used to capture from fixtures
use vars qw/$sent_report @cc_list/;

#--------------------------------------------------------------------------#
# test config file prep
#--------------------------------------------------------------------------#

sub test_fake_config_plan() { 3 }
sub test_fake_config {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my %overrides = @_;

    is( File::HomeDir::my_documents(), t::MockHomeDir::home_dir(),
        "home directory mocked"
    ); 
    mkpath $config_dir;
    ok( -d $config_dir,
        "config directory created"
    );

    my $tiny = Config::Tiny->new();
    $tiny->{_}{email_from} = $bogus_email_from;
    $tiny->{_}{email_to} = $bogus_email_to; # failsafe
    $tiny->{_}{smtp_server} = $bogus_smtp;
    $tiny->{_}{send_report} = "yes";
    $tiny->{_}{send_duplicates} = "yes"; # tests often repeat same stuff
    for my $key ( keys %overrides ) {
        $tiny->{_}{$key} = $overrides{$key};
    }
    ok( $tiny->write( $config_file ),
        "created temp config file"
    );
}

#--------------------------------------------------------------------------#
# Test grade_PL
#--------------------------------------------------------------------------#

sub test_grade_PL_iter_plan() { 5 }
sub test_grade_PL_plan() { test_grade_PL_iter_plan() * 2 } 
sub test_grade_PL {
    my ($case, $dist) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    local $ENV{PERL_MM_USE_DEFAULT} = 1;
    my $short_name = _short_name( $dist );

    for my $tool ( qw/eumm mb/ ) {
        SKIP: {
            my ($have_tool,$tool_mod,$tool_PL) = 
                @{$tool_constants{$tool}}{qw/have module PL/};
            my $tool_label = $tool eq 'eumm'  ? "Makefile.PL" 
                                            : "Build.PL";
            my $tool_cmd = "$perl $tool_label"; 

            skip "$tool_mod not installed or working", test_grade_PL_iter_plan()
                if ! $have_tool;
            
            my $tempd = _ok_clone_dist_dir( $case->{name} );
            local $dist->{build_dir} = "$tempd";
            
            $t::Helper::sent_report = undef;
            $t::Helper::comments = undef;

            my ($stdout, $stderr, $build_rc, $test_build_rc, 
                $output, $exit_value, $rc);

            eval {
                capture sub {
                    ($output, $exit_value) = 
                        CPAN::Reporter::record_command($tool_cmd);
                    $rc = CPAN::Reporter::grade_PL(
                        $dist, $tool_cmd, $output, $exit_value
                    );
                }, \$stdout, \$stderr;
            };
            if ( $@ ) {
                diag "DIED WITH:\n$@";
                _diag_output( $stdout, $stderr );
                skip "died grading PL", test_grade_PL_iter_plan() - 1;
            }
            
            my $is_rc_correct = $case->{"$tool\_success"} 
                              ? $rc : ! $rc;

            ok( $is_rc_correct, 
                "$case->{name}: grade_PL() for $tool_PL returned " . 
                $case->{"$tool\_success"}
            );
            
            my $case_grade = $case->{"$tool\_grade"};
            my $is_grade_correct;

            # Grade evaluation with special case if discarding
            my ($found_grade_result, $found_msg) = 
                ( $stdout =~ /^CPAN::Reporter: ([^,]+), ([^\n]+)/ms );
            if ( $case_grade eq 'discard' ) {
                is ($found_grade_result, "test results were not valid",
                    "$case->{name}: '$tool_label' saw test results not valid message"
                );
                    
                like( $stdout, 
                    "/Test report will not be sent/",
                    "$case->{name}: discard message correct"
                ) and $is_grade_correct++;

                ok( ! defined $t::Helper::sent_report,
                    "$case->{name}: test results discarded"
                );
            }
            else {
                my ($found_grade) = ( $found_grade_result =~ /$tool_label result is '([^']+)'/ );
                is( $found_grade, $case_grade, 
                    "$case->{name}: '$tool_label' grade reported as '$case_grade'"
                ) or _diag_output( $stdout, $stderr );
                
                my $ctr_regex = "/preparing a CPAN Testers report for \Q$short_name\E/";
                
                if ( $case_grade eq 'pass' ) {
                    unlike( $stdout, $ctr_regex ,
                        "$case->{name}: report notification correct"
                    ) and $is_grade_correct++;
                    ok( ! defined $t::Helper::sent_report,
                        "$case->{name}: results not sent"
                    );
                }
                else {
                    like( $stdout, $ctr_regex ,
                        "$case->{name}: report notification correct"
                    ) and $is_grade_correct++;
                    if ( -r $config_file ) {
                        ok( defined $t::Helper::sent_report && length $t::Helper::sent_report,
                            "$case->{name}: report was mock sent"
                        );
                    }
                    else {
                        ok( ! defined $t::Helper::sent_report,
                            "$case->{name}: results not sent"
                        );
                    }
                }
            }

            _diag_output( $stdout, $stderr ) 
                unless ( $is_rc_correct && $is_grade_correct );
        } # SKIP
    } # for
}

#--------------------------------------------------------------------------#
# Test grade_make
#--------------------------------------------------------------------------#

sub test_grade_make_iter_plan() { 6 }
sub test_grade_make_plan() { test_grade_make_iter_plan() * 2 } 
sub test_grade_make {
    my ($case, $dist) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    local $ENV{PERL_MM_USE_DEFAULT} = 1;
    my $short_name = _short_name( $dist );

    for my $tool ( qw/eumm mb/ ) {
        SKIP: {
            my ($have_tool,$tool_mod,$tool_PL) = 
                @{$tool_constants{$tool}}{qw/have module PL/};
            my $tool_cmd = $tool eq 'eumm' ? $Config{make} : "$perl Build";
            my $tool_label = $tool eq 'eumm' ? $Config{make} : "Build";

            skip "$tool_mod not installed or working", test_grade_make_iter_plan()
                if ! $have_tool;
            
            # Set up temporary directory for the case
            my $tempd = _ok_clone_dist_dir( $case->{name} );

            $t::Helper::sent_report = undef;
            $t::Helper::comments = undef;

            my ($stdout, $stderr, $build_err, $test_build_rc, 
                $output, $exit_value, $rc);

            capture sub {
                $build_err = system("$perl $tool_PL");
            }, \$stdout, \$stderr;

            ok( ! $build_err, "$case->{name}: $tool_PL successful" )
                or do {
                    _diag_output( $stdout, $stderr );
                    skip "$tool_PL failed", test_grade_make_iter_plan() - 1;
                };
            eval {
                capture sub {
                    ($output, $exit_value) = 
                    CPAN::Reporter::record_command($tool_cmd);
                    $rc = CPAN::Reporter::grade_make(
                        $dist, $tool_cmd, $output, $exit_value
                    );
                }, \$stdout, \$stderr;
            };
            if ( $@ ) {
                diag "DIED WITH:\n$@";
                _diag_output( $stdout, $stderr );
                skip "died grading make", test_grade_make_iter_plan() - 1;
            }

            my $is_rc_correct = $case->{"$tool\_success"} 
            ? $rc : ! $rc;

            ok( $is_rc_correct, 
                "$case->{name}: grade_make() for $tool_label returned " . 
                $case->{"$tool\_success"}
            );

            my $case_grade = $case->{"$tool\_grade"};
            my $is_grade_correct;

            # Grade evaluation with special case if discarding
            my ($found_grade_result, $found_msg) = 
                ( $stdout =~ /^CPAN::Reporter: ([^,]+), ([^\n]+)/ms );
            if ( $case_grade eq 'discard' ) {
                is ($found_grade_result, "test results were not valid",
                    "$case->{name}: '$tool_label' prerequisites not satisifed"
                );
                    
                like( $stdout, 
                    "/Test report will not be sent/",
                    "$case->{name}: discard message correct"
                ) and $is_grade_correct++;

                ok( ! defined $t::Helper::sent_report,
                    "$case->{name}: test results discarded"
                );
            }
            else {
                my ($found_grade) = ( $found_grade_result =~ /$tool_label result is '([^']+)'/ );
                is( $found_grade, $case_grade, 
                    "$case->{name}: '$tool_label' grade reported as '$case_grade'"
                ) or _diag_output( $stdout, $stderr );
                
                my $ctr_regex = "/preparing a CPAN Testers report for \Q$short_name\E/";
                
                if ( $case_grade eq 'pass' ) {
                    unlike( $stdout, $ctr_regex ,
                        "$case->{name}: report notification correct"
                    ) and $is_grade_correct++;
                    ok( ! defined $t::Helper::sent_report,
                        "$case->{name}: results not sent"
                    );
                }
                else {
                    like( $stdout, $ctr_regex ,
                        "$case->{name}: report notification correct"
                    ) and $is_grade_correct++;
                    if ( -r $config_file ) {
                        ok( defined $t::Helper::sent_report && length $t::Helper::sent_report,
                            "$case->{name}: report was mock sent"
                        );
                    }
                    else {
                        ok( ! defined $t::Helper::sent_report,
                            "$case->{name}: results not sent"
                        );
                    }
                }
            }

            _diag_output( $stdout, $stderr )
                unless ( $is_rc_correct && $is_grade_correct );

        } #SKIP
    } #for   
}

#--------------------------------------------------------------------------#
# Test grade_test
#--------------------------------------------------------------------------#

sub test_grade_test_iter_plan() { 7 }
sub test_grade_test_plan() { 2 * test_grade_test_iter_plan() }
sub test_grade_test {
    my ($case, $dist) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    local $ENV{PERL_MM_USE_DEFAULT} = 1;
    my $short_name = _short_name( $dist );

    for my $tool ( qw/eumm mb/ ) {
        SKIP: {
            my ($have_tool,$tool_mod,$tool_PL) = 
                @{$tool_constants{$tool}}{qw/have module PL/};
            my $tool_cmd = $tool eq 'eumm'  ?  "$make test"
                                            :  "$perl Build test" ;
            my $tool_label = $tool eq 'eumm'?  "make test"
                                            :  "perl Build test" ;

            skip "$tool_mod not installed or working", test_grade_test_iter_plan()
                if ! $have_tool; 

            my $tempd = _ok_clone_dist_dir( $case->{name} );
                
            $t::Helper::sent_report = undef;
            $t::Helper::comments = undef;

            my ($stdout, $stderr, $build_err, $test_build_rc);

            capture sub {
                $build_err = system("$perl $tool_PL");
            }, \$stdout, \$stderr;

            ok( ! $build_err, "$case->{name}: $tool_PL successful" )
                or do {
                    _diag_output( $stdout, $stderr );
                    skip "$tool_PL failed", test_grade_test_iter_plan() - 1;
                };

            eval {
                capture sub {
                    $test_build_rc = CPAN::Reporter::test( $dist, $tool_cmd )
                }, \$stdout, \$stderr;
            };
            if ( $@ ) {
                diag "DIED WITH:\n$@";
                _diag_output( $stdout, $stderr );
                skip "test() died", test_grade_test_iter_plan() - 1;
            }

            my $is_rc_correct = $case->{"$tool\_success"} 
                              ? $test_build_rc : ! $test_build_rc;
            ok( $is_rc_correct, 
                "$case->{name}: '$tool_label' returned " . 
                $case->{"$tool\_success"}
            );
            
            # Grade evaluation with special case if discarding
            my ($found_grade_result, $found_msg) = 
                ( $stdout =~ /^CPAN::Reporter: (Test result[^,]+), ([^\n]+)$/ims );
            if ( $case->{"$tool\_grade"} eq 'discard' ) {
                is ($found_grade_result, "test results were not valid",
                    "$case->{name}: '$tool_label' prerequisites not satisifed"
                );
                    
                like( $stdout, 
                    "/Test report will not be sent/",
                    "$case->{name}: discard message correct"
                );

                ok( ! defined $t::Helper::sent_report,
                    "$case->{name}: test results discarded"
                );
            }
            else {
                my $case_grade = $case->{"$tool\_grade"};
                my ($found_grade) = ( $found_grade_result =~ /Test result is '([^']+)'/ );
                is( $found_grade, $case_grade, 
                    "$case->{name}: '$tool_label' grade reported as '$case_grade'"
                ) or _diag_output( $stdout, $stderr );
                
                like( $stdout, "/preparing a CPAN Testers report for \Q$short_name\E/",
                    "$case->{name}: report notification correct"
                );

                if ( -r $config_file ) {
                    ok( defined $t::Helper::sent_report && length $t::Helper::sent_report,
                        "$case->{name}: test report was mock sent"
                    );
                }
                else {
                    ok( ! defined $t::Helper::sent_report,
                        "$case->{name}: test results not sent"
                    );
                }
            }
            
            # Grade explanation message
            is( $found_msg, 
                $case->{"$tool\_msg"} ? $case->{"$tool\_msg"} . q{.} : q{},
                "$case->{name}: '$tool_label' grade explanation correct"
            );

        } #SKIP
    } #for
}

#--------------------------------------------------------------------------#
# report tests
#--------------------------------------------------------------------------#

my %report_para = (
    'pass' => <<'HERE',
Thank you for uploading your work to CPAN.  Congratulations!
All tests were successful.
HERE

    'fail' => <<'HERE',
Thank you for uploading your work to CPAN.  However, there was a problem
testing your distribution.

If you think this report is invalid, please consult the CPAN Testers Wiki
for suggestions on how to avoid getting FAIL reports for missing library
or binary dependencies, unsupported operating systems, and so on:

http://wiki.cpantesters.org/wiki/CPANAuthorNotes
HERE

    'unknown' => << 'HERE',
Thank you for uploading your work to CPAN.  However, attempting to
test your distribution gave an inconclusive result.  

This could be because your distribution had an error during the make/build
stage, did not define tests, tests could not be found, because your tests were
interrupted before they finished, or because the results of the tests could not
be parsed.  You may wish to consult the CPAN Testers Wiki:

http://wiki.cpantesters.org/wiki/CPANAuthorNotes
HERE

    'na' => << 'HERE',
Thank you for uploading your work to CPAN.  While attempting to build or test 
this distribution, the distribution signaled that support is not available 
either for this operating system or this version of Perl.  Nevertheless, any 
diagnostic output produced is provided below for reference.  If this is not 
what you expect, you may wish to consult the CPAN Testers Wiki:

http://wiki.cpantesters.org/wiki/CPANAuthorNotes
HERE
    
);

sub test_report_plan() { 13 };
sub test_report {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($case) = @_;
    my $label = "$case->{label}:";
    my $expected_grade = $case->{expected_grade};
    my $prereq = CPAN::Reporter::_prereq_report( $case->{dist} );
    my $msg_re = $report_para{ $expected_grade };
    my $default_comment = $ENV{AUTOMATED_TESTING}
        ? "this report is from an automated smoke testing program\nand was not reviewed by a human for accuracy"
        : "none provided" ;

    my $tempd = _ok_clone_dist_dir( $case->{name} );
                
    my ($stdout, $stderr, $err, $test_output) = _run_report( $case );
    
    is( $err, q{}, 
        "$label report ran without error" 
    );

    ok( defined $msg_re && length $msg_re,
        "$label found '$expected_grade' grade paragraph"
    );
    
    # set PERL_MM_USE_DEFAULT to mirror _run_report
    local $ENV{PERL_MM_USE_DEFAULT} = 1;
    my $env_vars = CPAN::Reporter::_env_report();
    my $special_vars = CPAN::Reporter::_special_vars_report();
    my $toolchain_versions = CPAN::Reporter::_toolchain_report();
    
    like( $t::Helper::sent_report, '/' . quotemeta($msg_re) . '/ms',
        "$label correct intro paragraph"
    );

    like( $t::Helper::sent_report, '/' . quotemeta($default_comment) . '/ms',
        "$label correct default comment"
    );

    like( $t::Helper::sent_report, '/' . quotemeta($prereq) . '/ms',
        "$label found prereq report"
    );
    
    like( $t::Helper::sent_report, '/' . quotemeta($env_vars) . '/ms',
        "$label found environment variables"
    );
    
    like( $t::Helper::sent_report, '/' . quotemeta($special_vars) . '/ms',
        "$label found special variables"
    );
    
    like( $t::Helper::sent_report, '/' . quotemeta($toolchain_versions) . '/ms',
        "$label found toolchain versions found"
    );
    
    my $joined_output = join("", @$test_output);

    # extract just the test output
    my $found_test_output = q{};
    if ( $t::Helper::sent_report =~ m/
        ^Output\ from\ '[^\']+':\n          # lead-in to test output
        ^\n                                 # blank line
        ^(.+) \n                            # test output ending in newline
        ^------------------------------ \n  # separator
        ^PREREQUISITES \n                   # next section
        /xms ) 
    {
        $found_test_output = $1;
    }
    
    my $orig_found_length = length $found_test_output;
    ok( $orig_found_length, "$label located test output in report" );
    
    # if output appears longer than max, the excess should only be the
    # error message, so look for it, strip it and check it
    my $length_error = q{};
    my $max_in_k = int($max_report_length / 1000) . "K";
    if ( $found_test_output =~ m/
        ^(.+)\n             # test output ending in a newline
        ^\n                 # blank line
        ^(\[[^\n]+\]) \n    # stuff in brackets
        ^\n                 # blank line
        \z
        /xms
    ) {
        $found_test_output = $1;
        $length_error = $2;
    }

    if ( length $joined_output > $max_report_length ) {
        is( $length_error, "[Output truncated after $max_in_k]",
            "$label truncated length error message correct"
        )
    }
    else {
        pass( "$label no truncation message seen" );
    }

    # after extracting error, if any, the output should now be
    # less than the max length
    my $found_length = length $found_test_output;
    ok( $found_length <= $max_report_length, 
        "$label test_output less than or equal to maximum length"
    ) or diag "length $found_length > $max_report_length";

    # confirm that we indeed got the test output we expected
    # (whether all or just a truncated portion)
    if ( length $joined_output > $max_report_length ) {
        $joined_output = substr( $joined_output, 0, $max_report_length );
    }

    like( $t::Helper::sent_report, '/' . quotemeta($joined_output) . '/ms',
        "$label found output matches expected output"
    );

    return ($stdout, $stderr, $err, $test_output);
};

#--------------------------------------------------------------------------#
# test_dispatch
#
# case requires
#   label -- prefix for text output
#   dist -- mock dist object
#   name -- name for t/dist/name to copy
#   command -- command to execute within copy of dist dir
#   phase -- phase of PL/make/test to pass command results to
#--------------------------------------------------------------------------#

sub test_dispatch_plan { 4 };
sub test_dispatch {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $case = shift;
    my %opt = @_;

    my $tempd = _ok_clone_dist_dir( $case->{name} );
    local $case->{dist}{build_dir} = "$tempd";
                
    my ($stdout, $stderr, $err) = _run_report( $case );

    is( $err, q{}, 
            "generate report for $case->{label}" 
    );

    if ( $opt{will_send} ) {
        ok( defined $t::Helper::sent_report && length $t::Helper::sent_report,
            "report was sent for $case->{label}"
        );
        like( $stdout, "/sending test report with/",
            "saw report sent message for $case->{label}"
        );
    }
    else {
        ok( ! defined $t::Helper::sent_report,
            "report not sent for $case->{label}"
        );
        like( $stdout, "/report will not be sent/",
            "saw report not sent message for $case->{label}"
        );
    }

    return ($stdout, $stderr, $err);
}

#--------------------------------------------------------------------------#
# _diag_output
#--------------------------------------------------------------------------#

sub _diag_output {
    my ( $stdout, $stderr ) = @_;
    diag "STDOUT:\n$stdout\n\nSTDERR:\n$stderr\n"; 
}

#--------------------------------------------------------------------------#
# _ok_clone_dist_dir
#--------------------------------------------------------------------------#

sub _ok_clone_dist_dir {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $dist_name = shift;
    my $dist_dir = File::Spec->rel2abs(
        File::Spec->catdir( qw/t dist /, $dist_name )
    );
    my $work_dir = tempd() 
        or die "Couldn't create temporary distribution dir: $!\n";

    # workaround badly broken F::C::R 0.34 on Windows
    if ( File::Copy::Recursive->VERSION eq '0.34' && $^O eq 'MSWin32' ) {
        ok( 0 == system("xcopy /q /e $dist_dir $work_dir"),
            "Copying $dist_name to temp directory (XCOPY)"
        ) or diag $!;
    }
    else {
        ok( defined( dircopy($dist_dir, "$work_dir") ),
            "Copying $dist_name to temp directory $work_dir"
        ) or diag $!;
    }

    return $work_dir;
}

#--------------------------------------------------------------------------#
# _run_report
#--------------------------------------------------------------------------#

sub _run_report {
    my $case = shift;
    my $phase = $case->{phase};

    # automate CPAN::Reporter prompting
    local $ENV{PERL_MM_USE_DEFAULT} = 1;
    
    my ($stdout, $stderr, $output, $exit_value);
    
    $t::Helper::sent_report = undef;
    $t::Helper::comments = undef;

    eval {
        capture sub {
            # run any preliminaries to the command we want to record
            if ( $phase eq 'make' || $phase eq 'test' ) {
                system("$perl Makefile.PL");
            }
            if ( $phase eq 'test' ) {
                system("$make");
            }
            ($output, $exit_value) = 
                CPAN::Reporter::record_command( $case->{command} );
            no strict 'refs';
            &{"CPAN::Reporter::grade_$phase"}(
                $case->{dist},
                $case->{command},
                $output,
                $exit_value,
            );
        } => \$stdout, \$stderr;
    }; 
    if ( $@ ) {
        diag "DIED WITH:\n$@";
        _diag_output( $stdout, $stderr );
    }

    return ($stdout, $stderr, $@, $output);
}

#--------------------------------------------------------------------------#
# _short_name
#--------------------------------------------------------------------------#

sub _short_name {
    my $dist = shift;
    my $short_name = basename($dist->pretty_id);
    $short_name =~ s/(\.tar\.gz|\.tgz|\.zip)$//i;
    return $short_name;
}

#--------------------------------------------------------------------------#
# Mocking
#--------------------------------------------------------------------------#

BEGIN {
    $INC{"Test/Reporter.pm"} = 1; # fake load
}

package Test::Reporter;
use vars qw/$AUTOLOAD/;

sub new { return bless {}, 'Test::Reporter::Mocked' }

package Test::Reporter::Mocked;
use Config;
use vars qw/$AUTOLOAD/;

sub comments { shift; $t::Helper::comments = shift }

sub send { 
    shift; 
    $t::Helper::sent_report = $t::Helper::comments; 
    return 1 
} 

sub subject {
    my $self = shift;
    return uc($self->grade) . ' ' . $self->distribution .
        " $Config{archname} $Config{osvers}";
}

my %mocked_data;

my @valid_transport = qw/Mail::Send Net::SMTP Net::SMTP::Auth HTTP/;

sub transport {
    my ($self) = shift;
    if (@_) {
        my $t = shift;
        die __PACKAGE__ . ":transport: '$t' is invalid\n"
            unless grep { $t eq $_ } @valid_transport;
        $mocked_data{transport} = $t;
    }
    return $mocked_data{transport};
}
  
# must do this one manually so ->can('distfile') is true
sub distfile {
  my $self = shift;
  if ( @_ ) {
    $mocked_data{ distfile } = shift;
  }
  return $mocked_data{ distfile };
}

sub AUTOLOAD {
    my $self = shift;
    if ( @_ ) {
        $mocked_data{ $AUTOLOAD } = shift;
    }
    return $mocked_data{ $AUTOLOAD };
}


1;
