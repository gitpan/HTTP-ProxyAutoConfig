use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
	      'NAME'	  => 'HTTP::ProxyAutoConfig',
	      'PM' 	  => {
			      'ProxyAutoConfig.pm' => '$(INST_LIBDIR)/ProxyAutoConfig.pm'
			     },
	      'MAN3PODS'  => { 'ProxyAutoConfig.pm'=> '$(INST_MAN3DIR)/HTTP::ProxyAutoConfig.3pm',
			     },
	      'VERSION'   => '0.1',
	      'dist'      => { 'COMPRESS' => 'gzip --best' }
	     );
