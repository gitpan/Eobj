#
# This file is part of the Eobj project.
#
# Copyright (C) 2003, Eli Billauer
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# A copy of the license can be found in a file named "licence.txt", at the
# root directory of this project.
#

use Eobj::PLerror;
package Eobj;

use Eobj::PLerror;

use 5.004;
use strict 'vars';
use warnings;

require Exporter;


BEGIN {
  @Eobj::warnings = ();
  %Eobj::classes = ();
  $SIG{__WARN__} = sub {
    my ($class) = ($_[0] =~ /unquoted string.*?\"(.*?)\".*may clash/i);
    if (defined $class) {
      push @Eobj::warnings, $_[0]; 
    } else {
      warn ($_[0])
    }
  };
}

END {
  $SIG{__WARN__} = sub {warn $_[0]; }; # Prevent an endless recursion
  foreach (@Eobj::warnings) {
    my ($class) = ($_ =~ /unquoted string.*?\"(.*?)\".*may clash/i);
    warn ($_) 
      unless (defined $Eobj::classes{$class});
  }
}

# We use explicit package names rather than Perl 5.6.0's "our", so
# perl 5.004 won't yell at us.

@Eobj::ISA = qw[Exporter];
@Eobj::EXPORT = qw[&init &override &underride &inherit &definedclass &globalobj];
$Eobj::VERSION = '0.20';
$Eobj::STARTTIME = localtime();

$Eobj::eobjflag = 0;
$Eobj::globalobject=();

unless ($Eobj::eobjflag) {
  $Eobj::eobjflag = 1; # Indicate that this clause has been run once
  $Eobj::errorcrawl='system';
  $Eobj::callbacksdepth = 0; # This indicates when callbacks are going on.
  undef $Eobj::wrong_flag;

  #For unloaded classes: Value is [classfile, parent class, first-given classname].
  %Eobj::classes = ('PL_hardroot', 1);
  %Eobj::objects = ();
  $Eobj::objectcounter = 0;
  
  {
    my $home = $INC{'Eobj.pm'};
    ($home) = ($home =~ /^(.*)Eobj\.pm$/);
    blow("Failed to resolve Eobj.pm's directory")
      unless (defined $home);
    $Eobj::home = $home;
  }

  $Eobj::classhome = "${Eobj::home}Eobj/";
  inherit('root',"${Eobj::classhome}PLroot.pl",'PL_hardroot');
  inherit('global',"${Eobj::classhome}PLglobal.pl",'root');
  inherit('site_init',"${Eobj::classhome}site_init.pl",'PL_hardroot');
}

sub init {
  site_init -> init;
}
sub inherit {
  my $class = shift;
  my $file = shift;
  my $papa = shift;

  puke("Attempt to create the already existing class \'$class\'\n")
    if $Eobj::classes{$class};

  puke("No parent class defined for \'$class\'\n")
    unless (defined $papa);
  $Eobj::classes{$class} = [$file, $papa, $class];
  # The following two lines are a Perl 5.8.0 bug workaround (early
  # versions). Google "stash autoload" for why.
  undef ${"${class}::Eobj_dummy_variable"}; 
  undef ${"${class}::Eobj_dummy_variable"}; # No single use warning...
  return 1;
}


sub override {
  my $class = shift;
  my $file = shift;
  my $papa = shift;

  unless ($Eobj::classes{$class}) {
    return inherit($class, $file, $papa)
      if defined ($papa);
    puke("Tried to override nonexisting class \'$class\', and no alternative parent given\n");
  }

  puke("Attempt to override class \'$class\' after it has been loaded\n")
    unless ref($Eobj::classes{$class});

  # Now create a new name for the previous class pointer

  my $newname=$class.'_PL_';
  my $i=1;
  while (defined $Eobj::classes{$newname.$i}) {$i++;}
  $newname=$newname.$i;
  
  # This is the operation of overriding

  $Eobj::classes{$newname}=$Eobj::classes{$class};
  $Eobj::classes{$class}=[$file, $newname, $class];

  # The following two lines are a Perl 5.8.0 bug workaround (early
  # versions). Google "stash autoload" for why.
  undef ${"${newname}::Eobj_dummy_variable"};
  undef ${"${newname}::Eobj_dummy_variable"}; # No single use warning

  return 1;
}

sub underride {
  my $class = shift;
  my $file = shift;

  unless ($Eobj::classes{$class}) {
    puke("Tried to underride a nonexisting class \'$class\'\n");
  }

  puke("Attempt to underride class \'$class\' after it has been loaded\n")
    unless ref($Eobj::classes{$class});

  # Now create a new name for the previous class pointer

  my $newname=$class.'_PL_';
  my $i=1;
  while (defined $Eobj::classes{$newname.$i}) {$i++;}
  $newname=$newname.$i;
  
  my $victim = $class;

 # Now we look for the grandfather
 SEARCH: while (1) {
    my $parent = ${$Eobj::classes{$victim}}[1];
    if (${$Eobj::classes{$parent}}[2] ne $class) { # Same family?
      last SEARCH;
    } else {
      $victim = $parent; # Climb up the family tree
    }
  }
  # This is the operation of parenting

  $Eobj::classes{$newname}=[$file, ${$Eobj::classes{$victim}}[1], $class];
  ${$Eobj::classes{$victim}}[1]=$newname;

  # The following two lines are a Perl 5.8.0 bug workaround (early
  # versions). Google "stash autoload" for why.
  undef ${"${newname}::Eobj_dummy_variable"};
  undef ${"${newname}::Eobj_dummy_variable"}; # No single use warning.
  return 1;
}

#definedclass:
#0 - not defined, 1 - defined but not loaded, 2 - defined and loaded

sub definedclass {
  my $class = shift;
  my $p = $Eobj::classes{$class};
  return 0 unless (defined $p);
  return 1 if ref($p);
  return 2;
}

sub classload {
  my ($class, $schwonz) = @_;
  my $p = $Eobj::classes{$class};
  my $err;

  blow($schwonz."Attempt to use undeclared class \'$class\'\n")
    unless (defined $p);

  # If $p isn't a reference, the class has been loaded.
  # This trick allows recursive calls.
  return 1 unless ref($p);

  $Eobj::classes{$class} = 1;

  my ($file, $papa, $original) = @{$p};

  classload($papa, $schwonz); # Make sure parents are loaded

  # Now we create the package wrapping

  my $d = "package $class; use strict 'vars'; use Eobj::PLerror;\n";
  $d.='@'.$class."::ISA=qw[$papa];\n";

  # Registering MUST be the last line before the text itself,
  # since the line number is recorded. Line count in error
  # messages begin immediately after the line that registers.

  $d.="&Eobj::PLerror::register(\'$file\');\n# line 1 \"$file\"\n";

  open (CLASSFILE, $file) || 
    blow($schwonz."Failed to open resource file \'$file\' for class \'$class\'\n");
  $d.=join("",<CLASSFILE>);
  close CLASSFILE;
  eval($d);
  blow ($schwonz."Failed to load class \'$original\':\n $@")
    if ($@);
}

sub globalobj {
  return $Eobj::globalobject if (ref $Eobj::globalobject);
  puke("Global object was requested before init() was executed\n");
}

# This routine attempts to keep lines below 80 chrs/lines
sub linebreak {
  my $data = shift;
  my $extraindent = shift;
  $extraindent = '' unless (defined $extraindent);

  my @chunks = split("\n", $data);

  foreach (@chunks) {
    my $realout = '';
    while (1) { # Not forever. We'll break this in proper time
      if (/^.{0,79}$/) { # The rest fits well...
	$realout .= $_;
	last;
      }
      # We try to break the line after a comma.
      my ($x, $y) = (/^(.{50,78},)\s*(.*)$/);
      # Didn't work? A whitespace is enough, then.
      ($x, $y) = (/^(.{50,79})\s+(.*)$/)
	unless (defined $x);
      # Still didn't work? Break at first white space.
      ($x, $y) = (/^(.{50,}?)\s+(.*)$/)
	unless (defined $x);
      
      # THAT didn't work? Give up. Just dump it all out.
      unless (defined $x) {
	$realout .= $_;
	last;
      } else { # OK, we have a line split!
	$realout .= $x."\n";
	$_ = $extraindent.$y; # The rest, only indented.
      }
    }
    $_ = $realout;
  }
  return join("\n", @chunks);
}

# Just empty packages (used by PLroot).
package PL_hardroot;
package PL_settable;
package PL_const;

# And now the magic of autoloading.
package UNIVERSAL;
use Eobj::PLerror;
$UNIVERSAL::errorcrawl='skip';
%UNIVERSAL::blacklist=();

sub AUTOLOAD {
  my $class = shift;
  my $method = $UNIVERSAL::AUTOLOAD;
  my ($junk,$file,$line)=caller;
  my $schwonz = "at $file line $line";
  return undef if $method =~ /::SUPER::/;

  my ($package) = $method =~ /^(.*?)::/;
  $method =~ s/.*:://;

  my $name = ref($class);

  return undef if ($method eq 'DESTROY');
  
  print "$class, $package\n"  unless ($class eq $package);
  puke("Undefined function/method \'$method\' $schwonz\n")
    unless ($class eq $package);

  if ($name) {
    # Forgive. This is not our class anyway...
    return undef;
  }

  # Now we protect ourselves against infinite recursion, should
  # the classload call fail silently. This will happen if the
  # first attempt to call a method in a class is to a
  # method that isn't defined.
  puke("Undefined method \'$method\' in class \'$class\' $schwonz\n")
    if $UNIVERSAL::blacklist{$class};
  $UNIVERSAL::blacklist{$class}=1;

  &Eobj::classload($class,
		       "While trying to load class \'$class\' due to call ".
		       "of method \'$method\' $schwonz:\n");
 
  #Just loaded the new class? Let's use it!
  return $class->$method(@_);
}

# Now have the "defineclass" subroutine defined, so we can use it to
# generate bareword warnings for anything but a class name.



1; # Return true
__END__

=head1 NAME

Eobj - Easy Object Oriented programming environment

=head1 SYNOPSIS

  use Eobj;

  inherit('myclass','myclass.pl','root');

  init;

  $object = myclass->new(name => 'MyObject');
  $object->mymethod('hello');

  $object->set('myscalar', 'The value');
  $scalar = $object->get('myscalar');

  $object->set('mylist', 'One', 'Two', 'Three');
  @list = $object->get('mylist');

  %hash = ('Foo' => 'Bar',
           'Daa' => 'Doo');
  $object->set('myhash', %hash);
  %the_hash = $object->get('myhash');

  globalobj->objdump(); # Dump debug info
 

=head1 DESCRIPTION

Eobj is OO in Perl for the masses. It makes it possible to write complete OO
scripts with plain Perl syntax (unlike classic OO-Perl). And like plain Perl,
the syntax usually means what you think it means, as long as things are kept
plain.

Eobj doesn't reinvent Perl's natural OO environment, but is a wrapper for it.
The real engine is still Perl.

This man page is enough to get you going, but not more than that. If deeper
understanding is needed, the documentation, which can be found in the
Eobj guide, F<eobj.pdf> (PDF format), is the place to look. The PDF file
should come along with the module files.

=head1 HOW IT ALL WORKS

Before beginning, it's important to distinguish between the main script and the class
source files.

The main script is what you would usually call "the script": When we run Perl, we give
some file as the script to run. That file, possibly with some other Perl modules that
it runs, is the main script.

The main script is divided in two phases:

=over 4

=item 1.

Declaration of classes. The main script tells what classes it wants to have, and what
source file declares each class' methods.

=item 2.

Creating and using objects. This is usually where the main script does something
useful: Objects are created, their methods are called, and so on.

=back

We shift from phase 1 to phase 2 with a call to init(). All class declarations
I<must> come before init(), and all objects creations I<must> come afterwards.

init() does not accept
any arguments, so it's done exactly like in the Synopsis above.


=head1 CREATING CLASSES

Classes are defined by scripts ("class source files") that contain nothing
else than subroutine definitions. For example, the F<myclass.pl> file mentioned
in the Synopsis could very well consist of exactly the following:

  sub mymethod {
    my $self = shift;
    my $what = shift;
    print "I was told to say $what\n";
  }

This subroutine definition (in effect, method definition) could be followed
by other similar subroutine definitions.

=head2 Rules for writing classes

=over 4

=item *

The class source file should not contain anything else than C<sub { }>
declarations. 

=item *

All variables must be localized with C<my>. The method should not access
varibles beyond its own, temporary scope. It may, of course, access other
objects' properties.

=item *

If "global variables" are needed, they should be kept as properties in
the global object (see below).

=item *

Use puke() and blow() instead of die(). Use fishy() and wiz() instead of warn().
In error messages, identify your own object with C<$self-E<gt>who()>, and
other objects with C<$self-E<gt>safewho($otherobject)>

=item *

Call methods, including your own class' methods, in complete C<$obj-E<gt>method()>-like
format. This will assure consistency if your method is overridden.

=item *

Properties should be accessed only as described in the Eobj documentation (and not
as in classic Perl objects).

=back

=head2 Methods vs. Subroutines

Subroutines are routines that are not related to any specific object or other
kind of context (this is what plain Perl programmers do all the time).
Methods, on the other hand,  are routines that are called in conjunction with an
object. In other words, calling a method is I<telling an object> to do something.
This call's action often depends on the specific object's properties, and it may
also affect them.

Therefore, when a method is called in Perl, the first argument is always a handle
(reference) to the object whose method was called. In this way, the routine knows
what object it is related to.

The rest of the arguments appear exactly like a regular subroutine call. A subroutine
can be transferred into a method by putting a C<shift> command in the beginning.
In particular, the method's return values mechanism is exactly like the one of
plain subroutines.

=head1 DECLARING CLASSES

A class is declared by pointing at a source file (which consists of method declarations),
and bind its methods with a class name. This is typically done with either
inherit() or override(). For example,

  inherit('myclass','myclass.pl','root');

reads the file F<myclass.pl>, and creates a class named C<myclass>. This class is
derived from the C<root> class, and hence any method which is not defined in
C<myclass> will be searched for in C<root>.

As a result of this declaration, it will be possible to create a new object with
C<myclass-E<gt>new(...)>. 

Note that there is no necessary connection between the class' name and the name
of the source file. Also, it should be noted that the source file is not read
by the the Perl parser until it's specifically needed (usually because an object
is created).

Sometimes it's convenient to add methods to an existing class, without changing
the class' name. This is especially useful when we want to change the root class.

Suppose that we want the methods in the F<myclass.pl> file to be recognized by
all objects. We would then declare

  inherit('root','myclass.pl');

Since all classes are based on C<root>, all classes inherit the methods given in
F<myclass.pl>. Note that this includes classes that were declared I<before> the
override() call.

override() can be used on any class, not only C<root>, of course. It's a useful tool
to set default properties for all objects (by altering the new() method), but care
should be taken not to abuse override().

A call to init() is mandatory after all class declarations (inherit() and override()
statements) and before creating the first object is generated. 

=head2 Overriding methods

If a method, which is defined in the class source file, already exists in the classes
from which the new class is derived, the class source file's method overrides the
derived class' method. This means that the source class' method will be used I<instead>
of the derived class' method.

In many cases, we don't want our new method to come instead of the previous one, but
rather extend the method to do somthing in addition to what it did before.

Suppose, for example, that we inherited a method called mymethod(), which we want to extend.
The following declaration will do the job:

  sub mymethod {
    my $self = shift;
    $self->SUPER::mymethod(@_);
  
    # Here we do some other things...
  }

Note that we call the inherited mymethod() after shifting off the $self argument, buf before
doing anything else. This makes sure that the inherited method gets an unaltered list of
arguments. When things are organized like this, both methods may C<shift> their argument lists
without interfering with each other.

But this also means, that the extra functionality we added will be carried out I<after> the
inherited method's. Besides, we ignore any return value that the method returned.

Whenever the return value is of interest, or we want to run our code before the inherited
method's, the following schema should be used:

  sub mymethod {
    my $self = shift;
  
    # Here we do some other things...
    # Be careful not to change @_ !

    return $self->SUPER::mymethod(@_);
  }

The problem with this way of doing it, is that if we accidentally change the argument list
@_, the overridden method will misbehave, which will make it look like a bug in the overridden
method (when the bug is really ours).

Note that this is the easiest way to assure that the return value will be passed on correctly.
The inherited method may be context sensitve (behave differently if a scalar or list are exptected
as return value), and the last implementation above assures that context is passed correctly.

The new() method should be handled with extra care. The implementation
of the method should always be as follows:

  sub new {
    my $this = shift;
    my $self = $this->SUPER::new(@_);

    # Do your stuff here. $self is the
    # reference to the new object

    return $self; # Don't forget this!
  } 

=head1 USING OBJECTS

Objects are created by calling the new() method of the class. Something in the style of:

  $object = myclass->new(name => 'MyObject');

(You didn't for forget to call init() before creating an object, did you?)

This statement creates a new object of class C<myclass>, and puts its reference (handle,
if you want) in $object. The object is also given a name, C<Myobject>.

Every object must be created with  a unique name. This name is used in error messages,
and it's also possible to get an object's reference by its name with the C<root>
class' objbyname() method. The object's name can not be changed.

Since a fatal error occurs when trying to create an object with an already existing name,
the C<root> class' method suggestname() will always return a legal name to create a new
object with. This method accepts our suggested name as an argument, and returns a name
which is OK to use, possibly the same name with some enumeration.

So when the object's names are not completely known in advance, this is the safe way to do
it:

  my $name = globalobj->suggestname('MyObject');
  my $object = myclass->new(name => $name);

or, if we don't care about the object's name:

  my $object = myclass->new(name => globalobj->suggestname('MyObject'));

After the object has been created, we may access its properties (see below) and/or call
its methods.

For example,

  myclass->mymethod('Hello');

=head1 OBJECT'S PROPERTIES

Each object carries its own local variables. These are called the object's I<properties>.

The properties are accessed with mainly two methods, get() and set(). const() is used
to create constant properties, which is described in the PDF guide.

  $obj->set($prop, X);

Will set $obj's property $prop to X, where X is either a scalar, a list or a hash.

One can the reobtain the value by calling

  X = $obj->get($prop);

Where X is again, either a scalar, a list or a hash.

$prop is the property's name, typically a string. Unlike plain Perl variables, the
property's name is just any string (any characters except newlines), and it does
not depend on the type of the property (scalar, list or hash). It's the programmer's
responsibility to handle the types correctly.

Use set() and get() to write and read properties in the spirit of this man page's
Synopsis (beginning of document). It's simple and clean, but if you want to do something
else, there is much more to read about that in the PDF guide.

=head1 THE GLOBAL OBJECT

The global object is created as part of the init() call, and is therefore the first
object in the system. It is created from the C<global> class, which is derived from
the C<root> class.

The global object has two purposes:

=over 4

=item *

Its properties is the right place to keep "global variables".

=item *

It can be used to call methods which don't depend on the object they are called on.
For example, the suggestname() method, mentioned above, is a such a method. We may
want to call it before we have any object at hand, since this method is used to
prevent name collisions.

The global object's handle is returned by the globalobj() function in the main script
or with the C<root> class' globalobj() method. So when writing a class, getting the
global object is done with something like

  my $global = $self->globalobj;

=back

=head1 HOW TO DIE

Eobj comes with an error-reporting mechanism, which is based upon the Carp module.
It's was extended in order to give messages that fit Eobj better.

There are two main functions to use instead of die(): blow() and puke(). They are
both used like die() in the sense that a newline in the end of the error message
inhibits prinitng the file name and line number of where the error happened.

=over 4

=item *

blow() should be used when the error doesn't imply a bug. A failure to open a file,
wrong command line parameters are examples of when blow() is better used. Note that
if you use blow() inside a class, it's usually better to give a descriptive error
message, and terminate it with a newline. Otherwise, the class source file will be
given as where the error occured, which will make it look as if there's a bug in
the class itself.

=item *

puke() is useful to report errors that should never happen. In other words, they
report bugs, either in your class or whoever used it. puke() displays the entire call
trace, so that the problematic call can be found easier.

=back

For warnings, fishy() is like blow() and wiz() works like puke(). Only these are warnings.

Unlike Carp, there is no attepmt to distinguish between the "original caller", or the
"real script" and "modules" or "classes". Since classes are readily written per
application, there is no way to draw the line between "module" and "application".

It is possible to declare a class as "hidden" or "system", which will make it disappear
from stack traces. This is explained in the PDF guide.

=head1 ISSUES NOT COVERED

The following issues are covered in the Eobj guide (F<eobj.pdf>), and not in this
man page. Just so you know what you're missing out... ;)

=over 4

=item *

The and underride() function

=item *

Constant properties

=item *

Setting up properties during object creation with new()

=item *

List operations on properties: pshift(), punshift(), ppush() and ppop()

=item *

The property path: A way organize properties in a directory-like tree.

=item *

Several useful methods of the C<root> class: who(), safewho(), isobject(),
objbyname(), prettyval() and linebreak()

=back

=head1 EXPORT

The following functions are exported to the main script:

init(), override(), underride(), inherit(), definedclass(), globalobj()

These functions are exported everywhere (can be used by classes as well):

blow(), puke(), wiz(), wizreport(), fishy(), wrong(), say(), hint(), wink()

These methods are part of the C<root> class, and should not be overridden
unless an intentional change in their functionality is desired:

new(), who(), safewho(), isobject(), objbyname(), suggestname(), get(),
const(), set(),  seteq(), addmagic(), pshift(), ppop(),
punshift(), ppush(), globalobj(), linebreak(), objdump(), prettyval()

store_hash(), domutate(), getraw()

Note that the last three methods are for the class' internal use only.

=head1 HISTORY

Eobj is derived from a larger project, Perlilog, which was written in 2002 by the same
author.
A special OO environment was written in order to handle objects conveniently. This
environment was later on extracted from Perlilog, and became Eobj.

=head1 BUGS

Please send bug reports directly to the author, to the e-mail given below. Since Eobj
relies on some uncommonly used (but yet standard) features, the bug is sometimes in
Perl and not Eobj. In order to verify this, please send your version description
as given by running Perl with C<perl -V> (a capital V!).

These are the bugs that are known as of yet:

=over 4

=item *

Doesn't work with C<use strict> due to some games with references. Does work with
C<use strict 'vars'>, though.

=back

=head1 ACKNOWLEDGEMENTS

This project would not exist without the warm support of Flextronics Semiconductors in Israel,
and Dan Gunders in particular.

=head1 AUTHOR

Eli Billauer, E<lt>elib@flextronics.co.ilE<gt>

=head1 SEE ALSO

The Perlilog project: L<http://www.opencores.org/perlilog/>.

=cut
