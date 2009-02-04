#!/usr/bin/perl
use strict;
$ENV{PATH} = "/bin:/usr/bin"; 
delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};

#---------------------------------------------------------------------#
# Dada Bridge
# For instructions, see the pod of this file. try:
#  pod2text ./dada_bridge.pl | less
#
# Or try online: 
#  http://dadamailproject.com/support/documentation/dada_bridge.pl.html
#
#---------------------------------------------------------------------#
# REQUIRED:
# 
# It is only required that you read the documentation. All variables
# that are set here are *optional*
#---------------------------------------------------------------------#


use lib qw(../ ../DADA/perllib ../../../../perl ../../../../perllib); 


use CGI::Carp qw(fatalsToBrowser);
use DADA::Config 3.0.0;

use CGI; CGI->nph(1) if $DADA::Config::NPH == 1; my $q = new CGI; $q->charset($DADA::Config::HTML_CHARSET);

use Fcntl qw(
    O_CREAT 
    O_RDWR
    LOCK_EX
    LOCK_NB
); 

my $Plugin_Config = {}; 

# Usually, this doesn't need to be changed. 
# But, if you are having trouble saving settings 
# and are redirected to an 
# outside page, you may need to set this manually. 
$Plugin_Config->{Plugin_URL} = $q->url; 


# Can the checking of awaiting messages to send out happen by invoking this 
# script from a URL? (CGI mode?) 
# The URL would look like this: 
#
# http://example.com/cgi-bin/dada/plugins/dada_bridge.pl?run=1

$Plugin_Config->{Allow_Manual_Run}    = 1; 

# Set a passcode that you'll have to also pass to invoke this script as 
# explained above in, "$Plugin_Config->{Allow_Manual_Run}"

$Plugin_Config->{Manual_Run_Passcode} = '';


# How many messages does Dada Mail look at, at once? 
#
$Plugin_Config->{MessagesAtOnce} = 1;


# Is there a limit on how large a single email message can be, until we outright # reject it? 
# In, "octects" (bytes) - this is about 2.5 megs...
#
$Plugin_Config->{Max_Size_Of_Any_Message} = 2621440;


$Plugin_Config->{Plugin_Name} = 'Dada Bridge'; 


# This is a super super secret, undocumented feature. Why the secrecy? 'cause 
# we snuck this new feature in a bug-fix only release and this feature hasn't
# Properly tested. So - big flashing warning. 
# 
# What is this feature? If you set the below variable, "$Plugin_Config->{Allow_Open_Discussion_List}" 
# to, "1", you will be able to have an discussion list that anyone can email a message 
# to. Why would you want this? I don't know, since the original poster won't be able 
# to receive or reply to the postings, but hey, you may have an interesting use, so 
# here it is. 
# Last caveat: This feature may disappear later in the program's releases (or at 
# least, change drastically)
# If that doesn't scare you and you need the feature, set this variable to, "1". 
# You'll have a new option under the Discussion List options to have a
# discussion list, open for anyone to post. 

$Plugin_Config->{Allow_Open_Discussion_List} = 0; 


# Another Undocumented feature - Room for one more? 
# When set to, "1" we look to see how many mailouts there are, 
# And if its above or at the limit, we don't attempt to check 
# any Dada Bridge list emails for awaiting messages. 
# Sounds like a good idea, right? Well, the check has a bug in it, and this
# This is a kludge

$Plugin_Config->{Room_For_One_More_Check} = 1; 

# Another Undocumented Feature - Enable Pop3 File Locking?
# Sometimes, the file lock for the POP3 server doesn't work correctly
# and you get a stale lock. Setting this config variable to, "0"
# will disable this plugin's own lock file scheme. Should be fairly safe to use. 

$Plugin_Config->{Enable_POP3_File_Locking} = 1; 


$Plugin_Config->{Check_List_Owner_Return_Path_Header} = 1; 

# Gmail seems to have problems with this...
$Plugin_Config->{Check_Multiple_Return_Path_Headers}  = 0;

# This is the message sent to the List Owner, 
# telling them a message is waiting for their
# Approval! Yeah!

my $Moderation_Msg_Subject = 'Message on: [list_settings.list_name] needs to be moderated. (original message attached)';
my $Moderation_Msg = <<EOF

The attached message needs to be moderated:

    List:    [list_settings.list_name]
    From:    [subscriber.email]
    Subject: [message_subject]

To send this message to the list, click here: 

    <[moderation_confirmation_link]>
    
To deny sending this message to the list, click here: 

    <[moderation_deny_link]>

-- [Plugin_Name]

EOF
; 

my $Rejection_Message_Subject = 'Message to: [list_settings.list_name] Subject: [message_subject] rejected.'; 
my $Rejection_Message = <<EOF

Hello, 

Your recent message to [list_settings.list_name] with the subject of: 

    [message_subject]
    
was rejected by the list owner. You may email the list owner at: 

    [list_settings.list_owner_email]
    
for more details. 

-- [Plugin_Name]

EOF
; 



#
# There is nothing else to configure in this program. 
#---------------------------------------------------------------------#




#---------------------------------------------------------------------#

$ENV{PATH} = "/bin:/usr/bin"; 
delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};

my $App_Version = '0.0';


$DADA::Config::LIST_SETUP_DEFAULTS{open_discussion_list} = 0; 

# Phowaa - let's import *a few* things
use DADA::Template::HTML;
use DADA::App::Guts; 
use DADA::Mail::Send; 
use DADA::MailingList::Subscribers; 
use DADA::MailingList::Settings; 
use DADA::Security::Password;  
use DADA::App::POP3Tools; 
use Email::Address;
use Digest::MD5 qw(md5_hex);
use MIME::Parser;
use MIME::Entity; 
use Getopt::Long; 

# This is for the reusable DBI handle...
my $dbi_handle; 
if(
	$DADA::Config::SUBSCRIBER_DB_TYPE =~ m/SQL/ || 
	$DADA::Config::ARCHIVE_DB_TYPE    =~ m/SQL/ || 
	$DADA::Config::SETTINGS_DB_TYPE   =~ m/SQL/ ||
	$DADA::Config::SESSION_DB_TYPE    =~ m/SQL/ 	
){        
    require DADA::App::DBIHandle; 
    $dbi_handle = DADA::App::DBIHandle->new; 
}

$DADA::MailingList::Subscribers::dbi_obj = $dbi_handle;
$DADA::MailingList::Settings::dbi_obj    = $dbi_handle;
#$DADA::Mail::Send::dbi_obj               = $dbi_handle;


my %Global_Template_Options = (
		#debug              => 1, 		
		path                => [$DADA::Config::TEMPLATES],
		die_on_bad_params   => 0,	

		(
            ($DADA::Config::CPAN_DEBUG_SETTINGS{HTML_TEMPLATE} == 1) ? 
                (debug => 1, ) :
                ()
        ), 
        
        
);


my $parser = new MIME::Parser; 
   $parser = optimize_mime_parser($parser); 


	 
my $test; 

my $help;
my $verbose = 0;
my $debug   = 0; # not used? 
my $list;
my $run_list; 
my $check_deletions = 0; 

my $root_login = 0; 

my $checksums = {}; 

GetOptions("help"            => \$help, 
		   "test=s"          => \$test,
		   "verbose"         => \$verbose,
		   "list=s"          => \$run_list, 
		   "check_deletions" => \$check_deletions, 
		   );


&init_vars; 

main();



sub init_vars { 

    # DEV: This NEEDS to be in its own module - perhaps DADA::App::PluginHelper or something?

     while ( my $key = each %$Plugin_Config ) {
        
        if(exists($DADA::Config::PLUGIN_CONFIGS->{'Dada_Bridge'}->{$key})){ 
        
            if(defined($DADA::Config::PLUGIN_CONFIGS->{'Dada_Bridge'}->{$key})){ 
                    
                $Plugin_Config->{$key} = $DADA::Config::PLUGIN_CONFIGS->{'Dada_Bridge'}->{$key};
        
            }
        }
     }
}


sub main { 
	if(!$ENV{GATEWAY_INTERFACE}){ 
		&cl_main(); 
	}else{ 
		&cgi_main(); 
	}
}


sub cgi_main {

    if(keys %{$q->Vars}                         && 
       $q->param('run')                         && 
       xss_filter($q->param('run'))        == 1 &&
       $Plugin_Config->{Allow_Manual_Run}  == 1
      ) { 
        cgi_manual_start();
    } else { 
	
        my $admin_list; 
        
        ($admin_list, $root_login) = check_list_security(-cgi_obj    => $q,  
                                                         -Function   => 'dada_bridge',
                                                         -dbi_handle => $dbi_handle,
                                                        );
                                                                                                                
        $list  = $admin_list; 
        
        my $ls = DADA::MailingList::Settings->new({-list => $list}); 
        my $li = $ls->get(); 
                                                                  
        my $flavor = $q->param('flavor') || 'cgi_default';
        
        my %Mode = ( 
        'cgi_default'             => \&cgi_default, 
        'cgi_show_plugin_config'  => \&cgi_show_plugin_config,
        'test_pop3'               => \&cgi_test_pop3,
        'manual_start'            => \&admin_cgi_manual_start, 
        'mod'                     => \&cgi_mod, 
        ); 
        
        if(exists($Mode{$flavor})) { 
            $Mode{$flavor}->();  #call the correct subroutine 
        }else{
            &cgi_default;
        }
    }
}




sub cgi_manual_start { 
        
        if(
            (xss_filter($q->param('passcode')) eq $Plugin_Config->{Manual_Run_Passcode}) ||             
            ($Plugin_Config->{Manual_Run_Passcode} eq '')
            
          ) {
            
            print $q->header(); 
            
            if(defined(xss_filter($q->param('verbose')))){
                $verbose = xss_filter($q->param('verbose'));
            }
            else { 
                $verbose = 1;
            }
            
            
            $check_deletions = 1; 
            
            if(xss_filter($q->param(xss_filter('list')))){ 
            	$run_list        = xss_filter($q->param('list'));
            }

            print '<pre>'
                if $verbose; 
            start();
            print '</pre>'
                if $verbose; 
        }
        else { 
            print $q->header(); 
            print "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Authorization Denied.";
        }
}






sub cgi_test_pop3 { 

	print(admin_template_header(-Title      => "POP3 Login Test",
		                    -List       => $list,
		                    -Form       => 0,
		                    -Root_Login => $root_login
		                    ));
		                    
	$run_list = $list;
	$verbose  = 1; 
	print '<pre>';
	test_pop3();
	print '</pre>';
	print '<p><a href="' . $Plugin_Config->{Plugin_URL} . ' ">Back...</a></p>';
	
	print admin_template_footer(-Form    => 0, 
							-List    => $list,
						    );

}




sub admin_cgi_manual_start { 

	print(admin_template_header(
							-Title      => "Manually Running Mailing...",
		                    -List       => $list,
		                    -Form       => 0,
		                    -Root_Login => $root_login
		                    ));
		                    
	$run_list        = $list;
	$verbose         = 1; 
	$check_deletions = 1; 


  print '
     <p id="breadcrumbs">
        <a href="'  .  $Plugin_Config->{Plugin_URL} . '">
            ' . $Plugin_Config->{Plugin_Name} .'
        </a> &#187; Manually Running Mailing</p>'; 
        
        
        
        print '<pre>';
	start();
	print '</pre>';
	print '<p><a href="#" onclick="history.back();return false;">Back...</a></p>';
	 
	print admin_template_footer(-Form    => 0, 
							-List    => $list,
						    ); 

}




sub cgi_mod { 

    print(admin_template_header(
							-Title      => "Moderation",
		                    -List       => $list,
		                    -Form       => 0,
		                    -Root_Login => $root_login
		                    ));
	
	
	# $list is global, for some reason...
	if($list ne $q->param('list')){ 
	    print $q->header(); 
	    print "<p>Gah. You're either logged into a different list, or not logged in at all!</p>"; 
	}
										            
    my $ls = DADA::MailingList::Settings->new({-list => $list}); 
	my $li = $ls->get(); 
	
    my $mod = SimpleModeration->new({-List => $list}); 
	my $msg_id = $q->param('msg_id');     

    my $valid_msg = $mod->is_moderated_msg($msg_id); 

    if($valid_msg == 1){ 
        print "<p>Message appears to be valid and exists</p>"; 
        
    if($q->param('process') eq 'confirm'){ 
        process($list, $li, $mod->get_msg({-msg_id => $msg_id})); 
        $mod->remove_msg({-msg_id => $msg_id}); 
        print "<p>Message has been sent!</p>";
    } 
    elsif($q->param('process') eq 'deny'){ 

     
        print "<p>Message has been denied and being removed!</p>"; 
        if($li->{send_moderation_rejection_msg} == 1){ 
            print "<p>Sending rejection message!</p>"; 
            $mod->send_reject_msg({-msg_id => $msg_id, -parser => $parser, -subject => 'Fix Me'}); 

        }
        
        #gotta do this, after, since removing it will not make the send rejection message thing to work. 
        
        $mod->remove_msg({-msg_id => $msg_id}); 
           
           
    }
    else{ 
        print "<p>Invalid action - wazzah?</p>";
    }
    
    
    } else {
        print "<p>Moderated message doesn't exist - have you already moderated it?</p>"; 
    }
    
    
    

    print admin_template_footer(-Form    => 0, 
                            -List    => $list,
                            ); 

}







sub validate_list_email { 
	
	my $email  = shift; 
	   $email = DADA::App::Guts::strip($email); 
	my $valid = 1; 
	
	my @lists = DADA::App::Guts::available_lists; 
	foreach my $this_list(@lists){ 
		
		my $this_ls = DADA::MailingList::Settings->new({-list => $this_list}); 
		my $this_li = $this_ls->get; 
		
		if($this_li->{list_owner_email} eq $email ){ 
			$valid = 0; 
		}
		elsif($this_li->{admin_email} eq $email ){ 
			$valid = 0; 
		}
		
		next if $this_list eq $list; 
		
		if($this_li->{discussion_pop_email} eq $email ){ 
			$valid = 0; 
		}		
	} 
	
	return $valid; 
}

 
sub cgi_default { 

	
	my $ls = DADA::MailingList::Settings->new({-list => $list}); 
	my $li = $ls->get(); 
	my $list_email_validation = 1; 
	$q->param('saved', 0); 
	
	if($q->param('process') eq 'edit') { 
		
		# Vaidation, basically. 
		$list_email_validation = validate_list_email($q->param('discussion_pop_email')); 
		
		my $p = {}; 
		   $p->{disable_discussion_sending}                 = $q->param('disable_discussion_sending')                 || 0; 
		   $p->{group_list}                                 = $q->param('group_list')                                 || 0; 
		   $p->{append_list_name_to_subject}                = $q->param('append_list_name_to_subject')                || 0; 
		   $p->{no_append_list_name_to_subject_in_archives} = $q->param('no_append_list_name_to_subject_in_archives') || 0; 
		   $p->{add_reply_to}                               = $q->param('add_reply_to')                               || 0; 
	       $p->{discussion_pop_email}                       = $q->param('discussion_pop_email')                       || undef;
		   $p->{discussion_pop_server}                      = $q->param('discussion_pop_server')                      || undef;
		   $p->{discussion_pop_username}                    = $q->param('discussion_pop_username')                    || undef;
		   $p->{discussion_pop_password}                    = $q->param('discussion_pop_password')                    || undef;
		   $p->{discussion_pop_auth_mode}                   = $q->param('discussion_pop_auth_mode')                   || undef;
		   $p->{append_discussion_lists_with}               = $q->param('append_discussion_lists_with')               || '';
		   $p->{enable_moderation}                          = $q->param('enable_moderation')                          || 0; 
		   $p->{send_moderation_rejection_msg}              = $q->param('send_moderation_rejection_msg')              || 0; 
		   $p->{enable_authorized_sending}                  = $q->param('enable_authorized_sending')                  || 0; 
		   $p->{send_msgs_to_list}                          = $q->param('send_msgs_to_list')                          || 0; 
		   $p->{send_msg_copy_to}                           = $q->param('send_msg_copy_to')                           || 0; 
		   $p->{send_msg_copy_address}                      = $q->param('send_msg_copy_address')                      || ''; 
		   $p->{send_not_allowed_to_post_msg}               = $q->param('send_not_allowed_to_post_msg')               || 0; 
		   $p->{send_invalid_msgs_to_owner}                 = $q->param('send_invalid_msgs_to_owner')                 || 0; 
		   $p->{mail_discussion_message_to_poster}          = $q->param('mail_discussion_message_to_poster')          || 0; 
		   $p->{strip_file_attachments}                     = $q->param('strip_file_attachments')                     || 0; 
		   $p->{file_attachments_to_strip}                  = $q->param('file_attachments_to_strip')                  || '';
		   $p->{ignore_spam_messages}                       = $q->param('ignore_spam_messages')                       || 0; 
		   $p->{ignore_spam_messages_with_status_of}        = $q->param('ignore_spam_messages_with_status_of')        || 0; 
		   $p->{set_to_header_to_list_address}              = $q->param('set_to_header_to_list_address')              || 0; 
		   $p->{find_spam_assassin_score_by}                = $q->param('find_spam_assassin_score_by')                || undef; 
		   $p->{open_discussion_list}                       = $q->param('open_discussion_list')                       || 0; 
		   $p->{rewrite_anounce_from_header}                = $q->param('rewrite_anounce_from_header')                || 0; 
		   $p->{discussion_pop_use_ssl}                     = $q->param('discussion_pop_use_ssl')                     || 0; 	
	
		   $p->{open_discussion_list}    =  ($Plugin_Config->{Allow_Open_Discussion_List} == 1) ? $p->{open_discussion_list}  : 0;
		   $p->{discussion_pop_password} =  DADA::Security::Password::cipher_encrypt($li->{cipher_key}, $p->{discussion_pop_password});			
    
		
		if($list_email_validation == 1){ 
		
			$ls->save($p); 
			
			print $q->redirect(-uri => $Plugin_Config->{Plugin_URL} . '?saved=1'); 	
			return; 
		}
		else { 
			
			# rewind
			# DEV: Beats me why there's these two that need to be explicitly named, 
			# but the others, aren't:
			$p->{open_discussion_list}                       = $q->param('open_discussion_list')                       || 0; 
			$p->{discussion_pop_password}                    = $q->param('discussion_pop_password')                    || undef;
			
			foreach(keys %$p){ 
				$li->{$_} = $p->{$_};
			}
			
			$q->param('saved', 0); 
			
		}
	}

	my $lh = DADA::MailingList::Subscribers->new({-list => $list}); 
	my $auth_senders_count = $lh->num_subscribers(-Type => 'authorized_senders');
	my $show_authorized_senders_table = 1; 
	my $authorized_senders = []; 
	
	if($auth_senders_count > 100 || $auth_senders_count == 0){ 
		$show_authorized_senders_table = 0; 
	}
	else { 
		$authorized_senders           = $lh->subscription_list(-Type => 'authorized_senders')
	}
    
	print(admin_template_header(
		                    -Title      => "Discussion List Options",
		                    -List       => $list,
		                    -Form       => 0,
		                    -Root_Login => $root_login,
		                    -li         => $li, 
		                    
		                    
		                    ));
		                    
	
	my $can_use_set_to_header_to_list_address = 1; 
	# BUG: 
	# [ 2132872 ] 3.0.0 - header of discussion list to list address error?
	# http://sourceforge.net/tracker/index.php?func=detail&aid=2132872&group_id=13002&atid=113002
	# if($li->{send_via_smtp} == 1){ 
	#    $can_use_set_to_header_to_list_address = 0;
	# }
	# I'm guessing, as there's code for both the both the sendmail command
	# and SMTP, that both ways work, so there's no need to check...
	
	my $can_use_ssl = 0;
     eval { require IO::Socket::SSL };
    if(!$@){ 
        $can_use_ssl = 1;
    }
    
	my $discussion_pop_auth_mode_popup =  $q->popup_menu(
										      		-name     => 'discussion_pop_auth_mode', 
                                                    -default  => $li->{discussion_pop_auth_mode}, 
                                                   '-values'  => [qw(BEST PASS APOP CRAM-MD5)],
                                                    -labels   => {BEST => 'Automatic'},
                                           );
	my $spam_level_popup_menu = $q->popup_menu(
	'-values' => [1..50],
	-default => $li->{ignore_spam_messages_with_status_of},
	-name    => 'ignore_spam_messages_with_status_of',
	); 

	my $curl_location = `which curl`; 
	   $curl_location = strip(make_safer($curl_location));
	
	my $tmpl = default_cgi_template(); 	
	
	require DADA::Template::Widgets;                 
	print   DADA::Template::Widgets::screen(
		   		{ 
					-expr => 1, 
					-data => \$tmpl,
					-vars => { 
					
					authorized_senders                     => $authorized_senders, 
					show_authorized_senders_table           => $show_authorized_senders_table, 
					
				     list_email_validation             => $list_email_validation, 
					 #GOOD_JOB_MESSAGE                  => $DADA::Config::GOOD_JOB_MESSAGE, 
					 list     				           => $list,
					 list_name                         => $li->{list_name}, 
					 disable_discussion_sending        => $li->{disable_discussion_sending}, 
					 group_list                        => $li->{group_list},
					 append_list_name_to_subject       => $li->{append_list_name_to_subject},
					 add_reply_to                      => $li->{add_reply_to},
					 discussion_pop_email              => $li->{discussion_pop_email},
					 discussion_pop_server             => $li->{discussion_pop_server},
					 discussion_pop_username           => $li->{discussion_pop_username},
					 discussion_pop_password           => DADA::Security::Password::cipher_decrypt($li->{cipher_key}, $li->{discussion_pop_password}),
					
					discussion_pop_auth_mode           => $li->{discussion_pop_auth_mode}, 
					discussion_pop_auth_mode_popup     => $discussion_pop_auth_mode_popup, 
					discussion_pop_use_ssl             => $li->{discussion_pop_use_ssl}, 
					can_use_ssl                        => $can_use_ssl,
					
					 append_discussion_lists_with      => $li->{append_discussion_lists_with},
					 
					 no_append_list_name_to_subject_in_archives => $li->{no_append_list_name_to_subject_in_archives}, 
					 
					 list_owner_email                  => $li->{list_owner_email}, 
					 admin_email                       => $li->{admin_email}, 	
					 enable_moderation                 => $li->{enable_moderation}, 
					 send_moderation_rejection_msg     => $li->{send_moderation_rejection_msg}, 
					 
					 enable_authorized_sending         => $li->{enable_authorized_sending}, 
					 
					 send_msgs_to_list                 => $li->{send_msgs_to_list},  
					 send_msg_copy_to                  => $li->{send_msg_copy_to}, 
					 send_msg_copy_address             => $li->{send_msg_copy_address}, 
					 send_not_allowed_to_post_msg      => $li->{send_not_allowed_to_post_msg}, 
					 send_invalid_msgs_to_owner        => $li->{send_invalid_msgs_to_owner},
					 mail_discussion_message_to_poster => $li->{mail_discussion_message_to_poster}, 
					 PROGRAM_URL                       => $DADA::Config::PROGRAM_URL, 
					 archive_messages                  => $li->{archive_messages}, 
					 
					 strip_file_attachments            => $li->{strip_file_attachments}, 
					 file_attachments_to_strip         => $li->{file_attachments_to_strip}, 
					 
					 can_use_spam_assassin             => &can_use_spam_assassin(), 
					 spam_level_popup_menu             => $spam_level_popup_menu, 
					 
					 ignore_spam_messages              => $li->{ignore_spam_messages}, 
					 ignore_spam_messages_with_status_of => $li->{ignore_spam_messages_with_status_of}, 
					 
					 find_spam_assassin_score_by_calling_spamassassin_directly         => ($li->{find_spam_assassin_score_by} eq 'calling_spamassassin_directly') ? 1 : 0, 
					 find_spam_assassin_score_by_looking_for_embedded_headers          => ($li->{find_spam_assassin_score_by} eq 'looking_for_embedded_headers')  ? 1 : 0,       
					 
					 can_use_set_to_header_to_list_address => $can_use_set_to_header_to_list_address, 
					 set_to_header_to_list_address       => $li->{set_to_header_to_list_address}, 
					 
					 open_discussion_list                => ($Plugin_Config->{Allow_Open_Discussion_List} == 1) ? $li->{open_discussion_list} : 0, 
					 rewrite_anounce_from_header         => $li->{rewrite_anounce_from_header}, 
					 
					 Plugin_URL                          => $Plugin_Config->{Plugin_URL}, 
					 Plugin_Name                         => $Plugin_Config->{Plugin_Name},
					 Allow_Open_Discussion_List          => $Plugin_Config->{Allow_Open_Discussion_List}, 
					 Allow_Manual_Run                    => $Plugin_Config->{Allow_Manual_Run}, 
					 Plugin_URL                          => $Plugin_Config->{Plugin_URL}, 
					 Manual_Run_Passcode                 => $Plugin_Config->{Manual_Run_Passcode},
					 
					 S_PROGRAM_URL                       => $DADA::Config::S_PROGRAM_URL, 
						curl_location                      => $curl_location, 
					 saved                             => $q->param('saved'),
				
					
					}
				}
					 
		);
		
	print admin_template_footer(
			-Form => 0, 
			-List => $list,
			-li   => $li, 
		  ); 
}




sub cl_main { 
	
	init(); 

	if($test){ 

		$verbose = 1; 
		
		if($test eq 'pop3'){ 

			test_pop3(); 	

		}else{ 

			print "I don't know what you want to test!\n\n"; 
			help(); 

		}

	}elsif($help){ 

		help();		

	}else{ 

		start(); 
		
		
		require DADA::Mail::MailOut; 
		
		if($list){ 
		
		    DADA::Mail::MailOut::monitor_mailout({-verbose => 0, -list => $list});
        } 
        else { 
        
            DADA::Mail::MailOut::monitor_mailout({-verbose => 0});
        
        }
	}
	
}




sub init {};




sub start { 

	my @lists; 
	
	if(!$run_list){ 
		print "Running all lists - \nTo test an individual list, pass the list shortname in the '--list' parameter...\n\n"
			if $verbose; 
		@lists = available_lists(-dbi_handle => $dbi_handle);	
	}else{ 
		$lists[0] = $run_list; 
	}


	require DADA::Mail::MailOut; 
	my @mailouts = DADA::Mail::MailOut::current_mailouts(); 
	# DEV: This is wrong, as the number of mailouts will be different from the
	# number of *active* mailouts. Hmm...
	
	# KLUDGE!
	if($Plugin_Config->{Room_For_One_More_Check} == 1){ 
	#/KLUDGE!	
 	   if(($#mailouts + 1) >= $DADA::Config::MAILOUT_AT_ONCE_LIMIT){ 
			print "There are currently, " . 
			      ($#mailouts + 1)         .
			      " mass mailout(s) running or queued. Going to wait until that number falls below, " . 
			      $DADA::Config::MAILOUT_AT_ONCE_LIMIT . " mass mailout(s) \n"
					if $verbose;
			return; 
		}
		else { 
			print "There are currently, " . 
	      ($#mailouts + 1)         .
	      " mass mailout(s) running or queued. That's below our limit 
	        ($DADA::Config::MAILOUT_AT_ONCE_LIMIT), so we can check on awaiting 
	        messages:\n\n"
				if $verbose;
		}
	#KLUDGE!
	}
	else { 
		print "Skipping, 'Room for one more?' check\n"
			if $verbose; 
	}
	#/KLUDGE!

	my $messages_viewed = 0; 
	QUEUE: foreach my $list (@lists){ 
	
					
		if ($messages_viewed >= $Plugin_Config->{MessagesAtOnce}){ 
			last; 
		}
			
					
		print "\n" . '-' x 72 . "\nList: " . $list . "\n"
			if $verbose;
		
		my $ls = DADA::MailingList::Settings->new({-list => $list}); 
		my $li = $ls->get(); 
		
		
		
		if($li->{discussion_pop_email} eq $li->{list_owner_email}){ 
			print "\t\t***Warning!*** Misconfiguration of plugin! The list owner email cannot be the same address as the list email address!\n\t\tSkipping $list...\n"
				if $verbose; 
			next; 
		}
		
		next if ! valid_login_information(
				{
					-list      => $list, 
					-list_info => $li
				}
			);
		
		
		my $lock_file_fh = undef; 
		if($Plugin_Config->{Enable_POP3_File_Locking} == 1){
			$lock_file_fh = DADA::App::POP3Tools::_lock_pop3_check(
				{
					name => 'dada_bridge.lock'
				}
			);
		}
		
		my $pop = pop3_login(
							$list, 
							$li, 
							$li->{discussion_pop_server}, 
							$li->{discussion_pop_username}, 
							$li->{discussion_pop_password},
							$li->{discussion_pop_auth_mode}, 
							$li->{discussion_pop_use_ssl},			
		); 
		
		if(defined($pop)){  

			my $msg_count = $pop->Count;
			my $msgnums = {};
			# This is weird - do we get everything out of order, here?
			for ( my $cntr = 1; $cntr <= $msg_count; $cntr++ ) {
			    my ($msg_num, $msg_size) = split('\s+', $pop->List($cntr)) ;
			    $msgnums->{$msg_num} = $msg_size;
			}
			
			my $local_msg_viewed = 0; 
			
			# Hmm, we do, but then we sort them numerically here: 
			foreach my $msgnum (sort { $a <=> $b } keys %$msgnums) {
			
			    $local_msg_viewed++;
			    print "\t Message Size: " . $msgnums->{$msgnum} . "\n";
			    if($msgnums->{$msgnum} > $Plugin_Config->{Max_Size_Of_Any_Message}){ 
			    
			        print "\tWarning! Message size ( " . $msgnums->{$msgnum} . " ) is larger than the maximum size allowed ( " . $Plugin_Config->{Max_Size_Of_Any_Message} . ")"
			            if $verbose; 
			        warn  "dada_bridge.pl $App_Version: Warning! Message size ( " . $msgnums->{$msgnum} . " ) is larger than the maximum size allowed ( " . $Plugin_Config->{Max_Size_Of_Any_Message} . ")";
			    
			    }
			    else { 
			    
                    if ($li->{disable_discussion_sending} != 1){     
                    
         

                        my $full_msg = $pop->Retrieve($msgnum);

                        push(@{$checksums->{$list}}, create_checksum(\$full_msg));  
                        
                        
                        eval { 
                        
                            # The below line is just for testing purposes...
                            # die "aaaaaaarrrrgggghhhhh!!!"; 
	
                            my ($status, $errors) = validate_msg($list, $full_msg, $li);
                            if($status){  
                                
                                process($list, $li, $full_msg); 
                                
                            }else{  
                            
                                print "\tMessage did not pass verification - handling issues...\n"
                                    if $verbose; 
                                    
                                handle_errors($list, $errors, $full_msg, $li);  
                            
                            }
                            
                         };
                         
                         if($@){ 
                         
                            warn  "dada_bridge.pl - irrecoverable error processing message. Skipping message (sorry!): $@"; 
                            print "dada_bridge.pl - irrecoverable error processing message. Skipping message (sorry!): $@"
                                if $verbose; 
                                
                         }
                        
                        
                    }else{  
                        print "\tThis sending method has been disabled for $list, deleting message... \n" 
                            if $verbose;
                    }
                }
                
				$messages_viewed++; 
				
				if ($messages_viewed >= $Plugin_Config->{MessagesAtOnce}){ 
						print "\n\nThe limit has been reached of the amount of messages to be looked at for this execution\n\n"
							if $verbose;
						last; 
				}
					
					
			}


			my $delete_msg_count = 0; 
            
			foreach my $msgnum_d (sort { $a <=> $b } keys %$msgnums) {  
				print "\tremoving message from server...\n"
					 if $verbose;
				$pop->Delete($msgnum_d);  
				$delete_msg_count++; 
				
				
				last
					if $delete_msg_count >= $local_msg_viewed;
				
			} 
			print "\tdisconnecting from POP3 server\n" 
				if $verbose;
			
			$pop->Close();
			
			if($Plugin_Config->{Enable_POP3_File_Locking} == 1){	
				DADA::App::POP3Tools::_unlock_pop3_check(
					{
						name => 'dada_bridge.lock',
						fh   => $lock_file_fh,
					}
				);
			}
			
			if($check_deletions){
				if(keys %$msgnums){ 	
					message_was_deleted_check($list, $li); 
				}else{ 
					print "\tNo messages received, skipping deletion check.\n" 
						if $verbose;
				}	
			}
		}else{ 
			print "\tPOP3 connection failed!\n" 
				if $verbose; 
		}
	}	
}




sub message_was_deleted_check() { 
	
	# DEV: Nice for testing...
	#return; 
	 
	print "\n\tWaiting 5 seconds before removal check...\n"
		if $verbose; 
		
	sleep(5); 
	
	my $list = shift;
	my $li   = shift; 
	

    my $lock_file_fh = undef; 
	if($Plugin_Config->{Enable_POP3_File_Locking} == 1){	
		$lock_file_fh = DADA::App::POP3Tools::_lock_pop3_check(
							{
								name => 'dada_bridge.lock',
							}
						);
	}
	
	my $pop = pop3_login(
					$list, 
					$li, 
					$li->{discussion_pop_server},  
					$li->{discussion_pop_username}, 
					$li->{discussion_pop_password},
					$li->{discussion_pop_auth_mode}, 
					$li->{discussion_pop_use_ssl},
			);

	if($pop){  

		my $msg_count = $pop->Count;
		my $msgnums = {};
		
		for ( my $cntr = 1; $cntr <= $msg_count; $cntr++ ) {
		    my ($msg_num, $msg_size) = split('\s+', $pop->List($cntr));
		    $msgnums->{$msg_num} = $msg_size;
		}
		
		foreach my $msgnum (sort { $a <=> $b } keys %$msgnums) {
			my $msg = $pop->Retrieve($msgnum);
			
			my $cs = create_checksum(\$msg); 
			
			print "\t\tcs:             $cs\n" 
				if $verbose; 
			
            my @cs;
			if(defined(@{$checksums->{$list}})){ 
			    @cs = @{$checksums->{$list}};
			}

			foreach my $s_cs(@cs){ 
			
				print "\t\tsaved checksum: $s_cs\n"
						if $verbose; 
						
				if($cs eq $s_cs){ 
					print "\t\tMessage was NOT deleted from POP server! Will attempt to do that now...\n"
						if $verbose; 
					$pop->Delete($msgnum);
				} else { 
					print "\t\tMessage checksum does not match saved checksum, keeping message for later delivery...\n"
						if $verbose; 							 
				}
			}
		}	
		$pop->Close();
		
		
	}else{ 
		print "POP3 login failed.\n";
	}

	if($Plugin_Config->{Enable_POP3_File_Locking} == 1){	
		DADA::App::POP3Tools::_unlock_pop3_check(
			{
				name => 'dada_bridge.lock',
				fh   => $lock_file_fh, 
			}
		);
	}

}




sub help { 
print q{ 

arguments: 
-----------------------------------------------------------
--help                 		
--verbose
--test pop3

-----------------------------------------------------------
for a general overview and more instructions, try:

pod2text ./dada_bridge.pl | less

-----------------------------------------------------------

--help

Displays a help menu.

--list

Will allow you to work on one list at a time, instead of all the lists you 
have. 

--verbose 

Prints out a whole lot of stuff on the command line that may be helpful in 
determining what's happening. 

--test pop3

Allows you to test the pop3 login information on the command line. 
Currently the only test available. 

--check_deletions

When this flag is run, an extra check is done to ensure that messages on 
the POP server that should have been removed, have been removed. Shouldn't 
have to be used, but this problem has been... problematic. 

Example: 

 prompt>dada_bridge.pl --test pop3 --list yourlistshortname

Will test the pop3 connection of a list with a shortname of, 
yourlistshortname

Another Example: 

 prompt>dada_bridge.pl --verbose --list yourlistshortname

Will check for messages to deliver for list, 
yourlistshortname> and outputting a lot of information on the command line. 

};
	exit;
}




sub test_pop3 { 

    my $li = shift || undef; 
    
	
	my @lists; 
	
	if(!$run_list){ 
		print "Testing all lists - \nTo test an individual list, pass the list shortname in the '--list' parameter...\n\n"; 
		@lists = available_lists(-dbi_handle => $dbi_handle);
	}else{ 
		push(@lists, $run_list); 
	}

	foreach my $l(@lists){
		
		print "\n" . '-' x 72 . "\nTesting List: '" . $l . "'\n";
		
		unless(check_if_list_exists(-List => $l, -dbi_handle => $dbi_handle)){ 
			print "'$l' does not exist! - skipping\n";
			next;
		}
		
		if(!$li){ 
		    my $ls  = DADA::MailingList::Settings->new({-list => $l}); 
		       $li  = $ls->get();
		}
		
		if($li->{disable_discussion_sending} == 1){ 
			print "'$l' has this feature disabled - skipping.\n";
		}else{
		    
			my $lock_file_fh = undef; 
			if($Plugin_Config->{Enable_POP3_File_Locking} == 1){ 
			
		    	$lock_file_fh = DADA::App::POP3Tools::_lock_pop3_check(
									{
										name => 'dada_bridge.lock',
									}
								);
			}

			my $pop = pop3_login(
								 $l,
			                     $li, 
								 $li->{discussion_pop_server}, 
								 $li->{discussion_pop_username}, 
								 $li->{discussion_pop_password},
								 $li->{discussion_pop_auth_mode}, 
								 $li->{discussion_pop_use_ssl},
								);
		 	if($pop){
				$pop->Close();
				
				if($Plugin_Config->{Enable_POP3_File_Locking} == 1){
			 		DADA::App::POP3Tools::_unlock_pop3_check(
						{
							name => 'dada_bridge.lock',
							fh   => $lock_file_fh, 
						}
					);
				}
			   print "\tLogging off of the POP Server.\n";
			}
		}	
	}
	print "\n\nPOP3 Login Test Complete.\n\n";
}




sub pop3_login { 

	my ($l, $li, $server, $username, $password, $auth_mode, $use_ssl) = @_;
	
	$password = DADA::Security::Password::cipher_decrypt($li->{cipher_key}, $password);
	
	if(!valid_login_information({-list => $l, -list_info => $li})){ 
			print "Some POP3 Login Information is missing - please double check! (aborting login attempt)\n"
				if $verbose;
			return undef; 
	}else{

		my $pop = undef; 
		
		eval { 
			$pop =  DADA::App::POP3Tools::mail_pop3client_login(
			    {
			        server   => $server, 
			        username => $username, 
			        password => $password, 
		        
			        verbose  => $verbose, 
					        
	                USESSL    => $use_ssl,
	                AUTH_MODE => $auth_mode,		        
			    }
			); 
		};
		if(!$@){ 
			return $pop; 
		}
		else { 
			print "Problems Logging in:\n$@"
				if $verbose; 
			warn $@; 
			return undef; 
		}

	}
}




sub valid_login_information { 

	my ($args) = @_;
	
	my $list = $args->{-list}; 
	my $li = {}; 
	if($args->{-list_info}){ 
	    $li = $args->{-list_info}; 
	}
	else { 
	
        my $ls = DADA::MailingList::Settings->new({-list => $list}); 
           $li = $ls->get(); 
    }
    
	return 0 if ! $li->{discussion_pop_server};
	return 0 if ! $li->{discussion_pop_username};
	return 0 if ! $li->{discussion_pop_email};
	return 0 if ! $li->{discussion_pop_password};
	return 1; 
}




sub validate_msg { 

	my $list   = shift; 
	my $msg    = shift;
	my $li     = shift; 
	
	
	my $status = 1; 
	
	# DEV: 
	# This should *really* mention each and every test....
	
	my $errors = {
		msg_from_list_address => 0
	}; 
	


	my $lh = DADA::MailingList::Subscribers->new({-list => $list}); 
	
	if($li->{discussion_pop_email} eq $li->{list_owner_email}){ 
		print "\t\t***Warning!*** Misconfiguration of plugin! The list owner email cannot be the same address as the list email address!\n"
			if $verbose; 
		$errors->{list_email_address_is_list_owner_address} = 1;
	}
	
	my $entity; 
	 
	eval { $entity = $parser->parse_data($msg) };
	
	if(!$entity){
		print "\t\tMessage invalid! - no entity found.\n" if $verbose;  
		$errors->{invalid_msg} = 1;
		return (0, $errors); 
	}

    if($Plugin_Config->{Check_Multiple_Return_Path_Headers} == 1){ 
    
        if($entity->head->count('Return-Path') > 1) { 
            print "\t\tMessage has more than one 'Return-Path' header? Malformed email message - will reject!\n"
                if $verbose; 
                $errors->{multiple_return_path_headers} = 1;
        }
    
    }
	
	if($entity->head->count('X-BeenThere')){ 
	    my $x_been_there_header = $entity->head->get('X-BeenThere', 0);
	    chomp($x_been_there_header);
	    
	    if($x_been_there_header eq $li->{discussion_pop_email}){ 
	        print "\t\tMessage is from myself (the, X-BeenThere header has been set), message should be ignored...\n"
	            if $verbose;
	        $errors->{x_been_there_header_found} = 1;
	    } else { 
	        $errors->{x_been_there_header_found} = 0; 
        }	     

	}
	
	my $rough_from = $entity->head->get('From', 0); 
	my $from_address = '';

	if (defined($rough_from)){; 
		eval { $from_address = (Email::Address->parse($rough_from))[0]->address; }
	}
	
	print '\t\tWarning! Something\'s wrong with the From address - ' . $@ 
		if $@ && $verbose;
		
	$from_address = lc_email($from_address); 
	
	print "\t\tMessage is from: '" . $from_address . "'\n"
		if $verbose; 
	
	if($from_address eq $li->{list_owner_email}){ 
		print "\t\t * From: address is the list owner address ; (". $li->{list_owner_email} .')' . "\n"
			if $verbose;
		
		
            if($Plugin_Config->{Check_List_Owner_Return_Path_Header}){ 
            
                my $rough_return_path = undef; 


			 	if($entity->head->get( 'Return-Path', 0 )){ 
				
					$rough_return_path = $entity->head->get( 'Return-Path', 0 );
					
					my $return_path_address = '';

	                if (defined($rough_return_path)){; 
	                    eval { $return_path_address = (Email::Address->parse($rough_return_path))[0]->address; }
	                }
	                $return_path_address = lc_email($return_path_address); 

	                if($from_address eq $return_path_address){ 

	                    $errors->{list_owner_return_path_set_funny} = 0; 

	                    print "\t\t * Address set in, From: header, ($from_address) matches, Return-Path address ($return_path_address) Yeah!\n"
	                        if $verbose;


	                }
	                else { 

	                    print "\t\t * Address set in, From: header, ($from_address) doesn't match, Return-Path address ($return_path_address) ? Why?\n"
	                        if $verbose;
	                    warn "\t\t * Address set in, From: header, ($from_address) doesn't match, Return-Path address ($return_path_address) ? Why?\n";

	                    if($return_path_address eq $li->{admin_email}){ 

	                        print "\t\tAh! Ok, The Return-Path is set to the list administrator - I guess that's ok...."
	                            if $verbose; 
	                        warn "\t\tAh! Ok, The Return-Path is set to the list administrator - I guess that's ok....";    

	                        $errors->{list_owner_return_path_set_funny} = 0; 

	                    }
	                    else { 

	                        $errors->{list_owner_return_path_set_funny} = 1;            

	                    }
	                }
	
				
				
				}
				else { 
					# Strange, but there is no return-path... why?
					print "\t\t * No Return Path Found - Skipping Test"
				 		if $verbose;
					$errors->{list_owner_return_path_set_funny} = 0;
				}
				
            }
        
	}else{ 
	
		print "\t\t * From address is NOT from list owner address\n"
			if $verbose;
		$errors->{msg_not_from_list_owner} = 1; 
			
	    if($li->{enable_moderation}){ 
			print "\t\tModeration enabled...\n"
				if $verbose; 
				
			if($errors->{msg_not_from_list_owner} == 1){ 
			
			    print "\t\tMessage is not from list owner.\n"
			        if $verbose;
			        $errors->{needs_moderation} = 1; 
			}
							
		}else{ 
			print "\t\tModeration disabled...\n"
				if $verbose; 
		}
		
			
		if($li->{group_list} == 1){
		
			print "\t\tDiscussion Support enabled...\n"
				if $verbose; 
				
			#if($li->{enable_authorized_sending} && $errors->{msg_not_from_an_authorized_sender} == 0){ 
			#
		    #	print "\t\tSubscription checked skipped - authorized sending enabled and address passed validation.\n"
			#	    if $verbose; 
			#	
			#}else{ 
			
				my ($s_status, $s_errors) = $lh->subscription_check(
												{
													-email => $from_address,
												}
											);
			
				if ($s_errors->{subscribed} != 1){ 
					
					print "\t\t*Message is NOT from a subscriber.\n"
						if $verbose; 
				    
				   
				   if($li->{open_discussion_list} == 1 && $Plugin_Config->{Allow_Open_Discussion_List} == 1){ 
				    
				        print "\t\tPostings from non-subscribers is enabled...\n"
				            if $verbose;
				        # Just explicitly setting this...
				        $errors->{msg_not_from_subscriber} = 0;
				        $errors->{msg_not_from_list_owner} = 0; 
				    }
				    else { 
				    
				        $errors->{msg_not_from_subscriber} = 1;
				    }
				    
				}else{ 
					print "\t\t*Message *is* from a current subscriber.\n"
						if $verbose; 

					$errors->{msg_not_from_subscriber} = 0;
					$errors->{msg_not_from_list_owner} = 0; 			

				}
			#}
			
		}else{ 
			print "\t\tDiscussion Support disabled...\n"
			    if $verbose; 
		}
	}

    if($li->{enable_authorized_sending} == 1){ 
    
        print "\t\tAuthorized Senders List enabled...\n"
            if $verbose; 
       # if($errors->{msg_not_from_list_owner} == 0){ 
 
		# The f'ing check gets erased from above, so we sort of have to do it again...
       if($from_address eq $li->{list_owner_email}){ 
	
            print "\t\tSkipping Authorized Senders check - message is from the list owner.\n"
                if $verbose; 
            $errors->{msg_not_from_an_authorized_sender} = 0;

        }												  # only skip if we have a discussion list
		elsif($errors->{msg_not_from_subscriber} == 0 && $li->{group_list} == 1) { 
			
            print "\t\tSkipping Authorized Senders check - message is from a Subscriber\n"
                if $verbose; 
            $errors->{msg_not_from_an_authorized_sender} = 0;
	
		}
        else { 
        
            my ($m_status, $m_errors) = $lh->subscription_check(
											{
												-email => $from_address, 
                                                -type  => 'authorized_senders',
                                             }
										);
            if($m_errors->{subscribed} != 1){ 												   
                
               $errors->{msg_not_from_an_authorized_sender} = 1;
                print "\t\t\t*Message is NOT from an Authorized Sender.\n"
                    if $verbose; 
            }else{ 
                
                print "\t\t\t*Message *is* from a Authorized Sender!\n"
                    if $verbose; 

                $errors->{msg_not_from_list_owner} = 0
                    if $errors->{msg_not_from_list_owner} == 1; 

                $errors->{msg_not_from_subscriber} = 0
                    if $errors->{msg_not_from_subscriber} == 1; 

                $errors->{needs_moderation} = 0
                    if $errors->{needs_moderation} == 1; 
            }
        }

    }
    else { 
        print "\t\tAuthorized Senders List disabled...\n"
            if $verbose;         
    }
    
        
    if ($li->{ignore_spam_messages} == 1){ 
        print "\n\t\tSpamAssassin check enabled...\n\n"
            if $verbose;

        if($li->{find_spam_assassin_score_by} eq 'calling_spamassassin_directly'){ 
        
            print "\t\tLoading SpamAssassin directly...\n"
                if $verbose;
        
            eval { require Mail::SpamAssassin; }; 
            if(!$@){ 
                    
                if($Mail::SpamAssassin::VERSION <= 2.60 && $Mail::SpamAssassin::VERSION >= 2){ 
                    require Mail::SpamAssassin::NoMailAudit; 
                    
                    # this needs to be optimized...
                    my $spam_check_message = $entity->as_string; 
                    my @spam_check_message = split("\n", $spam_check_message); 
                  
                    my $mail = Mail::SpamAssassin::NoMailAudit->new(data => \@spam_check_message);
                      
                    my $spamtest = Mail::SpamAssassin->new({debug => 'all', local_tests_only => 1, dont_copy_prefs => 1, });
                  
                    my $score; 
                    my $report;
                    
                    if($spamtest){ 
                        my $spam_status;
                           $spam_status = $spamtest->check($mail);

                        if($spam_status){ 
                            $score  = $spam_status->get_hits();
                            $report = $spam_status->get_report();
                        }
                        
                    }
            

                    if($score eq undef && $score != 0){ 
                        print "\t\t\tTrouble parsing scoring information - letting message pass...\n"
                            if $verbose
                  
                    } else { 
                        
                        if($score >= $li->{ignore_spam_messages_with_status_of}){
                            print "\t\t\t Message has *failed* Spam Test (Score of: $score, " . $li->{ignore_spam_messages_with_status_of} . " needed.) - ignoring message.\n"
                                if $verbose;
                            
                            $errors->{message_seen_as_spam} = 1;

                            print "\n" . $report
                                if $verbose; 
                            
                        }else{ 
                            $errors->{message_seen_as_spam} = 0;
                            
                            print "\t\t\t Message passed! Spam Test (Score of: $score, " . $li->{ignore_spam_messages_with_status_of} . " needed.)\n"
                                if $verbose;
                        }
                    
                    }
                    
                    undef $mail;
                    undef $spamtest;
                    undef $score;
                    undef $report; 
                
                }else{ 
                    print "\t\tSpamAssassin 2.60 and below is currently only supported, you have version $Mail::SpamAssassin::VERSION, skipping test\n"
                        if $verbose;
                }
                
            } else { 
                print "\t\tSpamAssassin doesn't seem to be available. Skipping test.\n"
                    if $verbose;
            }
            

        } elsif($li->{find_spam_assassin_score_by} eq 'looking_for_embedded_headers'){ 
        
            print "\t\tLooking for embedding SpamAssassin Headers...\n"
                if $verbose;
           
           
           my $score = undef; 
           if($entity->head->count('X-Spam-Status')){
               
               my @x_spam_status_fields = split(' ', $entity->head->get('X-Spam-Status', 0)); 
               foreach(@x_spam_status_fields){ 
                   if($_ =~ m/score\=/){ 
                          $score = $_; 
                          $score =~ s/score\=//; 
                          
                          print "\t\tFound them...\n"
                            if $verbose;
                          
                       last; 
                    
                    }
               }
           }
           
           if($score eq undef && $score != 0){ 
                    
                print "\t\t\tTrouble parsing scoring information - letting message pass...\n"
                    if $verbose
              
            } else { 
                
                if($score >= $li->{ignore_spam_messages_with_status_of}){
                    print "\t\t\t Message has *failed* Spam Test (Score of: $score, " . $li->{ignore_spam_messages_with_status_of} . " needed.) - ignoring message.\n"
                        if $verbose;
                    
                    $errors->{message_seen_as_spam} = 1;
                    
                    if($verbose){   
                        my @x_spam_report = $entity->head->get('X-Spam-Report');
                        print "\n\t";
                        print "$_\n" foreach @x_spam_report;
                    }
                    
                   
                }else{ 
                    $errors->{message_seen_as_spam} = 0;
                    
                    print "\t\t\t Message passed! Spam Test (Score of: $score, " . $li->{ignore_spam_messages_with_status_of} . " needed.)\n"
                        if $verbose;
                }

            }
       } else { 
       
            print "\t\t\tDon't know how to find the SpamAssassin score, sorry!\n"
                if $verbose; 
       
       }
            
   } else{ 
        print "\n\t\tSpamAssassin check disabled...\n"
            if $verbose; 
   }

    print "\n"
        if $verbose;
    
    

    # This below probably can't happen anymore...
	if ($li->{discussion_pop_email} eq $from_address){ 
		$errors->{msg_from_list_address} = 1;
		print "\t\t *WARNING!* Message is from the List Address. That's bad.\n"
			if $verbose; 
	}	 
		
    foreach(keys %$errors){
        if($errors->{$_} == 1){ 
            $status = 0 ;
            last;
        }
    }	
    
	return ($status, $errors); 
}




sub process { 

	my $list     = shift; 
	my $li       = shift; 
	my $full_msg = shift; 
	
	print "\n\t\tProcessing Message...\n" 
		if $verbose; 
		
	if($li->{send_msgs_to_list} == 1){ 
	
		my $n_full_msg = dm_format($li->{list}, $full_msg, $li);
					
		print "\t\tMessage being delivered! \n"
			if $verbose; 
		
		my ($msg_id, $saved_message) = deliver($list, $n_full_msg);
		archive($list, $li, $n_full_msg, $msg_id, $saved_message);  
	
	}
	
	if($li->{send_msg_copy_to} && $li->{send_msg_copy_address}){ 
		print "\t\t Sending a copy of the message to: " . $li->{send_msg_copy_address}  . "\n"
			if $verbose; 
			
		deliver_copy($li->{list}, $full_msg); 
	}
	
	print "\t\tFinished Processing Message.\n\n"
		if $verbose; 
						
}




sub dm_format { 
	
	my $list       = shift; 
	my $msg        = shift; 
	my $li         = shift; 
	
	if($li->{strip_file_attachments} == 1){ 
		$msg = strip_file_attachments($msg, $li);
	}
	
	require DADA::App::FormatMessages; 
	
	my $fm = DADA::App::FormatMessages->new(-List => $list); 
	   $fm->treat_as_discussion_msg(1); 
	
	if($li->{group_list} == 0 && $li->{rewrite_anounce_from_header} == 0){ 
	   $fm->reset_from_header(0);
	}
	
	
	my ($header_str, $body_str) = $fm->format_headers_and_body(-msg => $msg);
	
	return $header_str . "\n\n" . $body_str; 
	
}




sub strip_file_attachments { 

	my $msg = shift; 
	my $li  = shift; 
	
		my $entity; 
	
	
	eval { $entity = $parser->parse_data($msg) };
	if(!$entity){
		die "no entity found! die'ing!";   
	}
	
	print "\t\t\tStripping banned file attachments...\n\n"
		if $verbose; 
	
	($entity, $li) = process_stripping_file_attachments($entity, $li); 
	
	return $entity->as_string; 

}




sub process_stripping_file_attachments { 

	my $entity = shift; 
	my $li     = shift; 
	
	my @att_bl = split(' ', $li->{file_attachments_to_strip}); 
	my $lt = {};
	
	foreach(@att_bl){ 
		
		$lt->{$_} = lc($lt->{$_}); 
		$lt->{$_} = 1; 
	}

	my @parts  = $entity->parts; 

	if(@parts){
	
		# multipart... 
		my $i;
		foreach $i (0 .. $#parts) {       			
			($parts[$i], $li) = process_stripping_file_attachments($parts[$i], $li);
			
	
		}
		
		my @new_parts; 
		
		foreach $i (0 .. $#parts) { 
			if(!$parts[$i]){

			}else{ 
			
				push(@new_parts, $parts[$i]); 
			}
		}
			
		$entity->parts(\@new_parts); 	
		
		
		
		
		$entity->sync_headers('Length'      =>  'COMPUTE',
							  'Nonstandard' =>  'ERASE');
		

		return ($entity, $li); 

			  
	}else{ 		
			
			my $name = $entity->head->mime_attr("content-type.name") || 
			   $entity->head->mime_attr("content-disposition.filename");
			   
			   my $f_ending = $name; 
			   
			      $f_ending =~ s/(.*)\.//g;
						      
			if($lt->{lc($entity->head->mime_type)} == 1 || $lt->{lc($f_ending)} == 1){ 
			
				print "\t\t\t * Stripping attachment with:\n\t\t\t\tname: $name and mime-type:\n\t\t\t\t" . $entity->head->mime_type . "\n";
				return (undef, $li);
			}
			
			$entity->sync_headers('Length'      =>  'COMPUTE',
					      		'Nonstandard' =>  'ERASE');
			return ($entity, $li); 
	}

	return ($entity, $li); 
}




sub deliver_copy { 

	print "Delivering Copy...\n"
		if $verbose; 
		
	my $list = shift;
	my $msg  = shift; 
	
	my $ls = DADA::MailingList::Settings->new({-list => $list}); 
	my $li = $ls->get; 
	my $mh = DADA::Mail::Send->new(
					{
						
						-list   => $list, 
						-ls_obj => $ls, 
					}
				);
				
	my $entity; 
	 
	eval { $entity = $parser->parse_data($msg) };
	
	if(!$entity){
		print "\t\tMessage sucks!\n" 
			if $verbose; 
	
	}else{

		my %headers =  $mh->return_headers($entity->stringify_header);
	       $headers{To} = $li->{send_msg_copy_address};
		   
		if($verbose){ 
			print "\tMessage Details: \n\t" . '-' x 50 . "\n"; 
			print "\tSubject: " .  $headers{Subject} . "\n";
		}
		
		# Um. I'm not touching that. 
		my $msg_id = $mh->send(
			
							  %headers,
						      # Trust me on these :) 

						      # These are here so the message doesn't cause an infinite loop BACK to the list - 
						      
						      # These are *probably* optional, 
						      'Bcc'         => '', 
						      'Cc'          => '', 
						      
						      # This'll do the trick, all by itself. 
						      'X-BeenThere' =>  $li->{discussion_pop_email},
							  
							  Body          => $entity->stringify_body,
				
				      );
		
	}
	
}




sub deliver { 

	my $list = shift;
	my $msg  = shift; 
	
	my $ls = DADA::MailingList::Settings->new({-list => $list}); 
	my $li = $ls->get; 
	my $mh = DADA::Mail::Send->new(
				{
					-list   => $list, 
					-ls_obj => $ls, 
				}
			);
	
	my $entity; 
	 
	eval { $entity = $parser->parse_data($msg) };
	
	if(!$entity){
		print "\t\tMessage sucks!\n" 
			if $verbose; 
	
	}else{
	
		my %headers     =  $mh->return_headers($entity->stringify_header);
	       $headers{To} = $li->{list_owner_email};
		
		if($verbose){ 
			print "\tMessage Details: \n\t" . '-' x 50 . "\n"; 
			print "\tSubject: " .  $headers{Subject} . "\n";
		}
		
		if($li->{group_list} == 1 && $li->{mail_discussion_message_to_poster} != 1){ 
		
			my $f_a; 
	
			if (defined($headers{From})){
				
				eval { $f_a = (Email::Address->parse($headers{From}))[0]->address; }
			}	

			if(!$@){ 
				print "\tGoing to skip sending original poster ($f_a) a copy of their own  message...\n"
					if $verbose; 
				$mh->do_not_send_to([$f_a]);
			}else{ 
				print "Problems not sending copy to original sender: $@\n\n" 
					if $verbose; 
			}
		}

		my $msg_id = $mh->mass_send(
								%headers,
								  # Trust me on these :) 
								 Body => $entity->stringify_body,
				
				 );

		return ($msg_id, $mh->saved_message); 

	}
	
}




sub archive {
	
	my $list      = shift; 
	my $li        = shift; 
	my $full_msg  = shift; 
	my $msg_id    = shift; 
	my $saved_msg = shift; 
	


	
	#my $ls = DADA::MailingList::Settings->new({-list => $list}); 	
	#my $li = $ls->get; 
	
	
	if ($li->{archive_messages} == 1){ 
		
		require DADA::MailingList::Archives; 
       
       # I'm having trouble with the db handle die'ing after we've forked a mailing.
       # I wonder if telling Mr. Archives here to create  new connection will help things...
       
       # $DADA::MailingList::Archives::dbi_obj = $dbi_handle;
        
		my $la = DADA::MailingList::Archives->new({-list => $list}); 
		
		my $entity;  
		
		eval { $entity = $parser->parse_data($full_msg) };
			
		if($entity){
		
			my $Subject = $entity->head->get('Subject', 0);
			   $Subject = $la->strip_subjects_appended_list_name($Subject)
			   	if $li->{no_append_list_name_to_subject_in_archives} == 1; 
			   	
           eval { 

                $la->set_archive_info(
                                  $msg_id, 
                                  $Subject, 
                                  undef, 
                                  undef,
                                  $saved_msg, 
                                 );
		  }; 
		  
		  if($@){ 
		      warn "$DADA::Config::PROGRAM_NAME $DADA::Config::VER warning! message did not archive correctly!: $@"; 
		  }
		}else{ 
			warn "Problem archiving message..."; 
		}
	
	}	
}




sub send_msg_not_from_subscriber { 

	my $list   = shift; 
	my $msg    = shift; 
	my $entity = $parser->parse_data($msg);

	my $rough_from = $entity->head->get('From', 0); 
	my $from_address;
	 	if (defined($rough_from)){; 
			eval { $from_address = (Email::Address->parse($rough_from))[0]->address; }
		}

	if($from_address && $from_address ne ''){ 
			require DADA::App::Messages; 
			DADA::App::Messages::send_not_allowed_to_post_message(
				{
					-list       => $list, 
					-email      => $from_address,	
					-attachment => $entity->as_string, 
				
				},
			); 
			
	}else{ 
		warn "Problem with send_msg_not_from_subscriber! There's no address to send to?: " . $rough_from;
	}

}




sub send_invalid_msgs_to_owner { 
	
	my $li     = shift; 
	my $list   = shift; 
	my $msg    = shift; 
	my $entity = $parser->parse_data($msg);
	
	my $rough_from = $entity->head->get('From', 0); 
	my $from_address;
	 	if (defined($rough_from)){; 
			eval { $from_address = (Email::Address->parse($rough_from))[0]->address; }
		}

	if($from_address && $from_address ne ''){ 
		
		my $reply = MIME::Entity->build(
			Type 	=> "multipart/mixed", 
			From    => $li->{list_owner_email},
			To      => $li->{list_owner_email},
			Subject => $DADA::Config::NOT_ALLOWED_TO_POST_NOTICE_MESSAGE_SUBJECT,									
		);
		# DEV: If the above works, we'll have to make this a per-list thingy.
		$reply->attach(
			Type => 'text/plain', 
			Data  => $DADA::Config::NOT_ALLOWED_TO_POST_NOTICE_MESSAGE, 
		); 			
		$reply->attach( 
			Type        => 'message/rfc822', 
			Disposition  => "inline",
			Data         => $entity->as_string,
		); 				

		my %msg_headers = DADA::App::Messages::_mime_headers_from_string($reply->stringify_header); 
		
		
		require DADA::App::Messages; 
		DADA::App::Messages::send_generic_email(
			{
				-list                     => $list, 
				-headers                  => {
					%msg_headers,
					# Hack? Or bug somewhere else...
					#'Content-Type' => 'multipart/mixed', 
				}, 
				-body                     => $reply->stringify_body, 
				-list_settings_vars       => $li, 
				-list_settings_vars_param => 
					{
						-dot_it => 1, 
					}
					
				-subscriber_vars          => 
					{
						'subscriber.email' => $from_address, 
					}
			}	
		);
	}else{ 
		warn "Problem with send_invalid_msgs_to_owner!";
	}
}




sub handle_errors { 

	my $list     = shift; 
	my $errors   = shift; 
	my $full_msg = shift; 
	my $li       = shift; 


	my $entity; 
	eval { $entity = $parser->parse_data($full_msg) };
	if(!$entity){
		die "no entity found! die'ing!";   
	}
	
	my $reasons = '';
	foreach(keys %$errors){ 
	    $reasons .=  $_ . ', ' 
	        if $errors->{$_} == 1; 
	}
	my $subject     = $entity->head->get('Subject', 0); 
	   $subject =~ s/\n//g; 
	my $from        = $entity->head->get('From', 0);
	   $from =~ s/\n//g;
	my $message_id  = $entity->head->get('Message-Id', 0);
       $message_id =~ s/\n//g; 
       if(!$message_id){ 
            
            require DADA::Security::Password; 	
            
            my ($f_user, $f_domain) = split('@', $from); 
            my $fake_message_id = '<' . DADA::App::Guts::message_id() . '.FAKE_MSG_ID' . DADA::Security::Password::generate_rand_string('1234567890') . '@' . $f_domain . '>'; 
            
            $message_id = $fake_message_id;
            $entity->head->replace('Message-ID', $fake_message_id);
       
            warn "dada_bridge.pl - message has no Message-Id header!...? Creating FAKE Message-Id ($fake_message_id) , to avoid any conflicts...";

       }
              
    warn "dada_bridge.pl rejecting sending of received message - \tFrom: $from\tSubject: $subject\tMessage-ID: $message_id\tReasons: $reasons";	
	
	
	print "\t\tError delivering message! Reasons:\n\n"
		if $verbose; 
	foreach(keys %$errors){ 
		print "\t\t\t" . $_ . "\n" 
			if $errors->{$_} == 1 && $verbose;
	}
	
	
	
	if($errors->{list_owner_return_path_set_funny} == 1){ 
	
	    print "\n\n\t\tlist_owner_return_path_set_funny\n\n"
	        if $verbose;
	        
	    # and I'm not going to do anything...
	
	}
	
	if($errors->{message_seen_as_spam} == 1){ 
	
	    print "\n\n\t\t *** Message seen as SPAM - ignoring. ***\n\n"
	        if $verbose;
	
	}
	elsif ($errors->{multiple_return_path_headers} == 1){ 
            
            print "\t\tMessage has multiple 'Return-Path' headers. Ignoring. \n\n"
                if $verbose; 
            warn "$DADA::Config::PROGRAM_NAME Error: Message has multiple 'Return-Path' headers. Ignoring.1023";	
	
	}
	elsif ($errors->{msg_from_list_address}){ 
            
            
            print "\t\tmessage was from the list address - will not process! - (ignoring) \n\n"
                if $verbose; 
            warn "$DADA::Config::PROGRAM_NAME Error: message was from the list address - will not process! - (ignoring)";
   }  		
   elsif(
		$errors->{msg_not_from_subscriber}           == 1 || 
		$errors->{msg_not_from_list_owner}           == 1 || 
		$errors->{msg_not_from_an_authorized_sender} == 1
		){ 
            
        if($li->{send_not_allowed_to_post_msg} == 1){ 
        
            print "\t\tmsg_not_from_subscriber on its way! \n\n"
                if $verbose; 
            send_msg_not_from_subscriber($list, $full_msg); 
        
        }
        
        if($li->{send_invalid_msgs_to_owner} == 1){ 
            print "\t\tinvalid_msgs_to_owner on its way! \n\n"
                if $verbose; 
            send_invalid_msgs_to_owner($li, $list, $full_msg); 
        
        }
        
        
        #if($errors->{msg_from_list_address}){ 
        #    warn "$DADA::Config::PROGRAM_NAME Error: message was from the list address - will not process! - (ignoring)";
        #}  			

    } 
    elsif($errors->{needs_moderation}){ 
	    
	    print "\t\Message being saved for moderation by list owner... \n\n"
	        if $verbose; 
	    
	    my $mod = SimpleModeration->new({-List => $list}); 
	       $mod->save_msg({-msg => $full_msg, -msg_id => $message_id});     
	       
		   # This is only used once...
	       $mod->moderation_msg({-msg => $full_msg, -msg_id => $message_id, -subject => $subject, -from => $from, -parser => $parser}); 
	       my $awaiting_msgs = $mod->awaiting_msgs(); 
	       
	       print "\t\tOther awaiting messages:\n\n"
	        if $verbose; 
	        
	        foreach(@$awaiting_msgs){ 
	            print "\t\t * " . $_ . "\n"
	                if $verbose; 
	       }
	}


}




sub create_checksum { 
 
	my $data = shift; 
	
	if($] >= 5.008){
		require Encode;
		my $cs = md5_hex(Encode::encode_utf8($$data));
		return $cs;
	}else{ 			
		my $cs = md5_hex($$data);
		return $cs;
	}
}




sub can_use_spam_assassin { 

    eval { require Mail::SpamAssassin; }; 
    
    if(!$@){ 
        return 1; 
    }else{ 
        return 0; 
    }
    
}

sub cgi_show_plugin_config { 


     	print(admin_template_header(
							-Title      => $Plugin_Config->{Plugin_Name} . " Plugin Configuration",
		                    -List       => $list,
		                    -Form       => 0,
		                    -Root_Login => $root_login
		                    ));
	
	my $tmpl = cgi_show_plugin_config_template(); 
    
    my $configs = []; 
    foreach(sort keys %$Plugin_Config){ 
        if($_ eq 'Password'){ 
            push(@$configs, {name => $_, value => '(Not Shown)'});
        }
        else { 
            push(@$configs, {name => $_, value => $Plugin_Config->{$_}}); 
        }
    }
	require DADA::Template::Widgets; 
    print   DADA::Template::Widgets::screen(
		  		{ 
			     	-data => \$tmpl, 
					-vars => { 				
								Plugin_URL   => $Plugin_Config->{Plugin_URL}, 
								Plugin_Name  => $Plugin_Config->{Plugin_Name}, 
								configs      => $configs, 
     						},
				},
    		);

    print admin_template_footer(-Form    => 0, 
                                -List    => $list,
                                ); 



}




sub cgi_show_plugin_config_template { 

    return q{ 
    
    
    
  <p id="breadcrumbs">
   <a href="<!-- tmpl_var Plugin_URL -->"> 
   <!-- tmpl_var Plugin_Name --> 
   </a> 
   
   &#187;
   
        Plugin Configuration
   </a> 
   
   
  </p> 
 
 
 
 
        <table> 
        
        <!-- tmpl_loop configs --> 
        
        <tr> 
          <td> 
           <p> 
             <strong> 
              <!-- tmpl_var name --> 
              </strong>
            </p>
           </td> 
           <td> 
            <p>
            <!-- tmpl_var value --> 
            </p>
            </td> 
            </tr> 
            
        <!-- /tmpl_loop --> 
 
        </table> 
        
    };


}





sub default_cgi_template {
	
return  q{ 

<!-- tmpl_if saved -->
	<!-- tmpl_var GOOD_JOB_MESSAGE  -->
<!-- /tmpl_if -->

<!--tmpl_unless list_email_validation -->
<p class="error">Information Not Saved! Please fix the below problems:</p>

<!--/tmpl_unless--> 
<form name="default_form" action="<!-- tmpl_var Plugin_URL --> "method="post">



<!--tmpl_if disable_discussion_sending -->
 <div style="background:#fcc;margin:5px;padding:5px;text-align:center">
  <h1>
   This Plugin is Currently Disabled for This List!
  </h1> 
 </div> 
  
<!--/tmpl_if--> 



<fieldset> 

<legend>List Address Configuration</legend>

 

  <blockquote class="positive">
 <p>
   The 
   <strong> 
    List Email 
   </strong>
   address is the email address you will be sending to, to have your messages 
   broadcasted to your entire Subscription List. This email account needs to be created, 
   if it's not already available. Make sure this address is not being used 
   for <strong>any</strong> other purpose.

 </p> 
 <p>
   The 
   <strong>
    List Email 
   </strong>
   should be different than both your list owner email address 
   (<em><!-- tmpl_var name="list_owner_email" escape="HTML" --></em>)
   and your list admin email address (<em><!-- tmpl_var name="admin_email" escape="HTML" --></em>). 
   If 
   <strong>
    &quot;Make this list a discussion list&quot;
   </strong> 
   has been checked, all subscribers can mail to the <strong>List Email</strong>
   and have their message sent all other subscribers. 
   Otherwise, only the list owner can email to this address. 
 </p>
</blockquote> 

 <table width="100%" cellpadding="5" cellspacing="0">
  <tr> 
   <td>
    <label for="discussion_pop_email">
     List Email:
    </label>
   </td>
   <td>
    <input name="discussion_pop_email" id="discussion_pop_email" type="text" value="<!-- tmpl_var name=discussion_pop_email -->" class="full" />
    <!-- tmpl_unless list_email_validation --> 
	<p class="error">!!! This email address is already being used for another List Owner Address, List Admin Email Address or List Email Address.</p>
   <!-- /tmpl_unless --> 

   </td>
  </tr>
  <tr> 
   <td width="125">
    <label for="discussion_pop_server">
     POP3 Server
    </label>
   </td>
   <td>
    <input name="discussion_pop_server" id="discussion_pop_server" type="text" value="<!-- tmpl_var name=discussion_pop_server -->" class="full" />
   </td>
  </tr>
  <tr>
   <td width="125">
    <label for="discussion_pop_username">
     POP3 Username:
    </label>
   </td>
   <td>
    <input name="discussion_pop_username" id="discussion_pop_username" type="text" value="<!-- tmpl_var name=discussion_pop_username -->" class="full" />
   </td>
  </tr>
  <tr>
   <td width="125">
    <label for="discussion_pop_password">
     POP3 Password:
    </label>
   </td>
   <td>
    <input name="discussion_pop_password" id="discussion_pop_password" type="password" value="<!-- tmpl_var name=discussion_pop_password escape="HTML"-->" />
   </td>
  </tr>


<tr>
     <td>
      <p>
       <label for="discussion_pop_auth_mode">
        Type:
       </label>
      </p>
     </td>
     <td>
      <p>
       <!-- tmpl_var discussion_pop_auth_mode_popup --> 
     </p>
     </td>
    </tr>
    
    
   </table>
   
    <table <!-- tmpl_unless can_use_ssl -->class="disabled"<!--/tmpl_unless-->> 
     <tr>
      <td>
       <p>
        <input type="checkbox" name="discussion_pop_use_ssl" id="discussion_pop_use_ssl" value="1" <!-- tmpl_if discussion_pop_use_ssl -->checked="checked"<!-- /tmpl_if --> <!-- tmpl_unless can_use_ssl -->disabled="disabled"<!--/tmpl_unless-->/>
       </p>
      </td>
      <td>
       <p>
        <label for="discussion_pop_use_ssl">
         Use Secure Sockets Layer (SSL)
        </label>
        <!-- tmpl_unless can_use_ssl -->
            <br />
            <span class="error">
             Disabled. The IO::Socket::SSL module needs to be installed.
            </span>
        <!--/tmpl_unless--> 
        
       </p>
      </td>
     </tr>
    </table> 
    
  </fieldset>   



<fieldset> 
 <legend> 
General
</legend> 


 <table width="100%" cellspacing="0" cellpadding="5">
  <tr>
   <td>
    <input name="disable_discussion_sending" id="disable_discussion_sending" type="checkbox" value="1" <!--tmpl_if disable_discussion_sending -->checked="checked"<!--/tmpl_if--> />
   </td>
   <td>
   
    
    <p>
     <label for="disable_discussion_sending">
      Disable sending using this method
     </label>
    </p>
   
   
   
   </td>
  </tr>


  <tr> 
   <td> 
    <input name="enable_authorized_sending" id="enable_authorized_sending" type="checkbox" value="1" <!--tmpl_if enable_authorized_sending -->checked="checked"<!--/tmpl_if--> /> 
   </td>
   <td>
    <p>
     <label for="enable_authorized_sending">
      Allow Messages Received From Authorized Senders
     </label>
     <br /> 
     
       Authorized Senders may post to announce-only lists and discussions lists without being on the subscription list themselves. Once enabled, you may 
     add Authorized Senders using the 
     
     <!-- tmpl_if enable_authorized_sending --> 
      <a href="<!-- tmpl_var S_PROGRAM_URL -->?f=view_list&type=authorized_senders">
     <!--/tmpl_if-->
     View/Add list Administration Screens.
     <!-- tmpl_if enable_authorized_sending --> 
      </a>
     <!--/tmpl_if-->
    </p>
	<!-- tmpl_if enable_authorized_sending --> 
	
	
	
	
     
  		  <!-- tmpl_if show_authorized_senders_table --> 
			<p><strong>Your Authorized Senders:</strong></p>
			<div style="max-height: 200px; width:250px; overflow: auto; border:1px solid black">
			 <table cellpadding="2" cellspacing="0" border="0" width="100%">
	
				<!-- tmpl_loop authorized_senders --> 
					  <tr
					 <!-- tmpl_if name="__odd__" --> style="background-color:#ccf;"<!-- tmpl_else --> style="background-color:#fff;" <!--/tmpl_if-->>
					 <td> 
					 <p><!-- tmpl_var email --></p>
					</td> 
					</tr> 
		
				<!--/tmpl_loop-->
				
				</table> 
				
				</div> 
				
		<!-- /tmpl_if --> 	
	
	
	<!--/tmpl_if-->

    </td> 
   </tr> 
   
   </table> 
   
</fieldset> 

<fieldset> 
 <legend> 
 Announce Only List Options
 </legend> 



 <table width="100%" cellspacing="0" cellpadding="5">
  <tr> 
   <td> 
    <input name="rewrite_anounce_from_header" id="rewrite_anounce_from_header" type="checkbox" value="1" <!--tmpl_if rewrite_anounce_from_header -->checked="checked"<!--/tmpl_if--> /> 
   </td>
   <td>
    <p>
     <label for="rewrite_anounce_from_header">
      Rewrite the From: header on announce-only messages to the List Owner address 
     </label>
     <br /> 
     
     Outgoing announce-only messages will go out with the address, 

      <strong> 
       <!-- tmpl_var list_owner_email -->
      </strong> 
      set in the From: header. 
     </p>
    </td> 
   </tr> 
   
   </table> 
   
</fieldset> 





<fieldset> 
 <legend> 
 Discussion List Options
 </legend> 


 <table width="100%" cellspacing="0" cellpadding="5">
  <tr> 
   <td align="right">
    <input name="group_list" id="group_list" type="checkbox" value="1" <!--tmpl_if group_list -->checked="checked"<!--/tmpl_if--> /> 
   </td>
   <td>
    <p>
     <label for="group_list">
      Make this list a discussion list
     </label>
     <br />
     Everyone subscribed to your list may send messages to everyone else 
     on your list by posting  messages to the <strong>List Email</strong>
     (below).
    </p>
  
  
  	 <table width="100%" cellspacing="0" cellpadding="5">
	<tr> 
   <td align="right">
    <input name="append_list_name_to_subject" id="append_list_name_to_subject" type="checkbox" value="1" <!--tmpl_if append_list_name_to_subject -->checked="checked"<!--/tmpl_if--> />
   </td>
   <td>  
    <p>
     <label for="append_discussion_lists_with">
      Append message subjects with the:
     </label>
     <br />
     <select name="append_discussion_lists_with">
      <option value="list_shortname" <!--tmpl_if expr="(append_discussion_lists_with eq 'list_shortname')" -->selected="selected" <!--/tmpl_if--> >list shortname (<!-- tmpl_var name="list" escape="HTML" -->)</option>
      <option value="list_name"      <!--tmpl_if expr="(append_discussion_lists_with eq 'list_name')" -->selected="selected" <!--/tmpl_if--> >List Name (<!-- tmpl_var name="list_name" escape="HTML" -->)</option>
     </select> 
     <br />
     The List Name/Short Name will be surrounded by square brackets. 
     
     <table>
      <tr> 
       <td>
           <input name="no_append_list_name_to_subject_in_archives" id="no_append_list_name_to_subject_in_archives" type="checkbox" value="1" <!--tmpl_if no_append_list_name_to_subject_in_archives -->checked="checked"<!--/tmpl_if--> />
       </td> 
       <td> 
        <label for="no_append_list_name_to_subject_in_archives">
         Do not append the list/list shortname to archived messages (only outgoing messages).  
        </label>
       </td> 
      </tr> 
     </table> 
    </p>
   </td>
  </tr>
  <tr> 
   <td align="right">
    <input name="add_reply_to" id="add_reply_to" type="checkbox" value="1" <!--tmpl_if add_reply_to -->checked="checked"<!--/tmpl_if--> />
   </td>
   <td>
    <label for="add_reply_to">
     Automatically have replies to messages directed to the group
    </label>
    <br />
     A 'Reply-To' header will be added to group list mailings that will direct 
     replies to list messages back to the list.
   </td>
  </tr>
   <tr> 
   <td align="right">
    <input name="mail_discussion_message_to_poster" id="mail_discussion_message_to_poster" type="checkbox" value="1" <!--tmpl_if mail_discussion_message_to_poster -->checked="checked"<!--/tmpl_if--> />
   </td>
   <td>
    <label for="mail_discussion_message_to_poster">
     Send message posters a copy of the message they've sent the discussion list. 
    </label>
    <br />
   </td>
  </tr>
  
  
  
     <tr> 
   <td align="right">
    <input name="set_to_header_to_list_address" id="set_to_header_to_list_address" type="checkbox" value="1" <!--tmpl_if set_to_header_to_list_address -->checked="checked"<!--/tmpl_if--> />
   </td>
   <td>
    <label for="set_to_header_to_list_address">
     Set the <strong>To:</strong> header of discussion list messages to the <strong>List Address</strong>, rather than the subscribers address.
     
     <!-- tmpl_unless can_use_set_to_header_to_list_address --> 
        <p class="error">Warning! Your current mailing backend does not support this feature.<br /> 
        Only the <strong>Net::SMTP</strong> SMTP engine and the <strong>sendmail</strong> command support this feature. 
     <!--/tmpl_unless --> 
     
    </label>
    <br />
   </td>
  </tr>
  
  <tr> 
   <td> 
    <input name="enable_moderation" id="enable_moderation" type="checkbox" value="1" <!--tmpl_if enable_moderation -->checked="checked"<!--/tmpl_if--> /> 
   </td>
   <td>
    <p>
     <label for="enable_moderation">
      Use Moderation
     </label>
     <br /> 
     
          Messages sent to your discussion list will have to be approved by the List Owner. 
      </p>
      
     
     <table  cellspacing="0" cellpadding="5">
      <tr>
       <td>
        <input name="send_moderation_rejection_msg" id="send_moderation_rejection_msg" type="checkbox" value="1" <!--tmpl_if send_moderation_rejection_msg -->checked="checked"<!--/tmpl_if--> />
       </td>
       <td>
        <p>
         <label for="send_moderation_rejection_msg">
          Send a Rejection Message
         </label><br /> 
         The original poster will receive a message stating that the message was rejected.
        </p>
       </td>
      </tr>
    </table> 
    
   </td>
  </tr>
 
 <!-- tmpl_if Allow_Open_Discussion_List -->
        <tr> 
       <td align="right">
        <input name="open_discussion_list" id="open_discussion_list" type="checkbox" value="1" <!--tmpl_if open_discussion_list -->checked="checked"<!--/tmpl_if--> />
       </td>
       <td>
        <label for="open_discussion_list">
         Allow messages to be posted to the list from non-subscribers. 
        </label>
        <br />
       </td>
      </tr>
 <!-- /tmpl_if -->  
  
  
  
	</table>
  
  </td>
  </tr>
  
  
  
 </table> 


</fieldset> 



<fieldset> 
 <legend> 
 Message Routing
 </legend> 

 <table width="100%" cellspacing="0" cellpadding="5">
  <tr> 
   <td> 
    <p>
     <label>
      Messages from addresses that are <em>allowed</em> to post to this list should:
     </label>
    </p>
    <table>
     <tr>
      <td> 
       <input type="checkbox" name="send_msgs_to_list" id="send_msgs_to_list" value="1" <!-- tmpl_if send_msgs_to_list -->checked="checked"<!--/tmpl_if--> />
      </td> 
      <td>
       <label for="send_msgs_to_list">
        be sent to the Subscription List.
       </label>
      </td>
     </tr> 
     <tr> 
      <td>
       <input type="checkbox" name="send_msg_copy_to" id="send_msg_copy_to" value="1" <!-- tmpl_if send_msg_copy_to -->checked="checked"<!--/tmpl_if--> />
      </td>
      <td>
       <label for="send_msg_copy_to">
        have a copy of the original message forwarded <label for="send_msg_copy_address">to</label>:
       </label>
       <p>
        <input type="text" name="send_msg_copy_address" id="send_msg_copy_address"value="<!-- tmpl_var send_msg_copy_address -->" />
       </p>
      </td> 
     </tr> 
     <tr> 
      <td>
		&nbsp;
      </td>
      <td>
       <p>
        <!-- tmpl_if archive_messages --> 
         <p class="positive"> 
         * Archiving is Enabled.
         </p>
        <!--/tmpl_if-->
       </p>
      </td> 
     </tr> 
    </table> 
   </td>
  </tr>
  <tr> 
  
  
  
  
   <td> 
    <p>
     <label>
      Message from addresses <em>not allowed</em> to post to this list should:
     </label>
    </p>
    <table> 
     <tr>
      <td> 
       <input type="checkbox" name="send_invalid_msgs_to_owner" id="send_invalid_msgs_to_owner" value="1" <!-- tmpl_if send_invalid_msgs_to_owner -->checked="checked"<!--/tmpl_if--> />
      </td> 
      <td>
       <label for="send_invalid_msgs_to_owner">
        send the list owner a &quot;Not a Subscriber&quot; email message, with original message attached.
       </label>
      </td>
     </tr> 
     
     <!--
     <tr> 
      <td>
       <input type="checkbox" />
      </td>
      <td>
       be forwarded to the Authorized Senders (Authorized Sending must be turned on!).
      </td> 
     </tr>
     --> 
     
     <tr> 
      <td> 
       <input type="checkbox" name="send_not_allowed_to_post_msg" id="send_not_allowed_to_post_msg" value="1" <!-- tmpl_if send_not_allowed_to_post_msg -->checked="checked"<!--/tmpl_if--> />
      </td> 
      <td> 
       <label for="send_not_allowed_to_post_msg">
        send back a &quot;Not Allowed to Post&quot; message.
       </label>
      </td>  
     </tr> 
    </table> 
   </td> 
  </tr>
 </table>
 
 </fieldset> 



<fieldset> 
 <legend> 
Mailing List Security
</legend> 
 


   <table>


   <tr>
      <td> 
       <input type="checkbox" name="ignore_spam_messages" id="ignore_spam_messages" value="1" <!-- tmpl_if ignore_spam_messages -->checked="checked"<!--/tmpl_if--> />
      </td> 
      <td>
       <label for="ignore_spam_messages">
        Ignore messages labeled as, &quot;SPAM&quot; by SpamAssassin filters. 
       </label></p> 
      
       
        <!-- tmpl_unless can_use_spam_assassin --> 
          <p class="error">* SpamAssassin may not be installed on your server.</p>
        <!--/tmpl_unless--> 
      
        <p>Find SpamAssassin Score By: 
        <table border="0"> 
         <tr> 
          <td><input type="radio" id="looking_for_embedded_headers" name="find_spam_assassin_score_by" value="looking_for_embedded_headers" <!-- tmpl_if find_spam_assassin_score_by_looking_for_embedded_headers -->checked="checked"<!--/tmpl_if--> /></td>
          <td>
           <p>
            <label for="looking_for_embedded_headers">
            Look for the embedded SpamAssassin Headers (Fast! But may not be available)
            </label> 
           </p>
          </td>
         </tr>
         
         <tr> 
          <td><input type="radio" id="calling_spamassassin_directly" name="find_spam_assassin_score_by" value="calling_spamassassin_directly" <!-- tmpl_if find_spam_assassin_score_by_calling_spamassassin_directly -->checked="checked"<!--/tmpl_if--> /></td>
          <td>
           <p>
            <label for="calling_spamassassin_directly">
            Use the SpamAssassin Modules directly (Slow, resource-intensive)
            </label> 
           </p>
          </td>
         </tr>
         
         <!-- 
         
         <tr> 
          <td><input type="radio" disabled="disabled" /></td>
          <td>
           <p>
            <label> 
             Use the spamd daemon (not currently supported)
            </label>
           </p>
          </td>
         </tr>
         
         --> 
         
        </table> 
      
       <p> 
        Messages must reach a SpamAssassin level of at least: <!-- tmpl_var spam_level_popup_menu --> to be considered SPAM.
       </p> 

      </td>
     </tr> 


     
     <tr>
      <td> 
      
 <input type="checkbox" name="strip_file_attachments" id="strip_file_attachments" value="1" <!-- tmpl_if strip_file_attachments -->checked="checked"<!--/tmpl_if--> />
 
 </td>
 <td>
 <p>
 <label for="strip_file_attachments">Strip attachments that have the following file ending or mime-type:</label> <em>(separated by spaces)</em>
	 <br />
	 
         <input type="text" name="file_attachments_to_strip" id="file_attachments_to_strip"value="<!-- tmpl_var file_attachments_to_strip -->" class="full" />

  </p>
 </td>
 </tr>
 </table> 
 
 
 </fieldset> 
 
 
   
 <input name="flavor"  type="hidden" value="cgi_default" />
 <input name="process" type="hidden" value="edit" />
 <div class="buttonfloat"> 
  <input type="reset"  class="cautionary" value="Clear Changes" />
  <input type="submit" class="processing" value="Save Changes" />
 </div> 
 <div class="floatclear"></div> 
 
 
</form>



<fieldset> 

<legend>Manually Run <!-- tmpl_var Plugin_Name --></legend>


 <div class="buttonfloat">


<form method="get" style="display:inline">
 <input name="flavor" type="hidden" value="test_pop3" />
  <input type="submit" class="cautionary" value="Test Saved POP3 Login Information..." />
</form> 



<form method="get" style="display:inline">
 <input name="flavor" type="hidden" value="manual_start" />
  <input type="submit" class="cautionary" value="Manually Check and Send Waiting Messages..." />

</form> 

 </div> 
 <div class="floatclear"></div> 



<p>
 <label for="cronjob_url">Manual Run URL:</label><br /> 
<input type="text" class="full" id="cronjob_url" value="<!-- tmpl_var Plugin_URL -->?run=1&passcode=<!-- tmpl_var Manual_Run_Passcode -->" />
</p>



<p> <label for="cronjob_command">curl command example (for a cronjob):</label><br /> 
<input type="text" class="full" id="cronjob_command" value="<!-- tmpl_var name="curl_location" default="/cannot/find/curl" -->  -s --get --data run=1\;passcode=<!-- tmpl_var Manual_Run_Passcode -->\;verbose=0  --url <!-- tmpl_var Plugin_URL -->" />
<!-- tmpl_unless curl_location --> 
	<span class="error">Can't find the location to curl!</span><br />
<!-- /tmpl_unless --> 

<!-- tmpl_unless Allow_Manual_Run --> 
    <span class="error">(Currently disabled)</a>
<!-- /tmpl_unless --> 

</p>



</fieldset> 



<fieldset> 
<legend><!-- tmpl_var Plugin_Name --> Configuration</legend>

 <div class="buttonfloat"> 
 <form action="<!-- tmpl_var Plugin_URL -->"> 
  <input type="hidden" name="flavor" value="cgi_show_plugin_config" /> 
  <input type="submit" value="View All Plugin Configurations..." class="cautionary" /> 
 </form> 
 </div> 

<div class="floatclear"></div> 


</fieldset> 


};

}


END { 
	
	if(defined ($parser)){ 
		$parser->filer->purge;
	}
}

package SimpleModeration;

use strict; 

use Carp qw(croak carp);
use DADA::Config qw(!:DEFAULT);
use DADA::App::Guts qw(!:DEFAULT); 
use MIME::Entity;

sub new { 
	my $class = shift;
	my $self = {@_};
	bless $self, $class;  


    my ($args) = @_;
    
    if ( !$args->{-List} ) {
        carp
            "You need to supply a list ->new({-List => your_list}) in the constructor.";
        return undef;
    }
    else {
    
        $self->{list} = $args->{-List}; 
    }
    
    
    $self->init; 
    
	return $self;

}

sub init { 

    my $self = shift; 
    $self->check_moderation_dir(); 

}




sub check_moderation_dir { 

        # Basically, just makes the tmp directory that we need...
        
        my $self = shift; 
        if(-d $self->mod_dir){ 
            # Well, ok!
        } else { 
        
            croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER warning! Could not create, '" . $self->mod_dir . "'- $!" 
			    unless mkdir ($self->mod_dir, $DADA::Config::DIR_CHMOD );
			    
            chmod($DADA::Config::DIR_CHMOD, $self->mod_dir)
			    if -d $self->mod_dir; 
        }
}




sub  awaiting_msgs { 

    my $self = shift; 
    my $pattern = quotemeta($self->{list} . '-'); 
    my @awaiting_msgs; 
    my %allfiles; 
    
    if(opendir(MOD_MSGS, $self->mod_dir)){ 

        %allfiles = map { $_ , (stat($_))[9]} readdir(MOD_MSGS);
			
        closedir(MOD_MSGS) 
            or carp "couldn't close: " . $self->mod_dir; 
            
        foreach my $key (sort $allfiles{$a} <=> $allfiles{$b}, keys %allfiles) {
        
            next if($key =~ /^\.\.?$/); 
            
            $key  =~ s(^.*/)();
            if($key =~ m/$pattern/){  
                push(@awaiting_msgs, $key); 
            }
        
        }
        
    }else{
		carp "could not open " . $self->mod_dir . " $!"; 
	}
	
	return [@awaiting_msgs]; 
	
}




sub save_msg { 

    my $self = shift; 
    my ($args) = @_;

    if(!$args->{-msg}){ 
        croak "You must supply a message!"; 
    }
    
    if(!$args->{-msg_id}){ 
        croak "You must supply a message id!"; 
    }    
    
    my $file = $self->mod_msg_filename($args->{-msg_id}); 
    
    open my $MSG_FILE, '>', $file
        or croak "Cannot write saved raw message at: '" . $file . " because: $!";
    
    print $MSG_FILE $args->{-msg}; 
    
    close($MSG_FILE)
        or croak "Coulnd't close: " . $file . "because: " . $!;

}



sub moderation_msg { 
    
    my $self = shift; 
    my ($args) = @_;
    
    
    if(!$args->{-msg}){ 
        croak "You must supply a message!"; 
    }
    
    if(!$args->{-msg_id}){ 
        croak "You must supply a message id!"; 
    }
    $args->{-msg_id} =~ s/\@/_at_/g;
    $args->{-msg_id} =~ s/\>|\<//g;
    $args->{-msg_id} = DADA::App::Guts::strip($args->{-msg_id});
    
    
    if(!$args->{-from}){ 
        croak "You must supply a from!"; 
    }
    
    if(!$args->{-parser}){ 
        croak "You must supply a parser!"; 
    }
    
    require DADA::MailingList::Settings; 
    my $ls = DADA::MailingList::Settings->new({-list => $self->{list}}); 
    my $li = $ls->get; 
    
    

    
    my $parser = $args->{-parser};
    my $entity = $parser->parse_data($args->{-msg});
  

    my $reply = MIME::Entity->build(
		Type 	=> "multipart/mixed", 
		Subject => $Moderation_Msg_Subject, 
		To      => $ls->param('list_owner_email'), 							
	);	
	$reply->attach(
		Type => 'text/plain', 
		Data  => $Moderation_Msg, 
	); 	
	$reply->attach(
		Type        => 'message/rfc822', 
		Disposition  => "inline",
		Data         => $entity->as_string,
	); 
	
	my $confirmation_link = $Plugin_Config->{Plugin_URL} . '?flavor=mod&list=' . $self->{list} . '&process=confirm&msg_id=' . $args->{-msg_id};
   	my $deny_link         = $Plugin_Config->{Plugin_URL} . '?flavor=mod&list=' . $self->{list} . '&process=deny&msg_id='    . $args->{-msg_id};
		
		 
			
    require DADA::App::Messages; 						
	DADA::App::Messages::send_generic_email(
		{
			-list    => $self->{list}, 
			-headers => {
				DADA::App::Messages::_mime_headers_from_string($reply->stringify_header),
			},
			-body =>  $reply->stringify_body, 
			-tmpl_params => { 
				-list_settings_vars        => $li, 
				-list_settings_vars_param => 
					{
						-dot_it => 1, 	
					},
				#-subscriber_vars =>
				#	{
				#		#'subscriber.email' =>  $args->{-from}, 
				#	},
			  	-vars => 
					{ 
						moderation_confirmation_link => $confirmation_link, 
						moderation_deny_link         => $deny_link, 
						message_subject              => $args->{-subject},
						msg_id                       => $args->{-msg_id},
						'subscriber.email'           =>  $args->{-from}, 

					}
				},
			}
		);
}




sub send_reject_msg { 
    
    my $self = shift; 
    my ($args) = @_;
    
    if(!$args->{-msg_id}){ 
        croak "You must supply a message id!"; 
    }
    $args->{-msg_id} =~ s/\@/_at_/g;
    $args->{-msg_id} =~ s/\>|\<//g;
    $args->{-msg_id} = DADA::App::Guts::strip($args->{-msg_id});
       
    if(!$args->{-parser}){ 
        croak "You must supply a parser!"; 
    }

	# DEV there are two instances of my $parser, and my $entity of them - which one is the correct one? 

    my $parser = $args->{-parser}; 

    my $entity; 
	eval { $entity = $parser->parse_data(
	                                     $self->get_msg(
	                                                    {
	                                                     -msg_id => $args->{-msg_id} 
	                                                    }
	                                                   )
	                                   ); 
	                                    
	     };
	if(!$entity){
		croak "no entity found! die'ing!";   
	}


    my $subject     = $entity->head->get('Subject', 0); 
	   $subject =~ s/\n//g; 
	my $from        = $entity->head->get('From', 0);
	   $from =~ s/\n//g;
	   
    require DADA::MailingList::Settings; 
    my $ls = DADA::MailingList::Settings->new({-list => $self->{list}}); 
    my $li = $ls->get; 
    
    my $reply = MIME::Entity->build(
		Type 	 => "text/plain", 
		To       => $from,
		Subject  => $Rejection_Message_Subject, 	
		Data     => $Rejection_Message, 
	);

	  require DADA::App::Messages; 						
	DADA::App::Messages::send_generic_email(
		{
			-list    => $self->{list}, 
			-headers => {
				DADA::App::Messages::_mime_headers_from_string($reply->stringify_header), 
			},
		-body =>  $reply->stringify_body, 
		-tmpl_params => { 
			-list_settings_vars        => $li, 
			-list_settings_vars_param => 
				{
					-dot_it => 1, 	
				},
			-subscriber_vars =>
				{
					'subscriber.email' =>  $args->{-from}, 

				},
		  	-vars => 
				{ 
			
					message_subject              => $args->{-subject},
					message_from                 => $args->{-from},
					msg_id                       => $args->{-msg_id},
					Plugin_Name                 => $Plugin_Config->{Plugin_Name}, 
				
				}
			},
		}
	);
 }






sub is_moderated_msg { 

    my $self = shift; 
    my $msg_id = shift; 
    
        print '<pre>' ;
        print "looking for:\n"; 
        print $self->mod_msg_filename($msg_id) . "\n"; 
        print '</pre>'; 
        
    if(-e $self->mod_msg_filename($msg_id)){ 
        return 1; 
    } else {
        return 0; 
    }

}




sub get_msg { 

    my $self   = shift; 
    my ($args) = @_;
    
    if(! $args->{-msg_id}){ 
        croak "You must supply a message id!"; 
    }    
    
    my $file = $self->mod_msg_filename($args->{-msg_id}); 

    if(! -e $file){ 
    
        croak "Message: $file doesn't exist?!"; 
  
    } 
    else { 
    
        open my $MSG_FILE, '<', $file
            or die "Cannot read saved raw message at: '" . $file
            . "' because: "
            . $!;


            my     $msg = do { local $/; <$MSG_FILE> };
            

        close $MSG_FILE
            or die "Didn't close: '" . $file . "'properly because: " . $!;

        return $msg; 
        
    }
    
    
    

}



sub remove_msg { 

    my $self   = shift; 
    my ($args) = @_;
    
    if(! $args->{-msg_id}){ 
        croak "You must supply a message id!"; 
    }    
    
    my $file = $self->mod_msg_filename($args->{-msg_id}); 


    if(-e $file){ 
    
        my $count = unlink($file); 
        if($count != 1){ 
            carp "Weird file delete count is: $count - should be, '1'";     
        }
    }else{ 
        carp "no file at: $file to delete!"; 
    }
    
    return 1; 
    
}




sub mod_msg_filename { 

    my $self = shift; 
    my $message_id = shift; 
    
    $message_id =~ s/\@/_at_/g;
    $message_id =~ s/\>|\<//g;
    $message_id = DADA::App::Guts::strip($message_id);

    return $self->mod_dir . '/' . $self->{list} . '-' . $message_id; 
    
}



sub mod_dir { 

    my $self = shift; 
    
    return $DADA::Config::TMP . '/moderated_msgs'; 

}






=pod

=head1 NAME 

Dada Bridge Announce-only and Discussion List Bridge from your mail client to Dada Mail. 

=head1 Obtaining The Plugin

Dada Bridge is located in the, I<dada/plugins> directory of the Dada Mail distribution, under the name: I<dada_bridge.pl>

=head1 DESCRIPTION 

Dada Bridge is a program created to allow the support of sending email from your mail reader to a Dada Mail list, both for announce-only tasks and discussion lists.

=head1 Intended Audience

Before I get asked the inevitable question, "why did you reinvent another wheel?", here's my response: 

dada_bridge.pl, along with Dada Mail is not meant to be a replacement for similar systems, such as Mailman or Majordomo. dada_bridge.pl is a much simpler program with far fewer features then either of these two programs. 

As with most of Dada Mail, the primary goals are usability and... well - style! 

dada_bridge.pl I<does> solve a few problems with trying to use similar programs  - 

=over

=item * You do NOT need root access to the server to install the program, or setup the list address

=item * You do NOT need to use an alias to a script to use dada_bridge.pl

=back

Having solved these two problems also makes dada_bridge.pl potentially more secure to use and opens its use to a wider audience. 

=head1 How does dada_bridge.pl work?

Many of dada_bridge.pl's concepts are slightly different than what you may be used to in traditional mailing lists: 


=over

=item * Subscription/Unsubscription requests are handled via Dada Mail itself

In other words, it's all web-based. There are currently no subscription mechanisms that use email commands. 


=item *  A, "List Email" is just a POP3 email account. 

In Dada Mail, a "List Email" is the address you send to when you want to post a message to the list. This differs from the "List Owner" email, which is the address that messages will be sent on behalf of (unless discussion lists are enabled). 

Usually, in a mailing list manager, this address is created automatically by the program itself: not so in Dada Mail - you'll have to manually create the email  (POP3) account and plug in the email, pop3 server and username/password into Dada Mail.

This sounds like a step I<backward>, but it allows anyone who can make POP3 accounts to have a discussion mailing list. You also have a whole lot of flexibility when it comes to what the List Email can be. 

In normal use, dada_bridge.pl will check this account and route any messages it finds accordingly. When in normal use, do not check this account yourself. 

=back

Saying all this, dada_bridge.pl's niche is probably with small to medium sized lists. This program has not been tested with lists larger than a few hundred, so your mileage may vary. 

The other thing you may want to take into consideration is the lack of proper threading in Dada Mail's web-based archives. At the moment, archives are only sorted by date. 

This may/may not be a deal breaker, but also take into consideration that the displaying of complex email messages is usually actually I<better> in Dada Mail than most other mail archive viewing programs. 

One more thing to take into consideration is that there is currently no filter in place to reject messages based on size or type. There is a way currently to strip messages with attachments of a certain file ending or mime-type. 

These two issues may be at least partly worked around using the preferences of your POP email account. Many services will at least allow you to set a per-mailbox limit, or even a per-message limit for size. 

As for content, Dada Mail is currently completely MIME-aware and will accept anything it can parse, which means, multipart messages, attachments, inline embedded images - the works. 

For a stopgap solution to the last issues, you may look into a mail filtering program like Procmail, which can be configured to death. 

=head1 REQUIREMENTS

=over

=item * Familiarity with setting cron jobs

If you do not know how to set up a cron job, attempting to set one up for Dada Bridge will result in much aggravation. Please read up on the topic before attempting!

=item * a free POP3 account for each list. 

=item * Ability to set cron jobs

=back 

=head1 RECOMMENDATIONS

=over

=item * Shell Access to Your Hosting Account

Shell Access is sometimes required to set up a cronjob, using the:

 crontab -e

command. You may also be able to set up a cron tab using a web-based control panel tool, like Cpanel.

Shell access also facilitates testing of the program.

=item * Use the *SQL backend for Archives

if not for subscribers as well. 

Multipart messages, attachments and inline embedded images will work very well if you use the *SQL backend for Archives. They may not work at all if you don't. 

Since you don't have any control over the type of messages being sent using dada_bridge.pl, I would use the *SQL backend for Archives. 

For the same reason, I also and cannot stress enough that you check,

B<Disable Embedded JavaScript in Archived Messages>

In Dada Mail's List control panel under, I<Manage Archives - Archive Options - Advanced>. This will prevent exploitations embedded in messages sent to the list when viewed in Dada Mail's own archives. Along with Javascript, this option will strip out: embed, object, frame, iframe, and meta tags. 

This feature does require the use of a CPAN module called, B<HTML::Scrubber>, which you may have to install yourself. 

If you do not have this available, I do urgently suggest you do not use archiving for B<discussion> lists. 

=back


=head1 Lightning Configuration/Installation Instructions

To get to the point:

=over 

=item * Upload the dada_bridge.pl script into the cgi-bin/dada/plugins directory (if it's not already there) 

=item * chmod 755 the dada_bridge.pl script

=item * run the plugin via a web browser.

=item * Set the cronjob

=back

Below is the detailed version of the above:


=head1 INSTALLATION

Before we get into installation, here's how Dada Bridge is used: 

One part of Dada Bridge is run as a Dada Mail plugin - you'll have to log into your list before you're able to make any changes to its settings. 

The second part of Dada Bridge is the part that actually looks for any new mail to be examined and hopefully, broadcasted and sent out to your list. This part of Dada Bridge is usually run via a cronjob.  

There's a few ways that Dada Bridge can do the second part, and we'll go in detail on how to set up both ways. 

=head2 Configuring dada_bridge.pl's Plugin Side

=head2 #1 Upload into the plugins directory

We're assuming your cgi-bin looks like this: 

 /home/account/cgi-bin/dada

and inside the I<dada> directory is the I<mail.cgi> file and the I<DADA> (uppercase) directory. Make a B<new> directory in the I<dada> directory called, B<plugins> (if it's not already there). 

If not already there, upload your copy of I<dada_bridge.pl> into that B<plugins> directory. chmod 755 dada_bridge.pl 

=head2 #2 Configure the Config.pm file

This plugin will give you a new menu item in your list control panel. Tell Dada Mail to make this menu item by tweaking the Config.pm file. Find these lines in the Config.pm file: 

 #					{-Title      => 'Discussion Lists',
 #					 -Title_URL  => $PLUGIN_URL."/dada_bridge.pl",
 #					 -Function   => 'dada_bridge',
 #					 -Activated  => 1,
 #					},

Uncomment it (take off the "#"'s) 

Save the Config.pm file. 

You're basically done configurating the Dada Bridge plugin. 


You can now log into your List Control Panel and under the, B<plugins> heading you should now see a linked entitled, "Discussion lists". Clicking that will allow you to set up your list to receive mail from a mail reader. 

Messages will not yet be received and sent out via Dada Bridge.

For that to happen - two things will have to be configured. The first is setting up the B<List Email> - that's done in the control panel for the plugin itself and should (hopefully) be self-explanitory. 

The second is to set up the cronjob and that's what we'll talk about next: 

=head1 Configurating the Cronjob to Automatically Run Dada Bridge

We're going to assume that you already know how to set up the actual cronjob, but we'll be explaining in depth on what the cronjob you need to set is.

=head2 Setting the cronjob

Generally, setting the cronjob to have Dada Bridge run automatically just means that you have to have a cronjob access a specific URL. The URL looks something like this:

 http://example.com/cgi-bin/dada/plugins/dada_bridge.pl?run=1&verbose=1

Where, I<http://example.com/cgi-bin/dada/plugins/dada_bridge.pl> is the URL to your copy of dada_bridge.pl

You'll see the specific URL used for your installation of Dada Mail in the web-based control panel for Dada Bridge, under the fieldset legend, Manually Run Dada Bridge. under the heading, Manual Run URL:

This will have Dada Bridge check any awaiting messages.

You may have to look through your hosting account's own FAQ, Knowledgebase and/or other docs to see exactly how you invoke a URL via a cronjob.

A Pretty Good Guess of what the entire cronjob should be set to is located in the web-based crontrol panel for Dada Bridge, under the fieldset legend, B<Manually Run Dada Bridge>, under the heading, B<curl command example (for a cronjob)>:

From my testing, this should work for most Cpanel-based hosting accounts.

Here's the entire thing explained:

In all these examples, I'll be running the script every 5 minutes ( */5 * * * * ) - tailor to your taste.

=over

=item * Using Curl:

 */5 * * * * /usr/local/bin/curl -s --get --data run=1 --url http://example.com/cgi-bin/dada/plugins/dada_bridge.pl

=item * Using Curl, a few more options (we'll cover those in just a bit):

 */5 * * * * /usr/local/bin/curl -s --get --data run=1\;verbose=0\;test=0 --url http://example.com/cgi-bin/dada/plugins/dada_bridge.pl

=back

=head3 $Plugin_Config->{Allow_Manual_Run}

If you DO NOT want to use this way of invoking the program to check awaiting messages and send them out, make sure to change the variable, $Plugin_Config-{Allow_Manual_Run}> to, 0:

 $Plugin_Config->{Allow_Manual_Run}    = 0;

at the top of the dada_bridge.pl script. If this variable is not set to, 1 this method will not work.

=head2 Security Concerns and $Plugin_Config->{Manual_Run_Passcode}

Running the plugin like this is somewhat risky, as you're allowing an anonymous web browser to run the script in a way that was originally designed to only be run either after successfully logging into the list control panel, or, when invoking this script via the command line.

If you'd like, you can set up a simple Passcode, to have some semblence of security over who runs the program. Do this by setting the, C<$Plugin_Config-{Manual_Run_Passcode}> variable in the dada_bridge.pl source itself.

If you set the variable like so:

    $Plugin_Config->{Manual_Run_Passcode} = 'sneaky';

You'll then have to change the URL in these examples to:

 http://example.com/cgi-bin/dada/plugins/dada_bridge.pl?run=1&passcode=sneaky

=head3 Other options you may pass

You can control quite a few things by setting variables right in the query string:

=over

=item * passcode

As mentioned above, the C<$Plugin_Config-{Manual_Run_Passcode}> allows you to set some sort of security while running in this mode. Passing the actual password is done in the query string:

 http://example.com/cgi-bin/dada/plugins/dada_bridge.pl?run=1&passcode=sneaky

=item * verbose

By default, you'll receive the a report of how Dada Bridge is doing downloading awaiting messages, validating them and sending them off. 

This is sometimes not so desired, especially in a cron environment, since all this informaiton will be emailed to you (or someone) everytime the script is run. You can run Dada Bridge with a cron that looks like this:

 */5 * * * * /usr/local/bin/curl -s --get --data run=1 --url http://example.com/cgi-bin/dada/plugins/dada_bridge.pl >/dev/null 2>&1

The, >/dev/null 2>&1 line throws away any values returned.

Since all the information being returned from the program is done sort of indirectly, this also means that any problems actually running the program will also be thrown away.

If you set verbose to, ``0'', under normal operation, Dada Bridge won't show any output, but if there's a server error, you'll receive an email about it. This is probably a good thing. Example:

 * * * * * /usr/local/bin/curl -s --get --data run=1\;verbose=0 --url http://example.com/cgi-bin/dada/plugins/dada_bridge.pl

=item * test

Runs Dada Bridge in test mode by checking the messages awaiting and parsing them, but not actually carrying out any sending. 

=back 

=head3 Notes on Setting the Cronjob for curl

You may want to check your version of curl and see if there's a speific way to pass a query string. For example, this:

 */5 * * * * /usr/local/bin/curl -s http://example.com/cgi-bin/dada/plugins/dada_bridge.pl?run=1&passcode=sneaky

Doesn't work for me.

I have to use the --get and --data flags, like this:

 */5 * * * * /usr/local/bin/curl -s --get --data run=1\;passcode=sneaky --url http://example.com/cgi-bin/dada/plugins/dada_bridge.pl

my query string is this part:

 run=1\;passcode=sneaky

And also note I had to escape the, ; character. You'll probably have to do the same for the & character.

Finally, I also had to pass the actual URL of the plugin using the --url flag.

=head1 Command Line Interface

There's a slew of optional arguments you can give to this script. To use Dada Bridge via the command line, first change into the directory that Dada Bridge resides in, and issue the command:

 ./dada_bridge.pl --help

=head2 Command Line Interface for Cronjobs: 

One reason that the web-based way of running the cronjob is better, is that it 
doesn't involve reconfiguring the plugin, every time you upgrade. This makes 
the web-based invoking a bit more convenient. 

=head2 #1 Change the lib path

You'll need to explicitly state where both the:

=over

=item * Absolute Path to the site-wide Perl libraries

=item * Absolute Path of the local Dada Mail libraries

=back

I'm going to rush through this, since if you want to run Dada Bridge this way
you probably know the terminology, but: 

This script will be running in a different environment and from a different location than what you'd run it as, when you visit it in a web-browser. It's annoying, but one of the things you have to do when running a command line script via a cronjob. 

As an example: C<use lib qw()> lines probably look like: 

 use lib qw(
 
 ../ 
 ../DADA/perllib 
 ../../../../perl 
 ../../../../perllib 
 
 );


To this list, you'll want to append your site-wide Perl Libraries and the 
path to the Dada Mail libraries. 

If you don't know where your site-wide Perl libraries are, try running this via the command line:

 perl -e 'print $_ ."\n" foreach @INC'; 

If you do not know how to run the above command, visit your Dada Mail in a web browser, log into your list and on the left hand menu and: click, B<About Dada Mail> 

Under B<Script Information>, click the, B< +/- More Information> link and under the, B<Perl Library Locations>, select each point that begins with a, "/" and use those as your site-wide path to your perl libraries. 

=head2 #2 Set the cron job 

Cron Jobs are scheduled tasks. We're going to set a cron job to test for new messages every 5 minutes. Here's an example cron tab: 

  */5  *  *  *  * /usr/bin/perl /home/myaccount/cgi-bin/dada/plugins/dada_bridge.pl >/dev/null 2>&1

Where, I</home/myaccount/cgi-bin/dada/plugins/dada_bridge.pl> is the full path to the script we just configured. 

=head1 Remember to enable sending using this method! 

By default, the ability for dada_bridge.pl to send and receive messages is disabled on a per-list basis. To enable sending, log into your list control panel and go to the dada_bridge.pl admin screen. 

Uncheck: 

 Disable sending using this method 

And you're off to the races. 

=head1 Misc. Options

=head2 $Plugin_Config->{Plugin_URL}

Sometimes, the plugin has a hard time guessing what its own URL is. If this is happening, you can manually set the URL of the plugin in B<$Plugin_Config->{Plugin_URL}>

=head2 $Plugin_Config->{Allow_Manual_Run}

Allows you to invoke the plugin to check and send awaiting messages via a URL. See, "The Easy Way" cronjob setting up docs, above. 

=head2 $Plugin_Config->{Manual_Run_Passcode}

Allows you to set a passcode if you want to allow manually running the plugin. See, "Tehe Easy Way" cronjob setting up docs, above. 

=head2 $Plugin_Config->{MessagesAtOnce}

You can specificy how many messages you want to have the program actually handle per execution of the script by changing the, B<$Plugin_Config->{MessagesAtOnce}> variable in the source of the script itself. By default, it's set conservatively to, B<1>.

=head2 $Plugin_Config->{Max_Size_Of_Any_Message}

Sets a hard limit on how large a single message can actually be, before you won't allow the message to be processed. If a message is too large, it'll be simple deleted. A warning will be written in the error log, but the original sender will not be notified. 

=head2 $Moderation_Msg

The text of the email message that gets sent out to the list owner, when they receive an email message that requires moderation. 

=head2 $Rejection_Message

The text of the email message that gets sent out to the subscriber who has a email message sent to the list that was rejected during moderation. 

=head1 DEBUGGING 

This plugin, much more so than the main Dada Mail program is a bit finicky, since you have to rely on getting a successful connection to your POP3 server and also be able to run the program via a cronjob. 

=head2 Debugging your POP3 account information

The easiest way to debug your POP3 account info is to actually test it out. 

If you have a command line, drop into it and connect to your POP3 server, like so: 

 prompt:]telnet pop3.example.com 110
 Trying 12.123.123.123...
 Connected to pop3.example.com.
 Escape character is '^]'.
 +OK <37892.1178250885@hedwig.summersault.com>
 user user%example.com
 +OK 
 pass sneaky
 +OK 
 list

In the above example, B<pop3.example.com> is your POP3 server. You'll be typing in: 

  user user%example.com

and: 

  pass sneaky

(changing them to their real values) when prompted. This is basically what dada_bridge.pl does itself. 

If you don't have a command line, try adding an account in a desktop mail reader. If these credentials work there, they'll most likely work for dada_bridge.pl. 

If your account information is correct and also logs in when you test the pop3 login information through dada_bridge.pl yourself, check to see if there isn't an email filter attached the account that looks at messages before they're delivered to the POP3 Mailbox and outright deletes messages because it triggered a flag. 

This could be the cause of mysterious occurences of messages never reaching the POP3 Mailbox. 

=head1 COPYRIGHT

Copyright (c) 2004 - 2008 Justin Simoni

All rights reserved.


=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=cut
