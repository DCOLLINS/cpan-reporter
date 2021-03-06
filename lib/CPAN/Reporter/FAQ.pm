package CPAN::Reporter::FAQ;
# Not really a .pm file, but holds wikidoc which will be
# turned into .pod by the Build.PL
use strict; # make CPANTS happy
use vars qw/$VERSION/;
$VERSION = '1.1708'; 
$VERSION = eval $VERSION; ## no critic
1;
__END__

=begin wikidoc

= NAME

CPAN::Reporter::FAQ - Answers and tips for using CPAN::Reporter

= VERSION

This documentation refers to version %%VERSION%%

= REPORT GRADES

== Why did I receive a report? 

Historically, CPAN Testers was designed to have each tester send a copy of
reports to authors.  This philosophy changed in September 2008 and CPAN Testers
tools were updated to no longer copy authors, but some testers may still be
using an older versions.

== Why was a report sent if a prerequisite is missing?

As of CPAN::Reporter 0.46, FAIL and UNKNOWN reports with unsatisfied 
prerequisites are discarded.  Earlier versions may have sent these reports 
out by mistake as either an NA or UNKNOWN report.

PASS reports are not discarded because it may be useful to know when tests
passed despite a missing prerequisite.  NA reports are sent because information
about the lack of support for a platform is relevant regardless of
prerequisites.

= SENDING REPORTS

== Why did I get an error sending a test report?

Test reports are sent via ordinary email.  The most common reason for errors
sending a report is that many Internet Service Providers (ISP's) will block
outbound SMTP (email) connections as part of their efforts to fight spam.
Instead, email must be routed to the ISP's outbound mail servers, which will
relay the email to the intended destination.

You can configure CPAN::Reporter to use a specific outbound email server 
with the {smtp_server} configuration option.

 smtp_server = mail.some-isp.com

In at least one case, an ISP has blocked outbound email unless the 
"from" address was the assigned email address from that ISP.

== Why didn't my test report show up on CPAN Testers?

CPAN Testers uses a mailing list to collect test reports.  If the email
address you set in {email_from} is subscribed to the list, your emails
will be automatically processed.  Otherwise, test reports will be held 
until manually reviewed and approved.  

Subscribing an account to the cpan-testers list is as easy as sending a blank
email to cpan-testers-subscribe@perl.org and replying to the confirmation
email.

There is a delay between the time emails appear on the mailing list and the
time they appear on the CPAN Testers website. There is a further delay before
summary statistics appear on search.cpan.org.

If your email address is subscribed to the list but your test reports are still
not showing up, your outbound email may have been silently blocked by your
ISP.  See the question above about errors sending reports.

== Why don't you support sending reports via HTTP or authenticated SMTP?

We do!  See the {transport} option in [CPAN::Reporter::Config].

= CPAN TESTERS

== Where can I find out more about CPAN Testers?

A good place to start is the CPAN Testers Wiki: 
[http://wiki.cpantesters.org/]

== Where can I find statistics about reports sent to CPAN Testers?

CPAN Testers statistics are compiled at [http://stats.cpantesters.org/]

== How do I make sure I get credit for my test reports?

To get credit in the statistics, use the same email address wherever 
you run tests.

For example, if you are a CPAN author, use your PAUSEID email address.

 email_from = pauseid@cpan.org

Otherwise, you should use a consistent "Full Name" as part of your 
email address in the {email_from} option.

 email_from = "John Doe" <john.doe@example.com> 

= SEE ALSO

* [CPAN::Testers]
* [CPAN::Reporter]
* [Test::Reporter]

= AUTHOR

David A. Golden (DAGOLDEN)

= COPYRIGHT AND LICENSE

Copyright (c) 2006, 2007, 2008 by David A. Golden

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at 
[http://www.apache.org/licenses/LICENSE-2.0]

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=end wikidoc

