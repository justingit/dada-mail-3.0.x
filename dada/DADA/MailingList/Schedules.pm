package DADA::MailingList::Schedules; 
use strict; 

use lib qw(./ ../ ../../ ../../DADA ../perllib); 


use DADA::Config qw(!:DEFAULT); 
use DADA::App::Guts; 
use DADA::MailingList::Settings;
use base "DADA::MailingList::Schedules::MLDb";

use Carp qw(croak carp);

=pod

=head1 NAME DADA::MailingList::Schedules

=head1 Synopsis

 my $mss = DADA::MailingList::Schedules->new({-list => 'listshortname'}); 

=head1 Description

This module holds shared methods used for the Beatitude scheduled 
mailer. The rest of the methods are located in DADA::MailingList::Schedules::MLDb.

=head1 Public Methods

=cut


=pod

=head2 run_schedules

 my $report = $mss->run_schedules(-test => 0);

Returns a nicely formatted report of the schedules that were run. 

If the B<-test> argument is passed with a value of 1, the schedules 
will go until actual mailing. 

=cut


sub run_schedules { 
	my $self = shift; 
	
	my %args = (-test    => undef, 
				-verbose => undef,
					       @_); 
	
	my $r = ''; 
				
	my $time        = time;
	
	$r .= "\n" . '-' x 72 . "\nRunning Schedule For: " . $self->{name} . "\n";
	#warn "\n" . '-' x 72 . "\nRunning Schedule For: " . $self->{name} . "\n";
	
	
	$r .=  "Current time is: " . $self->printable_date($time) . "\n";
	#warn "Current time is: " . $self->printable_date($time) . "\n";


	my @record_keys = $self->record_keys(); 
	

		$r .=  "    No schedules to run.\n" if ( !@record_keys);
		#warn  "    No schedules to run.\n" if ( !@record_keys);
		
	foreach my $rec_key(@record_keys){																#for all our schedules - 
		
		my $mail_status = {};
		my $checksums   = {};
		
		my $rec               = $self->get_record($rec_key); 	
		my $mailing_schedule  = $self->mailing_schedule($rec_key, $rec);
	
		my $run_this_schedule = 0;	
		my $never_ran_before  = 0; 
		
		$r .=  "\n    Examining Schedule: '" . $rec->{message_name} . "'\n";
		#warn "\n    Examining Schedule: '" . $rec->{message_name} . "'\n";
		
		if($rec->{active} ==1){													 							#first things first, is this schedule even active?
		
			$r .=  "    '" . $rec->{message_name} . "' is active -  \n";
			
			if (! $rec->{last_schedule_run}){
				$rec->{last_schedule_run} = ($time - 1);							# This must be your first time, don't be nervous; tee hee!
				$never_ran_before         = 1;
			}
			
			if($rec->{last_mailing}){ 
				$r .=  "        Last mailing:              " . $self->printable_date($rec->{last_mailing}) . "\n";
				#warn "        Last mailing:              " . $self->printable_date($rec->{last_mailing}) . "\n";
			}
			    
			    if($never_ran_before == 1){ 
			    	$r .=  "        This seems to be the first time schedule has been looked at...\n";
					#warn "        This seems to be the first time schedule has been looked at...\n";
			    }else{ 
			    	$r .=  "        Schedule last checked:     " .   $self->printable_date($rec->{last_schedule_run}) . "\n";
					#warn "        Schedule last checked:     " .   $self->printable_date($rec->{last_schedule_run}) . "\n";
				}
			
			if($mailing_schedule->[0]){ 
				$r .=  "        Next mailing should be on: " . $self->printable_date($mailing_schedule->[0]) . "\n";
				#warn "        Next mailing should be on: " . $self->printable_date($mailing_schedule->[0]) . "\n";
			}
			CHECKSCHEDULE: foreach my $s_time(@$mailing_schedule){
													# this should be last mailing, eh?!
													# no, since not all schedules repeat.
				if(($s_time <= $time) && ($s_time > $rec->{last_schedule_run})){								# Nothing in the future, mind.		
																			   		   							# Nothing before we need to.
																			   		   							
				# There's a bug in here. For instance, a schedule will not go out, even
				# though the scheduled mailing is in the past IF the schedule has never
				# been checked. 
				
				#	$s_time = scheduled times
				#	$time   = right now
				#	$rec->{last_schedule_run} - the last time it was run 
				
				# 	$rec->{last_schedule_run} COULD BE $time as well, 
				#   if the schedule had never run. What to do? 
				
				# we could set $rec->{last_schedule_run} to ($time - 1) if it's undefined,
				# or set the $rec->{last_schedule_run} to the time the schedule was first created...?
				# OR i guess we can do both..
				#
				# at the moment, i'm going to do both, since I can't remember if $rec->{last_schedule_run}
				# is wiped out everytime a schedule is edited. 
			
																			   		   							 
						$r .=  "            '" . $rec->{message_name} . "' scheduled to run now! \n";
						#warn "            '" . $rec->{message_name} . "' scheduled to run now! \n";
						$run_this_schedule = 1;
						last CHECKSCHEDULE; 															# run only the last schedule, lest we bombard a hapless list. 						 
				}
			}
		}else{ 
			$r .=  "        '" . $rec->{message_name} . "' is inactive. \n";
			#warn   "        '" . $rec->{message_name} . "' is inactive. \n";
		}
		
		#warn "here.1"; 
		
		if($run_this_schedule == 1){ 
	
		
			if($args{-test} == 1){ 		
				($mail_status, $checksums) = $self->send_scheduled_mailing(
																		   -key   => $rec_key, 
																		   -test  => 1, 
																		   -hold  => 1,
																		  ); 								
			}else{ 				
				 ($mail_status, $checksums) = $self->send_scheduled_mailing(
																			-key  => $rec_key, 
																			-test => $rec->{only_send_to_list_owner},
																			-hold => 1, 
																			); 
				if(! keys %$mail_status){ 
					$rec->{last_mailing} = $time;																# remember we sent the message at this time;  						
				}
			}			
		}
		
		#warn "here.2"; 
		
		# I don't know why this line wasn't in here: 
			if($run_this_schedule == 1){ 
				
		
				if(! $args{-test}){ 
			
					#warn "here.3"; 
			
				     $rec->{active}            = 0 if ! $mailing_schedule->[0];
				 	 $rec->{last_schedule_run} = $time;		
		 	 
					 if(keys %$checksums){ 
					 		$rec->{PlainText_ver}->{checksum} = $checksums->{PlainText_checksum};
					 		$rec->{HTML_ver}->{checksum}      = $checksums->{HTML_checksum};			 	
					 }	
			
						#warn "here.4"; 
				
					$self->save_record(
						-key => $rec_key, 
						-data => $rec, 
						-mode => 'append',
					);											# save the changes we've made to the record.			
						#warn "here.5"; 
					$rec = $self->get_record($rec_key); 
						#warn "here.6"; 
				} 
	
				if(keys %$mail_status){
					$r .=  "\n            ***    Scheduled Mailing Not Sent, Reason(s):    ***\n";
					#warn  "\n            ***    Scheduled Mailing Not Sent, Reason(s):    ***\n";
					$r .=   '                - ' .  DADA::App::Guts::pretty($_) . "\n" foreach keys %$mail_status;
					#warn '                - ' .  DADA::App::Guts::pretty($_) . "\n" foreach keys %$mail_status;
					$r .=  "\n";
			
				}
		
				if((! $args{-test})              && 
				   (! keys %$mail_status)        && 
				   ($rec->{active}         == 0) &&
				   ($rec->{self_destruct}  == 1)
				  ){ 
				  	$r .= "\n        Schedule is set to self destruct! \n";
				#warn "\n        Schedule is set to self destruct! \n";
					$self->remove_record($rec_key); 
				}else{ 
					#print "nope!"; 
				}
			}
		
		}
	# 	if($run_this_schedule == 1){ 
		
		
		
		
	$r .= '-' x 72 . "\n";
	
	$self->_send_held_messages; 
	
	#warn "here.7"; 
		
	return $r; 
	
	
}



=pod

=head2 mailing_schedule

 my $mailing_schedule = $mss->mailing_schedule($key);

returns a reference to an array of times that a schedule saved in $key has to be sent out.

=cut


sub mailing_schedule {
    my $self     = shift;
    my $key      = shift;
	my $r        = shift || $self->get_record($key);
    my $today_is = time;

    if ( !defined($key) ) {
        croak "no key $!";
    }

   my $sched_mailing = $r->{mailing_date};

    if ( $r->{repeat_mailing} != 1 ) {

        # not right now, when we last try to run the schedule.
        if ( $r->{mailing_date} > $r->{last_schedule_run} ) {
            return [ $r->{mailing_date} ];
        }
        else {
            return [];
        }
    }
    else {
        if ( $r->{repeat_times} < 1 ) {
            return [ $r->{mailing_date} ];
        }
        else {

            my $timespan = 0;
            $timespan = 60                 if $r->{repeat_label} eq 'minutes';
            $timespan = 60 * 60            if $r->{repeat_label} eq 'hours';
            $timespan = 60 * 60 * 24       if $r->{repeat_label} eq 'days';
            $timespan = 60 * 60 * 24 * 30  if $r->{repeat_label} eq 'months';
            $timespan = 60 * 60 * 24 * 265 if $r->{repeat_label} eq 'years';

            if ( $r->{repeat_times} ) {
                $timespan = ( $timespan * $r->{repeat_times} );
            }

            my $i = 0;
            my @mailing_times;    # = ($r->{mailing_date});
            if ( $r->{mailing_date} > $r->{last_schedule_run} ) {
                @mailing_times = ( $r->{mailing_date} );
            }

#Fucker. $r->{repeat_number}     = 1000      if $r->{repeat_number} eq 'indefinite';

            if ( !$r->{last_schedule_run} ) {
                $r->{last_schedule_run} = $today_is;
            }
            if ( !$r->{repeat_number} ) {
                $r->{repeat_number} = 0;
            }

            if ( $r->{repeat_number} eq 'indefinite' ) {

                # yeah, we *could* find each and every time a mailing should
                # go out, until... inifinity, but come now.
                # This will just find the next time a mailing should go out.

                my $i = 1;
                while ( $i == 1 ) {
                    $sched_mailing = ( $sched_mailing + $timespan );
                    if ( $sched_mailing > $r->{last_schedule_run} )
                    {    # should /this/ be $r->{last_mailing}?
                            # It doesn't matter, since only one schedule is
                            # passed to the scheduled runner.
                        push ( @mailing_times, $sched_mailing );
                        $i = 0;
                    }
                }

            }
            else {
                for ( $i = 0 ; $i <= $r->{repeat_number} ; $i++ ) {
                    $sched_mailing = ( $sched_mailing + $timespan );
                    push ( @mailing_times, $sched_mailing )
                      if $sched_mailing > $r->{last_schedule_run};
                }
            }

            return \@mailing_times;
        }

    }
}





=pod

=head2 printable_date

 $mss->printable_date($form_vals->{last_mailing})

returns a date that's pretty to look at, when given a number of seconds since epoch.

=cut


sub printable_date { 
	
	# DEV: Tests are needed for this and actually, a better method should be 
	# used to create this... 
	
	
	my $self = shift; 
	my $date = shift; 
	my %mail_month_values = (
	0  => 'January', 
	1  => 'February', 
	2  => 'March', 
	3  => 'April', 
	4  => 'May', 
	5  => 'June',
	6  => 'July', 
	7  => 'August', 
	8  => 'September', 
	9  => 'October', 
	10 => 'November', 
	11 => 'December', 
	); 
	
	
	
	my %mail_day_values = (
	
	1  => '1st', 
	2  => '2nd', 
	3  => '3rd', 
	4  => '4th', 
	5  => '5th',
	6  => '6th', 
	7  => '7th', 
	8  => '8th', 
	9  => '9th', 
	10 => '10th', 
	11 => '11th',
	12 => '12th', 
	13 => '13th', 
	14 => '14th', 
	15 => '15th', 
	16 => '16th', 
	17 => '17th', 
	18 => '18th', 
	19 => '19th', 
	20 => '20th', 
	21 => '21st', 
	22 => '22nd', 
	23 => '23rd', 
	24 => '24th', 
	25 => '25th', 
	26 => '26th', 
	27 => '27th', 
	28 => '28th', 
	29 => '29th', 
	30 => '30th', 
	31 => '31st',
	); 
	
	my %mail_minute_values = (
	0 => '00',
	1 => '01', 
	2 => '02',
	3 => '03',
	4 => '04',
	5 => '05',
	6 => '06',
	7 => '07',
	8 => '08',
	9 => '09',
	); 


	
	
		#  0    1    2     3     4    5     6     7     8
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($date);
		
	my $ending = 'a.m.'; 
	
	if($hour >= 12){ 
		$hour -= 12
			if $hour != 12; 
		$ending = 'p.m.';
	}
	elsif($hour == 0) {
		$hour = 12; 
	}
	
	$min = '0' . $min if $min < 10; 
	
	# # This works?
	# # return $mail_month_values{$mon} . ' ' . $mail_day_values{$mday} . ', ' . ($year + 1900) . ' - ' . $hour . ':' . $min . ' '. $ending; 

 	return scalar localtime($date); 


#use POSIX 'strftime';
#return POSIX::strftime("%d%b%y:%H:%M:%S", localtime($date));  # %b returns Mmm, not mmm

} 


=pod

=head2 send_scheduled_mailing

 my ($mail_status, $checksums) 
 	= $self->_send_scheduled_mailing(
									-key   => $rec_key, 
									-test  => 0, 
									-hold  => 1,
									);

Sends an individual schedule, as defined by the information 
in B<-key>. if B<-hold> is set to 1, mailing will be queued until all 
schedules are run. (should be set to 1). If B<-test> is set to 1, 
only a test mailing (message to the list owner) will be run. 

=cut

sub send_scheduled_mailing { 
	
	my $self = shift; 
	
	my %args = (-key  => undef, 
				-test => 0,
				-hold => 0,  
				@_); 
				
	croak "no key!" if ! $args{-key}; 
	
	my ($send_flags, $checksums, $message) = $self->_build_email(-key => $args{-key});
	
	
	if(! keys %$send_flags){ 
	
		my $ls = DADA::MailingList::Settings->new({-list => $self->{name}}); 

		my $list_info = $ls->get(); 
		
		require DADA::Mail::Send; 

		my $mh = DADA::Mail::Send->new(
					{
						-list   => $self->{name}, 
						-ls_obj => $ls, 
					}
				); 		   
				
		   $mh->ignore_schedule_bulk_mailings(1);
		   $mh->mass_test(1) if $args{-test} == 1;    

		### Partial Sending Stuff... 
		### This is very much... busy, to say the least... 
		# Probably should put this in its own method... 
		# What's funny to me, is that it works.... 
		
				my $record                 = $self->get_record($args{-key});
				my $partial_sending_params = $record->{partial_sending_params}; 
				my $partial_sending = {}; 


				foreach my $field(@$partial_sending_params){ 

					if($field->{field_comparison_type} eq 'equal_to'){ 
						$partial_sending->{$field->{field_name}} = {equal_to => $field->{field_value}}; 
					}
					elsif($field->{field_comparison_type} eq 'like'){ 
						$partial_sending->{$field->{field_name}} = {like => $field->{field_value}}; 
					}   
				}

				if(keys %$partial_sending){ 
					$mh->partial_sending($partial_sending); 
				}

		###/ Partial Sending Stuff... 


		   
		   if($args{-hold} == 1){ 
		   		push(@{$self->{held_mailings}}, {-key => $args{-key}, -test => $args{-test}, -obj => $mh, -message => $message}); 
		   }else{ 
		   		my $message_id = $mh->mass_send(%$message);
		   		if ($args{-test} != 1){
		   			$self->_archive_message(-key => $args{-key}, -message => $message, -mid => $message_id); 
	   	   		}
	   	   }
	}   
	   return ($send_flags, $checksums); 
	   
}







=pod

=head1 Private Methods

=head2 _send_held_messages

 $self->_send_held_messages; 

messages are queued up before being sent. Calling this method will send 
these queued messages. 

=cut


sub _send_held_messages { 

	my $self = shift; 
	foreach my $held(@{$self->{held_mailings}}){ 
		my $obj     = $held->{-obj}; 
		my $message = $held->{-message}; 
		my $key     = $held->{-key}; 
		my $test    = $held->{-test};
		my $message_id = $obj->mass_send(%$message); 
		if ($held->{-test} != 1){
			$self->_archive_message(-key => $key, -message => $message, -mid => $message_id); 
		}		   		
	}
} 








=pod

=head2 _build_email

 my ($send_flags, $checksums, $message) = $self->_build_email(-key => $key);

Creates an email message ($message) that can then be sent with DADA::Mail::Send. It also 
returns the hashref, $send_flags that will denote any problems with message building, 
as well as a MD5 checksum of the message itself. 

=cut

sub _build_email { 

	my $self = shift; 
	my %args = (-key => undef, 
				@_); 
				
	croak "no key!" if ! $args{-key}; 				

	my $record = $self->get_record($args{-key});
	
	require MIME::Lite; 
	#$MIME::Lite::PARANOID = $DADA::Config::MIME_PARANOID;
	MIME::Lite->quiet(1);
	
	my $send_flags = {}; 
	
	# Hmm - we can have this happen, to get the checksum stuff and then *redo* it for the URL stuff, if needed? 
	# Because - well, the checksum is probably even more accurate, before we bring the data into MIME::Lite::HTML - 
	# As it says right in the docs the MIME creation stuff is desctruction. Ok? OK.
	# Then, if we do pull data from a URL, we just throw the info from $HTML_ver away, remake it, via 
	# MIME::Lite::HTML and call it good. 
	my ($pt_flags,   $pt_checksum,   $pt_headers,   $PlainText_ver) = $self->_create_text_ver(-record => $record, -type => 'PlainText'); 
	my ($html_flags, $html_checksum, $html_headers, $HTML_ver)      = $self->_create_text_ver(-record => $record, -type => 'HTML'); 
	
	
	# So. Right here? 
	require DADA::App::FormatMessages; 
	($PlainText_ver, $HTML_ver) = DADA::App::FormatMessages::pre_process_msg_strings($PlainText_ver, $HTML_ver); 
	
	$send_flags->{PlainText_ver_undefined}  = 1 if (! $PlainText_ver)	&&	($record->{PlainText_ver}->{only_send_if_defined}) == 1;
	$send_flags->{HTML_ver_undefined}       = 1 if (! $HTML_ver)	    &&	($record->{HTML_ver}->{only_send_if_defined})      == 1;
	
	
	%$send_flags = (%$send_flags, %$pt_flags, %$html_flags); 
	
	my $msg; 
	
	
	my $ls = DADA::MailingList::Settings->new({-list => $self->{name}}); 
	my $list_info = $ls->get(); 


	if($PlainText_ver && $HTML_ver){ 
		$msg = MIME::Lite->new(
				Type      => 'multipart/alternative',
				Datestamp => 0, 
		);

	}elsif($PlainText_ver){ 

	}elsif($HTML_ver){ 

	}else{ 
		$msg = MIME::Lite->new(
					Type      =>'multipart/mixed',
					Datestamp => 0, 
			  ); 
	}
					
	if($PlainText_ver && $HTML_ver){ 
		$msg->attach(
					  Type     => 'text/plain', 
					  Data     => $PlainText_ver, 
					  Encoding => $list_info->{plaintext_encoding}, 
					); 
		$msg->attach(
		 			 Type      => 'text/html', 
		 			 Data      => $HTML_ver,
		 			 Encoding => $list_info->{html_encoding}, 
		 		    );
		 		    
		 		    foreach(keys %$pt_headers){ 
						$msg->add($_ => $pt_headers->{$_}); 
					}
					
		 		    foreach(keys %$html_headers){ 
						$msg->add($_ => $html_headers->{$_}); 
					}
					
					
				      	
					
	}elsif($PlainText_ver){ 
		$msg = MIME::Lite->new(
							  Type      => 'text/plain', 
							  Data      => $PlainText_ver, 
							  Encoding  => $list_info->{plaintext_encoding}, 
							  Datestamp => 0, 
					         );  
					         
				 		    foreach(keys %$pt_headers){ 
						$msg->add($_ => $pt_headers->{$_}); 
					}
					
					
	}elsif($HTML_ver){ 
		
		   
		$msg = MIME::Lite->new(
							  #Type     => $html_content_type,
							  Type      => 'text/html', # this is probably fine...
							  Data      => $HTML_ver,
							  Encoding  => $list_info->{html_encoding}, 
						   	  Datestamp => 0, 
				     		  );  
				     		  
		foreach(keys %$html_headers){ 
				$msg->add($_ => $html_headers->{$_}); 
		}
					
	}

	foreach my $att(@{$record->{attachments}}){ 
		$msg->attach(
					 Type        => $self->_find_mime_type($att), 
					 Path        => $att->{attachment_filename}, 
					 Disposition => $att->{attachment_disposition}
					); 
	} 
	
	$msg->replace('X-Mailer' =>"");
	 
	require DADA::App::FormatMessages; 
	my $fm = DADA::App::FormatMessages->new(-List => $self->{name}); 

	   # What?
	   $record->{headers}->{Subject} = $pt_headers->{Subject} if $pt_headers->{Subject};
	   $record->{headers}->{Subject} = $html_headers->{Subject} if $html_headers->{Subject};
	 
	   if(exists($record->{headers}->{Subject})){ 
	   		$fm->Subject($record->{headers}->{Subject}) 
	   }	
		
	if($PlainText_ver && $HTML_ver){ 
	
		$fm->use_plaintext_email_template($record->{PlainText_ver}->{use_email_template});
		$fm->use_html_email_template(     $record->{HTML_ver}->{use_email_template});
	
	}elsif($PlainText_ver){ 
	
		$fm->use_plaintext_email_template($record->{PlainText_ver}->{use_email_template});
		$fm->use_html_email_template(     $record->{PlainText_ver}->{use_email_template});
		
	}elsif($HTML_ver){
	
		$fm->use_plaintext_email_template($record->{HTML_ver}->{use_email_template});
		$fm->use_html_email_template(     $record->{HTML_ver}->{use_email_template});
		
	}
		
	   $fm->use_header_info(1);
	    
	my ($final_header, $final_body) = $fm->format_headers_and_body(-msg => $msg->as_string);
	
	require DADA::Mail::Send; 
	my $mh = DADA::Mail::Send->new(
				{ 
					-list   => $self->{name}, 
					-ls_obj => $ls, 
				}
			); 
	my %headers = $mh->clean_headers($mh->return_headers($final_header));	
		
	my $return = {};
	
	   $return = { 
			     # In this case, I don't want to overwrite %headers, 
	   			  %{$record->{headers}},
				  %headers, 
			      Body      => $final_body,
			   }; 
						  
	return ($send_flags, {PlainText_checksum => $pt_checksum, HTML_checksum => $html_checksum}, $return); 

}




=pod

=head2 _create_text_ver

my ($flags,   $checksum,   $headers,  $message) = $self->_create_text_ver(-record => $record, -type => 'PlainText'); 

Creates the text part of an email, using the information saved in the 
$record record. Returns any problemswith building the message in 
$flags ($hashref), a checksum in $checksum, headers (hashref) in 
$headers and the actual message in $message. B<-type> needs to 
be either B<PlaintText> or B<HTML>.

=cut




sub _create_text_ver { 
	
	my $self = shift; 
	
	my %args = (-record => {},
				-type   => undef,  
				@_); 
				
	croak "no record! $!"		unless keys %{$args{-record}}; 
	croak "no type!   $!"		unless $args{-type}; 	

	my $record       = $args{-record}; 
	my $type         = $args{-type};
	my $headers      = {};
	my $data         = undef;
	my $create_flags = {}; 
	 
	if($record->{$type . '_ver'}->{source} eq 'from_file'){ 
		$data = $self->_from_file($record->{$type . '_ver'}->{file});
	}elsif($record->{$type . '_ver'}->{source} eq 'from_url'){ 
		$data = $self->_from_url($record->{$type . '_ver'}->{url}); 
	}elsif($record->{$type . '_ver'}->{source} eq 'from_text'){ 
		$data = $record->{$type . '_ver'}->{text}; 
	}
		
	if($data){ 
		
		my $we_gotta_virgin = $self->_virgin_check($record->{$type . '_ver'}->{checksum}, \$data); 
		
		my $checksum = $self->_create_checksum(\$data);
		
		unless($we_gotta_virgin){  #mmmm, virgin...
			if($record->{$type . '_ver'}->{only_send_if_diff} == 1){ # hmmmm different...
				$create_flags->{$type . '_ver_same_as_last_mailing'} = 1; 
			}
		} 
		
		
		$data = DADA::App::Guts::strip($data); 
		($headers, $data) = $self->_grab_headers($data) if $record->{$type . '_ver'}->{grab_headers_from_message} == 1;
			
		return ($create_flags, $checksum, $headers, $data); 
	
	}else{  
		return ({},{}, undef), 	
	}	
	
}




=pod

=head2 _from_file

 my $data = $self->_from_file($filename); 

Grabs the contents of a file, returns contents.

=cut


sub  _from_file { 

	my $self = shift; 
	my $fn   = shift; 	
	croak "no filename!" if ! $fn; 
	
	open(FH, "<$fn") or return undef; 
	
	my $data = undef; 
       $data = do{ local $/; <FH> };
	 
	close(FH); 
	return $data; 
}





=pod

=head2 _from_url

	my $data = $self->_from_url($url); 

returns the $data fetched from a URL

=cut


sub _from_url { 

	my $self = shift; 
	my $url  = shift; 
	croak "no url! $!" if ! $url; 
	
	my $data = undef; 
	require LWP::Simple; 
	$data = LWP::Simple::get($url); 
	return $data; 
	
}






=pod

=head2 _create_checksum

 my $cmp_cs = $self->_create_checksum($data_ref);	

Returns an md5 checksum of the reference to a scalar being passed.

=cut


sub _create_checksum { 

	my $self = shift; 
	my $data = shift; 

	use Digest::MD5 qw(md5_hex); # Reminder: Ship with Digest::Perl::MD5....
	
	if($] >= 5.008){
		require Encode;
		my $cs = md5_hex(Encode::encode_utf8($$data));
		return $cs;
	}else{ 			
		my $cs = md5_hex($$data);
		return $cs;
	}
} 





=pod

=head2 _virgin_check

 my $we_gotta_virgin = $self->_virgin_check($record->{$type . '_ver'}->{checksum}, \$data); 
	
Figures if a copy of a message has previously been sent, using the previous checksum value.

=cut



sub _virgin_check { 

	my $self = shift; 
	my $cs   = shift; 
	
	my $data_ref = shift;
	
	
	my $cmp_cs = $self->_create_checksum($data_ref);

	#	carp 'comparing: ' . $cmp_cs . ' with: ' . $cs; 
	
	return 1 if ! $cs; 
	(($cmp_cs eq $cs) ? (return 0) : (return 1)); 
	
}





=pod

=head2 _grab_headers

 ($headers, $data) = $self->_grab_headers($data) if $record->{$type . '_ver'}->{grab_headers_from_message} == 1;
	
Splits the message in $data into headers and a body. 

=cut

sub _grab_headers { 

	my $self = shift; 
	my $data = shift; 

	$data =~ m/(.*?)\n\n(.*)/s; 
	
	my $headers = $1; 
	my $body    = $2;

	#init a new %hash
	my %headers;
	
	# split.. logically
	my @logical_lines = split /\n(?!\s)/, $headers;
	 
		# make the hash
		foreach my $line(@logical_lines) {
			  my ($label, $value) = split(/:\s*/, $line, 2);
			  $headers{$label} = $value;
			  
			 # carp '$label ' . $label; 
			 # carp '$value ' . $value; 
			}
	
	if(keys %headers){ 
		return (\%headers, $body);
	}else{ 
		return ({}, $data);
	} 
}




sub _archive_message { 
	my $self = shift; 
	my %args = (
				-key     => undef, 
				-message => {}, 
				-mid     => undef, 				
				@_,
			 ); 
	croak "no -key!"      if !$args{-key}; 
	croak "no -message!"  if !keys %{$args{-message}};
	croak "no -mid!"      if ! $args{-mid}; 
	
	my $rec = $self->get_record($args{-key}); 
	
	if($rec->{archive_mailings} != 1){ 
		return; 
	}

	require DADA::MailingList::Archives; 		
	my $ls        = DADA::MailingList::Settings->new({-list => $self->{name}}); 
	my $list_info = $ls->get();
		
	my $la = DADA::MailingList::Archives->new({-list => $self->{name}});  
		
	my $raw_msg; 
	
	foreach(keys %{$args{-message}}){ 
		next if $_ eq 'Body';
		$raw_msg .= $_ . ': ' . $args{-message}->{$_} . "\n";
	}
	$raw_msg .= "\n\n" . $args{-message}->{Body}; 


	$la->set_archive_info(
						  $args{-mid}, 
						  $args{-message}->{Subject}, 
						  undef, 
						  undef,
						  $raw_msg,
						 );
	
}



# deprecated.
sub can_archive { 
	return 1; 
}







=pod

=head2 _find_mime_type

 my $type = $self->_find_mime_type('filename.txt'); 

Attempts to figure out the MIME type of a filename.

=cut


sub _find_mime_type { 
	my $self = shift; 
	my $att  = shift; 
	
	croak "no attachment! $! " if ! $att; 
		
	my $mime_type = 'AUTO'; 
	
	if ($att->{attachment_mimetype} =~ m/auto/){ 
		my $file_ending = $att->{attachment_filename};
		
		require MIME::Types; 
		require MIME::Type;
	
		if(($MIME::Types::VERSION >= 1.005) && ($MIME::Type::VERSION >= 1.005)){ 
			$file_ending =~ s/^\.//; 
			my $mimetypes = MIME::Types->new;
			my MIME::Type $attachment_type  = $mimetypes->mimeTypeOf($file_ending);
			$mime_type = $attachment_type;
		}else{ 
			# Alright, we're going to have to figure this one ourselves...
			if(exists($DADA::Config::MIME_TYPES {'.'.lc($file_ending)})) {  
				$mime_type = $DADA::Config::MIME_TYPES {'.'.lc($file_ending)};
			}else{ 
				# Drat! all hope is lost! Abandom ship!
				$mime_type = $DADA::Config::DEFAULT_MIME_TYPE; 
			}
		}
	}else{ 
		$mime_type = $att->{attachment_mimetype};
	}		

	$mime_type = 'AUTO' if(! $mime_type); 
	
	return $mime_type; 
}

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

