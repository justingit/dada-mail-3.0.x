#!/usr/bin/perl -w
use strict; 

use lib qw(./t ./ ./DADA/perllib ../ ../DADA/perllib ../../ ../../DADA/perllib ); 
BEGIN{$ENV{NO_DADA_MAIL_CONFIG_IMPORT} = 1}
use dada_test_config; 

use Test::More qw(no_plan);  


my ($entity, $filename, $t_msg); 


use DADA::Config; 
use DADA::App::FormatMessages; 

use DADA::MailingList::Subscribers; 
use DADA::MailingList::Settings; 


my $list = dada_test_config::create_test_list;
my $ls   = DADA::MailingList::Settings->new({-list => $list}); 
my $li   = $ls->get;
my $fm = DADA::App::FormatMessages->new(-yeah_no_list => 1); 

$filename = 't/corpus/email_messages/simple_template.txt';
open my $MSG, '<', $filename or die $!; 
my $msg1 = do { local $/; <$MSG> }  or die $!; 
close $MSG  or die $!; 

### get_entity 


$entity = $fm->get_entity(
    {
        -data => $msg1,
    }
);
ok($entity->isa('MIME::Entity'));

undef $entity; 

$entity = $fm->get_entity(
    {
        -data          => $filename,
        -parser_params => {-input_mechanism => 'parse_open'},
    }
);

ok($entity->isa('MIME::Entity'));

###/ get_entity



### email_template
my $new_entity; 


$entity = $fm->email_template({-entity => $entity});
ok($entity->isa('MIME::Entity'));
undef $entity; 





$entity = $fm->get_entity(
    {
        -data => $msg1,
    }
);
ok($entity->isa('MIME::Entity'));
$entity = $fm->email_template(
    {
        -entity => $entity,
        -vars   => {
                    from_phrase => 'From Phrase',
                    to_phrase   => 'To Phrase', 
                    subject     => 'This is the subject', 
                    var1        => 'Variable 1', 
                    var2        => 'Variable 2', 
                    var3        => 'Variable 3', 
                    },
    }
);
ok($entity->isa('MIME::Entity'));

$t_msg = $entity->as_string; 

like($t_msg, qr/Subject: This is the subject/); 
like($t_msg, qr/From: "From Phrase" <from\@example.com/);
like($t_msg, qr/To: "To Phrase" <to\@example.com>/); 
like($t_msg, qr/Var1: Variable 1/); 
like($t_msg, qr/Var2: Variable 2/);
like($t_msg, qr/Var3: Variable 3/);
undef $t_msg; 
undef $entity;
undef $filename; 

### / email_template



# Multipart/Alternative Message...
$filename = 't/corpus/email_messages/multipart_alternative_template.txt';
$entity = $fm->get_entity(
    {
        -data          => $filename,
        -parser_params => {-input_mechanism => 'parse_open'},
    }
);

ok($entity->isa('MIME::Entity'));

###/ get_entity

$entity = $fm->email_template(
    {
        -entity => $entity,
        -vars   => {
                    from_phrase => 'From Phrase',
                    to_phrase   => 'To Phrase', 
                    subject     => 'This is the subject', 
                    var1        => 'Variable 1', 
                    var2        => 'Variable 2', 
                    var3        => 'Variable 3', 
                    },
    }
);
ok($entity->isa('MIME::Entity'));

$t_msg = $entity->as_string; 

like($t_msg, qr/Subject: This is the subject/); 
like($t_msg, qr/From: "From Phrase" <from\@example.com/);
like($t_msg, qr/To: "To Phrase" <to\@example.com>/); 
like($t_msg, qr/Var1: Variable 1/); 
like($t_msg, qr/Var2: Variable 2/);
like($t_msg, qr/Var3: Variable 3/);
like($t_msg, qr/<p>Var1: Variable 1<\/p>/);
like($t_msg, qr/<p>Var2: Variable 2<\/p>/);
like($t_msg, qr/<p>Var3: Variable 3<\/p>/);
undef $t_msg; 
undef $entity; 
undef $filename; 



# Multipart/Mixed Message...
$filename = 't/corpus/email_messages/simple_template_with_attachment.txt';
$entity = $fm->get_entity(
    {
        -data          => $filename,
        -parser_params => {-input_mechanism => 'parse_open'},
    }
);

ok($entity->isa('MIME::Entity'));

###/ get_entity

$entity = $fm->email_template(
    {
        -entity => $entity,
        -vars   => {
                    from_phrase => 'From Phrase',
                    to_phrase   => 'To Phrase', 
                    subject     => 'This is the subject', 
                    var1        => 'Variable 1', 
                    var2        => 'Variable 2', 
                    var3        => 'Variable 3', 
                    },
    }
);
ok($entity->isa('MIME::Entity'));

$t_msg = $entity->as_string; 

like($t_msg, qr/Subject: This is the subject/); 
like($t_msg, qr/From: "From Phrase" <from\@example.com/);
like($t_msg, qr/To: "To Phrase" <to\@example.com>/); 
like($t_msg, qr/Var1: Variable 1/); 
like($t_msg, qr/Var2: Variable 2/);
like($t_msg, qr/Var3: Variable 3/);


# These are to make sure the variables aren't being decoded, templated out and then encoded. 
#Base64 [var1]
like($t_msg, qr/W3ZhcjFd/); 

#Base 64 Variable 1
unlike($t_msg, qr/VmFyaWFibGUgMQ==/); 

undef $t_msg; 
undef $entity; 
undef $filename; 






# Multipart/Mixed with plaintext attachment
$filename = 't/corpus/email_messages/simple_message_with_plaintext_attachment.txt';
$entity = $fm->get_entity(
    {
        -data          => $filename,
        -parser_params => {-input_mechanism => 'parse_open'},
    }
);

ok($entity->isa('MIME::Entity'));

###/ get_entity

$entity = $fm->email_template(
    {
        -entity => $entity,
        -vars   => {
                    from_phrase => 'From Phrase',
                    to_phrase   => 'To Phrase', 
                    subject     => 'This is the subject', 
                    var1        => 'Variable 1', 
                    var2        => 'Variable 2', 
                    var3        => 'Variable 3', 
                    },
    }
);
ok($entity->isa('MIME::Entity'));

$t_msg = $entity->as_string; 

like($t_msg, qr/Subject: This is the subject/); 
like($t_msg, qr/From: "From Phrase" <from\@example.com/);
like($t_msg, qr/To: "To Phrase" <to\@example.com>/); 
like($t_msg, qr/Var1: Variable 1/); 
like($t_msg, qr/Var2: Variable 2/);
like($t_msg, qr/Var3: Variable 3/);

my $look = quotemeta('rfc822<!-- tmpl_var var1 -->rfc822'); 

unlike($t_msg, qr/$look/); 
like($t_msg, qr/rfc822Variable 1rfc822/);

undef $t_msg; 
undef $entity; 
undef $filename; 


# PlainText Message with a encoding of, "quoted-printable.

$filename = 't/corpus/email_messages/simple_message_quoted_printable.txt';
$entity = $fm->get_entity(
    {
        -data          => $filename,
        -parser_params => {-input_mechanism => 'parse_open'},
    }
);

ok($entity->isa('MIME::Entity'));

###/ get_entity

$entity = $fm->email_template(
    {
        -entity => $entity,
        -vars   => {
                    from_phrase => 'From Phrase',
                    to_phrase   => 'To Phrase', 
                    subject     => 'This is the subject', 
                    var1        => 'Variable 1', 
                    var2        => 'Variable 2', 
                    var3        => 'Variable 3', 
                    },
    }
);
ok($entity->isa('MIME::Entity'));

$t_msg = $entity->as_string; 

like($t_msg, qr/Subject: This is the subject/); 
like($t_msg, qr/From: "From Phrase" <from\@example.com/);
like($t_msg, qr/To: "To Phrase" <to\@example.com>/); 
like($t_msg, qr/Var1: Va\=\nriable 1/); 
like($t_msg, qr/Var2: Va\=\nriable 2/); 
like($t_msg, qr/Var3: Va\=\nriable 3/); 


undef $t_msg; 
undef $entity; 
undef $filename;


###########
#
#
# 


my $prefix; 
my $subject; 

$ls->param('append_list_name_to_subject', 1); 
$ls->param('append_discussion_lists_with', 'list_name'); 
$prefix = quotemeta('[<!-- tmpl_var list_settings.list_name -->]'); 

undef $fm; 
$fm = DADA::App::FormatMessages->new(-List => $list);
$subject = 'Subject'; 
$subject = $fm->_list_name_subject($subject); 
like($subject, qr/$prefix Subject/, "Subject set correctly (list name)");


undef $fm; 
$ls->param('append_discussion_lists_with', 'list_shortname'); 
$subject = 'Subject';
$prefix = quotemeta('[<!-- tmpl_var list_settings.list -->]');  

$fm = DADA::App::FormatMessages->new(-List => $list);
$subject = $fm->_list_name_subject($subject); 
like($subject, qr/$prefix Subject/, "Subject set correctly (list)");

undef $fm;
$fm = DADA::App::FormatMessages->new(-List => $list);
 
$subject = 'Re: [' . $ls->param('list') . '] Subject';
my $new_subject = quotemeta('[<!-- tmpl_var list_settings.list -->] Re: Subject'); 
 diag $fm->_list_name_subject($subject); 

like($fm->_list_name_subject($subject), qr/$new_subject/, "Subject set correctly with reply"); 
undef $fm; 
undef $new_subject; 


$ls->param('append_list_name_to_subject', 1); 
$ls->param('append_discussion_lists_with', 'list_name');

$fm = DADA::App::FormatMessages->new(-List => $list);

$subject = 'Re: [' . $ls->param('list_name') . '] Subject';
$new_subject = quotemeta('[<!-- tmpl_var list_settings.list_name -->] Re: Subject'); 
like($fm->_list_name_subject($subject), qr/$new_subject/, "Subject set correctly with reply for, 'list_name'"); 

undef $fm; 


# Dadamail 3.0 strips out [endif]
# http://sourceforge.net/tracker2/?func=detail&aid=2030573&group_id=13002&atid=113002
# For now, my fix is to just put *back* the, [endif] tag by having a global 
# tmpl var for the [endif] tag with a value of... [endif] - cheap, but I don't
# quite know what to do instead... 

my $html = slurp('t/corpus/html/outlook.html');
my $simple_email = qq{Content-type: text/html
Subject: Hello

$html
};

$fm = DADA::App::FormatMessages->new(-yeah_no_list => 1); 
$entity = $fm->get_entity(
    {
        -data => $simple_email,
    }
);
ok($entity->isa('MIME::Entity'));
$entity = $fm->email_template(
    {
        -entity => $entity,
        -vars   => {},
    }
);
ok($entity->isa('MIME::Entity'));
$t_msg = $entity->as_string; 

like($t_msg, qr/\[endif\]/, 'found the [endif] tag'); 





dada_test_config::remove_test_list;
dada_test_config::wipe_out;


sub slurp { 
	
		
		my ($file) = @_;

        local($/) = wantarray ? $/ : undef;
        local(*F);
        my $r;
        my (@r);

        open(F, "<$file") || die "open $file: $!";
        @r = <F>;
        close(F) || die "close $file: $!";

        return $r[0] unless wantarray;
        return @r;

}


