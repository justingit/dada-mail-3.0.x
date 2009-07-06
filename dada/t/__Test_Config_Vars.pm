package __Test_Config_Vars; 
use strict; 

require Exporter; 
use vars qw($TEST_SQL_PARAMS @EXPORT_OK @ISA);  

@ISA = qw(Exporter);
@EXPORT_OK = qw($TEST_SQL_PARAMS); 

$TEST_SQL_PARAMS = { 

	MySQL => { 
	
		test_enabled     => 1, 
	    database         => 'test',
	    dbserver         => 'localhost', # may just be, "localhost"   	   
	    port             => '3306',      # mysql: 3306, Postgres: 5432   	   
	    dbtype           => 'mysql',     # 'mysql' for 'MySQL', 'Pg' for 'PostgreSQL', and 'SQLite' for SQLite  
	    user             => 'dada',          
	    pass             => 'dada',
    
	    subscriber_table => 'test_dada_subscribers',
	    archives_table   => 'test_dada_archives', 
	    settings_table   => 'test_dada_settings', 
	    session_table    => 'test_dada_sessions',
		bounce_scores_table => 'test_dada_bounce_scores', 
	
	
	}, 

	PostgreSQL => { 
		test_enabled     => 0, 
		database         => 'dada',
	    dbserver         => 'localhost', # may just be, "localhost"   	   
	    port             => '5432',      # mysql: 3306, Postgres: 5432   	   
	    dbtype           => 'Pg',     # 'mysql' for 'MySQL', 'Pg' for 'PostgreSQL', and 'SQLite' for SQLite  
	    user             => 'postgres',          
	    pass             => '',
    
	    subscriber_table => 'test_dada_subscribers',
	    archives_table   => 'test_dada_archives', 
	    settings_table   => 'test_dada_settings', 
	    session_table    => 'test_dada_sessions',
		bounce_scores_table => 'test_dada_bounce_scores', 
	}, 

	SQLite => {
		test_enabled     => 1, 
	    dbtype           => 'SQLite',     # 'mysql' for 'MySQL', 'Pg' for 'PostgreSQL', and 'SQLite' for SQLite  
		database         => 'test_dada',
	    subscriber_table => 'test_dada_subscribers',
	    archives_table   => 'test_dada_archives', 
	    settings_table   => 'test_dada_settings', 
	    session_table    => 'test_dada_sessions',
		bounce_scores_table => 'test_dada_bounce_scores', 
	},
	

};
