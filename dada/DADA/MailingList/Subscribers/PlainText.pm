package DADA::MailingList::Subscribers::PlainText; 

use lib qw (../../../ ../../../DADA/perllib); 
 
use DADA::Config qw(!:DEFAULT);  

use Carp qw(croak carp); 

my $dbi_obj; 

use Fcntl qw(
O_WRONLY 
O_TRUNC 
O_CREAT 
O_CREAT 
O_RDWR
O_RDONLY
LOCK_EX
LOCK_SH 
LOCK_NB); 

use DADA::App::Guts;
use DADA::Logging::Usage;

my $log = new DADA::Logging::Usage;


use strict; 

sub new {
	my $class = shift;
	
	my ($args) = @_; 
	
	   my $self = {};			
       bless $self, $class;
	   $self->_init($args); 
	   return $self;
}

sub _init  { 
	
    my $self = shift; 

	my ($args) = @_; 

	if(!exists($args->{-ls_obj})){ 
		require DADA::MailingList::Settings; 
		$self->{ls} = DADA::MailingList::Settings->new({-list => $args->{-list}}); 
	}
	else { 
		$self->{ls} = $args->{-ls_obj};
	}
	
	$self->{list} = $args->{-list}; 

}



#######################################################################



=pod

=head1 NAME DADA::MailingList::PlainText

=head1 DESCRIPTION

This is the Plain Text version of Dada Mail's subscriber database.

=head1 SYNOPSIS

my $lh = List::Plaintext->new(-List => $list); 

=head2 to $lh->open_email_list(-Path => $path, -Type='list');

returns an array of all e-mail addresses for $list. It can also return only a reference 
you say -As_Ref => 1, 

this is used mostly for the black list functions, as its painfully clear that loading up 
100,000 email addreses into memory is a Bad Thing. 

=cut

# note. BAD to do on large lists. Bad Bad Bad

sub open_email_list { 

	my $self = shift; 	
	my %args = (-Type      => 'list',
				-As_Ref    => 0, 
				-Sorted    => 1,
				@_);
	
	my $list        = $self->{list} || undef; 
	my $file_ending = $args{-Type}; 
	my $want_ref    = $args{-As_Ref}; 
	   
	
	if($list){
	
	my @list     = (); 
	my @bad_list = (); 
	
	#untaint 
	$list = make_safer($list); 
	$list =~ /(.*)/; 
	$list = $1; 
	
	#untaint 
	$file_ending = make_safer($file_ending); 
	$file_ending =~ /(.*)/; 
	$file_ending = $1; 
	
	my $list_name = "$list.$file_ending";
	sysopen(LIST, "$DADA::Config::FILES/$list_name", O_RDWR|O_CREAT, $DADA::Config::FILE_CHMOD )
	    or croak "couldn't open $DADA::Config::FILES/$list_name for reading: $!\n";
	 
	flock(LIST, 1);
	  @bad_list = <LIST>;
	close (LIST);

	foreach(@bad_list) { 
	 $_  =~  s/^\s+|\s+$//o;
	}

	foreach(@bad_list) { 
		if ($_ ne ""){ 
			push(@list, $_); 
		}
	}

	 @list = sort(@list); 

	if($want_ref eq "1"){ 
		return \@list; 
	}else{ 
		return @list; 
	}

	}else{ 
		return undef;
	}
}


=pod

=head2 open_list_handle(-List => $list) 

This function will open the email list file with a handle of LIST, 
it also does a whole bunch of error checking, taint checking, etc, that I'm 
too lazy to do everytime I want a list open. 

=cut 


sub open_list_handle { 

	my $self = shift; 
	my %args = (
				-Type => 'list',
				@_,
				); 
				
	my $path_to_file = make_safer($DADA::Config::FILES . '/' . $self->{list} . '.' . $args{-Type}); 
	
	sysopen(LIST, $path_to_file, O_RDWR|O_CREAT, $DADA::Config::FILE_CHMOD ) 
	    or croak "couldn't open '$path_to_file' for reading: $!\n";
		   flock(LIST, LOCK_SH);
}



sub sort_email_list { 	

    carp "sort_email_list is not supported for the plain text backend.";
    return undef; 

}




sub search_list { 

	my $self = shift; 
	
	my ($args) = @_; 

    if(!exists($args->{-start})){ 
        $args->{-start} = 1;     
    }
    if(!exists($args->{'-length'})){ 
        $args->{'-length'} = 100;     
    }
        
	my $r       = [];
	my $email   = ''; 
	my $query = quotemeta($args->{-query}); 
    my $count   = 0;
    
    $self->open_list_handle(-Type => $args->{-type});
    while(defined($email = <LIST>)){ 
        if($email =~ m/$query/i){ 
			
			push(@$r, {email => $email, list_type => $args->{-type}, fields => []});
    
			$count++; 
	        next if $count <  $args->{-start}; 
	        last if $count > ($args->{-start} + $args->{'-length'});
	
        }
    }
    close(LIST); 
    

	return $r; 


}


=pod

=head2 my $matches = search_email_list(-Method => $method, -Keyword=> $keyword); 

searching through emails happens here, we can search using three methods, 'domain', where we search 
for '.com', '.edu' etc, 'service' where we look for things like 'altavista', 'yahoo', 'hotmail' adn things like that. 
the results will be printed out from here, the function returns how many results have been found. 
 

=cut

sub search_email_list { 

	my $self = shift; 
	
	my %args = (
	-Keyword   => undef,
	-Method    => undef, 
	-Type      => 'list',
	-as_string => 0, 
	
	@_
	);
	my @matches; 
	my $domain_regex = "(.*)\@(.*)"; 
	my $found = 0; 
	
	my $r = ''; 
	
	my $method  = $args{-Method} || "standard"; 
	my $keyword = $args{-Keyword}; 
	   $keyword = quotemeta($keyword); 
	
	my $type = $args{-Type};
	
	if($self->{list}){ 
	
	
	#open the list and grab what we can, 
	$self->open_list_handle(-Type => $args{-Type});
	
	my $email; 
	
	if(defined($keyword) && $keyword ne ""){
	if($method eq "domain"){ 
		while(defined($email = <LIST>)){ 
			if($email =~ m/$domain_regex$keyword$/i){ 
				 
				 
				 my $str  = "<input type=\"checkbox\" name=\"address\" value=\"$email\">&nbsp;&nbsp; <a href=\"$DADA::Config::S_PROGRAM_URL?f=edit_subscriber&email=$email&type=$type\">$email</a>  <br />\n";
				
					if($args{-as_string} == 1){ 
						$r .= $str; 
					}else{ 
						print $found; 
					}
				
			$found++;
			}
		}
	}elsif($method eq "service"){ 
		while(defined($email = <LIST>)){ 
			if($email =~ m/\@$keyword$/i){ 
				
				#push(@matches, $email); 
				my $str  = "<input type=\"checkbox\" name=\"address\" value=\"$email\">&nbsp;&nbsp; <a href=\"$DADA::Config::S_PROGRAM_URL?f=edit_subscriber&email=$email&type=$type\">$email</a> <br />\n";
				
				if($args{-as_string} == 1){ 
					$r .= $str; 
				}else{ 
					print $found; 
				}
					
			$found++;  
			}	   
		}  
	}else{ 
		while(defined($email = <LIST>)){ 
			if($email =~ m/$keyword/i){ 
				my $str  = "<input type=\"checkbox\" name=\"address\" value=\"$email\">&nbsp;&nbsp; <a href=\"$DADA::Config::S_PROGRAM_URL?f=edit_subscriber&email=$email&type=$type\">$email</a>  <br />\n";
				
				if($args{-as_string} == 1){ 
					$r .= $str; 
				}else{ 
					print $found; 
				}
					
				$found++;
				}
			}
		}
	}
	
	if($args{-as_string} == 1){ 
		return($found, $r); 	
	}else{ 
		return($found); 
		 
	}
					
	
	close(LIST); 
	
	}else{ 
	
	return undef;
	}

}


=pod


=head2 my $count = print_out_list(-List => $list);

This function will print out a list. 
Thats it. 


=cut

=pod

=head2 get_black_list_match(\@black_list, \@list); 


zooms through the black list and does regex matches on email addresses to see 
of they match. 




=cut
 
sub get_black_list_match{ 

my $self = shift; 

	my @got_black; 
	my @got_white; 

	my $black_list = shift; 
	my $try_this = shift; 

if($black_list and $try_this){ 

	my $black; 

	foreach $black(@$black_list){ 
			
		my $try; 

		foreach $try(@$try_this){ 
			my $qm_try = $try; 
			#my $s_black = quotemeta($black); 
			
            next if ! $black || $black eq ''; 
			
			if($qm_try =~ m/$black/i){ 
				push(@got_black, $try); 
			}
		}
	}
	return (\@got_black)
}else{ 

return 0;
}

}




sub print_out_list { 

	my $self = shift;
	 	
	my %args = (-Type => 'list',
				-FH  => \*STDOUT,
				@_); 
				
	$self->sort_email_list(-Type => $args{-Type}) if $DADA::Config::LIST_IN_ORDER == 1; 
	
	my $fh = $args{-FH};
	my $email; 
	my $count; 
	if($self->{list}){ 
		$self->open_list_handle(-Type => $args{-Type}); 
		while(defined($email = <LIST>)){ 
			
			# DEV: Do we remove newlines here? Huh? 
			# BUG: [ 2147102 ] 3.0.0 - "Open List in New Window" has unwanted linebreak?
			# https://sourceforge.net/tracker/index.php?func=detail&aid=2147102&group_id=13002&atid=113002
			$email =~ s/\n|\r/ /gi;
			
			
			#	chomp($email);
			print $fh $email; 
			$count++; 
			
		}
		close (LIST);            
		return $count; 
	}

}



sub subscription_list { 
	my $self = shift; 
	my %args = (-start    => 1, 
	            '-length' => 100,
	            -Type     => 'list',
	            @_); 
	
	$self->sort_email_list(-Type => $args{-Type}) 
		if $DADA::Config::LIST_IN_ORDER == 1; 

             
	my $count = 0; 
	my $list = []; 
	my $email; 
	
	$self->open_list_handle(-Type => $args{-Type}); 
	while(defined($email = <LIST>)){ 
			$count++; 

			next if $count <  $args{-start}; 
			last if $count > ($args{-start} + $args{'-length'});
			chomp($email); 
			push(@$list, {email => $email, list_type => $args{-Type}});  
					
		}
		close (LIST);            
		return $list; 
}




sub check_for_double_email {
	
    my $self = shift; 
    
    my %args = ( 
        -Email          => undef,
        -Type           => 'list', 
        -Match_Type     => 'sublist_centric',
        
        @_
    );
    
    if($self->{list} and $args{-Email}){ 
    
        $self->open_list_handle(-Type => $args{-Type});	 
        
        my $check_this = undef; 
        my $email      = $args{-Email}; 
        my $in_list    = 0; 

        while(defined($check_this = <LIST>)){ 
        
            chomp($check_this);
            if(
                (
                    $args{-Type} eq "black_list" || 
                    $args{-Type} eq "white_list"
                ) 
                && 
                $args{-Match_Type} eq 'sublist_centric'
              ){ 
            
                if (! $check_this || $check_this eq ''){ 
                    carp "blank line in subscription list?!";
                    next; 
                }
                if(cased($email) =~ m/$check_this/i){
                    $in_list=1;
                    last;
                }
            
            }else{
            
                if(cased($check_this) eq cased($email)){
                    $in_list=1;
                    last;
                }
            }
        }
        
        close (LIST);
        
        return $in_list; 
        
    }else{ 	

        return 0;

    }
    
    }


sub num_subscribers { 
	my $self = shift; 
	my %args = (-Type => 'list',
	            @_);
	my $count = 0; 
	my $buffer; 
	$self->open_list_handle(-Type => $args{-Type});
	while (sysread LIST, $buffer, 4096) {
		$count += ($buffer =~ tr/\n//);
	}
	close LIST or die $!;
	return $count; 
}




sub add_to_email_list { 

	my $self = shift; 
	
	my %args = (-Email_Ref => undef, 
				-Type      => "list",
				-Mode      => 'append',
				@_);
	
	my $address = $args{-Email_Ref} || undef;
	my $email_count = 0;
	my $ending = $args{-Type}; 
	my $write_list = $self->{list} || undef; 
	
	
	if($write_list and $address){
	
	$write_list =~ s/ /_/i; 
	#untaint 
	$write_list = make_safer($write_list); 
	$write_list =~ /(.*)/; 
	$write_list = $1; 
	
	
	#untaint 
	$ending = make_safer($ending); 
	$ending =~ /(.*)/; 
	$ending = $1; 
	
	
	if($args{-Mode} eq 'writeover'){ 
	
	
	sysopen(LIST, "$DADA::Config::FILES/$write_list.$ending",  O_WRONLY|O_TRUNC|O_CREAT,  $DADA::Config::FILE_CHMOD ) or 
				croak "couldn't open $DADA::Config::FILES/$write_list.$ending for writing: $!\n";
	}else{ 
	
	open (LIST, ">>$DADA::Config::FILES/$write_list.$ending") or 
		croak "couldn't open $DADA::Config::FILES/$write_list.$ending for reading: $!\n";
	}	
	
	
	flock(LIST, 2);
	foreach(@$address){
		chomp($_);
		$_ = strip($_); 
		print LIST "$_\n";
		$email_count++;
		# js - log it
		$log->mj_log($self->{list},"Subscribed to $write_list.$ending", $_) if (($DADA::Config::LOG{subscriptions}) && ($args{-Mode} ne 'writeover')); 
	}
		close(LIST);
		return $email_count; 
	}else{ 
		carp("$DADA::Config::PROGRAM_NAME $DADA::Config::VER: No list, or list ref was given!");
		return undef;
	}
}




sub add_subscriber { 

    my $self = shift; 
    
    my ($args) = @_;
 
	if(length(strip($args->{-email})) <= 0){ 
        croak("You MUST supply an email address in the -email paramater!"); 		
	}
	        
     $self->add_to_email_list(
     
        -Email_Ref => [($args->{-email})], 
	    -Type      => $args->{-type}, 
     
     ); 
}




sub get_subscriber { 

    my $self = shift; 
    my ($args) = @_;
    
    if(! exists $args->{-email}){ 
        croak "You must pass a email in the -email paramater!"; 
    }
    if(! exists $args->{-type}){ 
        $args->{-type} = 'list';
    }
    if(! exists $args->{-dotted}){ 
        $args->{-dotted} = 0;
    }    
    
    my ($n, $d) = split('@', $args->{-email}, 2);
        
    if($args->{-dotted} == 1){     
        return {'subscriber.email' => $args->{-email}, 'subscriber.email_name' => $n, 'subscriber.email_domain' => $d}; 
    } else { 
        return {email => $args->{-email, email_name => $n, email_domain => $d}}; 
    
    }
}




# NOTES: 
#
#This is especially the case for Solaris 9 where shared locks are the same as
#exclusive locks, AND the file MUST be writable even if you never write to
#it! If it isn't writable you get a "Bad file number" Error.#
#
#http://www.cit.gu.edu.au/~anthony/info/perl/lock.hints

sub remove_from_list { 

	my $self = shift; 
	
	my %args = (-Email_List => undef, 
	            -Type       => 'list',
	            @_); 

	my $list     = $self->{list}; 
	my $path     = $DADA::Config::FILES; 
	 
	 
	my $type     = $args{-Type}; 
	my $deep_six = $args{-Email_List}; 
	

	if($list and $deep_six){ 
	
		# create the lookup table 
		my %lookup_table; 
		foreach my $going(@$deep_six){
			chomp($going);
			$going = strip($going);
			$going = cased($going);
			$lookup_table{$going} = 1;
		}


		# the lookup table holds addresses WE DON'T WANT. SO rememeber that, u.
		my $main_list = "$path/$list.$type"; 
		   $main_list = make_safer($main_list); 
		   $main_list =~ /(.*)/;
		   $main_list = $1; 
			
		my $message_id = message_id();	
		my $temp_list = "$main_list.tmp-$message_id";
		my $count; 


		########################################################################
		# this is my big hulking Masterlock that you'll need a shotgun 
		# to blow off. This is me being anal retentive.
		#sysopen(SAFETYLOCK, "$DADA::Config::FILES/$list.lock",  O_RDWR|O_CREAT, 0777); 
			
		my $lock_file = "$DADA::Config::TMP/$list.lock"; 	
		   $lock_file = make_safer($lock_file); 
		   $lock_file =~ /(.*)/;
		   $lock_file = $1; 
		# from camel book:
		# sysopen(DBLOCK,     $LCK,        O_RDONLY| O_CREAT)  	
		# from 2.8.15 :
		# sysopen(SAFETYLOCK, $lock_file,  O_RDWR|O_CREAT, $DADA::Config::FILE_CHMOD ) 
		# new: 
		
		 
		 sysopen(SAFETYLOCK, $lock_file,  O_RDWR|O_CREAT, $DADA::Config::FILE_CHMOD ) 
			or croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error - Cannot open list lock file '$DADA::Config::TMP/$list.lock' - $!";

		 chmod($DADA::Config::FILE_CHMOD , $lock_file) 
		    if -e $lock_file; 
		    
		    {
			my $sleep_count = 0; 
				{ 
				# from camel book: 
				#flock(DBLOCK, LOCK_SH)   or croak "can't LOCK_SH $LCK: $!";
				
				# from 2.8.15 
				# flock SAFETYLOCK, LOCK_EX | LOCK_NB and last; 
				
				# NB = non blocking
				# I don't think you can have a non blocking and an exclusing block
				# in the same breadth...?
				
				flock SAFETYLOCK, LOCK_EX | LOCK_NB and last; 
				
				sleep 1;
				redo if ++$sleep_count < 11; 
				
				# ok, we've waited 'bout 10 seconds... 
				# nothing's happening, let's say  fuck it. 
				
				carp "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Warning: Server is way too busy to unsubscribe people, waited 10 seconds to get access to the list file for $list, giving up: $!\n";
			
				return 'too busy'; 
				exit(0); 
			}

		}


		# safety lock is set. This should give us a nice big shield to do some file 
		# juggling and updating. I think there is a race condition between when the 
		# the first time the temp and list file are open, and the second time. 
		# This should stop that. wee. 
		############################################################################		

		#open the original list
		sysopen(MAIN_LIST, $main_list,  O_RDWR|O_CREAT, $DADA::Config::FILE_CHMOD ) or 
			croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error: Can't open email list to sort through and make deletions at '$main_list': $!";
		flock(MAIN_LIST, LOCK_SH) or 
			croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error: Can't create a shared lock to sort through and make deletions at '$main_list': $!";
	  
		# open a temporary list
		sysopen(TEMP_LIST, $temp_list,  O_RDWR|O_CREAT, $DADA::Config::FILE_CHMOD ) or 
			croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error: can't create temporary list to sort out deleted e-mails at '$temp_list': $!" ; 
		flock(TEMP_LIST, LOCK_EX) or
			croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error: can't create an exculsive lock to sort out deleted e-mails at'$temp_list': $!" ; 	
			
		my $check_this; 
	
		while(defined($check_this  = <MAIN_LIST>)){ 
			 #lets see, if they pass, send em over. 
			 chomp($check_this); 
			 $check_this = strip($check_this);
			 $check_this = cased($check_this);
			 
			 # unless its in out delete list, 
			  unless(exists($lookup_table{$check_this})){ 
				  # print it into the temporary list
				  print TEMP_LIST $check_this, "\n";
	
			  }else{
				  #missed the boat! 
				  $count++;
				  # js - log it
					$log->mj_log($self->{list},"Unsubscribed from $list.$type", $check_this) if $DADA::Config::LOG{subscriptions}; 
			  }
		}
		
		close (MAIN_LIST) or 
			croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error - did not successfully close file '$main_list': $!"; 
			
		close (TEMP_LIST) or 
			croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error - did not successfully close file '$temp_list': $!";
	
		#open the new list, open the old list, copy old to new, done. 
	
	
		sysopen(TEMP_LIST, $temp_list,  O_RDWR|O_CREAT, $DADA::Config::FILE_CHMOD ) or 
			croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error: Can't open temp email list '$temp_list' to copy over to the main list : $!";
		flock(TEMP_LIST, LOCK_SH) or 
			croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error: Can't create a shared lock to copy over email addresses at  '$temp_list': $!";

		sysopen(MAIN_LIST, $main_list,  O_WRONLY|O_TRUNC|O_CREAT, $DADA::Config::FILE_CHMOD ) or 
			croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error: can't open email list to update '$main_list': $!" ; 
		flock(MAIN_LIST, LOCK_EX) or
			croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error: can't create an exclusive lock to update '$main_list': $!" ; 	
			
			
		my $passed_email;	
		while(defined($passed_email  = <TEMP_LIST>)){ 
			 #lets see, if they pass, send em over. 
			 chomp($passed_email); 
			 print MAIN_LIST $passed_email, "\n";
		}
		
		close (MAIN_LIST) or 
		croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error - did not sucessfully close file '$main_list': $!"; 
		
		close (TEMP_LIST) or 
		croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error - did not sucessfully close file '$temp_list': $!";
		
		unlink($temp_list) or 
		carp "$DADA::Config::PROGRAM_NAME  $DADA::Config::VER Error: Could not delete temp list file '$temp_list': $!"; 
		
		close(SAFETYLOCK);
		chmod($DADA::Config::FILE_CHMOD , $lock_file);
		unlink($lock_file) or carp "couldn't delete lock file: '$lock_file' - $!";
		
		 
		return $count; 
		
	}else{ 
	
		carp('$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error: No list information given at Plain_Text.pm for remove_from_list()');
		return ('no list');
	} 			 
}


=pod

=head2 my $listpath = create_mass_sending_file(-List => $list, -ID => $message_id); 

When sending list messages to the entire list, we make a temp file called $istname.list.$listid
where $listname is the name of your list, and $list_id is an id number, usually made form the list, 
and created form the message ID if we have one. This also creates the pin number for each emal address and 
saves it into this file like so: 

	email::pin 

This can easilly be feed into either the Mail::Bulkmail module or our homebrew batch system. 
after the Lists are send DADA::Mail::Send.pm should remove this file. 


This function can also pass a reference to an array of addresses that shouldn't get sent the lsit message, 
you could theoretically pass the black list, or for the Dada Bridge Plugin, the mail alias address you set up. 

				-Ban => [$address_on, $address_two], 
				
=cut


=pod

=head2 my ($count, \%domains,\%SERVICES) = list_option_form 

this is brand new shiny backend for the 'View List' Control Panel.
It does a whole bunch of things, 
first off, it prints each email address in an option tag, for a select box, like this: 

 <option value=$email>$email</option>

It will also count how many email addresses match each 'top level domains' and 'services' 
these are specifies in the Config.pm file in the @DADA::Config::DOMAINS array  and the %SERVICES hash.  You can also turn these off 
in the Config.pm by setting $DADA::Config::SHOW_DOMAIN_TABLE, $DADA::Config::SHOW_SERVICES_TABLE to 0. 
 

=cut

sub list_option_form { 

	my $self = shift; 
	
	my %args = (-Type     =>  'list', 
	            -In_Order =>  $DADA::Config::LIST_IN_ORDER, 
	            @_);


	if(defined($self->{list})){ 
	
	#make the 'Show Domains' Hash
	my %domains; 
	foreach(@DADA::Config::DOMAINS){ $domains{$_} = 0; }
	$domains{Other} = 0;
	
	#make the 'Show Services' Hash
	my %SERVICES; 
	foreach(@DADA::Config::SERVICES){ $SERVICES{$_} = 0; }
		
		my $email;
		my $count = 0; 
		my $test = 0;
		   $test = $DADA::Config::SHOW_DOMAIN_TABLE + $DADA::Config::SHOW_SERVICES_TABLE + $DADA::Config::SHOW_EMAIL_LIST; 
		   
		unless ($test == 0){
		
			#this is a stupid, dumb, idiotic idea, but, people want it. 
			if($args{-In_Order} == 1){
				$self->sort_email_list(%args);
			}
		
			$self->open_list_handle(-Type => $args{-Type}); 

			while(defined($email = <LIST>)){ 
			
				chomp($email);
				
				if($DADA::Config::SHOW_EMAIL_LIST ==1){
					print "<option value=",$email,">",$email,"</option>\n";
				}
                
                # this is the 'Show Domains' Hash Generator
				
				if($DADA::Config::SHOW_DOMAIN_TABLE ==1){
					my $domain_email = $email;
					#delete everything before the first . after the @. 
					$domain_email =~ s/^(.*)@//; 
					#lowercase the ending..
					$domain_email = lc($domain_email); 
					#strip everything before the last . 
					$domain_email  =~ s/^(.*?)\.//;
					
					# hey, if it matches, record it. 
					if(exists($domains{$domain_email})){ 
					 $domains{$domain_email}++; 
					 }else{ 
					 $domains{Other}++;
					 } 
                 }
        

				# Here be the 'Show Services' Hash Generator; 
			    if($DADA::Config::SHOW_SERVICES_TABLE == 1){ 
				    my $services_email = $email;
					#delete everything before the first . after the @. 
	                $services_email =~ s/(^.*)@//; 
	                #lowercase the ending..
	                $services_email = lc($services_email); 

	                # hey, if it matches, record it. 
	                if(exists($SERVICES{$services_email})){ 
	                $SERVICES{$services_email}++ ;
	                }else{ 
	                $SERVICES{Other}++;
	                }
                }
 				$count++;
			}
	
		close (LIST);
	
		}	
	
		return($count, \%domains,\%SERVICES);
	
	}else{ 
		return 0; 
	}

}


sub create_mass_sending_file { 

	my $self = shift; 
	
	my %args = (-Type      		  => 'list', 
				-Pin       		  =>  1,
				-ID        		  =>  undef, 
				-Ban      		  =>  undef, 
				-Bulk_Test		  =>  0,
				
				-Save_At          => undef, 
				
				-Test_Recipient   => undef, 
				
				@_); 
	
	my $list       = $self->{list}; 
	   $list       =~ s/ /_/g;
	my $path       = $DADA::Config::TMP ; 
	my $type       = $args{-Type}; 
	
	
	my $message_id = message_id();
	
	#use the message ID, If we have one. 
	my $letter_id = $args{'-ID'} ||  $message_id;	
	   $letter_id =~ s/\@/_at_/g; 
	   $letter_id =~ s/\>|\<//g; 
	
	my $n_msg_id = $args{'-ID'} || $message_id;
       $n_msg_id =~ s/\<|\>//g;
       $n_msg_id =~ s/\.(.*)//; #greedy
   
	   
	
	my %banned_list; 
	
	if($args{-Ban}){ 
		$banned_list{$_} = 1 foreach @{$args{-Ban}}; 
	}
	
	my $list_file    = make_safer($DADA::Config::FILES . '/' . $list . '.' . $type); 
	my $sending_file = make_safer($args{-Save_At}) || make_safer($DADA::Config::TMP    . '/msg-' . $list . '-' . $type . '-' . $letter_id); 
	
			
	#open one file, write to the other. 
	my $email; 
	
	require  DADA::MailingList::Settings; 
	my $ls = DADA::MailingList::Settings->new({-list => $list}); 
	my $li = $ls->get; 
	
	sysopen(LISTFILE, "$list_file",  O_RDONLY|O_CREAT, $DADA::Config::FILE_CHMOD ) or 
		croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error: Cannot open email list for copying, in preparation to send out bulk message: $! "; 
	flock(LISTFILE, LOCK_SH); 
		
	sysopen (SENDINGFILE, "$sending_file",  O_RDWR|O_CREAT, $DADA::Config::FILE_CHMOD ) or
		croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error: Cannot create temporary email list file for sending out bulk message: $!"; 
	flock(SENDINGFILE, LOCK_EX); 	


    my $first_email = $li->{list_owner_email}; 
    
    if($args{'-Bulk_Test'} == 1 && $args{-Test_Recipient}){ 
        $first_email = $args{-Test_Recipient};
    }
    
	my $to_pin = make_pin(-Email => $first_email);
	my ($lo_e_name, $lo_e_domain) = split('@', $first_email); 
	
	
	my $total = 0; 
	
	
	
	print SENDINGFILE join('::', 
	                             $first_email,
	                             $lo_e_name, 
	                             $lo_e_domain, 
	                             $to_pin, 
	                             $list, 
	                             $self->{ls}->param('list_name'), 
	                             $n_msg_id, 
	                       );
	$total++;
	
	if($args{'-Bulk_Test'} != 1){ 
        while(defined($email  = <LISTFILE>)){ 
            chomp($email); 
            unless(exists($banned_list{$email})){
                
                my $pin = make_pin(-Email => $email); 
                my ($e_name, $e_domain) = split('@', $email); 						
                print SENDINGFILE "\n" . join('::', 
                                                    $email,
                                                    $e_name, 
                                                    $e_domain, 
                                                    $pin,
                                                    $list,
                                                    $self->{ls}->param('list_name'), 
                                                    $n_msg_id, 
                                                    
                                            );
                $total++;
            }
		}		
	}

	# why aren't I using: flock(LISTFILE), LOCK_UN); ? I think it's because it's not needed, if close(LISTFILE) is called...
	close(LISTFILE) 
		or croak ("$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error - could not close list file '$list_file'  successfully"); 
	
	close(SENDINGFILE) 
		or croak ("$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error - could not close temporary sending  file '$sending_file' successfully"); 
	
	#chmod! 
	chmod($DADA::Config::FILE_CHMOD , $sending_file);	
	
	return ($sending_file, $total); 

}


=pod

=head2 my ($unique, $duplicate) = unique_and_duplicate(-New_List => \@new_list); 

This is used to mass add and remove email addresses from a list, it takes a 
array ref full of new email addresses, and see if they are already in the list. 

my ($unique_ref, $duplicate_ref) = weed_out_subscribers(-List     => $list, 
														-Path     => $DADA::Config::FILES, 
														-Type     => 'list', 
														-New_List => \@addresses, 
														);

=cut

 
sub unique_and_duplicate { 

	my $self = shift; 
	
	my %args = (-New_List      => undef, 
	            -Type          => 'list',
	            @_,
	           ); 
	
	
	# first thing we got to do is to make a lookup hash. 
	my %lookup_table; 
	my $address_ref = $args{-New_List}; 
	my $list        = $self->{list};
	
	if($list and $address_ref){
	
		foreach(@$address_ref){$lookup_table{$_} = 0}
		
		# easy enough, now, we'll open up the list, and 
		# keep them as 0 if they're all unique, and 
		# flag them as 1 if they're in the list. 
	
		$self->open_list_handle(-Type => $args{-Type});
						 
		my $email; 
		
		#let us go.. 
			while(defined($email = <LIST>)){ 
			chomp($email);
			$lookup_table{$email} = 1 if(exists($lookup_table{$email})); 
			#nabbed it, 
			}
			close (LIST); 
			
			
		#lets lookie and see what we gots.     
		my @unique; 
		my @double; 
		my $value; 
		
		
		
		foreach(keys %lookup_table){
			$value = $lookup_table{$_}; 
			if($value == 1){ 
				push(@double, $_)
			}else{ 
				push(@unique, $_) 
			}
		}
		
		#again, harmony is restored to the force.
		return(\@unique, \@double); 
	
	}else{ 
	
		carp("$DADA::Config::PROGRAM_NAME $DADA::Config::VER No list name or list reference provided!");
		return undef;
	
	}
}

sub remove_this_listtype {

    my $self = shift;
    my %args = (@_); 
    
    if(!exists($args{-Type})){ 
	    croak('You MUST specific a list type in the "-Type" paramater'); 
	}
	else { 
	    if(!exists( $self->allowed_list_types()->{$args{-Type}})){ 
	        croak '"' . $args{-Type} . '" is not a valid list type! '; 
	    }
	}

	my $deep_six = $DADA::Config::FILES . '/' . $self->{list} . '.' . $args{-Type};


	$deep_six = make_safer($deep_six); 
	$deep_six=~ /(.*)/; 
	$deep_six = $1; 

#    warn '$deep_six ' . $deep_six;  
    if(-e $deep_six){ 
        my $n = unlink($deep_six);
        carp "couldn't delete '$deep_six'! " . $!
            if $n == 0;
    }
    
}




sub can_use_global_black_list { 

	my $self = shift; 
	return 0; 

}




sub can_use_global_unsubscribe { 

	my $self = shift; 
	return 0; 

}




sub can_filter_subscribers_through_blacklist { 
	
	my $self = shift; 
	return 0; 
}




sub can_have_subscriber_fields { 

    my $self = shift; 
    return 0; 
}




sub subscriber_fields { 
    return []; 
}




sub move_subscriber { 
    
    my $self   = shift; 
    
    my ($args) = @_;
    
    if(! exists $args->{-to}){ 
        croak "You must pass a value in the -to paramater!"; 
    }
    if(! exists $args->{-from}){ 
        croak "You must pass a value in the -from paramater!"; 
    }    
    if(! exists $args->{-email}){ 
        croak "You must pass a value in the -email paramater!"; 
    }
    
    if($self->allowed_list_types->{$args->{-to}} != 1){ 
        croak "list_type passed in, -to is not valid"; 
    }

    if($self->allowed_list_types->{$args->{-from}} != 1){ 
        croak "list_type passed in, -from is not valid"; 
    }
    
     if(DADA::App::Guts::check_for_valid_email($args->{-email}) == 1){ 
        croak "email passed in, -email is not valid"; 
    }
    
    
    my $moved_from_checks_out = 0; 
    if(! exists($args->{-moved_from_check})){ 
        $args->{-moved_from_check} = 1; 
    }
    
    if($self->check_for_double_email(-Email => $args->{-email}, -Type => $args->{-from}) == 0){ 
        
        if($args->{-moved_from_check} == 1){ 
            croak "email passed in, -email is not subscribed to list passed in, '-from'";     
        }
        else { 
            $moved_from_checks_out = 0; 
        }
    }
    else { 
        $moved_from_checks_out = 1; 
    }


	if(!exists($args->{-mode})){ 
		$args->{-mode} eq 'writeover_check'; 
	}
		
	if($args->{-mode} eq 'writeover'){ 
		if($self->check_for_double_email(-Email => $args->{-email}, -Type => $args->{-to}) == 1){ 
			$self->remove_subscriber(
				{ 
					-email => $args->{-email},
					-type  => $args->{-to}, 
				}
			); 
		}
	}
	else { 
	    if($self->check_for_double_email(-Email => $args->{-email}, -Type => $args->{-to}) == 1){ 
	        croak "email passed in, -email ( $args->{-email}) is already subscribed to list passed in, '-to' ($args->{-to})"; 
	    }
	}

   
   
   if($moved_from_checks_out){ 
   
        $self->remove_from_list(
            -Email_List =>[$args->{-email}], 
            -Type       => $args->{-from}
        );   
   
    }
    
    $self->add_subscriber(
        { 
            -email => $args->{-email}, 
            -type  => $args->{-to}, 
        }
    ); 
    
    if ($DADA::Config::LOG{subscriptions}) { 
        $log->mj_log(
            $self->{list}, 
            'Moved from:  ' . $self->{list} . '.' . $args->{-from} . ' to: ' . $self->{list} . '.' . $args->{-to}, 
            $args->{-email}, 
        );
    }


	return 1; 

}






sub DESTROY {}

1;



=pod

=head1 COPYRIGHT 

Copyright (c) 1999-2008 Justin Simoni All rights reserved. 

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, 
Boston, MA  02111-1307, USA.

=cut 
