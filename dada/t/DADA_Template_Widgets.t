#!/usr/bin/perl -w
use strict; 

use lib qw(./t ./ ./DADA/perllib ../ ../DADA/perllib ../../ ../../DADA/perllib); 
BEGIN{$ENV{NO_DADA_MAIL_CONFIG_IMPORT} = 1}
use dada_test_config; 

use Test::More qw(no_plan); 


use DADA::Config; 
use DADA::Template::Widgets; 
use DADA::MailingList::Subscribers; 
use DADA::MailingList::Settings; 


BEGIN{$ENV{NO_DADA_MAIL_CONFIG_IMPORT} = 1}
use dada_test_config; 
my $list = dada_test_config::create_test_list;
my $ls   = DADA::MailingList::Settings->new({-list => $list}); 
my $li   = $ls->get; 


use DADA::Template::Widgets; 

### screen


# Variables to be used in the template can be passed using the, C<-vars> paramater, which maps to the, 
# B<H::T> paramater, C<param>. C<-vars> should hold a reference to a hash: 
# 
#  my $scalar = 'I wanted to say: <!-- tmpl_var var1 -->'; 
#  print DADA::Template::Widgets::screen(
#     {
#         -data => \$scalar,
#         -vars   => {var1 => "This!"}, 
#     }
#  );
# 
# This will print:
# 
#  I wanted to say: This!

my $scalar = 'I wanted to say: <!-- tmpl_var var1 -->'; 
my $r = DADA::Template::Widgets::screen(
          {
              -data   => \$scalar,
              -vars   => {var1 => "This!"}, 
          }
     );
ok($r eq 'I wanted to say: This!'); 
undef $r;
undef $scalar; 


# There is one small B<HTML::Template> filter that turns the very B<very> simple (oldstyle) Dada 
# Mail template-like files into something B<HTML::Template> can use. In the beginning (gather 'round, kids)
# Dada Mail didn't have a Templating system (really) at all, and just used regex search and replace - 
# sort of like everyone did, before they knew better. Old style Dada Mail variables looked like this: 
# 
#  [var1]
# 
# These oldstyle variables will still work, but do remember to pass the, C<-dada_pseudo_tag_filter>
# with a value of, C<1> to enable this filter: 
# 
#  my $scalar = 'I wanted to say: [var1]'; 
#  print DADA::Template::Widgets::screen(
#     {
#         -data                   => \$scalar,
#         -vars                   => {var1 => "This!"}, 
#         -dada_pseudo_tag_filter => 1, 
#     }
#  );


$scalar = 'I wanted to say: [var1]'; 
   $r = DADA::Template::Widgets::screen(
   {
       -data                   => \$scalar,
       -vars                   => {var1 => "This!"}, 
       -dada_pseudo_tag_filter => 1, 
   }
);
ok($r eq 'I wanted to say: This!'); 
undef $r;
undef $scalar; 




# My suggestion is to try not to mix the two dialects and note that we'll I<probably> be moving to 
# using the B<H::T> default template conventions, so as to make geeks and nerds more comfortable with 
# the program. Saying that, you I<can> mix the two dialects and everything should work. This may be 
# interesting in a pinch, where you want to say something like: 
# 
#  Welcome to [boring_name]
#  
#  <!-- tmpl_if boring_description --> 
#   Mription --> y boring description: 
#   
#     [boring_description]
#     
#  <!--/tmpl_if--> 
#  


$scalar = q{
Welcome to [boring_name]

<!-- tmpl_if boring_description --> 
    My boring description: 
 
   [boring_description]
   
<!--/tmpl_if--> 

}; 
   $r = DADA::Template::Widgets::screen(
   {
       -data                   => \$scalar,
       -vars                   => {boring_name => "Site Name", boring_description => 'Site Descripton'}, 
       -dada_pseudo_tag_filter => 1, 
   }
);

like($r, qr/Welcome to Site Name/); 
like($r, qr/Site Descripton/); 

undef $r; 
undef $scalar; 

# To tell C<screen> to use a specific subscriber information, you have two different methods. 
# 
# The first is to give the paramaters to *which* subscriber to use, via the C<-subscriber_vars_param>: 
# 
#  print DADA::Template::Widgets::screen(
#     {
#     -subscriber_vars_param => 
#         {
#             -list  => 'listshortname', 
#             -email => 'this@example.com', 
#             -type  => 'list',
#         }
#     }
#  );
# 
# 
my $lh = DADA::MailingList::Subscribers->new({-list => $list}); 

   $lh->add_subscriber(
       { 
             -email         => 'this@example.com',
             -type          => 'list', 
             -fields        =>  {},
        }
    );
    

my $d = q{ 

Subscriber Address: [subscriber.email]
Subscriber Name: [subscriber.email_name]
Subscriber Domain: [subscriber.email_domain]

}; 


$r =  DADA::Template::Widgets::screen(
   {
   -data                   => \$d,
   -subscriber_vars_param  => 
       {
           -list  => $list, 
           -email => 'this@example.com', 
           -type  => 'list',
       },
    -dada_pseudo_tag_filter => 1, 
   }
   
);

like($r, qr/Subscriber Address: this\@example.com/); 
like($r, qr/Subscriber Name: this/); 
like($r, qr/Subscriber Domain: example.com/); 

undef($r); 
undef($d);



$d = q{ 

Subscriber Address: <!-- tmpl_var subscriber.email -->
Subscriber Name: <!-- tmpl_var subscriber.email_name -->
Subscriber Domain: <!-- tmpl_var subscriber.email_domain -->
}; 


$r =  DADA::Template::Widgets::screen(
   {
   -data                   => \$d,
   -subscriber_vars_param  => 
       {
           -list  => $list, 
           -email => 'this@example.com', 
           -type  => 'list',
       },
    -dada_pseudo_tag_filter => 1, 
   }
   
);

like($r, qr/Subscriber Address: this\@example.com/); 
like($r, qr/Subscriber Name: this/); 
like($r, qr/Subscriber Domain: example.com/); 

undef($r); 
undef($d); 


# The other magical thing that will happen, is that you'll get a new variable to be used in your template
# called, B<subscriber>, which is a array ref of hashrefs with name/value pairs for all your subscriber 
# fields. So, this'll allow you to do something like this: 
# 
#  <!-- tmpl_loop subscriber --> 
#  
#   <!-- tmpl_var name -->: <!-- tmpl_value -->
#  
#  <!--/tmpl_loop-->
# 
# and this will loop over your subscriber fields. 

$d = q{ 

<!-- tmpl_loop subscriber --> 
 <!-- tmpl_var name -->: <!-- tmpl_var value -->
<!--/tmpl_loop-->
}; 


$r =  DADA::Template::Widgets::screen(
   {
   -data                   => \$d,
   -subscriber_vars_param  => 
       {
           -list  => $list, 
           -email => 'this@example.com', 
           -type  => 'list',
       },
    -dada_pseudo_tag_filter => 1, 
   }
   
);


like($r, qr/email: this\@example.com/); 
like($r, qr/email_name: this/); 
like($r, qr/email_domain: example.com/); 

undef($r); 
undef($d);


# If you'd like, you can also pass the subscriber fields information yourself - this may be useful if
# you're in some sort of recursive subroutine, or if you already have the information on hand. You may
# do so by passing the, C<-subscriber_vars> paramater, I<instead> of the C<-subscriber_vars_param>
# paramater, like so: 
# 
#  use DADA::MailingList::Subscribers; 
#  my $lh = DADA::MailingList::Subscribers->new({-list => 'listshortname'}); 
#  
#  my $subscriber = get_subscriber(
#                       {
#                          -email  => 'this@example.com', 
#                          -type   => 'list', 
#                          -dotted => 1, 
#                        }
#                    ); 
#  
#  use DADA::Template::Widgets; 
#  print DADA::Template::Wigets::screen(
#  
#            { 
#                 -subscriber_vars => $subscriber,
#            }
#        ); 
#
# The, B<subscriber> variable will still be magically created for you. 

my $subscriber = $lh->get_subscriber(
                     {
                        -email  => 'this@example.com', 
                        -type   => 'list', 
                        -dotted => 1, 
                      }
                  ); 


$d = q{ 

<!-- tmpl_loop subscriber --> 
 <!-- tmpl_var name -->: <!-- tmpl_var value -->
<!--/tmpl_loop-->
}; 


$r =  DADA::Template::Widgets::screen(
   {
   -data                   => \$d,
    -subscriber_vars        => $subscriber,
    -dada_pseudo_tag_filter => 1, 
   }
   
);

like($r, qr/email: this\@example.com/); 
like($r, qr/email_name: this/); 
like($r, qr/email_domain: example.com/); 

undef($r); 
undef($d);

# The B<-subscriber_vars> paramater is also a way to override what gets printed for the, B<subscriber.> 
# variables, since nothing is done to check the validity of what you're passing. So, keep that in mind - 
# all these are shortcuts and syntactic sugar. And we I<like> sugar. 



$d = q{ 

<!-- tmpl_loop subscriber --> 
 <!-- tmpl_var name -->: <!-- tmpl_var value -->
<!--/tmpl_loop-->
}; 


$r =  DADA::Template::Widgets::screen(
   {
   -data                   => \$d,
   -subscriber_vars        => {foo => 'bar', ping => 'pong'},
   
   }
   
);

like($r, qr/foo: bar/); 
like($r, qr/ping: pong/); 

undef($r); 
undef($d);



# A similar thing can be used to retrieve the list settings of a particular list: 
# 
#  print DADA::Template::Widgets::screen(
#     {
#     -list_settings_vars_param => 
#         {
#             -list  => 'listshortname', 
#         }
#     }
#  );
#  

$d = q{ 
list: [list_settings.list]
list name: [list_settings.list_name]
list owner: [list_settings.list_owner_email]
info: [list_settings.info]
}; 

$r =  DADA::Template::Widgets::screen(
   {
   -data                     => \$d, 
   -list_settings_vars_param => 
       {
           -list  => $list, 
       },
   -dada_pseudo_tag_filter => 1, 
   }
);

like($r, qr/list: $list/); 
like($r, qr/list name: $li->{list_name}/); 
like($r, qr/list owner: $li->{list_owner_email}/); 
like($r, qr/info: $li->{info}/); 

undef($r); 
undef($d);



# or:
# 
#  use DADA::MailingList::Settings; 
#  my $ls = DADA::MailingList::Settings->new({-list => 'listshortname'}); 
#  
#  my $list_settings = $ls->get(
#                          -dotted => 1, 
#                      ); 
#  
#  use DADA::Template::Widgets; 
#  print DADA::Template::Wigets::screen(
#  
#            { 
#                 -list_settings_vars => $list_settings,
#            }
#        ); 
#        


$d = q{ 
list: [list_settings.list]
list name: [list_settings.list_name]
list owner: [list_settings.list_owner_email]
info: [list_settings.info]
}; 

my $list_settings = $ls->get(
                        -dotted => 1, 
                    ); 



$r =  DADA::Template::Widgets::screen(
   {
   -data                     => \$d, 
   -list_settings_vars       => $list_settings, 
   -dada_pseudo_tag_filter   => 1, 
   }
);

like($r, qr/list: $list/); 
like($r, qr/list name: $li->{list_name}/); 
like($r, qr/list owner: $li->{list_owner_email}/); 
like($r, qr/info: $li->{info}/); 

undef($r); 
undef($d);


# This will even work, as well in a template: 
# 
#  <!-- tmpl_loop list_settings --> 
#  
#     <!-- tmpl_var name -->: <!-- tmpl_var value -->
#  
#  <!-- /tmpl_loop -->

$d = q{ 
<!-- tmpl_loop list_settings --> 
    <!-- tmpl_var name -->: <!-- tmpl_var value -->
<!-- /tmpl_loop -->
}; 


$r =  DADA::Template::Widgets::screen(
   {
   -data                     => \$d, 
   -list_settings_vars_param => {-list => $list}, 
   }
);

like($r, qr/list: $list/); 
like($r, qr/list_name: $li->{list_name}/); 
like($r, qr/list_owner_email: $li->{list_owner_email}/); 
like($r, qr/info: $li->{info}/); 

undef($r); 
undef($d);




### 
# Let's set our own subscriber information, and see if it comes back: 
=cut
$d = q{ 
Subscriber: <!-- tmpl_var subscriber.email --> 
}; 


$r =  DADA::Template::Widgets::screen(
   {
   -data                     => \$d, 
   -list_settings_vars_param => {-list => $list}, 
   }
);

like($r, qr/list: $list/); 
like($r, qr/list_name: $li->{list_name}/); 
like($r, qr/list_owner_email: $li->{list_owner_email}/); 
like($r, qr/info: $li->{info}/); 

undef($r); 
undef($d);

=cut




###



  
###/ screen


### dada_backwards_compatibility
my $string = q{
[subscriber_email]
[list_info]
[subscriber_email]
[email]
[email_name]
[email_domain]
[pin]
[list]
[list_name]
[info]
[physical_address]
[privacy_policy]
[list_owner_email]
[list_admin_email]
};

DADA::Template::Widgets::dada_backwards_compatibility(\$string);

like($string, qr/\[subscriber.email\]/);
like($string, qr/\[subscriber.email_name\]/);
like($string, qr/\[subscriber.email_domain\]/);
like($string, qr/\[subscriber.pin\]/);

like($string, qr/\[list_settings.info\]/);
like($string, qr/\[list_settings.list\]/);
like($string, qr/\[list_settings.list_name\]/);
like($string, qr/\[list_settings.physical_address\]/);
like($string, qr/\[list_settings.privacy_policy\]/);
like($string, qr/\[list_settings.list_owner_email\]/);
like($string, qr/\[list_settings.list_admin_email\]/);

unlike($string, qr/\[subscriber_email\]/);
unlike($string, qr/\[list_info\]/);
unlike($string, qr/\[subscriber_email\]/);
unlike($string, qr/\[email\]/);
unlike($string, qr/\[email_name\]/);
unlike($string, qr/\[email_domain\]/);
unlike($string, qr/\[pin\]/);
unlike($string, qr/\[list\]/);
unlike($string, qr/\[list_name\]/);
unlike($string, qr/\[info\]/);
unlike($string, qr/\[physical_address\]/);
unlike($string, qr/\[privacy_policy\]/);
unlike($string, qr/\[list_owner_email\]/);
unlike($string, qr/\[list_admin_email\]/);

undef $string; 
	



### /dada_backwards_compatibility




dada_test_config::remove_test_list;
dada_test_config::wipe_out;




