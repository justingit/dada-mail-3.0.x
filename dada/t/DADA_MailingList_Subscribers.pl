#!/usr/bin/perl 


use lib qw(./t ./ ./DADA/perllib ../ ../DADA/perllib ../../ ../../DADA/perllib ); 
BEGIN{$ENV{NO_DADA_MAIL_CONFIG_IMPORT} = 1}
use dada_test_config; 



diag('$DADA::Config::SUBSCRIBER_DB_TYPE ' . $DADA::Config::SUBSCRIBER_DB_TYPE); 



use strict;

use Carp; 

# This doesn't work, if we're eval()ing it. 
# use Test::More qw(no_plan); 


my $list = dada_test_config::create_test_list({-remove_existing_list => 1, -remove_subscriber_fields => 1});


use DADA::MailingList::Subscribers; 


# Filter stuff

my @email_list = qw(

    user@example.com
    user
    example.com
    @example.com
    
);


chmod(0777, $DADA::Config::TMP . '/mail.txt'); 


my $lh = DADA::MailingList::Subscribers->new({-list => $list}); 


ok($lh->{ls}->isa('DADA::MailingList::Settings'), "looks like there's a Settings obj in ->{ls}, good!"); 

my ($subscribed, $not_subscribed, $black_listed, $not_white_listed, $invalid) 
    = $lh->filter_subscribers(
		{
            -emails => [@email_list],
        }
	);



ok(eq_array($subscribed,       []                                           ) == 1, "Subscribed"); 
ok(eq_array($not_subscribed,   ['user@example.com']                         ) == 1, "Not Subscribed"); 
ok(eq_array($black_listed,     []                                           ) == 1, "Black Listed"); 
ok(eq_array($not_white_listed, []                                           ) == 1, "Not White Listed"); 
ok(eq_array([sort(@$invalid)], [sort('user', 'example.com', '@example.com')]) == 1, "Invalid"); 

undef($subscribed);
undef($not_subscribed);
undef($black_listed);
undef($not_white_listed);
undef($invalid);


my $count = $lh->add_to_email_list(-Email_Ref => [qw(
                                            user@example.com
                                                 )], 
                                   -Type     => 'list',
                          );
                    
ok($count == 1, "added one address");                           
undef($count); 

my ($subscribed, $not_subscribed, $black_listed, $not_white_listed, $invalid) 
    = $lh->filter_subscribers(
		{
            -emails => [@email_list],
        }
	);



ok(eq_array($subscribed,        ['user@example.com']                         ) == 1, "Subscribed"); 
ok(eq_array($not_subscribed,    []                                           ) == 1, "Not Subscribed"); 
ok(eq_array($black_listed,      []                                           ) == 1, "Black Listed"); 
ok(eq_array($not_white_listed,  []                                           ) == 1, "Not White Listed"); 
ok(eq_array([sort(@$invalid)],  [sort('user', 'example.com', '@example.com')]) == 1, "Invalid"); 


undef($subscribed);
undef($not_subscribed);
undef($black_listed);
undef($not_white_listed);
undef($invalid);

my $r_count = $lh->remove_from_list(-Email_List => ['user@example.com']); 
ok($r_count == 1, "removed one address (user\@example.com)");                           
undef($r_count); 




use DADA::MailingList::Settings; 
my $ls = DADA::MailingList::Settings->new({-list => $list}); 
   $ls->save({black_list => 1}); 
my $li = $ls->get(); 
ok($li->{black_list} == 1, "black list enabled."); 



foreach my $blacklist_this('user', 'example.com', 'user@', '@example.com', 'user@example.com', 'u', '@'){ 

    my $count = $lh->add_to_email_list(-Email_Ref => [
                                                $blacklist_this
                                                     ], 
                                       -Type     => 'black_list',
                              );
    
    ok($count == 1, "added one address");                           
    undef($count); 
    
    
    my ($subscribed, $not_subscribed, $black_listed, $not_white_listed, $invalid) 
        = $lh->filter_subscribers(
			{
                -emails => [@email_list],
            }
		);
    
    ok(eq_array($subscribed,      []                                           ) == 1, "Subscribed"); 
    ok(eq_array($not_subscribed,  []                                           ) == 1, "Not Subscribed"); 
    ok(eq_array($black_listed,    ['user@example.com']                         ) == 1, "Black Listed"); 
    ok(eq_array($not_white_listed,[]                                           ) == 1, "Not White Listed"); 
    ok(eq_array([sort(@$invalid)],[sort('user', 'example.com', '@example.com')]) == 1, "Invalid"); 
    
    
    undef($subscribed);
    undef($not_subscribed);
    undef($black_listed);
    undef($not_white_listed);
    undef($invalid);
    
    my $r_count = $lh->remove_from_list(-Email_List => [$blacklist_this], -Type => 'black_list'); 
    ok($r_count == 1, "removed one address from blacklist ($blacklist_this)");                           
    undef($r_count); 

}
   $ls->save({black_list => 0}); 
   $li = $ls->get(); 
ok($li->{black_list} == 0, "black list disabled."); 


# Oh geez. This should have a million tests. 
my @good_addresses = ('user@example.com', 'another@here.com', 'blah@somewhere.co.uk');
foreach my $good_address(@good_addresses){
    my ($status, $errors) = $lh->subscription_check(
								{
									-email => $good_address,
								}
							);
    ok($status == 1, "Status is 1"); 
    ok($errors->{invalid_email} != 1, "Address seen as valid");
}
 


my @bad_addresses = qw(These are all bad addresses yup);
foreach my $bad_address(@bad_addresses){
    my ($status, $errors) = $lh->subscription_check(
								{
									-email => $bad_address,
								}
							);
    ok($status == 0, "Status is 0"); 
    ok($errors->{invalid_email} == 1, "Address seen as invalid");
}
 

ok($lh->can_have_subscriber_fields == 1 || $lh->can_have_subscriber_fields == 0, "'->can_have_subscriber_fields' returns either 1 or 0"); 



 ### move_subscriber
    
        eval { $lh->move_subscriber(); }; 
        ok($@, "calling move_subscriber without any paramaters causes an error!: $@");     

   
        eval { $lh->move_subscriber({-to => 'blahblah'}); }; 
        ok($@, "calling move_subscriber with incorrect -to paramater causes an error!: $@");     

        eval { $lh->move_subscriber({-to => 'blahblah', -from => 'yayaya'}); }; 
        ok($@, "calling move_subscriber wwith incorrect -to and -from paramater causes an error!: $@");     
        
        eval { $lh->move_subscriber({-to => 'blahblah', -from => 'yayaya', -email => 'whackawhacka'}); }; 
        ok($@, "calling move_subscriber with incorrect list_type in, '-to' causes an error!: $@");   

        eval { $lh->move_subscriber({-to => 'list', -from => 'yayaya', -email => 'whackawhacka'}); }; 
        ok($@, "calling move_subscriber with incorrect list_type in, '-from' causes an error!: $@");   


        eval { $lh->move_subscriber({-to => 'list', -from => 'black_list', -email => 'whackawhacka'}); }; 
        ok($@, "calling move_subscriber with invalid address causes an error!: $@");   
        
        

        eval { $lh->move_subscriber({-to => 'list', -from => 'black_list', -email => 'mytest@example.com'}); }; 
        ok($@, "calling move_subscriber with invalid address causes an error!: $@");  
        
        
        ok($lh->add_subscriber({
            -email => 'mytest@example.com',
            -type  => 'list', 
        })); 
    
    
        ok($lh->add_subscriber({
            -email => 'mytest@example.com',
            -type  => 'black_list', 
        }));
        

        

        eval { $lh->move_subscriber({-to => 'list', -from => 'black_list', -email => 'mytest@example.com'}); }; 
        ok($@, "calling move_subscriber with address already subscribed in, '-to' causes error!: $@");          
    
    
        ok($lh->remove_from_list(-Email_List => ['mytest@example.com'], -Type => 'list')); 
        ok($lh->remove_from_list(-Email_List => ['mytest@example.com'], -Type => 'black_list')); 

    ###
    

	#### copy_subscriber
	
    eval { $lh->copy_subscriber(); }; 
    ok($@, "calling copy_subscriber without any paramaters causes an error!: $@");     


    eval { $lh->copy_subscriber({-to => 'blahblah'}); }; 
    ok($@, "calling copy_subscriber with incorrect -to paramater causes an error!: $@");     

    eval { $lh->copy_subscriber({-to => 'blahblah', -from => 'yayaya'}); }; 
    ok($@, "calling copy_subscriber wwith incorrect -to and -from paramater causes an error!: $@");     
    
    eval { $lh->copy_subscriber({-to => 'blahblah', -from => 'yayaya', -email => 'whackawhacka'}); }; 
    ok($@, "calling move_subscriber with incorrect list_type in, '-to' causes an error!: $@");   

    eval { $lh->copy_subscriber({-to => 'list', -from => 'yayaya', -email => 'whackawhacka'}); }; 
    ok($@, "calling copy_subscriber with incorrect list_type in, '-from' causes an error!: $@");   


    eval { $lh->copy_subscriber({-to => 'list', -from => 'black_list', -email => 'whackawhacka'}); }; 
    ok($@, "calling move_subscriber with invalid address causes an error!: $@");   
    
    

    eval { $lh->copy_subscriber({-to => 'list', -from => 'black_list', -email => 'mytest@example.com'}); }; 
    ok($@, "calling move_subscriber with invalid address causes an error!: $@");  
    
    
    ok($lh->add_subscriber({
        -email => 'mytest@example.com',
        -type  => 'list', 
    })); 


    ok($lh->add_subscriber({
        -email => 'mytest@example.com',
        -type  => 'black_list', 
    }));
    

    

    eval { $lh->copy_subscriber({-to => 'list', -from => 'black_list', -email => 'mytest@example.com'}); }; 
    ok($@, "calling copy_subscriber with address already subscribed in, '-to' causes error!: $@");          


    ok($lh->remove_subscriber({-email => 'mytest@example.com', -type => 'list'})); 
    ok($lh->remove_subscriber({-email => 'mytest@example.com', -type => 'black_list'}));	


    ok($lh->add_subscriber({
        -email => 'mytest@example.com',
        -type  => 'list', 
    }));

	ok($lh->copy_subscriber({-to => 'black_list', -from => 'list', -email => 'mytest@example.com'}), "Calling copy_subscriber with correct paramaters works!"); 
	ok($lh->remove_from_list(-Email_List => ['mytest@example.com'], -Type => 'list')); 
    ok($lh->remove_from_list(-Email_List => ['mytest@example.com'], -Type => 'black_list'));	
   
	###
    
SKIP: {

    skip "Multiple Subscriber Fields is not supported with this current backend." 
        if $lh->can_have_subscriber_fields == 0; 


    ok(eq_array($lh->subscriber_fields, []), 'no fields currently present.'); 

    my $s = $lh->add_subscriber_field({-field => 'myfield'}); 
    ok($s == 1, "adding a new field is successful"); 

    ok(eq_array($lh->subscriber_fields, ['myfield']), 'New field is being reported.'); 
    undef($s); 
    my $s = $lh->remove_subscriber_field({-field => 'myfield'}); 
    ok($s == 1, "removing a new field is successful"); 


    ### validate_subscriber_field_name
    
    
        # The order of these is important for later tests....
        my @bad_field_names = (
        'this one has spaces', 
        '"thisOneHasQuotes"', 
        'thisOneIsOverSixtyFourCharactersNoReallyItIsPleaseJustBeleiveMeOnThisOnePleasePleasePleaseOK', 
        '/slashes/', 
        '', 
        '@WeirdCharacters+',
        ); 
        
        foreach my $bfn(@bad_field_names) { 
            my ($errors, $details) = $lh->validate_subscriber_field_name({-field => $bfn});
            ok($errors == 1, "Bad Field is reporting an error."); 
            undef($errors); 
            undef($details); 
        }
        
        my $s = $lh->add_subscriber_field({-field => 'myfield'}); 
        ok(eq_array($lh->subscriber_fields, ['myfield']), 'New field is being reported.'); 
        
        
        my ($errors, $details) = $lh->validate_subscriber_field_name({-field => 'myfield'});
        ok($errors == 1, "Error being reported by duplicate field"); 
        ok($details->{field_exists} == 1, "Error being report as, 'field_exists'"); 
        undef($errors); undef($details);
    
        my $s = $lh->remove_subscriber_field({-field => 'myfield'}); 
        ok($s == 1, "removing a new field is successful"); 
        
        # spaces
        my ($errors, $details) = $lh->validate_subscriber_field_name({-field => $bad_field_names[0]});
        ok($errors == 1, "Error being reported"); 
        ok($details->{spaces} == 1, "Error being report as, 'spaces'"); 
        undef($errors); undef($details);
    
    
        # quotes
        my ($errors, $details) = $lh->validate_subscriber_field_name({-field => $bad_field_names[1]});
        ok($errors == 1, "Error being reported"); 
        ok($details->{quotes} == 1, "Error being report as, 'quotes'"); 
        undef($errors); undef($details);
    
    
        # field_name_too_long
        my ($errors, $details) = $lh->validate_subscriber_field_name({-field => $bad_field_names[2]});
        ok($errors == 1, "Error being reported"); 
        ok($details->{field_name_too_long} == 1, "Error being report as, 'field_name_too_long'"); 
        undef($errors); undef($details);    
    
    
        # slashes_in_field_name
        my ($errors, $details) = $lh->validate_subscriber_field_name({-field => $bad_field_names[3]});
        ok($errors == 1, "Error being reported"); 
        ok($details->{slashes_in_field_name} == 1, "Error being report as, 'slashes_in_field_name'"); 
        undef($errors); undef($details);      
    
    
        # field_blank
        my ($errors, $details) = $lh->validate_subscriber_field_name({-field => $bad_field_names[4]});
        ok($errors == 1, "Error being reported"); 
        ok($details->{field_blank} == 1, "Error being report as, 'field_blank'"); 
        undef($errors); undef($details);   
    
    
        # weird_characters
        my ($errors, $details) = $lh->validate_subscriber_field_name({-field => $bad_field_names[5]});
        ok($errors == 1, "Error being reported"); 
        ok($details->{weird_characters} == 1, "Error being report as, 'weird_characters'"); 
        undef($errors); undef($details);  
        
        foreach(qw(email_id email list list_type list_status)){ 
            my ($errors, $details) = $lh->validate_subscriber_field_name({-field => $_});
            ok($errors == 1, "Error being reported"); 
            ok($details->{field_is_special_field} == 1, "Error being report as, 'field_is_special_field'"); 
            undef($errors); undef($details);          
        }
    
        
    
    
        eval { my ($errors, $details) = $lh->validate_subscriber_field_name(); }; 
        ok($@, "calling validate_subscriber_field_name without any paramaters causes an error!: $@"); 
        undef($errors); undef($details);  
  
    ###
    
  
    ### subscriber_field_exists
        eval { $lh->subscriber_field_exists }; 
        ok($@, "calling subscriber_field_exists without any paramaters causes an error!: $@"); 
        
        my $s = $lh->add_subscriber_field({-field => 'myfield'}); 
        ok(eq_array($lh->subscriber_fields, ['myfield']), 'New field is being reported.'); 
        undef($s); 
        
        ok($lh->subscriber_field_exists({-field => 'myfield'}) == 1, "field is being reported as being existingly...like"); 
        
        my $s = $lh->remove_subscriber_field({-field => 'myfield'}); 
        ok($s == 1, "removing a new field is successful"); 
    
    ###
    
   
    
    
    
    ### add_subscriber_field w/fallback field....
    
        my $ff = { 
        one          => 'This is one!', 
        two          => 'This is two!', 
        three        => 'This is three!', 
        four         => 'This is four!', 
        five         => 'This is five!', 
        six          => 'This is six!', 
        seven        => 'This is seven!', 
        eight        => 'This is eight!', 
        nine         => 'This is nine!', 
        ten          => 'This is ten!', 
        eleven       => 'This is eleven!', 
        twelve       => 'This is twelve!', 
        thirteen     => 'This is thirteen!', 
        fourteen     => 'This is fourteen!', 
        fifteen      => 'This is fifteen!', 
        sixteen      => 'This is sixteen!', 
        seventeen    => 'This is seventeen!', 
        eighteen     => 'This is eighteen!', 
        nineteen     => 'This is nineteen!', 
        twenty       => 'This is twenty!', 
        };
        
       foreach(keys %$ff){ 
       
        
            my $s = $lh->add_subscriber_field({-field => $_, -fallback_value => $ff->{$_}}); 
            ok($s == 1, "adding a new field, " . $_ . "with fallback of, " .  $ff->{$_} . "is successful"); 
            undef $s; 
            
            my $fallbacks = $lh->get_fallback_field_values; 
            
            ok($fallbacks->{$_} eq $ff->{$_}, $ff->{$_} . ' equals: ' . $fallbacks->{$_} . "for: " . $_); 
            
            
            # This won't kill us, but it will return an, "undef" 
            my $s = $lh->add_subscriber_field({-field => $_, -fallback_value => $ff->{$_}}); 
            ok($s eq undef, "adding a new field, " . $_ . "with fallback of, " .  $ff->{$_} . "isn't successful"); 
            undef $s; 
            
       }
       
       foreach(keys %$ff){ 
       
            ok($lh->remove_subscriber_field({-field => $_}),    'Field, ' . $_ . ' removed successfully'); 
            my $fallbacks = $lh->get_fallback_field_values; 
            ok(!exists($fallbacks->{$_}), "old fallback value for $_ has been removed."); 
     
     }
       
       
    
    
    ### 
    
    
    ### remove_subscriber_field
    
        foreach(qw(email_id email list list_type list_status)){ 
            eval { $lh->remove_subscriber_field({-field => $_}); }; 
            ok($@, "calling remove_subscriber_field with special field name causes error!: $@"); 
        }    
    
        eval { $lh->remove_subscriber_field({-field => 'foo'}); }; 
        ok($@, "calling remove_subscriber_field with a non-existent field causes error!: $@"); 
    
        ok($lh->add_subscriber_field({-field    => 'foo'}),    'New field created successfully'); 
        ok($lh->remove_subscriber_field({-field => 'foo'}),    'New field removed successfully'); 

    ###

    #### copy_subscriber w/subscriber fields 
	# the idea is that the subscriber field information
    # should be copied over correctly as well. 

	ok($lh->add_subscriber_field({-field    => 'first_name'}),    'New field, first_name created successfully'); 
  	ok($lh->add_subscriber_field({-field    => 'last_name'}),     'New field, last_name created successfully'); 
  
	ok($lh->add_subscriber({
        -email  => 'one@example.com',
        -type   => 'list', 
        -fields =>  { 
                        first_name => 'One First Name', 
                        last_name  => 'One Last Name', 
                    }
    }));
	ok(
		$lh->copy_subscriber(
			{
				-email => 'one@example.com', 
				-from  => 'list', 
				-to    => 'black_list', 
			}
		)
	);
		 
	
	ok($lh->check_for_double_email(-Email => 'one@example.com',-Type  => 'list')  == 1); 
	ok($lh->check_for_double_email(-Email => 'one@example.com',-Type  => 'black_list')  == 1); 	

	my $one_info = $lh->get_subscriber({-email => 'one@example.com', -type => 'list'}); 
    ok($one_info->{first_name} eq 'One First Name'); 
    ok($one_info->{last_name}  eq 'One Last Name'); 
	undef $one_info; 

	my $one_info = $lh->get_subscriber({-email => 'one@example.com', -type => 'black_list'}); 
    ok($one_info->{first_name} eq 'One First Name'); 
    ok($one_info->{last_name}  eq 'One Last Name'); 
	undef $one_info;
	
	ok($lh->remove_from_list(-Email_List => ['one@example.com'], -Type => 'list'      )); 
  	ok($lh->remove_from_list(-Email_List => ['one@example.com'], -Type => 'black_list'));   	
	
	ok($lh->remove_subscriber_field({-field => 'first_name'})); 
  	ok($lh->remove_subscriber_field({-field => 'last_name'})); 
  

    # Stress Testin'
    my $count = 100;  
    while ($count > 0){ 
        ok($lh->add_subscriber_field({-field    => 'foo' . $count}),    'New field # ' . $count . ' created successfully'); 
        $count--;
    }
    
    $count = 100;  
    while ($count > 0){ 
        ok($lh->remove_subscriber_field({-field    => 'foo' . $count}),    'New field # ' . $count . ' removed successfully'); 
        $count--;
    }

	

  



ok(-e $DADA::Config::TMP); 

### Mail Merging stuff - should really be in its own test file.


    # First, let's create some fields: 
    # 
    
    
    my $s = $lh->add_subscriber_field({-field => 'first_name', -fallback_value => 'John'}); 
    ok($s == 1, "adding a new field, " . 'first_name' . "with fallback of, " .  'John' . "is successful"); 
    undef $s; 

    my $s = $lh->add_subscriber_field({-field => 'last_name', -fallback_value => 'Doe'}); 
    ok($s == 1, "adding a new field, " . 'last_name' . "with fallback of, " .  'Doe' . "is successful"); 
    undef $s;
    
            
    ok($lh->add_subscriber({
        -email  => 'mike.kelley@example.com',
        -type   => 'list', 
        -fields =>  { 
                        first_name => 'Mike', 
                        last_name  => 'Kelley', 
                    }
    })); 
 	ok(-e $DADA::Config::TMP); 
   
    my $sub_info = $lh->get_subscriber({-email => 'mike.kelley@example.com'}); 
    ok($sub_info->{first_name} eq 'Mike', "first_name eq 'Mike' (" . $sub_info->{first_name} . ")"); 
    ok($sub_info->{last_name}  eq 'Kelley', "last_name eq 'Kelley'  (" . $sub_info->{last_name} . ")"); 
    undef($sub_info); 
    
    ok($lh->add_subscriber({
        -email  => 'raymond.pettibon@example.com',
        -type   => 'list', 
        -fields =>  { 
                        first_name => 'Raymond', 
                        last_name  => 'Pettibon', 
                    }
    })); 

    my $sub_info = $lh->get_subscriber({-email => 'raymond.pettibon@example.com'}); 
    ok($sub_info->{first_name} eq 'Raymond'); 
    ok($sub_info->{last_name}  eq 'Pettibon'); 
    undef($sub_info); 
 
	ok(-e $DADA::Config::TMP); 

   
    ok($lh->add_subscriber({
        -email  => 'marcel.duchamp@example.com',
        -type   => 'list', 
        -fields =>  { 
                        first_name => 'Marcel', 
                        last_name  => 'Duchamp', 
                    }
    }));

    my $sub_info = $lh->get_subscriber({-email => 'marcel.duchamp@example.com'}); 
    ok($sub_info->{first_name} eq 'Marcel'); 
    ok($sub_info->{last_name}  eq 'Duchamp'); 
    undef($sub_info); 
    
    ok($lh->add_subscriber({
        -email  => 'man.ray@example.com',
        -type   => 'list', 
        -fields =>  { 
                        first_name => 'Man', 
                        last_name  => 'Ray', 
                    }
    })); 
 	ok(-e $DADA::Config::TMP); 

    my $sub_info = $lh->get_subscriber({-email => 'man.ray@example.com'}); 
    ok($sub_info->{first_name} eq 'Man'); 
    ok($sub_info->{last_name}  eq 'Ray'); 
    undef($sub_info); 



    ok($lh->add_subscriber({
        -email  => 'no.one@example.com',
        -type   => 'list', 
    })); 
 
    my $sub_info = $lh->get_subscriber({-email => 'no.one@example.com'}); 
    ok($sub_info->{first_name} eq ''); 
    ok($sub_info->{last_name}  eq ''); 
    undef($sub_info); 
    

    my $body = q{ 
    
    email: [subscriber.email], First Name: [subscriber.first_name], Last Name: [subscriber.last_name]
    
    [subscriber.first_name][subscriber.first_name][subscriber.first_name][subscriber.first_name][subscriber.first_name][subscriber.first_name]
    [subscriber.last_name][subscriber.last_name][subscriber.last_name][subscriber.last_name][subscriber.last_name][subscriber.last_name][subscriber.last_name]
    
    };
    
	ok(-e $DADA::Config::TMP); 


 

    require DADA::Security::Password; 
    my $test_msg_fields = {
        Subject      => 'Hello.',
        'Message-ID' => '<' .  DADA::App::Guts::message_id() . '.'. DADA::Security::Password::generate_rand_string('1234567890') . '@' . 'some-example-with-dashes.com' . '>',
        Body         => $body, 
    };

    require DADA::Mail::Send;
    my $mh = DADA::Mail::Send->new({-list => $list}); 
	   #$mh->test_send_file($DADA::Config::TMP . '/mail.txt'); 
	   $mh->test(1);
    require DADA::Mail::MailOut; 
    my $mailout = DADA::Mail::MailOut->new({ -list => $list });
    my $rv; 
    eval { $rv = $mailout->create({-fields => $test_msg_fields, -mh_obj => $mh, -list_type => 'list' }) }; 
    ok(!$@, "Passing  a correct DADA::Mail::Send object does not create an error! - $@"); 
    ok($rv == 1, " create() returns 1!"); 

    my $tmp_sub_list = $mailout->dir . '/' . 'tmp_subscriber_list.txt';
	ok(-e $DADA::Config::TMP); 

    ok(-e $tmp_sub_list, $tmp_sub_list . ' exists.'); 

    open my $TMP_SUB_LIST, '<', $tmp_sub_list
        or die "Cannot read file at: '" . $tmp_sub_list
        . "' because: "
        . $!;
        
    my $contents = do { local $/; <$TMP_SUB_LIST> }; 

    
    close $TMP_SUB_LIST or die $!;


    like($contents, qr/Mike::Kelley/); 
    like($contents, qr/Raymond::Pettibon/); 
    like($contents, qr/Marcel::Duchamp/); 
    like($contents, qr/Man::Ray/); 
   # ok($contents =~ m/John\:\:Doe/); 

    #my $msg = do { local $/; <$MSG_FILE> };
    ok($mailout->clean_up() == 1, "cleanup still returned a TRUE value!"); 

    undef($mailout); 
   
	ok(-e $DADA::Config::TMP); 

    #diag( 'orig: $DADA::Config::MAIL_SETTINGS ' . $DADA::Config::MAIL_SETTINGS ); 

   $ls->save({
       enable_bulk_batching => 0,
   
   });

    unlink $DADA::Config::TMP . '/mail.txt'
        if(-e $DADA::Config::TMP . '/mail.txt'); 
   # $DADA::Config::MAIL_SETTINGS = '>>' . $DADA::Config::TMP . '/mail.txt'; 

    #diag( 'now: $DADA::Config::MAIL_SETTINGS ' . $DADA::Config::MAIL_SETTINGS ); 

    
    my $mh = DADA::Mail::Send->new({-list => $list});
       $mh->test_send_file($DADA::Config::TMP . '/mail.txt');
	   $mh->test(1);
    my $msg_id = $mh->mass_send(
        %$test_msg_fields,
    );    
    
    my $mailout = DADA::Mail::MailOut->new({ -list => $list });
    my $associate_worked = $mailout->associate($msg_id, 'list'); 
    ok($associate_worked == 1, "We assocaited the mailing with what we got."); 
	ok(-e $DADA::Config::TMP); 

    my $status        = $mailout->status; 
    #my $percent_done = $status->{percent_done};
    my $seconds      = 60; 

	ok(-e $DADA::Config::TMP, "TMP dir still around..."); 
	
	diag ' $mailout->status->{percent_done} ' . $mailout->status->{percent_done}; 
	
    while($mailout->status->{percent_done} < 100){

		ok(-e $DADA::Config::TMP, "TMP dir still around (2)..."); 		
        diag ("Sleeping..."); 
        
        sleep(1); 
		
		diag q{ DADA::Mail::MailOut::mailout_exists($list, $msg_id, 'list') } . DADA::Mail::MailOut::mailout_exists($list, $msg_id, 'list'); 
		
        if(DADA::Mail::MailOut::mailout_exists($list, $msg_id, 'list') == 1){ 
            diag("waiting for mailing to finish... " . $mailout->status->{percent_done}); 
            $seconds--; 
            if($seconds == 0){
				ok(-e $DADA::Config::TMP); 
	
                diag("Waiting timed out! Breaking out!"); 
                $mailout->clean_up();
				diag "here 8"; 
                undef $mailout; 
                last; 
            }
        }
        else { 
            undef $mailout; 
            diag "Sending is finished..."; 
            last; 
        }
    
    }
 ok(-e $DADA::Config::TMP); 

    sleep(2); 
    

    undef $contents; 
    
     open my $TMP_MAIL_FILE, '<', $DADA::Config::TMP . '/mail.txt'
        or die "Cannot read file at: '" . $DADA::Config::TMP . '/mail.txt'
        . "' because: "
        . $!;
        
    my $contents = do { local $/; <$TMP_MAIL_FILE> }; 
    close $TMP_MAIL_FILE or die $!;

  
    my $l = 'email: mike.kelley@example.com, First Name: Mike, Last Name: Kelley'; 
    my $l2 = 'MikeMikeMikeMikeMikeMike'; 
    my $l3 = 'KelleyKelleyKelleyKelleyKelleyKelleyKelley';
    like($contents, qr/$l/); 
    like($contents, qr/$l2/); 
    like($contents, qr/$l3/); 
    undef $l;     
    undef $l2; 
    undef $l2; 
  
  
    my $l  = 'email: raymond.pettibon@example.com, First Name: Raymond, Last Name: Pettibon'; 
    my $l2 = 'RaymondRaymondRaymondRaymondRaymondRaymond'; 
    my $l3 = 'PettibonPettibonPettibonPettibonPettibonPettibonPettibon';   
    like($contents, qr/$l/); 
    like($contents, qr/$l2/); 
    like($contents, qr/$l3/); 
    undef $l;     
    undef $l2; 
    undef $l2;   
    
    
    my $l =  'email: man.ray@example.com, First Name: Man, Last Name: Ray'; 
    my $l2 = 'ManManManManManMan'; 
    my $l3 = 'RayRayRayRayRayRayRay';   
    like($contents, qr/$l/); 
    like($contents, qr/$l2/); 
    like($contents, qr/$l3/); 
    undef $l;     
    undef $l2; 
    undef $l2;   
    
    
    my $l = 'email: no.one@example.com, First Name: John, Last Name: Doe'; 
    my $l2 = 'JohnJohnJohnJohnJohnJohn'; 
    my $l3 = 'DoeDoeDoeDoeDoeDoeDoe';       
    like($contents, qr/$l/, 'FOUND: email: no.one@example.com, First Name: John, Last Name: Doe'); 
    like($contents, qr/$l2/, 'FOUND: JohnJohnJohnJohnJohnJohn' ); 
    like($contents, qr/$l3/, 'FOUND: DoeDoeDoeDoeDoeDoeDoe'); 
    undef $l;     
    undef $l2; 
    undef $l2;   
    
    
    
    
    #undef $lh; 
    #my $lh = DADA::MailingList::Subscribers->new({-list => $list}); 
 
 ### 
 
     # We'll just do this again, for good measure...
 
    unlink $DADA::Config::TMP . '/mail.txt'
        if(-e $DADA::Config::TMP . '/mail.txt'); 
    #$DADA::Config::MAIL_SETTINGS = '>>' . $DADA::Config::TMP . '/mail.txt'; 
   

    undef $mh; 
    undef $msg_id; 
    undef $mailout; 
    
    my $mh = DADA::Mail::Send->new({-list => $list}); 
	   $mh->test_send_file($DADA::Config::TMP . '/mail.txt'); 
       $mh->test(1);
	   $mh->partial_sending({'first_name' => {'equal_to' =>'Raymond'}});
       my $mess_id = '<' .  DADA::App::Guts::message_id() . '.'. DADA::Security::Password::generate_rand_string('1234567890') . '@' . 'some-example-with-dashes.com' . '>'; 
    my $msg_id = $mh->mass_send(
        %$test_msg_fields,
        'Message-ID' => $mess_id,
    );  
    

    my $mailout = DADA::Mail::MailOut->new({ -list => $list });
    my $associate_worked = $mailout->associate($msg_id, 'list'); 
    ok($associate_worked == 1, "We assocaited the mailing with what we got."); 

  
     while($mailout->status->{percent_done} < 100){
        diag ("Sleeping..."); 
        
        sleep(1); 
        if(DADA::Mail::MailOut::mailout_exists($list, $msg_id, 'list') == 1){ 
        
            diag("waiting for mailing to finish... " . $mailout->status->{percent_done}); 
            
        }
        else { 
            undef $mailout; 
            diag "Sending is finished..."; 
            last; 
        }
        
        $seconds--; 
        if($seconds == 0){ 
            diag("Waiting timed out! Breaking out!"); 
            $mailout->clean_up();
            undef $mailout; 
            last; 
        }
    }
    
    
    
    
     undef $contents; 
     undef $TMP_MAIL_FILE; 
     
     open my $TMP_MAIL_FILE, '<', $DADA::Config::TMP . '/mail.txt'
        or die "Cannot read file at: '" . $DADA::Config::TMP . '/mail.txt'
        . "' because: "
        . $!;
        
    my $contents = do { local $/; <$TMP_MAIL_FILE> }; 
    close $TMP_MAIL_FILE or die $!;
    
        
    my $l = quotemeta('email: mike.kelley@example.com, First Name: Mike, Last Name: Kelley'); 
    my $l2 = quotemeta('MikeMikeMikeMikeMikeMike'); 
    my $l3 = quotemeta('KelleyKelleyKelleyKelleyKelleyKelleyKelley');
    ok($contents !~ m/$l/); 
    ok($contents !~ m/$l2/); 
    ok($contents !~ m/$l3/); 
    undef $l;     
    undef $l2; 
    undef $l2; 
  
  
    my $l  = quotemeta('email: raymond.pettibon@example.com, First Name: Raymond, Last Name: Pettibon'); 
    my $l2 = quotemeta('RaymondRaymondRaymondRaymondRaymondRaymond'); 
    my $l3 = quotemeta('PettibonPettibonPettibonPettibonPettibonPettibonPettibon');   
    ok($contents =~ m/$l/); 
    ok($contents =~ m/$l2/); 
    ok($contents =~ m/$l3/); 
    undef $l;     
    undef $l2; 
    undef $l2;   
    
    
    my $l = quotemeta('email: man.ray@example.com, First Name: Man, Last Name: Ray'); 
    my $l2 = quotemeta('ManManManManManMan'); 
    my $l3 = quotemeta('RayRayRayRayRayRayRay');   
    ok($contents !~ m/$l/); 
    ok($contents !~ m/$l2/); 
    ok($contents !~ m/$l3/, 'DID NOT FIND: RayRayRayRayRayRayRay'); 
    undef $l;     
    undef $l2; 
    undef $l2;
    


### This is sort of weird, since this is a little more low level than we just did, but... 

    undef $lh; 
    my $lh = DADA::MailingList::Subscribers->new({-list => $list}); 

     my ( $path_to_list, $total_sending_out_num)
        = $lh->create_mass_sending_file(
        -ID   => DADA::App::Guts::message_id(), #argh. That's messy. 
        -Type => 'list'
        #-partial_sending => $args->{-partial_sending}, 
        );
        

  
        ok($lh->num_subscribers + 1 == $total_sending_out_num, "This file is to send to " . $total_sending_out_num . 'subscribers'); 
        ok(unlink($path_to_list) == 1, 'Unlinking ' . $path_to_list . ' worked.'); 
        undef($path_to_list); 
        undef($total_sending_out_num); 
        
    sleep(1); 
    
     my ( $path_to_list, $total_sending_out_num)
        = $lh->create_mass_sending_file(
            -ID   => DADA::App::Guts::message_id(), #argh. That's messy. 
            -Type => 'list',
            -partial_sending => {'first_name' => {'equal_to' =>'Raymond'}},
        );
        
        ok($total_sending_out_num == 2, "This file is to send to 2 people ($total_sending_out_num)", ); 
        ok(unlink($path_to_list) == 1, 'Unlinking ' . $path_to_list . ' worked.'); 
        undef($path_to_list); 
        undef($total_sending_out_num); 
        
        
    sleep(1); 
    
     my ( $path_to_list, $total_sending_out_num)
        = $lh->create_mass_sending_file(
            -ID   => DADA::App::Guts::message_id(), #argh. That's messy. 
            -Type => 'list',
            -partial_sending => {'first_name' => {'like' =>'a'}},
        );
        
        ok($total_sending_out_num == 4, "This file is to send to 4 people ($total_sending_out_num)", ); 
        ok(unlink($path_to_list) == 1, 'Unlinking ' . $path_to_list . ' worked.'); 
        undef($path_to_list); 
        undef($total_sending_out_num);         
     
     
     
    sleep(1); 
    
     my ( $path_to_list, $total_sending_out_num)
        = $lh->create_mass_sending_file(
            -ID   => DADA::App::Guts::message_id(), #argh. That's messy. 
            -Type => 'list',
            -partial_sending => {'last_name' => {'like' =>'a'}},
        );
        
        ok($total_sending_out_num == 3, "This file is to send to 3 people ($total_sending_out_num)", ); 
        ok(unlink($path_to_list) == 1, 'Unlinking ' . $path_to_list . ' worked.'); 
        undef($path_to_list); 
        undef($total_sending_out_num);  



    sleep(1); 
    
     my ( $path_to_list, $total_sending_out_num)
        = $lh->create_mass_sending_file(
            -ID   => DADA::App::Guts::message_id(), #argh. That's messy. 
            -Type => 'list',
            -partial_sending => {'last_name' => {'equal_to' =>'Duchamp'}},
        );
        
        ok($total_sending_out_num == 2, "This file is to send to 2 people ($total_sending_out_num)", ); 
        ok(unlink($path_to_list) == 1, 'Unlinking ' . $path_to_list . ' worked.'); 
        undef($path_to_list); 
        undef($total_sending_out_num);  




    sleep(1); 
    
     my ( $path_to_list, $total_sending_out_num)
        = $lh->create_mass_sending_file(
            -ID   => DADA::App::Guts::message_id(), #argh. That's messy. 
            -Type => 'list',
            -partial_sending => {'first_name' => {'like' =>'Ma'}},
        );
        
        ok($total_sending_out_num == 3, "This file is to send to 3 people ($total_sending_out_num)", ); 
        ok(unlink($path_to_list) == 1, 'Unlinking ' . $path_to_list . ' worked.'); 
        undef($path_to_list); 
        undef($total_sending_out_num);  





    ok($lh->add_subscriber({
            -email  => 'raymond.lame@example.com',
            -type   => 'list', 
            -fields =>  { 
                            first_name => 'Raymond', 
                            last_name  => 'Lame', 
                        }
        })); 
        
        
    sleep(1); 
    
     my ( $path_to_list, $total_sending_out_num)
        = $lh->create_mass_sending_file(
            -ID   => DADA::App::Guts::message_id(), #argh. That's messy. 
            -Type => 'list',
            -partial_sending => {'first_name' => {'equal_to' =>'Raymond'}},
        );
        
        ok($total_sending_out_num == 3, "This file is to send to 3 people ($total_sending_out_num)", ); 
        ok(unlink($path_to_list) == 1, 'Unlinking ' . $path_to_list . ' worked.'); 
        undef($path_to_list); 
        undef($total_sending_out_num);  
        
        my $r_count = $lh->remove_from_list(-Email_List => ['raymond.lame@example.com']); 
        ok($r_count == 1, "removed one address (raymond.lame\@example.com)");                           
        undef($r_count); 
        

        
        
###
    
    
    
 
 ### 


    
    my $s = $lh->remove_subscriber_field({-field => 'first_name'}); 
    ok($s == 1, "removing field 'first_name' is successful"); 
    undef($s); 
    
    my $s = $lh->remove_subscriber_field({-field => 'last_name'}); 
    ok($s == 1, "removing field 'last_name' is successful"); 
    undef($s); 
    
    sleep(2); 

    chmod(0777, $DADA::Config::TMP . '/mail.txt'); 
    
    
        
    ok($lh->remove_from_list(-Email_List => ['mike.kelley@example.com'], -Type => 'list'), "removed: " . 'mike.kelley@example.com'); 




    ok($lh->remove_from_list(-Email_List => ['raymond.pettibon@example.com'], -Type => 'list'), "removed: " . 'raymond.pettibon@example.com'); 
    ok($lh->remove_from_list(-Email_List => ['marcel.duchamp@example.com'], -Type => 'list'), "removed: " . 'marcel.duchamp@example.com'); 
    ok($lh->remove_from_list(-Email_List => ['man.ray@example.com'], -Type => 'list'), "removed: " . 'man.ray@example.com'); 
    ok($lh->remove_from_list(-Email_List => ['no.one@example.com'], -Type => 'list'), "removed: " . 'no.one@example.com'); 

} # Skip?!


### search_list  

undef $lh; 

$lh = DADA::MailingList::Subscribers->new({-list => $list}); 
ok($lh->isa('DADA::MailingList::Subscribers'));

my $n_subs = $lh->num_subscribers; 
if($n_subs > 0){ 
	my $ll = $lh->subscription_list;
	require Data::Dumper;
	print Data::Dumper::Dumper($ll); 
	
}


ok($n_subs == 0, "no subscribers right now ($n_subs)"); 

my $i = 0; 
for($i=0;$i<10;$i++){ 

        ok($lh->add_subscriber({
            -email => 'example' . $i . '@example.com',
            -type  => 'list', 
        }), 'added: example' . $i . '@example.com' );
    
}

undef $i;

my $results = $lh->search_list(
    {
        -query => 'example', 
        -type  => 'list', 
    }
); 

ok($results->[9], "Have 10 results");
ok(!$results->[10], "Do NOT have 11 results."); 


foreach(@$results){ 
    like($_->{email}, qr/example/, "Found: " . $_->{email}); 
}
$i = 0; 
for($i=0;$i<10;$i++){ 
        ok($lh->remove_from_list(-Email_List => ['example' . $i . '@example.com'], -Type => 'list') == 1, "removed: " . 'example' . $i . '@example.com'); 
}
undef $i;

SKIP: {

    skip "Multiple Subscriber Fields is not supported with this current backend." 
        if $lh->can_have_subscriber_fields == 0; 
        
        diag "still here."; 
        
        foreach(qw(1 2)){ 
            ok($lh->add_subscriber_field({-field => 'field' . $_})); 
        }
        
        my $subscribers = []; 
        $subscribers = [
        [
        'example1@example.com', "Fred", "Jones"
        ],
        [
        'example2@example.com', "Tom", "Jones"
        ],
        [
        'example3@example.com', "Wes", "Anderson"
        ]
        ];
        
        
        
    foreach(@$subscribers){     
            ok($lh->add_subscriber({
                    -email => $_->[0],
                    -fields => {
                                field1 => $_->[1],
                                field2 => $_->[2],
                                },
                    -type  => 'list', 
            }), 'added:  '. $_->[0]);
            
        }   
        
  
    undef $results;   
    $results = $lh->search_list(
        {
            -query => 'example', 
            -type  => 'list', 
        }
    ); 
    
    ok($results->[2],  "Found 3 results"); 
    ok(!$results->[3], "Did not find 4 results"); 


    undef $results;   
    $results = $lh->search_list(
        {
            -query => 'Jones', 
            -type  => 'list', 
        }
    );
    
    ok($results->[1],  "Found 2 results"); 
    ok(!$results->[2], "Did not find 3 results"); 
    
    $results = $lh->search_list(
        {
            -query => 'Wes', 
            -type  => 'list', 
        }
    );    

    $results = $lh->search_list(
        {
            -query => 'Wes', 
            -type  => 'list', 
        }
    );    
    ok($results->[0],  "Found 1 result"); 
    ok(!$results->[1], "Did not find 0 results"); 
    
   # require Data::Dumper; 
   # print Data::Dumper::Dumper($results); 
   my $r = $results->[0];
    ok($r->{fields}->[0]->{value} eq 'Wes'); 
    ok($r->{fields}->[1]->{value} eq 'Anderson'); 
    undef $r; 
    
  
        foreach(@$subscribers){ 
                ok($lh->remove_from_list(-Email_List => [$_->[0]], -Type => 'list'), "removed: " . $_->[0]); 
        } 
        
    foreach(qw(1 2)){ 
        ok($lh->remove_subscriber_field({-field => 'field' . $_})); 
    }
        
} # SKIP

### /search_list









 
dada_test_config::remove_test_list;
dada_test_config::wipe_out;
