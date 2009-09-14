package DADA::App::FormatMessages;

use strict; 
use lib qw(../../ ../../DADA/perllib); 

use DADA::Config qw(!:DEFAULT); 

use MIME::Parser;
use MIME::Entity; 

use DADA::Config qw(!:DEFAULT); 
use DADA::App::Guts; 


use Carp qw(croak carp); 

use vars qw($AUTOLOAD); 

=pod

=head1 NAME

DADA::App::FormatMessages

=head1 SYNOPSIS

 my $fm = DADA::App::FormatMessages->new(-List => $list); 
 
 # The subject of the message is...  
   $fm->Subject('This is the subject!'); 
   
 # Use information you find in the headers 
  $fm->use_header_info(1);
 
 # Use the list template   
   $fm->use_list_template(1); 
 
 # Use the email template.
   $fm->use_email_templates(1);  
 
 # Consider this message as if it's from a discussion list
   $fm->treat_as_discussion_msg(1);
 
 my ($header_str, $body_str) = $fm->format_headers_and_body(-msg => $msg);
 
 # (... later on... 
 
 use DADA::MAilingList::Settings; 
 use DADA::Mail::Send; 
 
 my $ls = DADA::MailingList::Settings->new({-list => $list}); 
 my $mh = DADA::Mail::Send->new({-list => $list}); 
 
 $mh->send(
           $mh->return_headers($header_str), 
		   Body => $body_str,
		  ); 

=head1 DESCRIPTION

DADA::App::FormatMessages is used to get a email message ready for sending to your 
mailing list. Most of its magic is behind the scenes, and isn't something you have
to worry about, but we'll go through some detail. 



=head1 METHODS

=cut




my %allowed = (
	Subject                      => undef, 
	use_list_template            => 0, 
	use_html_email_template      => 1,
	use_plaintext_email_template => 1, 
	treat_as_discussion_msg      => 0, 
	use_header_info              => 0, 
	orig_entity                  => undef, 
	
	originating_message_url      => undef, 
	
	reset_from_header            => 1, 
);



=pod

=head2 new


 my $fm = DADA::App::FormatMessages->new(-List => $list); 


=cut

sub new {

	my $that = shift; 
	my $class = ref($that) || $that; 
	
	my $self = {
		_permitted => \%allowed, 
		%allowed,
	};
	
	bless $self, $class;
	
	my %args = (-List         => undef,
	            -yeah_no_list => 0, 
					@_); 
    
    if(!exists($args{-List}) && $args{-yeah_no_list} == 0){ 
    
        die "no list!" if ! $args{-List}; 	
	}
	
	
   $self->_init(\%args); 
   return $self;
}




sub AUTOLOAD { 
    my $self = shift; 
    my $type = ref($self) 
    	or croak "$self is not an object"; 
    	
    my $name = $AUTOLOAD;
       $name =~ s/.*://; #strip fully qualifies portion 
    
    unless (exists  $self -> {_permitted} -> {$name}) { 
    	croak "Can't access '$name' field in object of class $type"; 
    }    
    if(@_) { 
        return $self->{$name} = shift; 
    } else { 
        return $self->{$name}; 
    }
}




sub _init  {

	my $self    = shift; 
	my $args    = shift;
	
	my $parser = new MIME::Parser; 
	   $parser = optimize_mime_parser($parser); 
	   
 	$self->{parser} = $parser; 
 	
 	if(exists($args->{-List}) && $args->{-yeah_no_list} == 0){ 
 	    require DADA::MailingList::Settings; 


		my $ls = DADA::MailingList::Settings->new(
				{
					-list => $args->{-List}
				}                           	   
			); 

        $self->{ls} = $ls; 
        
        $self->{list} = $args->{-List};
    
        $self->Subject($self->{ls}->param('list_name')); 
        
		$self->use_list_template($self->{ls}->param('apply_list_template_to_html_msgs') ); 

    }
    
	$self->use_email_templates(1); 

}




sub use_email_templates { 
	
	my $self = shift; 
	my $v    = shift; 
		
	if($v == 1 || $v == 0) { 
	
		$self->use_html_email_template($v); 
		$self->use_plaintext_email_template($v); 
		$self->{use_email_templates} = $v;
		
		return  $self->{use_email_templates}; 
		
	}else{ 
		return $self->{use_email_templates};
	}

}




sub format_message { 

	my $self = shift; 
	
	my %args = (-msg  => undef, 
				@_); 
	
	die "no msg!"  if ! $args{-msg};
	
	
    my ($h, $b) = $self->format_headers_and_body(%args);
    return $h . "\n" . $b; 
}




=pod

=head2 format_headers_and_body

 my ($header_str, $body_str) = $fm->format_headers_and_body(-msg => $msg);

Given a string, $msg, returns two variables; $header_str, which will have all 
the headers and $body_str, that holds the body of your message. 

=head1 ACCESSORS

=head2 Subject

Set the subject of a message

=head2 use_list_template

If set to a true value, will apply the list template to the HTML part of your message 

=head2 use_email_templates

If set to a true value, will apply your email templates to the HTML/PlainText parts 
of your message. 

=head2 treat_as_discussion_msg 

When set to a true value, will try the message as if it was from a discussion list. 

=head2 use_header_info

If set to a true value, will inspect the headers of a message (for example, the From: line) 
to work with

=cut

sub format_headers_and_body { 

	my $self = shift; 
	
	my %args = (-msg                 => undef, 
		  	    @_
		  	   ); 

	die "no msg!"  if ! $args{-msg};
	
	my $entity     = $self->{parser}->parse_data($args{-msg});

	$self->orig_entity($entity); 

	$self->Subject($entity->head->get('Subject', 0))
		if $entity->head->get('Subject', 0);

	$entity     = $self->_format_headers($entity)
		if $self->treat_as_discussion_msg; 
	
	$entity     = $self->_fix_for_only_html_part($entity); 
	$entity     = $self->_format_text($entity);		
	
	# yeah, don't know why you have to do it 
	# RIGHT BEFORE you make it a string...
	$entity->head->delete('X-Mailer')
    	if $entity->head->get('X-Mailer', 0); 


	return ($entity->head->as_string, $entity->body_as_string) ;

}


=pod

=head1 PRIVATE METHODS

=head2 _fix_for_only_html_part

 $entity = $self->_fix_for_only_html_part($entity); 

Changes the single part, HTML entity into a multipart/alternative message, 
with an auto plaintext version. 

=cut


sub _fix_for_only_html_part { 

	my $self   = shift; 
	my $entity = shift; 
	
	$entity = $self->_create_multipart_from_html($entity); 

	return $entity; 

}




=pod

=head2 _format_text

 $entity = $self->_format_text($entity);	

Given an MIME::Entity (may be multipart) will attempt to:

=over

=item * Apply the List Template

=item * Apply the Email Template

=item * interpolate the message to change Dada Mail's pseudo tags to their real value

=back

=cut

sub _format_text { 

	my $self   = shift; 
	my $entity = shift; 
	
	
	
	my @parts  = $entity->parts; 
	
	if(@parts){
		my $i; 
		foreach $i (0 .. $#parts) {
			$parts[$i]= $self->_format_text($parts[$i]);	
		}
		$entity->sync_headers('Length'      =>  'COMPUTE',
							  'Nonstandard' =>  'ERASE');
	}else{ 		
	
		my $is_att = 0; 
		if (defined($entity->head->mime_attr('content-disposition'))) { 
				$is_att = 1
				 if  $entity->head->mime_attr('content-disposition') =~ m/attachment/; 
			}
			
		if(
		    (
		    ($entity->head->mime_type eq 'text/plain') ||
			($entity->head->mime_type eq 'text/html')  
		  	) 
		    && 
		    ($is_att != 1)
		  ) {
			
			
			        
			my $body    = $entity->bodyhandle;
			my $content = $body->as_string;
			
			
			if($content){ # do I need this?
			
				my $switch = 1; 
				   $switch = 0 
						if	$self->treat_as_discussion_msg                       &&
							$self->{ls}->param('group_list')                == 1 && 
							$self->{ls}->param('allow_group_interpolation') != 1;
				
				if($switch){ 	
					   $content = $self->_parse_in_list_info(-data => $content, 
															 -type => $entity->head->mime_type, 
														    );
				
				}

				$content = $self->_apply_template(-data => $content, 
												  -type => $entity->head->mime_type, 
												);
												

			    if($DADA::Config::GIVE_PROPS_IN_EMAIL == 1){ 
                    $content = $self->_give_props(
                        -data => $content, 
					    -type => $entity->head->mime_type, 
                    );
                }
                
        

				
				
				$content = $self->_add_opener_image($content)
					if $self->{ls}->param('enable_open_msg_logging') == 1            && 
					   $entity->head->mime_type                      eq 'text/html';
						   
		       my $io = $body->open('w');
				  $io->print( $content );
				  $io->close;
				$entity->sync_headers('Length'      =>  'COMPUTE',
									  'Nonstandard' =>  'ERASE');
		
			}
		}
		return $entity; 
	}
	
	return $entity; 
}




sub _give_props { 

    my $self = shift;
    my %args = (-data => undef, -type => 'text/plain', @_); 

    if($DADA::Config::GIVE_PROPS_IN_EMAIL == 1){ 
    
    
    
        my $html_props = "\n" . '<p><a href="' . $DADA::Config::PROGRAM_URL . '/what_is_dada_mail/">Mailing List Powered by Dada Mail</a></p>' . "\n";
        my $text_props = "\n\nMailing List Powered by Dada Mail\n$DADA::Config::PROGRAM_URL/what_is_dada_mail/";
        
        
        $args{-type} = 'HTML'      if $args{-type} eq 'text/html';
        $args{-type} = 'PlainText' if $args{-type} eq 'text/plain';
           
        if($args{-type} eq 'HTML'){ 
           
            if($args{-data} =~ m{<!--/signature-->}){ 
                 $args{-data} =~ s{<!--/signature-->}{$html_props<!--/signature-->}i; 
           }
           elsif($args{-data} =~ m{</body>}){  
           
                $args{-data} =~ s{</body>}{$html_props</body>}i
           
           }
           else { 
            
                $args{-data} = $args{-data} . $html_props
            
            }
        } 
        else { 
        
            $args{-data} = $args{-data} .  $text_props;
        }

    }
    
    return $args{-data};

}




sub _add_opener_image { 

	my $self    = shift; 
	my $content = shift; 
	
	# body tags will now be on their own line, regardless.
	$content =~ s/(\<body.*?\>|<\/body\>)/\n$1\n/gi; 
	
	my $img_opener_code = '<!--open_img--><img src="' . $DADA::Config::PROGRAM_URL . '/spacer_image/[list_settings.list]/[message_id]/spacer.png" /><!--/open_img-->';

	$content =~ s/(\<body.*?\>)/$1\n$img_opener_code/i;
	
	return $content; 

}




=pod

=head2 _create_multipart_from_html

 $entity = $self->_create_multipart_from_html($entity); 


Recursively goes through a multipart entity, changing any non-attachment
singlepart HTML message into a multipart/alternative message with an 
auto-generated PlainText version. 

=cut


sub _create_multipart_from_html { 

	my $self   = shift; 
	my $entity = shift; 
	
	if(
	  ($entity->head->mime_type                         eq 'text/html' ) && 
	  ($entity->head->mime_attr('content-disposition') !~ m/attachment/)
	  ){ 	  		
			$entity = $self->_make_multipart($entity); 		   
	}
	elsif(
		   ($entity->head->mime_type                         eq 'multipart/mixed') && 
	       ($entity->head->mime_attr('content-disposition') !~ m/attachment/)){ 
      		
      		my @parts = $entity->parts(); 
      		my $i = 0; 
      		if(!@parts){ 
      			warn 'multipart/mixed with no parts?! Something is screwy....'; 
      		}else{ 
      			my $i; 
				foreach $i (0 .. $#parts) {
					if(
					  ($parts[$i]->head->mime_type eq 'text/html') &&
					  ($parts[$i]->head->mime_attr('content-disposition') !~ m/attachment/)) { 
							$parts[$i] = $self->_make_multipart($parts[$i]);
					}
				$entity->sync_headers('Length'      =>  'COMPUTE',
						  			  'Nonstandard' =>  'ERASE');
				}
      		}
	}
	
	$entity->sync_headers('Length'      =>  'COMPUTE',
						  'Nonstandard' =>  'ERASE');

	return $entity; 
}



=pod

=head2 _make_multipart

 $entity = $self->_make_multipart($entity); 	
 
Takes a single part entity and changes it to a multipart/alternative message, 
with an autogenerated PlainText version. 

=cut

sub _make_multipart { 

	my $self   = shift; 
	my $entity = shift; 
	
	# I wanted to do this, before we make it multipart: 
    my $orig_charset = $entity->head->mime_attr('content-type.charset'); 
   
	require MIME::Entity; 
		
	my $html_body    = $entity->bodyhandle;
	my $html_content = $html_body->as_string;

	$entity->make_multipart('alternative'); 
	
	my $plaintext_entity = MIME::Entity->build(
          Type    => 'text/plain', 
          Data    => $self->_create_plaintext_from_html($html_content),
   ); 
   $plaintext_entity->head->mime_attr(
          "content-type.charset" => $orig_charset,
   );
	
	$entity->add_part($plaintext_entity, 0); 

	return $entity; 
}



=pod

=head2 _create_plaintext_from_html

 my $PlainText_var = $self->_create_plaintext_from_html($HTML_Ver); 

 Given a B<string>, simple converts the HTML to PlainText

=cut

sub _create_plaintext_from_html { 

	my $self   = shift; 
	my $body   = shift; 
	#yay, we'll see...
	return convert_to_ascii($body); 
}




=pod

=head2 _format_headers 

 $entity = $self->_format_headers($entity)

Given an entity, will do some transformations on the headers. It will: 

=over

=item * Tack on the list name/list shortname on the Subject header for discussion lists

=item * Add the correct Reply-To header

=item * Remove any Message-ID headers

=item * Makes sure the To: header has a real name associated with it

=back

=cut

sub _format_headers { 

	my $self   = shift; 	 
	my $entity = shift; 
	
	
	require Email::Address; 
	
	if($self->{ls}->param('group_list') == 1){

#		if($self->{li}->{append_list_name_to_subject} == 1){  
#			if($self->{li}->{append_discussion_lists_with} eq "list_name"){ 
#				my $subject = $entity->head->get('Subject', 0);
#				$entity->head->replace('Subject', $self->_list_name_subject($self->{li}->{list_name}, $subject));
#			}else{ 
#				my $subject = $entity->head->get('Subject', 0);
#				$entity->head->replace('Subject', $self->_list_name_subject($self->{list}, $subject));			
#			}
#		}

		if($self->{ls}->param('append_list_name_to_subject') == 1){ 
			my $subject = $entity->head->get('Subject', 0);
			$entity->head->replace('Subject', $self->_list_name_subject($subject));
		}
		
		
	
				
		if($self->{ls}->param('add_reply_to') == 1){ 
			# DEV:  Does this have to be updated!?
			my $reply_to = Email::Address->new(
								$self->{ls}->param('list_name'), 
								$self->{ls}->param('discussion_pop_email')
							);
							
							
		   $entity->head->delete('Reply-To');
		   $entity->head->add('Reply-To', $reply_to);
		
		} else {
		
			my $original_sender = $entity->head->get('From', 0);
		   $entity->head->delete('Reply-To');
		   $entity->head->add('Reply-To', $original_sender); 
		}
		
		$entity->head->delete('Return-Path'); 

	}else{ 
	
	    if($self->reset_from_header){ 
	    	$entity->head->delete('From'); 
	    }
	}

	$entity->head->delete('Cc')
	    if $entity->head->count('Cc');
    $entity->head->delete('Bcc')
        if $entity->head->count('Bcc');
        
	
	
	$entity->head->delete('Message-ID'); 
	
	
	
	# If there ain't a TO: header, add one: 
	# (usually, this happens (or doesn't happen) in program
	
	$entity->head->add('To', $self->{ls}->param('list_owner_email'))
	 	if ! $entity->head->get('To', 0); 
	
	
	# If there's already a To: header, put a phrase in it, to make it look
	# nice...
	
	
	my $test_To = $entity->head->get('To', 0); 
	chomp($test_To); 
	$test_To = strip($test_To); 
	
	if($test_To =~ m{undisclosed\-recipients\:\;}i){ 
        warn "I'm SILENTLY IGNORING a, 'undisclosed-recipients:;' header!"; 
        
    } else { 
    
        my @addrs = Email::Address->parse($entity->head->get('To', 0));
        
        if($addrs[1]){ 
            # more than 1? What's going on?!
            # who knows. Leave it at that!

        }else{ 
            
            my $to_addy = $addrs[0];
            
            if(!$to_addy){ 
            
                warn "couldn't get a valid Email::Address object? SILENTLY (*wink wink*) ignorning"; 
            
            }elsif(!$to_addy->phrase){ 
            
                $to_addy->phrase($self->{ls}->param('list_name')); 
                $entity->head->delete('To');
                $entity->head->add('To', $to_addy->format); 
            
            }
        }
    }  
  
  
   if($self->{ls}->param('discussion_pop_email')){ 
         $entity->head->add('X-BeenThere', $self->{ls}->param('discussion_pop_email')); 
   } 
   
   
 	return $entity;
}




=pod

=head2 _list_name_subject

 my $subject = $self->_list_name_subject($list_name, $subject));

Appends, B<$list_name> onto subject. 


=cut

sub _list_name_subject { 

	# This is awful code, yuck!
	
	my $self         = shift;
	my $orig_subject = shift; 
	
	
	my $list       = $self->{ls}->param('list'); 
	my $list_name  = $self->{ls}->param('list_name'); 
	
	# This really needs to look for both list name and list short name... I'm thinking...
	$orig_subject   =~ s/\[($list|$list_name)\]//; # This only looks for list shortname...

	$orig_subject   =~ s/^((RE:|AW:)\s+)+//i; # AW (German!) 
	
	my $re      = $1;
	   $re      =~ s/^(\s+)//; 
	   $re      =~ s/(\s+)$//; 
	   $re      = ' ' . $re if $re; 
	   
	$orig_subject    =~ s/^(\s+)//;
	
	if($self->{ls}->param('append_list_name_to_subject') == 1){ 
					
		if($self->{ls}->param('append_discussion_lists_with') eq "list_name"){ 
			$orig_subject    = '[' . '<!-- tmpl_var list_settings.list_name -->' . ']' . "$re $orig_subject"; 		
		}
		elsif($self->{ls}->param('append_discussion_lists_with') eq "list_shortname"){ 
			$orig_subject    = '[' . '<!-- tmpl_var list_settings.list -->' . ']' . "$re $orig_subject"; 
		}
	}

	return $orig_subject; 

}




=pod

=head2 _parse_in_list_info

 $data = $self->_parse_in_list_info(-data => $data, 
                                    -type => (PlainText/HTML), 
                                   );
								        
Given a string, changes Dada Mail's pseudo tags into what they represent. 

B<-type> can be either PlainText or HTML

=cut

sub _parse_in_list_info { 

	my $self = shift; 
	
	my %args = (-data => undef, 
				-type => undef, 
					@_); 
 
 	die "no data! $!" if ! $args{-data}; 
 	
 	my $data = $args{-data}; 

 	   	   
#### Not completely happy with the below --v

    my $s_link   = $self->_macro_tags(-type => 'subscribe'  ); 
    my $us_link  = $self->_macro_tags(-type => 'unsubscribe'); 
     
### this is messy. 

	$data =~ s/\[plain_list_subscribe_link\]/$s_link/g;	
	$data =~ s/\[plain_list_unsubscribe_link\]/$us_link/g;

	
	$data =~ s/\[list_subscribe_link\]/$s_link/g;	
	$data =~ s/\[list_unsubscribe_link\]/$us_link/g;

	# confirmations.
	
    my $cs_link  = $self->_macro_tags(-type => 'confirm_subscribe'); 
    my $cus_link = $self->_macro_tags(-type => 'confirm_unsubscribe'); 

	$data =~ s/\[list_confirm_subscribe_link\]/$cs_link/g;	
	$data =~ s/\[list_confirm_unsubscribe_link\]/$cus_link/g;
	
	
# This is kinda out of place...
    if($self->originating_message_url){ 
        my $omu = $self->originating_message_url; 
        $data =~ s/\[originating_message_url\]/$omu/g;
    }
    
	return $data; 
	
}




=pod

=head2 _macro_tags

 my $s_link   = $self->_macro_tags(-type => 'subscribe'  ); 
 my $us_link  = $self->_macro_tags(-type => 'unsubscribe');

Explode the various B<link> pseudo tags into a form that will later be interpolated. 

B<-type> can be: 

=over

=item * subscribe

=item * unsubscribe

=item * confirm_subscribe

=item * confirm_unsubscribe

=back


=cut

sub _macro_tags { 

	my $self = shift; 
	

	my %args = (-url         => $DADA::Config::PROGRAM_URL, # Really.
				-email        => undef, 
				-pin          => undef, 
				-make_pin     => 0,
				-list         => $self->{list},
				-escape_list  => 1,
				-escape_all   => 0,
				@_
				); 
	
	my $type; 
	
	#if($self->use_header_info){ 
	#	require Mail::Address; 
	#	if(my $to_temp = (Mail::Address->parse($self->orig_entity()->head->get('To', 0)))[0]){ 
	#  		$args{-email} = $to_temp->address();
	#	}
	#
	#}
	
	if($args{-email} && $args{-make_pin} == 1){ 
		$args{-pin} = make_pin(-Email => $args{-email}); 
	}

	if($args{-type} eq 'subscribe'){ 
	
		$type = 's'; 
	
	}elsif($args{-type} eq 'unsubscribe'){ 
	
		$type = 'u'; 
	
	}elsif($args{-type} eq 'confirm_subscribe'){ 
	
		$type = 'n';
		$args{-email} ||= '[subscriber.email_name]@[subscriber.email_domain]';
		$args{-pin}   ||= '[subscriber.pin]';
	
	}elsif($args{-type} eq 'confirm_unsubscribe'){ 
		
		$type = 'u'; 
		$args{-email} ||= '[subscriber.email_name]@[subscriber.email_domain]';
		$args{-pin}   ||= '[subscriber.pin]';
	
	}
	
	my $link = $args{-url} . '/';
	
	if($args{-escape_all} == 1){ 
		foreach($args{-email}, $args{-pin}, $type, $args{-list}){ 
			$_ = uriescape($_);
		}
		
	}elsif($args{-escape_list} == 1){ 
		require URI::Escape;
		$args{-list} = URI::Escape::uri_escape($args{-list}, "\200-\377");
	}
	
	if($args{-email}){ 
	my $tmp_email = $args{-email};
	
	    $tmp_email =~ s/\@/\//g;	# snarky. Replace, "@" with, "/"
	    $tmp_email =~ s/\+/_p2Bp_/g;
	    
	    $args{-email} = $tmp_email; 
	}
	
	my @qs; 
	push(@qs,  $type)         if $type;   
	push(@qs,  '[list]')  if $args{-list};	
	push(@qs,  $args{-email}) if $args{-email};
	push(@qs,  $args{-pin})   if $args{-pin};
	
	$link .= join '/', @qs; 
	
	return $link . '/';
	
}




=pod

=head2 _apply_template

$content = $self->_apply_template(-data => $content, 
								  -type => $entity->head->mime_type, 
								 );

Given a string in B<-data>, applies the correct email mailing list template, 
depending on what B<-type> is passed, this will be either the PlainText or
HTML version.							 	

=cut

sub _apply_template {

	my $self = shift; 
	
	my %args = (-data                => undef, 
				-type                => undef, 
				@_,
				); 

	die "no data! $!" if ! $args{-data}; 
	die "no type! $!" if ! $args{-type}; 

 	# These are stupid.   
 	   $args{-type} = 'HTML'      if $args{-type} eq 'text/html';
 	   $args{-type} = 'PlainText' if $args{-type} eq 'text/plain';
 	   
	my $data = $args{-data}; 

	my $new_data; 
	my $template_out = 0; 
	
	  
	if($args{-type} eq 'PlainText'){ 
		$template_out = $self->use_plaintext_email_template;
	}elsif($args{-type} eq 'HTML'){   
		$template_out = $self->use_html_email_template;
	}
	
	if($template_out){ 
	
		if($args{-type} eq 'PlainText'){ 
			$new_data = strip($self->{ls}->param('mailing_list_message')) || '[message_body]';
		}else{ 
			$new_data = strip($self->{ls}->param('mailing_list_message_html')) || '[message_body]';
		}
		
		if($args{-type} eq 'HTML'){  
		
			my $bodycontent     = undef; 
			my $new_bodycontent = undef; 
		
			# code below replaces code above - any problems?
			# as long as the message dada is valid HTML...
			$data =~ m/\<body.*?\>([\s\S]*?)\<\/body\>/i;
			$bodycontent = $1; 
   
			if($bodycontent){ 
							
				$new_bodycontent = $bodycontent;
			
				$new_data =~ s/\[message_body\]/$new_bodycontent/;
				
				my $safe_bodycontent = quotemeta($bodycontent);
				
				$data     =~ s/$safe_bodycontent/$new_data/;			
				$new_data = $data; 
				
			}else{ 			
					$new_data =~ s/\[message_body\]/$data/g;
			}
			
		}else{ 
				$new_data =~ s/\[message_body\]/$data/g;	
		}
	}else{ 
	
		$new_data = $data; 
	}
	
	
	if($args{-type} eq 'HTML'){  

		$new_data = $self->_apply_list_template($new_data)
				if $self->use_list_template; 			
	}
	
	$new_data = $self->_parse_in_list_info(-data => $new_data, 
								          -type => $args{-type}, 
								        );
	
	#dude. If there ain't no body...
	if($args{-type} eq 'HTML'){  
		if($new_data !~ /\<body(.*?)\>/i){

			my $title = $self->Subject || 'Mailing List Message'; 

			$new_data = qq{ 
<html> 
<head>
<title>$title</title>
</head> 
<body> 
$new_data
</body> 
</html> 
			};
		}
	}
	# seriously...
	
	return $new_data; 
	
}

=pod

=head2 _apply_list_template

 $new_data = $self->_apply_list_template($new_data);

Given a string, will apply the List Template. The List Template is 
usually used for HTML screens that appear in your web browser. 

=cut

sub _apply_list_template { 

	my $self = shift; 
	
	require DADA::Template::HTML; 
	
	my $html      = shift; 
	my $new_html  = shift; 
	my $body_html = ''; 
	
	$html =~ s/(\<body.*?\>|<\/body\>)/\n$1\n/gi; 

	my @lines = split("\n", $html); 
		foreach (@lines){ 
			if(/\<body(.*?)\>/i .. /\<\/body\>/i)	{
				next if /\<body(.*?)\>/i || /\<\/body\>/i;
				$body_html .= $_ . "\n";
			}
		}

	$body_html ||= $html; 
			 
	$new_html = (DADA::Template::HTML::list_template(
					-Part         => "header",
					-Title        =>  $self->Subject,
					-List         => $self->{ls}->param('list'),
					-HTML_Header  => 0,
			     )) . 
									   
	 $body_html                     	          .       						   
			   
	 DADA::Template::HTML::list_template(-Part     => "footer",
			                       -List   => $self->{ls}->param('list'), 
			                       , 
			 );                   
			 
	return $new_html;
	
}

sub entity_from_dada_style_args { 

    my $self = shift; 
    my ($args) = @_; 

    if(! exists($args->{-fields})){ 
    
        croak 'did not pass data in, "-fields"' ;
    }
    
    


    if(!exists($args->{-parser_params})){ 
        $args->{-parser_params} = {};
    }
    elsif(!exists($args->{-parser_params}->{-input_mechanism})){ 
        $args->{-parser_params}->{-input_mechanism} = 'parse';
    }

    if($args->{-parser_params}->{-input_mechanism} eq 'parse_open'){ 
    
        
       my $filename = $self->file_from_dada_style_args(
                                        {
                                            -fields => $args->{-fields},
                                         }
                                      );
    
    
            return ($self->get_entity(
                            {
                                -data          => $filename,
                                -parser_params => {-input_mechanism => 'parse_open'},
                            }
                    ), $filename); 
    
    }
    else { 
    
    
        my $str = $self->string_from_dada_style_args(
                                        {
                                            -fields => $args->{-fields},
                                         }
                                      );
    
    
            return $self->get_entity(
                            {
                                -data => $str, 
                            }
                    ); 
                    

    }
}

sub string_from_dada_style_args { 

    my $self = shift; 
    my ($args) = @_; 

    my $str = ''; 
    
    if(! exists($args->{-fields})){ 
    
        croak 'did not pass data in, "-fields"' ;
    }
    
    foreach(keys %{$args->{-fields}}){
    #foreach (@DADA::Config::EMAIL_HEADERS_ORDER) {
	# You want the above because of tricky headers like Content-Type (or Content-type - you see?)
        next if $_ eq 'Body';
        next if $_ eq 'Message';    # Do I need this?!
        $str .= $_ . ': ' . $args->{-fields}->{$_} . "\n"
        if ( ( defined $args->{-fields}->{$_} ) && ( $args->{-fields}->{$_} ne "" ) );
    }
    
    $str .= "\n" . $args->{-fields}->{Body};
    
    return $str;

    
}




sub file_from_dada_style_args { 

    my $self = shift; 
    my ($args) = @_; 

    my $str = ''; 
    
    require DADA::Security::Password; 
    
    my $filename = $DADA::Config::TMP . '/' . 'tmp_msg_ ' . time . '_' . DADA::Security::Password::generate_rand_string(); 
       $filename = make_safer($filename); 
    
    open my $MAIL, '>', $filename or croak $!; 
    
    if(! exists($args->{-fields})){ 
        croak 'did not pass data in, "-fields"' ;
    }
    
    foreach(keys %{$args->{-fields}}){
#    foreach (@DADA::Config::EMAIL_HEADERS_ORDER) {
        next if $_ eq 'Body';
        next if $_ eq 'Message';    # Do I need this?!
        print $MAIL $_ . ': ' . $args->{-fields}->{$_} . "\n"
        if ( ( defined $args->{-fields}->{$_} ) && ( $args->{-fields}->{$_} ne "" ) );
    }
    
    print $MAIL "\n" . $args->{-fields}->{Body};
    close $MAIL or croak $!; 
    
    return $filename; 
    
}




=pod

=head1 get_entity

C<get_entity> is a simple subroutine that takes a string, passed in, C<-data> and turns it into a 
B<HTML::Entities> entity: 

 my $entity = get_entity(
                  {
                      -data => $str, 
                  }
              ); 

Optionally, you may also pass the C<-parser_params> paramater, which will direct the parser on how
specifically to parse the message. Currently, there is only one param to play around with: 
C<-input_mechanism> - you can set this to either, B<parse> (which is the default), or B<parse_open>. 

If you pass, B<parse_open>, also pass a filename in B<-data> instead of a string. Right. 

my $entity = get_entity(
                  {
                      -data => $filename, 
                  }
              ); 

Make sure to delete the file when you're finished. 


=cut


sub get_entity { 
    
    my $self = shift; 
    my ($args) = @_; 
    
    if(! exists($args->{-data})){ 
        croak 'did not pass data in, "-data"' ;
    }
    
    my $entity;
	# $self->{parser}->extract_nested_messages(0);
    
    if(!exists($args->{-parser_params})){ 
        $args->{-parser_params} = {};
    }
    elsif(!exists($args->{-parser_params}->{-input_mechanism})){ 
        $args->{-parser_params}->{-input_mechanism} = 'parse';
    }
    
	if(!exists($args->{-parser_params}->{-input_mechanism})){ 
		$args->{-parser_params}->{-input_mechanism} = 'parse_data';
	}
    if($args->{-parser_params}->{-input_mechanism} eq 'parse_open'){ 
        eval { $entity = $self->{parser}->parse_open($args->{-data}) };        
    }
    else { 
        eval { $entity = $self->{parser}->parse_data($args->{-data}) };
    }
	
	if($@){ 
	   carp "Problems making an entity: $@";	    
	}
	
	if(!$entity){
	    carp "No entity made! Gah! "; 
	}
	
	return $entity; 
    
}



=pod

=head1 email_template

This subroutine is extremely similar to B<DADA::Template::Widgets> C<screen> subroutine and in fact 
is basically a wrapper around it, although it also "knows" about Email Message headers and attempts
not to muck them up when you place variables in the template. 

It basically looks at the various parts of your email message and passes these parts to 
B<DADA::Template::Widgets> C<screen> subroutine to be templated out.

The parts of the email message that will be templated out are any and all B<text/plain>, B<text/html> 
bodies - both of which have an B<inline> content disposition (ie: it's not an attachment) 
and the B<To>, B<From> and B<Subject> headers of a message. 

For the B<To> and B<From> headers, this subroutine will only attempt to template out the B<phrase>
part of the header and will make sure that the phrase is properly escaped out. 

One main difference between this subroutine and C<screen> is that this subroutine does not take the
template to work with in the C<-data>, or, C<-screen> paramater, but instead takes it in the, C<-entity>
paramater. The C<-entity> paramater should be populated like so: 

 use MIME::Parser;
 my $parser = new MIME::Parser; 
 my $entity = $parser->parse_data($msg);
 
 DADA::App::FormatMessages::email_template({-entity => $entity});

( Probably should elaborate...) 

The subroutine also passes the C<-dada_pseudo_tag_filter> (set to 1) automatically to C<screen>.

=cut



sub email_template { 
	
	# Tests and documentation
	# OK, MORE documentation
	#
	#
	# OK - Headers don't work, if there's a multipart/alternative message (or, a message with an attachment, etc) 
	
	my $self   = shift; 
	
	my ($args) = @_;
	
	require DADA::Template::Widgets; 
    
    if(! exists($args->{-entity})){ 
	    croak 'did not pass an entity in, "-entity"!'; 
	}
 
	my @parts  = $args->{-entity}->parts; 
	

	if(@parts){
	    
		my $i; 
		foreach $i (0 .. $#parts) {
			$parts[$i]= $self->email_template({%{$args}, -entity => $parts[$i] });	# -entity should only pass the current part, but have the rest of the params passed...?
		}
		

		
		
		
		
		 $args->{-entity}->sync_headers('Length'      =>  'COMPUTE',
							            'Nonstandard' =>  'ERASE');
	    
	}else{ 	
	
		my $is_att = 0; 
		if (defined($args->{-entity}->head->mime_attr('content-disposition'))) { 
		    if ($args->{-entity}->head->mime_attr('content-disposition') =~ m/attachment/){
	        	$is_att = 1; 
		    }
		}
			
		if(
		    (
		    ($args->{-entity}->head->mime_type eq 'text/plain') ||
			($args->{-entity}->head->mime_type eq 'text/html')
		  	) 
		    && 
		    ($is_att != 1)
		  ) {

###			
            # ?!
            my %screen_vars = (); 
            foreach(keys %{$args}){ 
                next if $_ eq '-entity';
                $screen_vars{$_} = $args->{$_}; 
            }
            $screen_vars{-dada_pseudo_tag_filter} = 1; 
###/
	
			if(
			    (
			    ($args->{-entity}->head->mime_type eq 'text/plain') ||
				($args->{-entity}->head->mime_type eq 'text/html')
				)
			){ 
				
				
				my $body    = $args->{-entity}->bodyhandle;
				my $content = $body->as_string;

				if($content){
			
				    # And, that's it. 
	                $content = DADA::Template::Widgets::screen(
	                    {
	                                %screen_vars,
	                                -data                   => \$content, 
									(
										($args->{-entity}->head->mime_type eq 'text/html') ? 
										(
											-webify_these => [qw(list_settings.info list_settings.privacy_policy list_settings.physical_address)], 
								        ) 
										: ()
									),

	                    }
	                ); 

			       my $io = $body->open('w');
					  $io->print( $content );
					  $io->close;
				}
		    
				$args->{-entity}->sync_headers('Length'      =>  'COMPUTE',
					  				           'Nonstandard' =>  'ERASE');
			}
		}
		
	#	return $args->{-entity}; 
	}
	
	
	
	###/ 
	# Headers...
	
    # ?!
    my %screen_vars = (); 
    foreach(keys %{$args}){ 
        next if $_ eq '-entity';
        $screen_vars{$_} = $args->{$_}; 
    }
    $screen_vars{-dada_pseudo_tag_filter} = 1; 
    
	foreach my $header(qw(Subject From To Reply-To  Errors-To Return-Path)){ 
		
		
	    if($args->{-entity}->head->get($header, 0)){ 
			
            if($header =~ m/From|To|Reply\-To|Return\-Path|Errors\-To/){ 
                #Special Case - only format the phrase. 
                require Email::Address; 
                my @addresses = Email::Address->parse($args->{-entity}->head->get($header, 0));
                if($addresses[0]){
			        my $phrase = $addresses[0]->phrase; 
					   $phrase = DADA::Template::Widgets::screen(
                        {
                            %screen_vars,
                            -data => \$phrase, 

                        }
                    ); 

                    # Munge! 
                    $phrase =~ s{^\"|\"$}{}g;
				    $addresses[0]->phrase($phrase); 
                    
                    
                    my $new_header = $addresses[0]->format; 
                    
                    $args->{-entity}->head->delete($header);
                    $args->{-entity}->head->add($header, $new_header); 
                
                }
                else { 
                    #warn "couldn't find the first address?"; 
                }
            
            } 
            else { 
	    
                my $header_value = $args->{-entity}->head->get($header, 0);
                    
               $args->{-entity}->head->delete($header);
           
           
                $header_value = DADA::Template::Widgets::screen(
                    {
                       %screen_vars,
                        -data                   => \$header_value, 
                    }
                ); 
                
                $args->{-entity}->head->add($header, $header_value); 
            }                
        }
	}        
	
	
		
	###/
	
	return $args->{-entity}; 
}



sub DESTROY {

	my $self = shift; 
	$self->{parser}->filer->purge;
}




sub pre_process_msg_strings { 
	
	my $text_ver = shift || undef; 
	my $html_ver = shift || undef; 
	
	
	if($text_ver){ 
	    $text_ver =~ s/\r\n/\n/g;
	}   

	if($html_ver){ 
   		$html_ver    =~ s/\r\n/\n/g;
	}               

	if(defined($html_ver)){ 
		$html_ver         =~ s/^\n+//o; 
		my $orig_html_ver = $html_ver; 
		
		# DEV: Hmm. Make sure my indenting doesn't break this... 
		my $fckeditor_blank = strip(q{<html dir="ltr">
	    <head>
	        <title></title>
	    </head>
	    <body>
	        <p>&nbsp;</p>
	    </body>
	</html>});

		if($html_ver =~ m/$fckeditor_blank/){ 
			undef $html_ver; 
		}
		else { 		

			$html_ver =~ s/(^\n<br \/>|^<br \/>|^<br \/>\n)//;
			$html_ver = convert_to_ascii($html_ver); # what? what did I miss?
			$html_ver = strip($html_ver); 
			$html_ver =~ s/^\n+|\n+$//o;

		}
		if(length($html_ver) <= 1){ 
			$html_ver = undef; 
		}else{ 
			$html_ver = $orig_html_ver;
			undef $orig_html_ver; 
		}
	}

	if(! defined $html_ver && ! defined $text_ver) { 
		# Got no text kludge...
		#
		# Why. Why why why?!
		#$text_ver = "\n" 
	}
	
	return($text_ver, $html_ver); 
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


