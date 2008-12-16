#!/usr/bin/perl 

use strict; 

use lib qw(./t ./ ./DADA/perllib ../ ../DADA/perllib ../../ ../../DADA/perllib); 
BEGIN{$ENV{NO_DADA_MAIL_CONFIG_IMPORT} = 1}
BEGIN{$ENV{NO_DADA_MAIL_CONFIG_IMPORT} = 1}
use dada_test_config; 

my $list  = dada_test_config::create_test_list;
my $list2 = dada_test_config::create_test_list({-name => 'test2'});

use DADA::Config; 
   $DADA::Config::GLOBAL_BLACK_LIST = 1; 

use DADA::MailingList::Subscribers; 
use DADA::MailingList::Settings; 


ok($DADA::Config::GLOBAL_BLACK_LIST == 1, 'Global Black List is set!'); 


my $lh = DADA::MailingList::Subscribers->new({-list => $list}); 

SKIP: {

    skip "Global Black List Not Supported with this backend." 
        if $lh->can_use_global_black_list == 0; 

    my $ls = DADA::MailingList::Settings->new({-list => $list}); 
       $ls->save({black_list => 1}); 
    my $li = $ls->get(); 
    ok($li->{black_list} == 1, "black list enabled."); 
    
    
    
    my $count = $lh->add_to_email_list(-Email_Ref => [qw(
                                                test
                                                     )], 
                                       -Type     => 'black_list',
                              );
     
    ok($count == 1); 
    undef $count; 
    
    ####
    # Global Black List Stuff....
    
    my $ls2 = DADA::MailingList::Settings->new({-list => $list2}); 
    
       $ls2->save({black_list => 1}); 
    
    my $li2 = $ls2->get(); 
    
    ok($li2->{black_list} == 1, "black list enabled."); 
    
    
    my $lh2 = DADA::MailingList::Subscribers->new({-list => $list2}); 
    
    
    
    
    my ($status, $errors) = $lh2->subscription_check(
								{
									-email => 'test@example.com',
								}
							);     
    ok($status == 0, "Status returned 0");
    ok($errors->{black_listed} == 1, "Subscriber is black listed."); 
    undef $status; 
    undef $errors; 
    

    my $r_count = $lh->remove_from_list(-Email_List => ['test'], -Type => 'black_list'); 
    ok($r_count == 1, "removed one address");                           
    undef($r_count); 



    my ($status, $errors) = $lh2->subscription_check(
								{
									-email => 'test@example.com',
								}
							);     
    ok($status == 1, "Status returned 1");
    undef $status; 
    undef $errors; 


## 

} # Skip


### check_for_double_email stuff

    my $count = $lh->add_to_email_list(-Email_Ref => [qw(
                                                test
                                                     )], 
                                       -Type     => 'black_list',
                              );
     
    ok($count == 1); 
    undef $count; 
    
    ok($lh->check_for_double_email(-Email => 'test@example.com', -Type => 'black_list') == 1, "Address is subscribed to black list"); 
    ok($lh->check_for_double_email(-Email => 'test@example.com', -Type => 'black_list', -Match_Type => 'exact') == 0, "Address does not match exactly, though"); 
 

# So here's the setup: 
# The person gets subscribed, gets unsubscribed, 
# Gets moved to the black_list - which is on, but! 
# An error occurs, if they're already on: 

my $sub = 'already_blacklisted@example.com'; 

ok($lh->add_subscriber({-email  => $sub, -type   => 'list', })); 
ok($lh->add_subscriber({-email  => $sub, -type   => 'black_list', })); 
eval {
	$lh->move_subscriber(
		{
			-email => $sub, 
			-from  => 'list', 
			-to    => 'black_list', 
		}
	);
}; 

like($@, qr/is already subscribed to list passed in/, "Trying to writeover an address fails."); 

eval { 

	$lh->move_subscriber(
		{
			-email => $sub, 
			-from  => 'list', 
			-to    => 'black_list', 
			-mode  => 'writeover', 
		}
	); 
}; 



	
ok(!$@, "But passing the, -mode => 'writeover' paramater seems to let this happen just fine.");  







dada_test_config::remove_test_list;
dada_test_config::remove_test_list({-name => 'test2'});
dada_test_config::wipe_out;

