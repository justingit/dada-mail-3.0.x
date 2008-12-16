#!/usr/bin/perl -w
use strict; 

use lib qw(./t ./ ./DADA/perllib ../ ../DADA/perllib ../../ ../../DADA/perllib 
	
	/Users/justin/Documents/DadaMail/build/bundle/perllib
	
	
	); 
BEGIN{$ENV{NO_DADA_MAIL_CONFIG_IMPORT} = 1}
use dada_test_config; 

#use Test::More qw(no_plan); 

use DADA::Config qw(!:DEFAULT); 

use DADA::App::Guts; 
use DADA::MailingList::Settings; 


my $list = dada_test_config::create_test_list;
my $ls  = DADA::MailingList::Settings->new({-list => $list}); 
   

   
### check_for_valid_email
 
ok(check_for_valid_email('test@example.com')             == 0); 
ok(check_for_valid_email('test@example.co.uk')           == 0); 
ok(check_for_valid_email('test.one.two@example.co.uk')   == 0); 
ok(check_for_valid_email('test@example.nu')              == 0); 
ok(check_for_valid_email('test+0@example.nu')            == 0); 
ok(check_for_valid_email('test')                         == 1); 
ok(check_for_valid_email('test@example')                 == 1); 
ok(check_for_valid_email('example.co.uk')                == 1); 
ok(check_for_valid_email('newline@example.com' . "\n")   == 1); 
ok(check_for_valid_email('newline@example.com' . "\r\n") == 1); 
ok(check_for_valid_email('newline@example.com' . "\r")   == 1); 


TODO: {
    local $TODO = 'This test fails, see bug report at: http://rt.cpan.org/Public/Bug/Display.html?id=24465';
       
   # diag("Next test will fail."); 
   # diag("See: http://rt.cpan.org/Public/Bug/Display.html?id=24465 ");
    ok(check_for_valid_email('test @example.nu')           == 1); 

};



ok(check_for_valid_email('test+0')                     == 1); 



### strip

ok(strip(' foo ') eq 'foo'); 
ok(strip('foo ')  eq 'foo'); 
ok(strip(' foo')  eq 'foo'); 



### pretty

ok(pretty('_foo_') eq ' foo '); 
ok(pretty('foo_')  eq 'foo '); 
ok(pretty('_foo')  eq ' foo'); 


### make_pin
### check_email_pin


### make_template


my $template = 'blah blah blah'; 


ok(make_template() eq undef); 
ok(make_template({ -List => $list }) eq undef); 
ok(make_template({ -List => $list, -Template => $template }) == 1); 

my $template_file = $DADA::Config::TEMPLATES . '/' . $list . '.template'; 


ok(-e $template_file); 

    open my $TEMPLATE_FILE, '<', $template_file
        or die $!;

    my $template_info = do { local $/; <$TEMPLATE_FILE> };

    close $TEMPLATE_FILE
        or die $!;
 
ok($template_info eq $template, 'Template info saved correctly'); 




### delete_list_template

ok(delete_list_template() eq undef); 
ok(delete_list_template( { -List => $list })); 
ok(! -e $template_file); 



### delete_list_info
### delete_email_list



### check_if_list_exists

ok(check_if_list_exists(-List => $list)        == 1); 
ok(check_if_list_exists(-List => 'idontexist') == 0); 




my $Remove = DADA::MailingList::Remove({ -name => $list }); 
ok($Remove == 1, "Remove returned a status of, '1'");

ok(date_this(-Packed_Date => '20061120024010') =~ m{(\s*)November 20th 2006(\s*)}); 
ok(date_this(-Packed_Date => '20061120024010', -All => 1) =~ m{(\s*)November 20th 2006 2:40:10 a.m.(\s*)}); 


# t/corpus/html/utf8.html


### csv_subscriber_parse
$list = dada_test_config::create_test_list;

    diag('csv_subscriber_parse'); 
    
    require DADA::MailingList::Subscribers; 
    my $lh = DADA::MailingList::Subscribers->new({-list => $list}); 

	SKIP: {

	    skip "Multiple Subscriber Fields is not supported with this current backend." 
	        if $lh->can_have_subscriber_fields == 0;
	
	    
	    ok($lh->add_subscriber_field({-field => 'First_Name'})); 
	    ok($lh->add_subscriber_field({-field => 'Last_Name'})); 
    
	    my @test_files = qw(
	    DOS.csv
	    DOS2.csv
	    Mac.csv
	    Mac2.csv
	    Unix.csv
	    Unix2.csv
	    );
    
	    foreach my $test_file(@test_files){ 
    
	        `cp t/corpus/csv/$test_file $DADA::Config::TMP/$test_file`;
        
	        my ($new_emails, $new_info) = DADA::App::Guts::csv_subscriber_parse($list, $test_file);
	        ok($new_emails->[0] eq 'example1@example.com', 'example1@example.com');
	        ok($new_emails->[1] eq 'example2@example.com', 'example2@example.com');
	        ok($new_emails->[2] eq 'example3@example.com', 'example3@example.com');
        
	        ok($new_info->[0]->{email} eq 'example1@example.com',      'example1@example.com');
	        ok($new_info->[0]->{fields}->[0]->{name}  eq 'first_name', "first_name");
	        ok($new_info->[0]->{fields}->[0]->{value} eq 'Example',    "Example");
	        ok($new_info->[0]->{fields}->[1]->{name}  eq 'last_name',  "last_name");
	        ok($new_info->[0]->{fields}->[1]->{value} eq 'One',         "One");
    
	        ok($new_info->[1]->{email} eq 'example2@example.com');
	        ok($new_info->[1]->{fields}->[0]->{name}  eq 'first_name');
	        ok($new_info->[1]->{fields}->[0]->{value} eq 'Example');
	        ok($new_info->[1]->{fields}->[1]->{name}  eq 'last_name');
	        ok($new_info->[1]->{fields}->[1]->{value} eq 'Two');
    
	        ok($new_info->[2]->{email} eq 'example3@example.com');
	        ok($new_info->[2]->{fields}->[0]->{name}  eq 'first_name');
	        ok($new_info->[2]->{fields}->[0]->{value} eq 'Example');
	        ok($new_info->[2]->{fields}->[1]->{name}  eq 'last_name');
	        ok($new_info->[2]->{fields}->[1]->{value} eq 'Three');
        
        
	        # It's kina weird this subroutine removes the file but... ok!
	        ok(! -e $DADA::Config::TMP . '/$test_file'); 
	    }
    
    
    
	    ok($lh->remove_subscriber_field({-field => 'First_Name'})); 
	    ok($lh->remove_subscriber_field({-field => 'Last_Name'})); 
	
} # Skip


### /csv_subscriber_parse

# isa_url

ok(isa_url('http://example.com') == 1, 'http://example.com seems to be a URL!');
ok(isa_url('example.com')        == 0, 'example.com does not seem to be a URL!');
ok(isa_url('ftp://example.com')  == 1, 'ftp://example.com seems to be a URL!');
ok(isa_url('ical://example.com') == 1, 'ical://example.com seems to be a URL!');


dada_test_config::remove_test_list;
dada_test_config::wipe_out;


