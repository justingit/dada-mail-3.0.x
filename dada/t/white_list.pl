#!/usr/bin/perl 

use strict; 
use lib qw(./t ./ ./DADA/perllib ../ ../DADA/perllib ../../ ../../DADA/perllib ); 

BEGIN{$ENV{NO_DADA_MAIL_CONFIG_IMPORT} = 1}
use dada_test_config; 
my $list = dada_test_config::create_test_list({-remove_existing_list => 1, -remove_subscriber_fields => 1});



use DADA::MailingList::Subscribers; 


# Filter stuff

my @email_list = qw(

    user@example.com
    user
    example.com
    @example.com
    
);


my $lh = DADA::MailingList::Subscribers->new({-list => $list}); 


use DADA::MailingList::Settings; 
my $ls = DADA::MailingList::Settings->new({-list => $list}); 
   $ls->save({enable_white_list => 1}); 
my $li = $ls->get(); 
ok($li->{enable_white_list} == 1, "white list enabled."); 



my $count = $lh->add_to_email_list(-Email_Ref => [qw(
                                            test
                                                 )], 
                                   -Type     => 'white_list',
                          );
 
ok($count == 1, "added one address to the white list.");                           
undef($count); 

my ($subscribed, $not_subscribed, $black_listed, $not_white_listed, $invalid) 
    = $lh->filter_subscribers(
		{
        	-emails => ['test@example.com'],
   		}
	);        
ok(eq_array($subscribed,         []                  ) == 1, "Subscribed"); 
ok(eq_array($not_subscribed,     ['test@example.com']) == 1, "Not Subscribed"); 
ok(eq_array($not_white_listed,   []                  ) == 1, "Black Listed"); 
ok(eq_array($black_listed,       []                  ) == 1, "White Listed"); 
ok(eq_array([],                  []) == 1, "Invalid");

undef($subscribed);
undef($not_subscribed);
undef($black_listed);
undef($not_white_listed);
undef($invalid);

my ($subscribed, $not_subscribed, $black_listed, $not_white_listed, $invalid) 
    = $lh->filter_subscribers(
		{
        	-emails => ['user@example.com'],
		}
	);        
ok(eq_array($subscribed,         []                  ) == 1, "Subscribed"); 
ok(eq_array($not_subscribed,     []                  ) == 1, "Not Subscribed"); 
ok(eq_array($not_white_listed,   ['user@example.com']) == 1, "White Listed"); 
ok(eq_array($black_listed,       []                  ) == 1, "Black Listed"); 
ok(eq_array([],                  []                  ) == 1, "Invalid"); 

my $r_count = $lh->remove_from_list(-Email_List => [qw(test)], -Type => 'white_list'); 
ok($r_count == 1, "removed one address from white list");                           
undef($r_count);






my $count = $lh->add_to_email_list(-Email_Ref => [qw(
                                            test
                                                 )], 
                                   -Type     => 'white_list',
                          );
ok($count == 1, "added one address to the white list.");                           
undef($count); 

                   
my @not_white_listed_addresseses = ('user@example.com', 'another@here.com', 'blah@somewhere.co.uk');
foreach my $not_white_listed_addresses(@not_white_listed_addresseses){
    my ($status, $errors) = $lh->subscription_check(
								{
									-email => $not_white_listed_addresses,
								}
							);
    ok($status == 0, "Status is 0"); 
    ok($errors->{not_white_listed} == 1, "Address was not_white_listed");
}

my $r_count = $lh->remove_from_list(-Email_List => [qw(test)], -Type => 'white_list'); 
ok($r_count == 1, "removed one address from white list");                           
undef($r_count);




my $count = $lh->add_to_email_list(-Email_Ref => [qw(example.com)], 
                                   -Type     => 'white_list',
                          );
 
 
ok($count == 1, "added one address to the white list.");                           
undef($count); 


my @white_listed_addresses = ('user@example.com', 'another@example.com', 'blah@example.com');
foreach my $white_listed_addresses(@white_listed_addresses){
    my ($status, $errors) = $lh->subscription_check(
								{
									-email => $white_listed_addresses,
    							}
							);
    foreach(keys %$errors){ 
        diag($_ . ' => ' . $errors->{$_}); 
    }
    ok($status == 1, "Status is 1"); 
    ok($errors->{not_white_listed} == 0, "Address ($white_listed_addresses) was White Listed");
}

my $r_count = $lh->remove_from_list(-Email_List => [qw(example.com)], -Type => 'white_list'); 
ok($r_count == 1, "removed one address from white list");                           
undef($r_count);




# Black List addresses have more of a precedence than white listed addresses. 
# If an address is subscribed to both - the black listed will precende the 
# white listed stuff and the address won't be able to be subscribed. 







   $ls->save({black_list => 1}); 
   $li = $ls->get(); 
ok($li->{black_list} == 1, "black list enabled."); 



my $count = $lh->add_to_email_list(-Email_Ref => [qw(
                                            example.com
                                                 )], 
                                   -Type     => 'white_list',  
  
  );
  
  

ok($count == 1, "added one address to the white list.");                           
undef($count); 


my $count = $lh->add_to_email_list(-Email_Ref => [qw(
                                            example.com
                                                 )], 
                                   -Type     => 'black_list',
                          );
ok($count == 1, "added one address to the black list.");                           
undef($count); 





my ($status, $errors) = $lh->subscription_check(
							{
								-email => 'test@example.com',
							}
						);
  ok($status == 0, "Status is 0"); 
    ok($errors->{black_listed} == 1, "Address is black listed.");


my $r_count = $lh->remove_from_list(-Email_List => [qw(example.com)], -Type => 'black_list'); 
ok($r_count == 1, "removed one address from black list");                           
undef($r_count);


my ($status, $errors) = $lh->subscription_check(
							{
								-email => 'test@example.com',
							}
						);
  ok($status == 1, "Status is 1"); 
  if($status == 0){ 
    foreach(keys %$errors){ 
        diag 'test@example.com Error: ' . $_;
    }
  }
  
  ok($errors->{black_listed} == 0, "Address is NOT black listed.");





my $r_count = $lh->remove_from_list(-Email_List => [qw(example.com)], -Type => 'white_list'); 
ok($r_count == 1, "removed one address from white list");                           
undef($r_count);

dada_test_config::remove_test_list;
dada_test_config::wipe_out;



