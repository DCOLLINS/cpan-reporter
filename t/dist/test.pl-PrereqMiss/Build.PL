use strict;
use Module::Build;

Module::Build->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    create_makefile_pl  => 'traditional',
    requires => {
        'Bogus::Module::Doesnt::Exist' => 0,
    }
)->create_build_script;
