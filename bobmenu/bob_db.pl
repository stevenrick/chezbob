# bob_db.pl
#
# A set of routines that encapsulates the calls to the Postgres database 
# backend.  The routines are rather repetitive and not particularly 
# flexible, but it certainly makes the other code a lot simpler to read 
# and maintain.  Any future database calls should be placed in this module.
#
# It's worth remembering that strings in most databases (incl. Postgres)
# are delimited by single (') quotation marks/apostrophes.  The database
# will crash if you try inserting a string with an apostrophe.  Check out
# the 'esc_apos' function which looks for apostrophes in a string and 
# escapes them by adding a second apostrophe.
#
# 'Pg' is a Perl module that allows us to access a Postgres database.  
# Packages are available for both Redhat and Debian.
#
# $Id: bob_db.pl,v 1.14 2001-05-19 22:37:54 mcopenha Exp $
#

use Pg;

my $conn = ""; 		# the database connection	
$NOT_FOUND = -1;	

sub
bob_db_connect
{
  $conn = Pg::connectdb("dbname=bob");
  if ($conn->status == PGRES_CONNECTION_BAD) {
    print STDERR "Error connecting to database...exiting.\n";
    print STDERR $conn->errorMessage;
    exit 1;
  }
}


sub
bob_db_check_conn
{
  if ($conn->status != PGRES_CONNECTION_OK) {
    print STDERR "Not connected to Bob database...exiting.\n";
    exit 1;
  }
}


#---------------------------------------------------------------------------
# users table

sub
bob_db_get_username_from_userbarcode
{
  my ($barcode) = @_;

  &bob_db_check_conn;
  my $queryFormat = q{
    select username
    from users
    where userbarcode = '%s';
  };
  my $result = $conn->exec(sprintf($queryFormat, $barcode));
  if ($result->ntuples != 1) {
    return undef;
  } else {
    return ($result->getvalue(0,0));
  }
}


sub
bob_db_get_userid_from_username
{
  my ($username) = @_;

  &bob_db_check_conn;
  my $queryFormat = q{
    select userid
    from users
    where username ~* '^%s$';
  };
  my $result = $conn->exec(sprintf($queryFormat, &esc_apos($username)));
  if ($result->ntuples != 1) {
    return $NOT_FOUND;
  } else {
    return ($result->getvalue(0,0));
  }
}


sub
bob_db_get_userid_from_userbarcode
{
  my ($barcode) = @_;

  &bob_db_check_conn;
  my $queryFormat = q{
    select userid
    from users
    where userbarcode = '%s';
  };
  my $result = $conn->exec(sprintf($queryFormat, $barcode));
  if ($result->ntuples != 1) {
    return $NOT_FOUND;
  } else {
    return ($result->getvalue(0,0));
  }
}


sub
bob_db_get_nickname_from_userid
{
  my ($userid) = @_;

  &bob_db_check_conn;
  my $queryFormat = q{
    select nickname
    from users
    where userid = %d;
  };
  my $result = $conn->exec(sprintf($queryFormat, $userid));
  if ($result->ntuples != 1) {
    return undef;
  } else {
    return ($result->getvalue(0,0));
  }
}


sub
bob_db_get_userbarcode_from_userid
{
  my ($userid) = @_;

  &bob_db_check_conn;
  my $queryFormat = q{
    select userbarcode
    from users
    where userid = %d;
  };
  my $result = $conn->exec(sprintf($queryFormat, $userid));
  if ($result->ntuples != 1) {
    return undef;
  } else {
    return ($result->getvalue(0,0));
  }
}


sub
bob_db_add_user
{
  my ($username, $email) = @_;

  &bob_db_check_conn;
  my $insertqueryFormat = q{
    insert
    into users
    values(nextval('userid_seq'), '%s', '%s'); 
  };

  my $query = sprintf($insertqueryFormat, 
                      &esc_apos($username), 
                      &esc_apos($email));
  my $result = $conn->exec($query);
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error inserting record...exiting\n";
    exit 1;
  }
}


sub
bob_db_update_user_barcode
{
  my ($userid, $barcode) = @_;

  &bob_db_check_conn;
  my $updatequeryFormat = q{
    update users
    set userbarcode = '%s'
    where userid = %d;
  };      

  my $result = $conn->exec(sprintf($updatequeryFormat, $barcode, $userid));
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error updating new barcode\n";
    exit 1;
  }
}


sub
bob_db_update_nickname
{
  my ($userid, $name) = @_;

  &bob_db_check_conn;
  my $updatequeryFormat = q{
    update users
    set nickname = '%s'
    where userid = %d;
  };      

  my $result = $conn->exec(sprintf($updatequeryFormat, 
                                   &esc_apos($name), 
                                   $userid));
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error updating new nickname\n";
    exit 1;
  }
}

#---------------------------------------------------------------------------
# balance table

sub
bob_db_get_balance
{
  my ($userid) = @_;

  &bob_db_check_conn;
  my $queryFormat = q{
    select balance
    from balances
    where userid = %d;
  };
  my $result = $conn->exec(sprintf($queryFormat,$userid));

  if ($result->ntuples != 1) {
    return $NOT_FOUND;
  } else {
    return ($result->getvalue(0,0));
  }
}


sub
bob_db_init_balance
{
  my ($userid) = @_;

  &bob_db_check_conn;
  my $insertqueryFormat = q{ 
    insert 
    into balances 
    values(%d, %.2f); 

    insert 
    into transactions 
    values('now', %d, %.2f, 'INIT'); 
  };

  my $query = sprintf($insertqueryFormat, $userid, 0.0, $userid, 0.0);
  my $result = $conn->exec($query);
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error inserting record...exiting\n";
    exit 1;
  }
}


sub
bob_db_update_balance
#
#
{
  my($userid, $amt, $type) = @_;

  &bob_db_check_conn;
  my $updatequeryFormat = q{
    update balances
    set balance = balance + %.2f
    where userid = %d;

    insert
    into transactions
    values('now', %d, %.2f, '%s'); 
  };

  my $query = sprintf($updatequeryFormat, 
                      $amt, 
                      $userid, 
                      $userid, 
                      $amt, 
                      &esc_apos(uc($type)));
  my $result = $conn->exec($query);
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error update record...exiting\n";
  }
}

#---------------------------------------------------------------------------
# msg table

sub
bob_db_insert_msg
{
  my ($userid, $msg) = @_;

  &bob_db_check_conn;
  my $insertqueryFormat = q{
    insert
    into messages
    values( nextval('msgid_seq'), 'now', %s, '%s');
  };

  my $query = sprintf($insertqueryFormat, 
                      defined $userid ? $userid : "null", 
                      &esc_apos($msg));
  my $result = $conn->exec($query);
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error inserting record...exiting\n";
    exit 1;
  }
}

#---------------------------------------------------------------------------
# transactions table

sub
bob_db_log_transactions
{
  my ($userid, $logfile) = @_;

  &bob_db_check_conn;
  if ( !open(LOG_OUT, "> $logfile")) {
    print STDERR "unable to write to log file.\n";
    exit 1;
  }

  my $logqueryFormat = q{
    select xacttime,xactvalue,xacttype
    from transactions
    where userid = %d
    order by xacttime;
  };

  my $result = $conn->exec(sprintf($logqueryFormat, $userid));
  for ($i = 0 ; $i < $result->ntuples ; $i++) {
    $time = $result->getvalue($i,0);
    $val = $result->getvalue($i,1);
    $type = $result->getvalue($i,2);

    if ($i == 0) {
      $win_title .= " since $time";
    }

    print LOG_OUT sprintf("%s: %.2f (%s)\n", $time, $val, $type);
  }

  close(LOG_OUT);
}


#---------------------------------------------------------------------------
# pwd table

sub
bob_db_get_pwd
{
  my ($userid) = @_;

  &bob_db_check_conn;
  my $query = qq{
    select p
    from pwd
    where userid = $userid;
  };
  my $result = $conn->exec($query);

  if ($result->ntuples != 1) {
    return undef;
  } else {
    return $result->getvalue(0,0);
  }
}


sub
bob_db_remove_pwd
{
  my ($userid) = @_;

  &bob_db_check_conn;
  my $removequery = qq{
    delete
    from pwd
    where userid = $userid;
  };

  my $result = $conn->exec($removequery);
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error deleting record...exiting\n";
    exit 1;
  }
}


sub
bob_db_update_pwd
{
  my ($userid, $c_pwd) = @_;

  &bob_db_check_conn;
  my $updatequery = qq{
    update pwd
    set p = '$c_pwd'
    where userid = $userid;
  };

  my $result = $conn->exec($updatequery);
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error updating record...exiting\n";
    exit 1;
  }
}


sub
bob_db_insert_pwd
{
  my ($userid, $c_pwd) = @_;

  &bob_db_check_conn;
  my $insertquery = qq{
    insert
    into pwd
    values($userid, '$c_pwd'); 
  };

  my $result = $conn->exec($insertquery);
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error inserting record...exiting\n";
    exit 1;
  }
}

#---------------------------------------------------------------------------
# products table

sub
bob_db_insert_product
{
  my ($barcode, $name, $phonetic_name, $price, $stock) = @_;
  &bob_db_check_conn;

  my $insertqueryFormat = q{
    insert 
    into products 
    values('%s', '%s', '%s', %.2f, %d);
  };      

  my $query = sprintf($insertqueryFormat, $barcode, &esc_apos($name), 
                      &esc_apos($phonetic_name), $price, $stock);
  my $result = $conn->exec($query);
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error inserting record...exiting\n";
    exit 1;
  }
}


sub
bob_db_set_stock
{
  my ($barcode, $stock) = @_;

  $updatequeryFormat = q{
    update products
    set stock = %d
    where barcode = '%s';
  };
  my $result = $conn->exec(sprintf($updatequeryFormat, $stock, $barcode));
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error update record...exiting\n";
    exit 1;
  }
}


sub
bob_db_update_stock
{
  my ($delta, $prodname) = @_;

  my $updatequeryFormat = q{
    update products
    set stock = stock + %d
    where name = '%s';
  };
  my $query = sprintf($updatequeryFormat, $delta, &esc_apos($prodname));
  my $result = $conn->exec($query);
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error update record...exiting\n";
    exit 1;
  }
}


sub
bob_db_get_productname_from_barcode
{
  my ($barcode) = @_;

  my $selectqueryFormat = q{
    select name
    from products
    where barcode = '%s';
  };
  my $result = $conn->exec(sprintf($selectqueryFormat, $barcode));
  if ($result->ntuples != 1) {
    return undef;
  } else {
    return $result->getvalue(0,0);
  }
}


sub
bob_db_get_phonetic_name_from_barcode
{
  my ($barcode) = @_;

  &bob_db_check_conn;
  my $selectqueryFormat = q{
    select phonetic_name
    from products
    where barcode = '%s';
  };
  my $result = $conn->exec(sprintf($selectqueryFormat, $barcode));
  if ($result->ntuples != 1) {
    return undef;
  } else {
    return $result->getvalue(0,0);
  }
}


sub
bob_db_get_price_from_barcode
{
  my ($barcode) = @_;

  &bob_db_check_conn;
  my $selectqueryFormat = q{
    select price
    from products
    where barcode = '%s';
  };
  my $result = $conn->exec(sprintf($selectqueryFormat, $barcode));
  if ($result->ntuples != 1) {
    return $NOT_FOUND;
  } else {
    return $result->getvalue(0,0);
  }
}


sub
bob_db_get_stock_from_barcode
{
  my ($barcode) = @_;

  &bob_db_check_conn;
  my $selectqueryFormat = q{
    select stock
    from products
    where barcode = '%s';
  };
  my $result = $conn->exec(sprintf($selectqueryFormat, $barcode));
  if ($result->ntuples != 1) {
    return $NOT_FOUND;
  } else {
    return $result->getvalue(0,0);
  }
}


sub
bob_db_delete_product
{
  my ($barcode) = @_;

  &bob_db_check_conn;
  my $deletequeryFormat = q{
    delete
    from products
    where barcode = '%s';
  };
  $result = $conn->exec(sprintf($deletequeryFormat, $barcode));
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error deleting record...exiting\n";
    exit 1;
  }
}

#---------------------------------------------------------------------------
# bulk_items table

sub
bob_db_get_bulk_name_from_barcode
{
  my ($barcode) = @_;
  &bob_db_check_conn;

  my $selectqueryFormat = q{
    select bulk_name
    from bulk_items
    where bulk_barcode = '%s';
  };
  my $result = $conn->exec(sprintf($selectqueryFormat, $barcode));
  if ($result->ntuples < 1) {
    return undef;
  } else {
    return $result->getvalue(0,0);
  }
}

sub
bob_db_delete_bulk
{
  my ($barcode) = @_;

  &bob_db_check_conn;
  my $deletequeryFormat = q{
    delete
    from bulk_items
    where bulk_barcode = '%s';
  };
  $result = $conn->exec(sprintf($deletequeryFormat, $barcode));
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error deleting record...exiting\n";
    exit 1;
  }
}


sub
bob_db_insert_bulk_item
{
  my ($barcode, $name, $prodbarcode, $quan) = @_;
  &bob_db_check_conn;

  my $insertqueryFormat = q{
    insert 
    into bulk_items
    values('%s', '%s', '%s', %d);
  };
  my $query = sprintf($insertqueryFormat, 
                      $barcode, 
                      &esc_apos($name), 
                      &esc_apos($prodbarcode), 
                      $quan);
  my $result = $conn->exec($query);

  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error inserting record...exiting\n";
    exit 1;
  }
}


sub
bob_db_update_products_in_bulk_item
{
  my ($bulk_barcode) = @_;

  &bob_db_check_conn;
  my $selectqueryFormat = q{
    select *
    from bulk_items
    where bulk_barcode = '%s';
  };
  my $listofproducts = $conn->exec(sprintf($selectqueryFormat, $bulk_barcode));

  if ($listofproducts->ntuples != 0) {
    for ($i=0; $i<$listofproducts->ntuples; $i++) {
      my $prodbarcode = $listofproducts->getvalue($i, 2);
      my $quantoadd = $listofproducts->getvalue($i, 3);

      my $updatequeryFormat = q{
        update products
        set stock = stock + %d
        where barcode = '%s';
      };
      my $query = sprintf($updatequeryFormat, $quantoadd, $prodbarcode);
      my $rv = $conn->exec($query);
      if ($rv->resultStatus != PGRES_COMMAND_OK) {
        print STDERR "error update record...exiting\n";
        exit 1;
      }
    }

    my $bulkname = $listofproducts->getvalue(0,1);
    return $bulkname;
  } else {
    return undef;
  }
}

#---------------------------------------------------------------------------
# profiles table

sub
bob_db_get_profile_setting
{
  my ($userid, $property) = @_;
  &bob_db_check_conn;  
  my $queryFormat = q{
    select setting
    from profiles
    where userid = %d and property = '%s';
  };
  my $result = $conn->exec(sprintf($queryFormat, 
                                   $userid, 
                                   &esc_apos($property)));
  if ($result->ntuples != 1) {
    return $NOT_FOUND;
  } else {
    return $result->getvalue(0,0);
  }
}


sub
bob_db_insert_property
{
  my ($userid, $property) = @_;
  &bob_db_check_conn;
  my $insertqueryFormat = q{
    insert
    into profiles
    values(%d, '%s', 0);
  };
  my $result = $conn->exec(sprintf($insertqueryFormat, 
                                   $userid, &esc_apos($property)));
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error insert new property...exiting\n";
    exit 1;
  }
}


sub
bob_db_update_profile_settings
{
  my ($userid, %newsettings) = @_;
  &bob_db_check_conn;

  while ( ($property, $setting) = each(%newsettings) ) {
    my $updatequeryFormat = q{
      update profiles
      set setting = %d
      where userid = %d and property = '%s'; 
    };
    my $query = sprintf($updatequeryFormat, 
                        $setting, 
                        $userid, 
                        &esc_apos($property));
    my $result = $conn->exec($query);
    if ($result->resultStatus != PGRES_COMMAND_OK) {
      print STDERR "error updating profile\n";
      exit 1;
    }
  }
}

#---------------------------------------------------------------------------
# books table

sub
bob_db_insert_book
{
  my ($barcode, $isbn, $author, $title) = @_;
  &bob_db_check_conn;
  my $insertqueryFormat = q{
    insert
    into books
    values('%s', '%s', '%s', '%s');
  };
  my $query = sprintf($insertqueryFormat, 
                      $barcode, 
                      $isbn, 
                      &esc_apos($author), 
                      &esc_apos($title));
  my $result = $conn->exec($query);
  if ($result->resultStatus != PGRES_COMMAND_OK) {
    print STDERR "error insert new book...exiting\n";
    exit 1;
  }
}


sub
bob_db_get_book_from_barcode
{
  my ($barcode) = @_;
  &bob_db_check_conn;

  my $selectqueryFormat = q{
    select author, title
    from books
    where barcode = '%s';
  };
  my $result = $conn->exec(sprintf($selectqueryFormat, $barcode));
  if ($result->ntuples < 1) {
    return undef;
  } else {
    return $result->getvalue(0,0) . "\t" . $result->getvalue(0,1);
  }
}

#---------------------------------------------------------------------------
# utilities 

sub
esc_apos
#
# escape any apostrophes
#
{
  my ($str) = @_;
  $str =~ s/\'/\'\'/g;
  return $str;
}


1;