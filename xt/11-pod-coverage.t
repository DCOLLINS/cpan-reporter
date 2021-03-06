use Test::More;
use t::Helper; # Fake homedir, other mocks

my $min_tpc = 1.08;
eval "use Test::Pod::Coverage $min_tpc";
plan skip_all => "Test::Pod::Coverage $min_tpc required for testing POD coverage"
    if $@;

my $min_pc = 0.17;
eval "use Pod::Coverage $min_pc";
plan skip_all => "Pod::Coverage $min_pc required for testing POD coverage"
    if $@;

my @modules = all_modules();

plan tests => scalar @modules;

my %doc_map = (
    'CPAN::Reporter' => 'CPAN::Reporter::API'
);

for my $mod ( @modules ) {
    my %opts;
    if ( exists $doc_map{$mod} ) {
        $mod = $doc_map{$mod};
    }
    $opts{pod_from} = "lib/$mod\.pod";
    $opts{pod_from} =~ s{::}{/}g;
    pod_coverage_ok( $mod, \%opts );
}
