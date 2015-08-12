package Marcion;

use File::Basename;
use DBI;
use Data::Dumper;
use Scalar::Util;
use XML::Entities;
use HTML::Entities;
use XML::LibXML;

use Moo;
extends 'Dancer2::Core::DSL';

%HTML::Entities::char2entity = %{
  XML::Entities::Data::char2entity('all');
};

sub BUILD {
  my $self = shift;

  $self->_process_sql();
  $self->_process_views();
}

sub _process_views {
  my $self = shift;
  opendir(my $dh, "views");
  while(readdir $dh) {
    next if ($_ !~ /html$/);
    my ($name,$path,$suffix) = fileparse($_, ".html");
    open (HTML, "views/$_");
    my $html_content = <HTML>;
    $self->{app}->add_route(
      method => 'get',
      regexp => "/$name",
      code => sub {$html_content}
     );
  }
  closedir $dh;
}

sub _process_sql {
  my $self = shift;
  my $parser = XML::LibXML->new();
  my $doc    = $parser->parse_file('config.xml');
  my $dsn;
  my $username;
  my $password;
  foreach my $node ($doc->findnodes('/config')) {
    $dsn = $node->findnodes('./dsn');
    $password = $node->findnodes('./password');
    $username = $node->findnodes('./username');
  }

  my $dbh = DBI->connect("$dsn", "$username", "$password");
  opendir(DIR,"sql");
  my @sql_files = readdir DIR;
  foreach my $sql_file (@sql_files) {
    next if ($sql_file !~ /sql$/);
    my ($name,$path,$suffix) = fileparse($sql_file, ".sql");
    open (SQL, "sql/$sql_file");
    my $sth;
    while (my $sqlStatement = <SQL>) {
      $sth = $dbh->prepare($sqlStatement);
    }
    my $xml_string = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<rows>";
    $sth->execute;
    while (my $hash_ref = $sth->fetchrow_hashref) {
      $xml_string .= "\n<row>";
      foreach my $key (keys %{$hash_ref}) {
	$xml_string .= "<" . $key . ">";
	$xml_string .= encode_entities($hash_ref->{$key});
	$xml_string .= "</" . $key . ">";
      }
      $xml_string .= "</row>";
    }
    $xml_string .= "</rows>";
    #add route for each file
    $self->{app}->add_route(
       method => 'get',
       regexp => "/$name",
       code => sub {$xml_string}
      );
  }
  $dbh->disconnect;
  closedir DIR;
}

sub preach {
  my $self = shift;
  Dancer2->runner->start($self->app);
}

around dsl_keywords => sub {
  my $keywords = {};
  $keywords->{data}   = { 'is_global' => 1 };
  $keywords->{preach} = { 'is_global' => 1 };
  return $keywords;
};

1;
